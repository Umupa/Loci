//! The client side: a window of this Loci connects to another Loci's gateway
//! and talks the gateway's wire protocol (see `gateway.rs`) through these
//! commands. Each window has at most one connection; what comes back from the
//! host reaches only the window that connected.
//!
//! Window ↔ Rust:
//!
//! - `remote_client_connect({target})` → `{hostKey}`; `target` is
//!   `{kind: "loopback"}` or `{kind: "relay", relay, code, hostKey}`.
//! - `remote_client_call({cmd, args?, requestId?})` → the command's value, or
//!   an ArrayBuffer when the host returned bytes.
//! - `remote_client_subscribe({epoch?, seq?})` → `null` once caught up.
//! - `remote_client_upload({path})` → the file's path on the host, once this
//!   device's file (at most `MAX_UPLOAD` bytes) is saved there.
//! - `remote_client_cache_put({key, value})` / `remote_client_cache_get({key})`:
//!   JSON the window keeps for its host on this device (its session mirror).
//!
//! The replies to `Read` commands are kept on this device per host
//! (`cache.rs`). While there is no connection, a `Read` command is answered
//! from them, or refused with `NOT_KEPT`; anything else is refused with
//! `"Not connected to the host"`.
//! - `remote_client_disconnect()`.
//! - Events to that window: `remote-client-event` `{name, payload}` and
//!   `remote-client-status` `{state: "connecting" | "connected" | "disconnected", error?}`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use ed25519_dalek::VerifyingKey;
use serde::Deserialize;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager, WebviewWindow};
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;

use ed25519_dalek::SigningKey;

use super::alma_relay::AlmaRelayTunnel;
use super::cache::{self, HostCache, HOST_CACHE_LIMIT};
use super::device_group::DeviceGroup;
use super::gateway::{Reply, BLOB_CHUNK, MAX_UPLOAD};
use super::secure_channel::{self, ConnectCode, SecureChannel};
use super::tunnel::{Connection, Tunnel};
use super::RemoteHost;
use crate::remote_catalog::{class_of, CommandClass};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const MEMBER_RETRY: Duration = Duration::from_secs(3);
const DISCONNECTED: &str = "Not connected to the host";
/// A `Read` command asked while offline that was never answered before.
pub const NOT_KEPT: &str = "This was not read from the host before it went offline";
const BLOB: u8 = 1;

type Pending = Arc<Mutex<Option<HashMap<u64, oneshot::Sender<Result<Reply, String>>>>>>;

pub enum ClientEvent {
    /// `{"t":"event"}` from the host.
    Event { name: String, payload: Value },
    /// The connection ended, with the reason when it was not a clean close.
    Closed(Option<String>),
}

/// One connection to a host's gateway. Dropping it closes the connection and
/// fails the calls still waiting.
pub struct Client {
    out: mpsc::Sender<Vec<u8>>,
    /// `None` once the connection has ended, so a late call fails at once.
    pending: Pending,
    next_id: AtomicU64,
    tasks: [JoinHandle<()>; 2],
}

impl Client {
    pub fn start(channel: SecureChannel, on_event: impl Fn(ClientEvent) + Send + 'static) -> Self {
        let SecureChannel {
            mut sender,
            mut receiver,
            ..
        } = channel;
        let (out, mut outgoing) = mpsc::channel::<Vec<u8>>(64);
        let writer = tokio::spawn(async move {
            while let Some(message) = outgoing.recv().await {
                if sender.send(&message).await.is_err() {
                    break;
                }
            }
        });
        let pending: Pending = Arc::new(Mutex::new(Some(HashMap::new())));
        let reading = pending.clone();
        let reader = tokio::spawn(async move {
            // Blob results being received: id -> (expected size, bytes so far).
            let mut blobs: HashMap<u64, (usize, Vec<u8>)> = HashMap::new();
            let error = loop {
                match receiver.recv().await {
                    Ok(Some(message)) => receive(&message, &reading, &mut blobs, &on_event),
                    Ok(None) => break None,
                    Err(error) => break Some(error),
                }
            };
            fail_all(&reading);
            on_event(ClientEvent::Closed(error));
        });
        Self {
            out,
            pending,
            next_id: AtomicU64::new(1),
            tasks: [writer, reader],
        }
    }

