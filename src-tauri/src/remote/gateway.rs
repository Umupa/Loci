//! The host's end of a connected device: authenticates it over the secure
//! channel, then answers its calls and streams the session feed.
//!
//! # Wire protocol
//!
//! Every secure-channel message is one frame: a JSON object (UTF-8, starts
//! with `{`), or a binary blob chunk (starts with `0x01`).
//!
//! Device -> host:
//!
//! ```text
//! {"t":"call","id":7,"cmd":"agent_transcript_page","args":{...}}
//!     A registered command, `args` as the webview passes them to `invoke`.
//!     Runs on the host if `remote_catalog` classes it Read, Write or OnHost;
//!     SessionAction commands go to the host window like intents; everything
//!     else is refused.
//! {"t":"call","id":8,"cmd":"session.submit","args":[...],"requestId":"<uuid>"}
//!     An intent (any name with a dot), run by the host window. Resend after
//!     a lost connection with the same requestId and it runs only once.
//! {"t":"subscribe","id":9,"epoch":"<epoch>","seq":41}
//!     Start (or restart) the session feed after the last patch applied;
//!     leave out epoch and seq to start from a snapshot.
//! {"t":"upload","id":10,"name":"photo.png","size":<bytes>}
//!     A file from the device, at most `MAX_UPLOAD` bytes. Its bytes follow
//!     as chunks 0x01 || id (u64, big-endian) || at most 1 MiB, in order, the
//!     same framing results use. Once all of them are in, the host saves the
//!     file beside pasted attachments and answers with its path on the host.
//!     A refused upload is answered at once; chunks sent for it are dropped.
//! ```
//!
//! Host -> device:
//!
//! ```text
//! {"t":"result","id":7,"ok":true,"value":...}
//! {"t":"result","id":7,"ok":false,"error":"..."}
//! {"t":"result","id":7,"ok":true,"blob":<bytes>}
//!     The command returned bytes (`ipc::Response`); they follow as chunks
//!     0x01 || id (u64, big-endian) || at most 1 MiB, in order.
//! {"t":"result","id":9,"ok":true,"value":null}
//!     The subscription has caught up: missed patches, or a snapshot, went
//!     out before this.
//! {"t":"event","name":"session.feed","payload":<SessionFeed>}
//!     A snapshot or patch, as `src/app/remote/sessionFeed.ts` defines it.
//!     Apply in order; on a gap in seq, subscribe again.
//! ```

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

use ed25519_dalek::SigningKey;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::{broadcast, mpsc, watch};
use tokio::task::{AbortHandle, JoinSet};

use super::secure_channel::{self, ConnectCode, SecureChannel, TrustedDevices};
use super::session_master::SessionMaster;
use super::tunnel::{Connection, Listener};
use crate::remote_catalog::{class_of, CommandClass};

const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
pub const BLOB_CHUNK: usize = 1024 * 1024;
/// The most one uploaded file may hold, and the most a connection may have
/// announced and not yet sent.
pub const MAX_UPLOAD: usize = 100 * 1024 * 1024;
const BLOB: u8 = 1;

pub enum Reply {
    Json(Value),
    Bytes(Vec<u8>),
}

pub type ReplyFuture = Pin<Box<dyn Future<Output = Result<Reply, String>> + Send>>;
/// Runs a registered command on the host.
pub type Invoke = Box<dyn Fn(String, Value) -> ReplyFuture + Send + Sync>;
/// Saves an uploaded file (name, bytes) on the host; the reply is its path.
pub type SaveUpload = Box<dyn Fn(String, Vec<u8>) -> ReplyFuture + Send + Sync>;

pub struct Gateway {
    pub master: Arc<SessionMaster>,
    pub invoke: Invoke,
    pub save_upload: SaveUpload,
    pub code: ConnectCode,
    pub device_key: SigningKey,
    pub trusted: Box<dyn TrustedDevices + Send + Sync>,
}

#[derive(Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
enum Frame {
    Call {
        id: u64,
        cmd: String,
        #[serde(default)]
        args: Value,
        #[serde(rename = "requestId")]
        request_id: Option<String>,
    },
    Subscribe {
        id: u64,
        epoch: Option<String>,
        seq: Option<u64>,
    },
    Upload {
        id: u64,
        name: String,
        size: usize,
    },
}