    pub async fn call(
        &self,
        cmd: &str,
        args: Value,
        request_id: Option<String>,
    ) -> Result<Reply, String> {
        self.request(|id| {
            let mut frame = json!({"t": "call", "id": id, "cmd": cmd, "args": args});
            if let Some(request_id) = request_id {
                frame["requestId"] = json!(request_id);
            }
            frame
        })
        .await
    }

    pub async fn subscribe(&self, epoch: Option<String>, seq: Option<u64>) -> Result<(), String> {
        self.request(|id| json!({"t": "subscribe", "id": id, "epoch": epoch, "seq": seq}))
            .await
            .map(|_| ())
    }

    /// Sends a file to the host; its reply is the path it was saved at.
    pub async fn upload(&self, name: &str, bytes: &[u8]) -> Result<Reply, String> {
        if bytes.len() > MAX_UPLOAD {
            return Err(too_large());
        }
        self.request_with(
            |id| json!({"t": "upload", "id": id, "name": name, "size": bytes.len()}),
            |id| {
                bytes
                    .chunks(BLOB_CHUNK)
                    .map(|chunk| {
                        let mut message = Vec::with_capacity(9 + chunk.len());
                        message.push(BLOB);
                        message.extend_from_slice(&id.to_be_bytes());
                        message.extend_from_slice(chunk);
                        message
                    })
                    .collect()
            },
        )
        .await
    }

    async fn request(&self, frame: impl FnOnce(u64) -> Value) -> Result<Reply, String> {
        self.request_with(frame, |_| Vec::new()).await
    }

    /// Sends a frame, then `then` (an upload's chunks), and waits for the result.
    async fn request_with(
        &self,
        frame: impl FnOnce(u64) -> Value,
        then: impl FnOnce(u64) -> Vec<Vec<u8>>,
    ) -> Result<Reply, String> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        self.pending
            .lock()
            .unwrap()
            .as_mut()
            .ok_or(DISCONNECTED)?
            .insert(id, tx);
        self.out
            .send(frame(id).to_string().into_bytes())
            .await
            .map_err(|_| DISCONNECTED)?;
        for message in then(id) {
            self.out.send(message).await.map_err(|_| DISCONNECTED)?;
        }
        rx.await.map_err(|_| DISCONNECTED.to_string())?
    }
}

impl Drop for Client {
    fn drop(&mut self) {
        for task in &self.tasks {
            task.abort();
        }
        fail_all(&self.pending);
    }
}

fn fail_all(pending: &Pending) {
    for (_, waiting) in pending.lock().unwrap().take().into_iter().flatten() {
        let _ = waiting.send(Err(DISCONNECTED.into()));
    }
}

fn resolve(pending: &Pending, id: u64, result: Result<Reply, String>) {
    if let Some(waiting) = pending.lock().unwrap().as_mut().and_then(|p| p.remove(&id)) {
        let _ = waiting.send(result);
    }
}

fn receive(
    message: &[u8],
    pending: &Pending,
    blobs: &mut HashMap<u64, (usize, Vec<u8>)>,
    on_event: &impl Fn(ClientEvent),
) {
    if message.first() == Some(&BLOB) && message.len() >= 9 {
        let id = u64::from_be_bytes(message[1..9].try_into().unwrap());
        if let Some((size, bytes)) = blobs.get_mut(&id) {
            bytes.extend_from_slice(&message[9..]);
            if bytes.len() >= *size {
                let (_, bytes) = blobs.remove(&id).unwrap();
                resolve(pending, id, Ok(Reply::Bytes(bytes)));
            }
        }
        return;
    }
    let Ok(mut frame) = serde_json::from_slice::<Value>(message) else {
        return;
    };
    match frame["t"].as_str() {
        Some("result") => {
            let Some(id) = frame["id"].as_u64() else {
                return;
            };
            if frame["ok"] != true {
                let error = frame["error"]
                    .as_str()
                    .unwrap_or("The host refused the call");
                resolve(pending, id, Err(error.to_owned()));
            } else if let Some(size) = frame["blob"].as_u64() {
                let size = size as usize;
                if size == 0 {
                    resolve(pending, id, Ok(Reply::Bytes(Vec::new())));
                } else {
                    blobs.insert(
                        id,
                        (
                            size,
                            Vec::with_capacity(size.min(secure_channel::MAX_MESSAGE)),
                        ),
                    );
                }
            } else {
                resolve(pending, id, Ok(Reply::Json(frame["value"].take())));
            }
        }
        Some("event") => {
            let name = frame["name"].as_str().unwrap_or_default().to_owned();
            on_event(ClientEvent::Event {
                name,
                payload: frame["payload"].take(),
            });
        }
        _ => {}
    }
}