/// A file a device is sending, chunk by chunk.
struct Upload {
    name: String,
    size: usize,
    bytes: Vec<u8>,
}

/// Uploads one connection has announced and not finished, by id.
#[derive(Default)]
struct Uploads(std::collections::HashMap<u64, Upload>);

impl Uploads {
    /// Starts an upload, or says why not.
    fn start(&mut self, id: u64, name: String, size: usize) -> Result<Option<Vec<u8>>, String> {
        let waiting: usize = self.0.values().map(|upload| upload.size).sum();
        if size > MAX_UPLOAD || waiting + size > MAX_UPLOAD {
            return Err(format!(
                "Files sent to the host can be at most {} MB",
                MAX_UPLOAD / 1024 / 1024
            ));
        }
        if size == 0 {
            return Ok(Some(Vec::new()));
        }
        self.0.insert(
            id,
            Upload {
                name,
                size,
                bytes: Vec::with_capacity(size.min(BLOB_CHUNK)),
            },
        );
        Ok(None)
    }

    /// Adds a chunk; the name and bytes once the file is complete. Chunks of
    /// an upload that was never started, or was refused, are dropped.
    fn add(&mut self, id: u64, chunk: &[u8]) -> Option<Result<(String, Vec<u8>), String>> {
        let upload = self.0.get_mut(&id)?;
        if upload.bytes.len() + chunk.len() > upload.size {
            self.0.remove(&id);
            return Some(Err("The upload was longer than it said".into()));
        }
        upload.bytes.extend_from_slice(chunk);
        if upload.bytes.len() < upload.size {
            return None;
        }
        let Upload { name, bytes, .. } = self.0.remove(&id)?;
        Some(Ok((name, bytes)))
    }
}

enum Route {
    Host,
    Window,
    Refused,
}

fn route(cmd: &str) -> Route {
    if cmd.contains('.') {
        return Route::Window;
    }
    match class_of(cmd) {
        Some(CommandClass::Read | CommandClass::Write | CommandClass::OnHost) => Route::Host,
        Some(CommandClass::SessionAction) => Route::Window,
        Some(CommandClass::ClientLocal | CommandClass::Never) | None => Route::Refused,
    }
}

type Out = mpsc::Sender<Vec<u8>>;

impl Gateway {
    /// Serves every device the tunnel brings until it stops.
    /// Serves every device the tunnel brings until it stops. Dropping this
    /// future (stopping remote access) closes every connection it opened.
    pub async fn run(self: Arc<Self>, mut listener: Listener) {
        let mut connections = JoinSet::new();
        while let Some(conn) = listener.accept().await {
            while connections.try_join_next().is_some() {}
            connections.spawn(self.clone().serve(conn));
        }
    }

    pub async fn serve(self: Arc<Self>, conn: Connection) {
        let handshake = secure_channel::accept(conn, &self.code, &self.device_key, &*self.trusted);
        let Ok(Ok(SecureChannel {
            peer,
            mut sender,
            mut receiver,
        })) = tokio::time::timeout(HANDSHAKE_TIMEOUT, handshake).await
        else {
            return;
        };
        let connection_id = uuid::Uuid::new_v4().to_string();
        let (out, mut outgoing) = mpsc::channel::<Vec<u8>>(64);
        // The writer and the feed end with this connection, however it ends.
        let mut tasks = JoinSet::new();
        tasks.spawn(async move {
            while let Some(message) = outgoing.recv().await {
                if sender.send(&message).await.is_err() {
                    break;
                }
            }
        });

        let mut feed: Option<AbortHandle> = None;
        let mut uploads = Uploads::default();
        let mut trust = self.trusted.changes();
        loop {
            let message = tokio::select! {
                message = receiver.recv() => match message {
                    Ok(Some(message)) => message,
                    _ => break,
                },
                still = trust_changed(&mut trust) => {
                    // A device removed from the group loses its open
                    // connections too, not just its next handshake.
                    if still && !self.trusted.is_trusted(&peer) {
                        break;
                    }
                    continue;
                }
            };
            if message.first() == Some(&BLOB) && message.len() >= 9 {
                let id = u64::from_be_bytes(message[1..9].try_into().unwrap());
                match uploads.add(id, &message[9..]) {
                    Some(Ok((name, bytes))) => self.save(id, name, bytes, &out),
                    Some(Err(error)) => send_result(&out, id, Err(error)).await,
                    None => {}
                }
                continue;
            }
            let Ok(frame) = serde_json::from_slice::<Frame>(&message) else {
                continue;
            };
            match frame {
                Frame::Call {
                    id,
                    cmd,
                    args,
                    request_id,
                } => {
                    let gateway = self.clone();
                    let (connection_id, out) = (connection_id.clone(), out.clone());
                    tokio::spawn(async move {
                        let result = gateway.call(&connection_id, cmd, args, request_id).await;
                        send_result(&out, id, result).await;
                    });
                }
                Frame::Subscribe { id, epoch, seq } => {
                    if let Some(task) = feed.take() {
                        task.abort();
                    }
                    let position = epoch.zip(seq);
                    feed = Some(tasks.spawn(stream_feed(
                        self.master.clone(),
                        connection_id.clone(),
                        position,
                        id,
                        out.clone(),
                    )));
                }
                Frame::Upload { id, name, size } => match uploads.start(id, name.clone(), size) {
                    Ok(Some(empty)) => self.save(id, name, empty, &out),
                    Ok(None) => {}
                    Err(error) => send_result(&out, id, Err(error)).await,
                },
            }
        }

        drop(tasks);
        self.master.connection_closed(&connection_id);
        // Release whatever this device was keeping open on the host.
        let _ = self
            .master
            .intent(&connection_id, new_id(), "session.view", json!([[]]))
            .await;
    }

    /// Saves a finished upload without holding up the connection's other frames.
    fn save(&self, id: u64, name: String, bytes: Vec<u8>, out: &Out) {
        let saving = (self.save_upload)(name, bytes);
        let out = out.clone();
        tokio::spawn(async move { send_result(&out, id, saving.await).await });
    }

    async fn call(
        &self,
        connection_id: &str,
        cmd: String,
        args: Value,
        request_id: Option<String>,
    ) -> Result<Reply, String> {
        match route(&cmd) {
            Route::Host => (self.invoke)(cmd, args).await,
            Route::Window => self
                .master
                .intent(connection_id, request_id.unwrap_or_else(new_id), &cmd, args)
                .await
                .map(Reply::Json),
            Route::Refused => Err(format!("{cmd} is not available to connected devices")),
        }
    }
}

/// Catches the device up from `position` (or a snapshot), then forwards the
/// live feed. A device that falls too far behind starts over from where it
/// got to, which is a replay or a fresh snapshot.
async fn stream_feed(
    master: Arc<SessionMaster>,
    connection_id: String,
    mut position: Option<(String, u64)>,
    id: u64,
    out: Out,
) {
    let mut answered = false;
    loop {
        let (mut live, missed) = master.subscribe(position.as_ref().map(|(e, s)| (e.as_str(), *s)));
        match missed {
            Some(items) => {
                for item in items {
                    if !send_feed(&out, &item.json).await {
                        return;
                    }
                    position = Some((item.epoch.clone(), item.seq));
                }
            }
            None => {
                let snapshot = master
                    .intent(&connection_id, new_id(), "session.snapshot", json!([]))
                    .await;
                let at = snapshot.as_ref().ok().and_then(|snapshot| {
                    Some((
                        snapshot["epoch"].as_str()?.to_owned(),
                        snapshot["seq"].as_u64()?,
                    ))
                });
                let (Ok(snapshot), Some(at)) = (snapshot, at) else {
                    if !answered {
                        send_result(&out, id, Err("The host has no session feed".into())).await;
                    }
                    return;
                };
                if !send_feed(&out, &snapshot.to_string()).await {
                    return;
                }
                position = Some(at);
            }
        }
        if !answered {
            send_result(&out, id, Ok(Reply::Json(Value::Null))).await;
            answered = true;
        }
        loop {
            match live.recv().await {
                Ok(item) => {
                    let seen = position
                        .as_ref()
                        .is_some_and(|(epoch, seq)| *epoch == item.epoch && item.seq <= *seq);
                    if seen {
                        continue;
                    }
                    if !send_feed(&out, &item.json).await {
                        return;
                    }
                    position = Some((item.epoch.clone(), item.seq));
                }
                Err(broadcast::error::RecvError::Lagged(_)) => break,
                Err(broadcast::error::RecvError::Closed) => return,
            }
        }
    }
}