/// Each window's connection, with a number that tells a stale close from
/// the current connection's.
#[derive(Default)]
pub struct RemoteClients {
    windows: Mutex<HashMap<String, (u64, Arc<Client>)>>,
    /// The host each window connects to, kept while it is offline too.
    hosts: Mutex<HashMap<String, String>>,
    next: AtomicU64,
}

impl RemoteClients {
    fn cache(&self, app: &AppHandle, label: &str) -> Option<HostCache> {
        let host = self.hosts.lock().unwrap().get(label)?.clone();
        let data = app.path().app_data_dir().ok()?;
        Some(HostCache::new(&cache::root(&data), &host, HOST_CACHE_LIMIT))
    }

    fn get(&self, label: &str) -> Result<Arc<Client>, String> {
        self.windows
            .lock()
            .unwrap()
            .get(label)
            .map(|(_, client)| client.clone())
            .ok_or_else(|| DISCONNECTED.to_string())
    }

    /// Takes the window's connection out, if it is still `generation` (any
    /// generation when `None`). The caller drops it outside the lock.
    fn take(&self, label: &str, generation: Option<u64>) -> Option<Arc<Client>> {
        let mut windows = self.windows.lock().unwrap();
        let current = windows.get(label).map(|(generation, _)| *generation)?;
        if generation.is_some_and(|generation| generation != current) {
            return None;
        }
        windows.remove(label).map(|(_, client)| client)
    }
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Target {
    /// This process's own gateway (two windows of one Loci, for development).
    Loopback,
    /// A member of this device's group, by its `deviceId`.
    Device {
        #[serde(rename = "deviceId")]
        device_id: String,
    },
    /// Any host, given its relay, connection code and key (development).
    Relay {
        relay: String,
        code: String,
        #[serde(rename = "hostKey")]
        host_key: String,
    },
}

impl Target {
    /// Whose cache this window uses: the host's device id, or what stands for it.
    fn host(&self) -> String {
        match self {
            Target::Loopback => "loopback".into(),
            Target::Device { device_id } => device_id.clone(),
            Target::Relay { host_key, .. } => host_key.clone(),
        }
    }
}

fn emit_status(app: &AppHandle, label: &str, state: &str, error: Option<String>) {
    let mut status = json!({ "state": state });
    if let Some(error) = error {
        status["error"] = json!(error);
    }
    let _ = app.emit_to(label, "remote-client-status", status);
}

/// Dials and authenticates the host; returns the channel.
async fn open(app: &AppHandle, target: Target) -> Result<SecureChannel, String> {
    let host = app.state::<RemoteHost>();
    let (device_key, group) = host.identity(app)?;
    match target {
        Target::Loopback => {
            let gateway = host
                .gateway()
                .ok_or("Remote access is off on this device")?;
            let conn = host.loopback.dial().await?;
            let trusted = [gateway.device_key.verifying_key()];
            handshake(conn, &gateway.code, &device_key, &trusted).await
        }
        Target::Device { device_id } => {
            let group = group.ok_or("This device is not in a device group")?;
            connect_to_member(group, &device_key, &device_id).await
        }
        Target::Relay {
            relay,
            code,
            host_key,
        } => {
            let code = ConnectCode::parse(&code)?;
            let host_key = STANDARD
                .decode(host_key)
                .ok()
                .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
                .and_then(|bytes| VerifyingKey::from_bytes(&bytes).ok())
                .ok_or("Invalid host key")?;
            let conn = relay_tunnel(super::normalize_relay(&relay)?, code.clone())
                .dial()
                .await?;
            handshake(conn, &code, &device_key, &[host_key]).await
        }
    }
}

fn relay_tunnel(relay: String, code: ConnectCode) -> AlmaRelayTunnel {
    AlmaRelayTunnel {
        relay,
        code,
        name: String::new(),
        registration_key: None,
    }
}

async fn handshake(
    conn: Connection,
    code: &ConnectCode,
    device_key: &SigningKey,
    trusted: &[VerifyingKey],
) -> Result<SecureChannel, String> {
    let handshake = secure_channel::connect(conn, code, device_key, trusted);
    tokio::time::timeout(CONNECT_TIMEOUT, handshake)
        .await
        .map_err(|_| "The host did not answer".to_string())?
}

/// Connects to the group member `device_id` through the relay its heartbeat
/// names, with the connection code every member derives, trusting only the
/// key the group signed for it. A host that has not yet seen this device
/// join turns the first attempt away and looks again; one retry covers that.
pub async fn connect_to_member(
    group: Arc<DeviceGroup>,
    device_key: &SigningKey,
    device_id: &str,
) -> Result<SecureChannel, String> {
    let mut member = group.find(device_id);
    if member.as_ref().is_none_or(|m| m.route.is_none()) {
        let refreshing = group.clone();
        tauri::async_runtime::spawn_blocking(move || refreshing.refresh())
            .await
            .map_err(|e| e.to_string())??;
        member = group.find(device_id);
    }
    let member = member.ok_or("That device is not in the group")?;
    let route = member
        .route
        .ok_or("That device is not hosting remote access")?;
    let code = group.connect_code(device_id);
    let mut attempt = 0;
    loop {
        let conn = relay_tunnel(route.relay.clone(), code.clone())
            .dial()
            .await?;
        match handshake(conn, &code, device_key, &[member.key]).await {
            Err(error) if attempt == 0 && error == secure_channel::CLOSED_IN_HANDSHAKE => {
                attempt += 1;
                tokio::time::sleep(MEMBER_RETRY).await;
            }
            result => return result,
        }
    }
}

#[tauri::command]
pub async fn remote_client_connect(window: WebviewWindow, target: Target) -> Result<Value, String> {
    let app = window.app_handle().clone();
    let label = window.label().to_owned();
    // Before connecting, so a window that cannot reach its host still reads what was kept for it.
    let host = target.host();
    app.state::<RemoteClients>()
        .hosts
        .lock()
        .unwrap()
        .insert(label.clone(), host);
    emit_status(&app, &label, "connecting", None);
    let channel = match open(&app, target).await {
        Ok(channel) => channel,
        Err(error) => {
            emit_status(&app, &label, "disconnected", Some(error.clone()));
            return Err(error);
        }
    };
    let host_key = STANDARD.encode(channel.peer.to_bytes());
    let clients = app.state::<RemoteClients>();
    let generation = clients.next.fetch_add(1, Ordering::Relaxed);
    let (events_app, events_label) = (app.clone(), label.clone());
    let client = Client::start(channel, move |event| match event {
        ClientEvent::Event { name, payload } => {
            let _ = events_app.emit_to(
                events_label.as_str(),
                "remote-client-event",
                json!({ "name": name, "payload": payload }),
            );
        }
        ClientEvent::Closed(error) => {
            let clients = events_app.state::<RemoteClients>();
            if let Some(client) = clients.take(&events_label, Some(generation)) {
                emit_status(&events_app, &events_label, "disconnected", error);
                drop(client);
            }
        }
    });
    let replaced = clients
        .windows
        .lock()
        .unwrap()
        .insert(label.clone(), (generation, Arc::new(client)));
    drop(replaced);
    emit_status(&app, &label, "connected", None);
    Ok(json!({ "hostKey": host_key }))
}

#[tauri::command]
pub async fn remote_client_call(
    window: WebviewWindow,
    cmd: String,
    args: Option<Value>,
    request_id: Option<String>,
) -> Result<tauri::ipc::Response, String> {
    let clients = window.state::<RemoteClients>();
    let client = clients.get(window.label());
    let cache = clients.cache(window.app_handle(), window.label());
    let args = args.unwrap_or_else(|| json!({}));
    match call_or_kept(client, cache, cmd, args, request_id).await? {
        Reply::Json(value) => Ok(tauri::ipc::Response::new(value.to_string())),
        Reply::Bytes(bytes) => Ok(tauri::ipc::Response::new(bytes)),
    }
}

/// Asks the host, keeping what a `Read` command returns; without a
/// connection, answers a `Read` command from what was kept.
async fn call_or_kept(
    client: Result<Arc<Client>, String>,
    cache: Option<HostCache>,
    cmd: String,
    args: Value,
    request_id: Option<String>,
) -> Result<Reply, String> {
    let kept = (!cmd.contains('.') && class_of(&cmd) == Some(CommandClass::Read))
        .then_some(cache)
        .flatten();
    let key = cache::key(&cmd, &args);
    let result = match client {
        Ok(client) => client.call(&cmd, args, request_id).await,
        Err(error) => Err(error),
    };
    let Some(kept) = kept else {
        return result;
    };
    match result {
        Ok(reply) => {
            let (reply, copy) = match reply {
                Reply::Json(value) => (Reply::Json(value.clone()), Reply::Json(value)),
                Reply::Bytes(bytes) => (Reply::Bytes(bytes.clone()), Reply::Bytes(bytes)),
            };
            tauri::async_runtime::spawn_blocking(move || kept.put(&key, &copy));
            Ok(reply)
        }
        Err(error) if error == DISCONNECTED => {
            tauri::async_runtime::spawn_blocking(move || kept.get(&key))
                .await
                .ok()
                .flatten()
                .ok_or_else(|| NOT_KEPT.to_string())
        }
        Err(error) => Err(error),
    }
}

/// Keeps JSON for this window's host on this device, such as its session mirror.
#[tauri::command]
pub async fn remote_client_cache_put(window: WebviewWindow, key: String, value: Value) {
    if let Some(cache) = window
        .state::<RemoteClients>()
        .cache(window.app_handle(), window.label())
    {
        let _ = tauri::async_runtime::spawn_blocking(move || {
            cache.put(&format!("window\0{key}"), &Reply::Json(value))
        })
        .await;
    }
}

/// JSON kept for this window's host, or `null`.
#[tauri::command]
pub async fn remote_client_cache_get(window: WebviewWindow, key: String) -> Value {
    let Some(cache) = window
        .state::<RemoteClients>()
        .cache(window.app_handle(), window.label())
    else {
        return Value::Null;
    };
    match tauri::async_runtime::spawn_blocking(move || cache.get(&format!("window\0{key}"))).await {
        Ok(Some(Reply::Json(value))) => value,
        _ => Value::Null,
    }
}

#[tauri::command]
pub async fn remote_client_subscribe(
    window: WebviewWindow,
    epoch: Option<String>,
    seq: Option<u64>,
) -> Result<(), String> {
    let client = window.state::<RemoteClients>().get(window.label())?;
    client.subscribe(epoch, seq).await
}

fn too_large() -> String {
    format!(
        "Files sent to the host can be at most {} MB",
        MAX_UPLOAD / 1024 / 1024
    )
}

/// Sends a file on this device to the host, which saves it beside pasted
/// attachments; its path there.
#[tauri::command]
pub async fn remote_client_upload(window: WebviewWindow, path: String) -> Result<String, String> {
    let client = window.state::<RemoteClients>().get(window.label())?;
    let source = std::path::PathBuf::from(&path);
    let name = source
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "file".into());
    let bytes = tauri::async_runtime::spawn_blocking(move || {
        let size = std::fs::metadata(&source)
            .map_err(|e| format!("{path}: {e}"))?
            .len();
        if size > MAX_UPLOAD as u64 {
            return Err(too_large());
        }
        std::fs::read(&source).map_err(|e| format!("{path}: {e}"))
    })
    .await
    .map_err(|e| e.to_string())??;
    match client.upload(&name, &bytes).await? {
        Reply::Json(Value::String(saved)) => Ok(saved),
        _ => Err("The host did not say where it saved the file".into()),
    }
}