async fn send_feed(out: &Out, feed: &str) -> bool {
    let frame = format!(r#"{{"t":"event","name":"session.feed","payload":{feed}}}"#);
    out.send(frame.into_bytes()).await.is_ok()
}

async fn send_result(out: &Out, id: u64, result: Result<Reply, String>) {
    let frame = match &result {
        Ok(Reply::Json(value)) => json!({"t": "result", "id": id, "ok": true, "value": value}),
        Ok(Reply::Bytes(bytes)) => {
            json!({"t": "result", "id": id, "ok": true, "blob": bytes.len()})
        }
        Err(error) => json!({"t": "result", "id": id, "ok": false, "error": error}),
    };
    if out.send(frame.to_string().into_bytes()).await.is_err() {
        return;
    }
    if let Ok(Reply::Bytes(bytes)) = result {
        for chunk in bytes.chunks(BLOB_CHUNK) {
            let mut message = Vec::with_capacity(9 + chunk.len());
            message.push(BLOB);
            message.extend_from_slice(&id.to_be_bytes());
            message.extend_from_slice(chunk);
            if out.send(message).await.is_err() {
                return;
            }
        }
    }
}

/// Waits for the trust list to change: `true` when it did, `false` (once)
/// when it never will again.
async fn trust_changed(changes: &mut Option<watch::Receiver<()>>) -> bool {
    let Some(receiver) = changes else {
        return std::future::pending().await;
    };
    if receiver.changed().await.is_ok() {
        return true;
    }
    *changes = None;
    false
}

fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::remote::secure_channel::tests::device;
    use crate::remote::session_master::tests::{patch, recording};
    use crate::remote::session_master::{IntentEvent, FEED_BUFFER_BYTES};
    use std::sync::Mutex;

    struct Device {
        channel: SecureChannel,
        master: Arc<SessionMaster>,
        intents: Arc<Mutex<Vec<IntentEvent>>>,
        invoked: Arc<Mutex<Vec<String>>>,
    }

    impl Device {
        async fn connect() -> Self {
            let (master, intents) = recording(FEED_BUFFER_BYTES);
            let invoked = Arc::new(Mutex::new(Vec::new()));
            let log = invoked.clone();
            let (host_key, client_key, code) = (device(), device(), ConnectCode::generate());
            let gateway = Arc::new(Gateway {
                master: master.clone(),
                invoke: Box::new(move |cmd, args| {
                    log.lock().unwrap().push(cmd.clone());
                    Box::pin(async move {
                        match cmd.as_str() {
                            "read_binary_file" => Ok(Reply::Bytes(vec![7; BLOB_CHUNK * 2 + 5])),
                            _ => Ok(Reply::Json(json!({"cmd": cmd, "args": args}))),
                        }
                    })
                }),
                save_upload: Box::new(|name, bytes| {
                    Box::pin(async move {
                        Ok(Reply::Json(
                            json!({"path": format!("/host/{name}"), "size": bytes.len(), "first": bytes.first()}),
                        ))
                    })
                }),
                code: code.clone(),
                device_key: host_key.clone(),
                trusted: Box::new(vec![client_key.verifying_key()]),
            });
            let (client, host) = Connection::pair();
            tokio::spawn(gateway.serve(host));
            let channel = secure_channel::connect(
                client,
                &code,
                &client_key,
                &[host_key.verifying_key()][..],
            )
            .await
            .unwrap();
            Self {
                channel,
                master,
                intents,
                invoked,
            }
        }

        async fn send(&mut self, frame: Value) {
            self.channel
                .sender
                .send(frame.to_string().as_bytes())
                .await
                .unwrap();
        }

        async fn recv(&mut self) -> Vec<u8> {
            self.channel.receiver.recv().await.unwrap().unwrap()
        }

        async fn json(&mut self) -> Value {
            serde_json::from_slice(&self.recv().await).unwrap()
        }

        async fn call(&mut self, cmd: &str, args: Value) -> Value {
            self.send(json!({"t": "call", "id": 1, "cmd": cmd, "args": args}))
                .await;
            self.json().await
        }

        async fn chunk(&mut self, id: u64, bytes: &[u8]) {
            let mut message = vec![BLOB];
            message.extend_from_slice(&id.to_be_bytes());
            message.extend_from_slice(bytes);
            self.channel.sender.send(&message).await.unwrap();
        }

        /// Waits for the next intent the window receives and answers it.
        async fn answer(&self, value: Value) -> IntentEvent {
            let event = loop {
                if let Some(event) = self.intents.lock().unwrap().pop() {
                    break event;
                }
                tokio::time::sleep(Duration::from_millis(1)).await;
            };
            self.master.reply(&event.request_id, Ok(value));
            event
        }
    }

    #[tokio::test]
    async fn saves_an_uploaded_file_from_its_chunks() {
        let mut device = Device::connect().await;
        let size = BLOB_CHUNK * 2 + 3;
        device
            .send(json!({"t": "upload", "id": 4, "name": "notes.pdf", "size": size}))
            .await;
        let bytes = vec![5u8; size];
        for chunk in bytes.chunks(BLOB_CHUNK) {
            device.chunk(4, chunk).await;
        }
        assert_eq!(
            device.json().await,
            json!({"t": "result", "id": 4, "ok": true, "value": {"path": "/host/notes.pdf", "size": size, "first": 5}})
        );
    }

    #[tokio::test]
    async fn refuses_an_upload_too_large_and_drops_its_chunks() {
        let mut device = Device::connect().await;
        device
            .send(json!({"t": "upload", "id": 5, "name": "big.mov", "size": MAX_UPLOAD + 1}))
            .await;
        let refused = device.json().await;
        assert_eq!(refused["ok"], false);
        assert!(refused["error"].as_str().unwrap().contains("100 MB"));
        device.chunk(5, b"ignored").await;
        // The connection still answers, and nothing was saved for the dropped chunk.
        assert_eq!(device.call("notes_get", json!({})).await["t"], "result");
    }

    #[tokio::test]
    async fn refuses_an_upload_longer_than_it_said() {
        let mut device = Device::connect().await;
        device
            .send(json!({"t": "upload", "id": 6, "name": "a.txt", "size": 3}))
            .await;
        device.chunk(6, b"abcd").await;
        let refused = device.json().await;
        assert_eq!(
            (refused["id"].clone(), refused["ok"].clone()),
            (json!(6), json!(false))
        );
    }

    #[test]
    fn keeps_what_is_announced_and_unsent_under_the_limit() {
        let mut uploads = Uploads::default();
        assert_eq!(uploads.start(1, "a".into(), MAX_UPLOAD / 2), Ok(None));
        assert!(uploads.start(2, "b".into(), MAX_UPLOAD / 2 + 1).is_err());
        assert_eq!(uploads.start(3, "empty".into(), 0), Ok(Some(Vec::new())));
        assert_eq!(uploads.add(9, b"never announced"), None);
        assert_eq!(uploads.add(1, &vec![1; MAX_UPLOAD / 2 - 1]), None);
        assert_eq!(
            uploads.add(1, &[2]).unwrap().unwrap().1.len(),
            MAX_UPLOAD / 2
        );
        assert_eq!(uploads.start(2, "b".into(), MAX_UPLOAD / 2 + 1), Ok(None));
    }

    #[tokio::test]
    async fn refuses_commands_that_are_never_remote_or_belong_to_the_client() {
        let mut device = Device::connect().await;
        for cmd in [
            "harness_spawn",
            "control_reply",
            "hide_window",
            "remote_intent_reply",
            "no_such_command",
        ] {
            let reply = device.call(cmd, json!({})).await;
            assert_eq!(reply["ok"], false, "{cmd}");
            assert_eq!(
                reply["error"],
                format!("{cmd} is not available to connected devices")
            );
        }
        assert!(device.invoked.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn runs_host_commands() {
        let mut device = Device::connect().await;
        let args = json!({"agentId": "a1", "before": null});
        let reply = device.call("agent_transcript_page", args.clone()).await;
        assert_eq!(
            reply,
            json!({"t": "result", "id": 1, "ok": true, "value": {"cmd": "agent_transcript_page", "args": args}})
        );
    }

    #[tokio::test]
    async fn sends_bytes_in_chunks_of_at_most_a_mebibyte() {
        let mut device = Device::connect().await;
        let head = device
            .call("read_binary_file", json!({"path": "/tmp/a.pdf"}))
            .await;
        assert_eq!(head["blob"], BLOB_CHUNK * 2 + 5);
        let mut total = 0;
        while total < BLOB_CHUNK * 2 + 5 {
            let chunk = device.recv().await;
            assert_eq!(chunk[0], BLOB);
            assert_eq!(u64::from_be_bytes(chunk[1..9].try_into().unwrap()), 1);
            assert!(chunk.len() - 9 <= BLOB_CHUNK);
            total += chunk.len() - 9;
        }
        assert_eq!(total, BLOB_CHUNK * 2 + 5);
    }

    #[tokio::test]
    async fn intents_and_session_actions_go_to_the_host_window() {
        let mut device = Device::connect().await;
        device
            .send(json!({"t": "call", "id": 4, "cmd": "session.stop", "args": ["s1"], "requestId": "r-1"}))
            .await;
        let event = device.answer(json!("stopped")).await;
        assert_eq!(
            (event.request_id.as_str(), event.name.as_str()),
            ("r-1", "session.stop")
        );
        assert_eq!(event.args, json!(["s1"]));
        assert_eq!(
            device.json().await,
            json!({"t": "result", "id": 4, "ok": true, "value": "stopped"})
        );

        device
            .send(json!({"t": "call", "id": 5, "cmd": "session_upsert", "args": {}}))
            .await;
        assert_eq!(device.answer(Value::Null).await.name, "session_upsert");
        assert_eq!(device.json().await["ok"], true);
        assert!(device.invoked.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn closing_the_connection_clears_its_view() {
        let mut device = Device::connect().await;
        device
            .send(json!({"t": "call", "id": 1, "cmd": "session.view", "args": [["s1"]]}))
            .await;
        let viewed = device.answer(Value::Null).await;
        device.json().await;
        let Device {
            channel,
            master,
            intents,
            ..
        } = device;
        drop(channel);
        let cleared = loop {
            if let Some(event) = intents.lock().unwrap().pop() {
                break event;
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        };
        master.reply(&cleared.request_id, Ok(Value::Null));
        assert_eq!(cleared.name, "session.view");
        assert_eq!(cleared.args, json!([[]]));
        assert_eq!(cleared.connection_id, viewed.connection_id);
    }

    #[tokio::test]
    async fn a_returning_device_gets_the_patches_it_missed_then_live_ones() {
        let mut device = Device::connect().await;
        device
            .master
            .publish(&json!({"kind": "snapshot", "epoch": "e1", "seq": 0}))
            .unwrap();
        device.master.publish(&patch("e1", 1)).unwrap();
        device.master.publish(&patch("e1", 2)).unwrap();
        device
            .send(json!({"t": "subscribe", "id": 2, "epoch": "e1", "seq": 1}))
            .await;
        let replayed = device.json().await;
        assert_eq!(
            (
                replayed["name"].as_str(),
                replayed["payload"]["seq"].as_u64()
            ),
            (Some("session.feed"), Some(2))
        );
        assert_eq!(
            device.json().await,
            json!({"t": "result", "id": 2, "ok": true, "value": null})
        );
        device.master.publish(&patch("e1", 3)).unwrap();
        assert_eq!(device.json().await["payload"]["seq"], 3);
        assert!(device.intents.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_device_that_cannot_catch_up_gets_a_snapshot_from_the_window() {
        let mut device = Device::connect().await;
        device
            .master
            .publish(&json!({"kind": "snapshot", "epoch": "e2", "seq": 5}))
            .unwrap();
        device
            .send(json!({"t": "subscribe", "id": 3, "epoch": "e1", "seq": 9}))
            .await;
        let asked = device
            .answer(json!({"kind": "snapshot", "epoch": "e2", "seq": 6, "sessions": []}))
            .await;
        assert_eq!(
            (asked.name.as_str(), asked.args.clone()),
            ("session.snapshot", json!([]))
        );
        assert_eq!(device.json().await["payload"]["seq"], 6);
        assert_eq!(device.json().await["ok"], true);
        // Already in the snapshot, so not sent again.
        device.master.publish(&patch("e2", 6)).unwrap();
        device.master.publish(&patch("e2", 7)).unwrap();
        assert_eq!(device.json().await["payload"]["seq"], 7);
    }
}