#[tauri::command]
pub fn remote_client_disconnect(window: WebviewWindow) {
    let client = window.state::<RemoteClients>().take(window.label(), None);
    if client.is_some() {
        drop(client);
        emit_status(window.app_handle(), window.label(), "disconnected", None);
    }
}

pub fn window_closed(app: &AppHandle, label: &str) {
    if let Some(clients) = app.try_state::<RemoteClients>() {
        clients.hosts.lock().unwrap().remove(label);
        drop(clients.take(label, None));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::remote::gateway::{Gateway, BLOB_CHUNK};
    use crate::remote::loopback::LoopbackTunnel;
    use crate::remote::secure_channel::tests::device;
    use crate::remote::session_master::tests::{patch, recording};
    use crate::remote::session_master::FEED_BUFFER_BYTES;
    use ed25519_dalek::SigningKey;

    struct Host {
        tunnel: LoopbackTunnel,
        gateway: Arc<Gateway>,
        intents: Arc<Mutex<Vec<crate::remote::session_master::IntentEvent>>>,
    }

    /// A real gateway on a loopback tunnel, with a fake command runner and a
    /// window that only records what it is asked.
    fn host(trusts: VerifyingKey) -> Host {
        let (master, intents) = recording(FEED_BUFFER_BYTES);
        let gateway = Arc::new(Gateway {
            master,
            invoke: Box::new(|cmd, args| {
                Box::pin(async move {
                    match cmd.as_str() {
                        "read_binary_file" => Ok(Reply::Bytes(vec![9; BLOB_CHUNK + 5])),
                        _ => Ok(Reply::Json(json!({"cmd": cmd, "args": args}))),
                    }
                })
            }),
            // Answers with the name, length and a checksum of what arrived.
            save_upload: Box::new(|name, bytes| {
                Box::pin(async move {
                    let sum: u64 = bytes.iter().map(|&b| b as u64).sum();
                    Ok(Reply::Json(json!(format!(
                        "/host/{name}:{}:{sum}",
                        bytes.len()
                    ))))
                })
            }),
            code: ConnectCode::generate(),
            device_key: device(),
            trusted: Box::new(vec![trusts]),
        });
        let tunnel = LoopbackTunnel::default();
        tokio::spawn(gateway.clone().run(tunnel.listen()));
        Host {
            tunnel,
            gateway,
            intents,
        }
    }

    async fn dial(
        host: &Host,
        me: &SigningKey,
        trusted_host: VerifyingKey,
    ) -> Result<(Client, mpsc::UnboundedReceiver<ClientEvent>), String> {
        let conn = host.tunnel.dial().await?;
        let channel =
            secure_channel::connect(conn, &host.gateway.code, me, &[trusted_host][..]).await?;
        let (events, received) = mpsc::unbounded_channel();
        let client = Client::start(channel, move |event| {
            let _ = events.send(event);
        });
        Ok((client, received))
    }

    #[tokio::test]
    async fn answers_reads_from_what_was_kept_while_offline_and_refuses_writes() {
        let me = device();
        let host = host(me.verifying_key());
        let (client, _events) = dial(&host, &me, host.gateway.device_key.verifying_key())
            .await
            .unwrap();
        let client = Arc::new(client);
        let root = std::env::temp_dir().join(format!("loci-offline-{}", uuid::Uuid::new_v4()));
        let cache = || Some(HostCache::new(&root, "laptop", HOST_CACHE_LIMIT));
        let offline = || Err(DISCONNECTED.to_string());

        let read = |cmd: &str| (cmd.to_string(), json!({"id": "n1"}));
        let (cmd, args) = read("notes_get");
        let Reply::Json(online) = call_or_kept(Ok(client.clone()), cache(), cmd, args, None)
            .await
            .unwrap()
        else {
            panic!("expected JSON");
        };
        call_or_kept(
            Ok(client.clone()),
            cache(),
            "read_binary_file".into(),
            json!({"path": "/a.pdf"}),
            None,
        )
        .await
        .unwrap();
        // Keeping happens beside the reply; wait for it.
        for _ in 0..100 {
            if cache()
                .unwrap()
                .get(&cache::key("read_binary_file", &json!({"path": "/a.pdf"})))
                .is_some()
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }

        let (cmd, args) = read("notes_get");
        let Reply::Json(kept) = call_or_kept(offline(), cache(), cmd, args, None)
            .await
            .unwrap()
        else {
            panic!("expected JSON");
        };
        assert_eq!(kept, online);
        let bytes = call_or_kept(
            offline(),
            cache(),
            "read_binary_file".into(),
            json!({"path": "/a.pdf"}),
            None,
        )
        .await;
        assert!(matches!(bytes, Ok(Reply::Bytes(bytes)) if bytes == vec![9; BLOB_CHUNK + 5]));
        let never = call_or_kept(
            offline(),
            cache(),
            "notes_get".into(),
            json!({"id": "other"}),
            None,
        )
        .await;
        assert_eq!(never.err().unwrap(), NOT_KEPT);
        let write = call_or_kept(offline(), cache(), "notes_upsert".into(), json!({}), None).await;
        assert_eq!(write.err().unwrap(), DISCONNECTED);
        let intent =
            call_or_kept(offline(), cache(), "session.submit".into(), json!([]), None).await;
        assert_eq!(intent.err().unwrap(), DISCONNECTED);
        cache::clear(&root, None);
    }

    #[tokio::test]
    async fn uploads_a_file_in_chunks_and_refuses_one_too_large() {
        let me = device();
        let host = host(me.verifying_key());
        let (client, _events) = dial(&host, &me, host.gateway.device_key.verifying_key())
            .await
            .unwrap();
        let bytes: Vec<u8> = (0..BLOB_CHUNK * 2 + 7).map(|i| (i % 251) as u8).collect();
        let sum: u64 = bytes.iter().map(|&b| b as u64).sum();
        let Reply::Json(saved) = client.upload("scan.pdf", &bytes).await.unwrap() else {
            panic!("expected JSON");
        };
        assert_eq!(
            saved,
            json!(format!("/host/scan.pdf:{}:{sum}", bytes.len()))
        );
        let Reply::Json(empty) = client.upload("empty.txt", &[]).await.unwrap() else {
            panic!("expected JSON");
        };
        assert_eq!(empty, json!("/host/empty.txt:0:0"));
        let too_large = client.upload("big.mov", &vec![0; MAX_UPLOAD + 1]).await;
        assert!(too_large.err().unwrap().contains("100 MB"));
    }

    #[tokio::test]
    async fn calls_subscribes_and_disconnects_through_a_real_gateway() {
        let me = device();
        let host = host(me.verifying_key());
        let (client, mut events) = dial(&host, &me, host.gateway.device_key.verifying_key())
            .await
            .unwrap();

        let Reply::Json(value) = client
            .call("notes_get", json!({"id": "n1"}), None)
            .await
            .unwrap()
        else {
            panic!("expected JSON");
        };
        assert_eq!(value, json!({"cmd": "notes_get", "args": {"id": "n1"}}));
        let Reply::Bytes(bytes) = client
            .call("read_binary_file", json!({"path": "/a.pdf"}), None)
            .await
            .unwrap()
        else {
            panic!("expected bytes");
        };
        assert_eq!(bytes, vec![9; BLOB_CHUNK + 5]);
        assert_eq!(
            client
                .call("harness_spawn", json!({}), None)
                .await
                .err()
                .unwrap(),
            "harness_spawn is not available to connected devices"
        );

        let master = host.gateway.master.clone();
        master
            .publish(&json!({"kind": "snapshot", "epoch": "e1", "seq": 0}))
            .unwrap();
        master.publish(&patch("e1", 1)).unwrap();
        client.subscribe(Some("e1".into()), Some(0)).await.unwrap();
        let Some(ClientEvent::Event { name, payload }) = events.recv().await else {
            panic!("expected a feed event");
        };
        assert_eq!(
            (name.as_str(), &payload["seq"]),
            ("session.feed", &json!(1))
        );
        master.publish(&patch("e1", 2)).unwrap();
        let Some(ClientEvent::Event { payload, .. }) = events.recv().await else {
            panic!("expected a live feed event");
        };
        assert_eq!(payload["seq"], 2);

        drop(client);
        // The host lets the window know the device went away.
        let cleared = loop {
            if let Some(event) = host.intents.lock().unwrap().pop() {
                break event;
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        };
        assert_eq!(
            (cleared.name.as_str(), &cleared.args),
            ("session.view", &json!([[]]))
        );
    }

    #[tokio::test]
    async fn refuses_a_host_whose_key_it_does_not_trust() {
        let me = device();
        let host = host(me.verifying_key());
        let result = dial(&host, &me, device().verifying_key()).await;
        assert_eq!(result.err().unwrap(), "The host is not a trusted device");
    }

    #[tokio::test]
    async fn reports_the_end_of_the_connection_and_fails_later_calls() {
        let (me, host_key, code) = (device(), device(), ConnectCode::generate());
        let (trust_host, trust_me) = ([host_key.verifying_key()], [me.verifying_key()]);
        let (c, h) = Connection::pair();
        let (channel, host_end) = tokio::join!(
            secure_channel::connect(c, &code, &me, &trust_host[..]),
            secure_channel::accept(h, &code, &host_key, &trust_me[..])
        );
        let (events, mut received) = mpsc::unbounded_channel();
        let client = Client::start(channel.unwrap(), move |event| {
            let _ = events.send(event);
        });
        drop(host_end);
        assert!(matches!(
            received.recv().await,
            Some(ClientEvent::Closed(None))
        ));
        assert_eq!(
            client
                .call("notes_get", json!({}), None)
                .await
                .err()
                .unwrap(),
            DISCONNECTED
        );
    }

    /// Against a real registry and relay. Start both, then:
    /// `LOCI_TEST_REGISTRY=http://127.0.0.1:<port> LOCI_TEST_RELAY=ws://127.0.0.1:<port>
    /// cargo test -p loci through_the_registry -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn a_member_connects_through_the_registry_until_removed() {
        use crate::remote::alma_relay::AlmaRelayTunnel;
        use crate::remote::device_group::{now_ms, parse_invite, Identity, Registry, Route};
        use crate::remote::tunnel::TunnelStatus;
        use rand_core::{OsRng, RngCore};

        async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> T {
            tokio::task::spawn_blocking(work).await.unwrap()
        }

        let registry = Registry {
            url: std::env::var("LOCI_TEST_REGISTRY").expect("LOCI_TEST_REGISTRY"),
            key: std::env::var("LOCI_TEST_REGISTRY_KEY").ok(),
        };
        let relay = std::env::var("LOCI_TEST_RELAY").expect("LOCI_TEST_RELAY");

        // A creates the group.
        let mut secret = [0; 32];
        OsRng.fill_bytes(&mut secret);
        let a_key = device();
        let a = Arc::new(DeviceGroup::new(secret, a_key.clone(), registry.clone()));
        let joining = a.clone();
        blocking(move || joining.join("Laptop")).await.unwrap();

        // B joins with the text A shows.
        let (b_secret, b_registry) = parse_invite(&a.invite()).unwrap();
        assert_eq!(b_registry.as_deref(), Some(registry.url.as_str()));
        let b_key = device();
        let b = Arc::new(DeviceGroup::new(
            b_secret,
            b_key.clone(),
            Registry {
                url: b_registry.unwrap(),
                key: registry.key.clone(),
            },
        ));
        let joining = b.clone();
        blocking(move || joining.join("Mac mini")).await.unwrap();

        // A hosts on the relay, trusting its group, and says where it is.
        let code = a.connect_code(&a.device_id);
        let (master, _) = recording(FEED_BUFFER_BYTES);
        let gateway = Arc::new(Gateway {
            master,
            invoke: Box::new(|cmd, _| {
                Box::pin(async move { Ok(Reply::Json(json!({ "ran": cmd }))) })
            }),
            save_upload: Box::new(|_, _| {
                Box::pin(async { Ok(Reply::Json(json!("/host/upload"))) })
            }),
            code: code.clone(),
            device_key: a_key,
            trusted: Box::new(a.clone()),
        });
        let tunnel = AlmaRelayTunnel {
            relay: relay.clone(),
            code: code.clone(),
            name: "Laptop".into(),
            registration_key: None,
        };
        let mut listener = tunnel.listen();
        tokio::time::timeout(
            Duration::from_secs(10),
            listener.status.wait_for(|s| *s == TunnelStatus::Online),
        )
        .await
        .unwrap()
        .unwrap();
        tokio::spawn(gateway.run(listener));
        let route = Route {
            relay,
            token: code.routing_token(),
        };
        let beating = a.clone();
        blocking(move || beating.heartbeat(Some(&route)))
            .await
            .unwrap();

        // B sees A online, reachable, and connects. A has not looked at the
        // list since B joined, so this also exercises the look-again retry.
        let refreshing = b.clone();
        blocking(move || refreshing.refresh()).await.unwrap();
        let laptop = b.find(&a.device_id).expect("B lists A");
        assert!(laptop.online(now_ms()) && laptop.route.is_some());
        let started = std::time::Instant::now();
        let channel = connect_to_member(b.clone(), &b_key, &a.device_id)
            .await
            .unwrap();
        println!("B connected to A in {:?}", started.elapsed());
        let client = Client::start(channel, |_| {});
        let Reply::Json(value) = client.call("notes_list", json!({}), None).await.unwrap() else {
            panic!("expected JSON");
        };
        assert_eq!(value, json!({ "ran": "notes_list" }));
        drop(client);

        // A removes B; B is turned away from then on.
        let removing = a.clone();
        let b_id = b.device_id.clone();
        blocking(move || removing.remove(&b_id)).await.unwrap();
        let refused = connect_to_member(b.clone(), &b_key, &a.device_id).await;
        assert_eq!(refused.err().unwrap(), secure_channel::CLOSED_IN_HANDSHAKE);
        let refreshing = b.clone();
        blocking(move || refreshing.refresh()).await.unwrap();
        assert!(b.find(&b.device_id).is_none());
        // Removal is permanent: the same key cannot join again.
        let rejoining = b.clone();
        assert!(blocking(move || rejoining.join("Mac mini")).await.is_err());
    }
}
