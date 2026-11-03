//! A tunnel through an alma-relay (Node or Cloudflare edition). The host dials
//! out and registers the hash of its routing token; clients reach it at
//! `/c/<token>/__loci__`, and the relay bridges each client WebSocket over the
//! host's socket. The wire protocol is alma-relay's `docs/PROTOCOL.md`; this
//! side speaks protocol 2 and falls back to 1 on older relays.
//!
//! Only the bridged WebSockets on [`CLIENT_PATH`] are served. Plain HTTP
//! requests (`hreq`) get 403 and other paths `werr`: everything Loci sends is
//! end-to-end encrypted above this layer, so anything else could only have
//! come from the relay itself.

use std::collections::HashMap;
use std::time::Duration;

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::json;
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::tungstenite::Message;

use super::secure_channel::ConnectCode;
use super::tunnel::{Connection, Listener, Tunnel, TunnelStatus, CONNECTION_DEPTH};

pub const CLIENT_PATH: &str = "/__loci__";
const PROTOCOL: u8 = 2;
const MAX_BACKOFF: Duration = Duration::from_secs(60);
/// Cloudflare drops a WebSocket after 100 s without traffic and the relay
/// never pings, so each end pings on its own; the pongs keep it alive.
const PING_EVERY: Duration = Duration::from_secs(30);
/// This much silence, pongs included, means the socket is dead.
const IDLE_TIMEOUT: Duration = Duration::from_secs(90);
/// A dial that hangs, as one through a stalled proxy can, is given up.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

/// Binary frame kinds (protocol 2).
const WBIN: u8 = 3;
const WTEXT: u8 = 4;

#[derive(Clone)]
pub struct AlmaRelayTunnel {
    /// `wss://relay.example.com`, or `ws://127.0.0.1:8787` for a local relay.
    pub relay: String,
    pub code: ConnectCode,
    /// Shown in the relay's logs only.
    pub name: String,
    /// `RELAY_REGISTRATION_KEY` or a signed relay token, if the relay wants one.
    pub registration_key: Option<String>,
}

impl Tunnel for AlmaRelayTunnel {
    fn listen(&self) -> Listener {
        let (incoming_tx, incoming) = mpsc::channel(CONNECTION_DEPTH);
        let (status_tx, status) = watch::channel(TunnelStatus::Connecting);
        let task = tokio::spawn(host(self.clone(), incoming_tx, status_tx));
        Listener::new(incoming, status, Some(task))
    }

    async fn dial(&self) -> Result<Connection, String> {
        let url = format!(
            "{}/c/{}{CLIENT_PATH}",
            self.relay.trim_end_matches('/'),
            self.code.routing_token()
        );
        let (socket, _) = connect(&url)
            .await
            .map_err(|error| format!("Could not reach the relay: {error}"))?;
        let (client, inner) = Connection::pair();
        let (tx, mut rx) = inner.split();
        tokio::spawn(async move {
            let (mut sink, mut stream) = socket.split();
            let mut ping = pings();
            loop {
                tokio::select! {
                    _ = ping.tick() => {
                        if sink.send(Message::Ping(Default::default())).await.is_err() {
                            break;
                        }
                    }
                    outgoing = rx.recv() => match outgoing {
                        Some(data) => {
                            if sink.send(Message::binary(data)).await.is_err() {
                                break;
                            }
                        }
                        None => {
                            let _ = sink.close().await;
                            break;
                        }
                    },
                    incoming = tokio::time::timeout(IDLE_TIMEOUT, stream.next()) => {
                        let data = match incoming {
                            Ok(Some(Ok(Message::Binary(data)))) => data.to_vec(),
                            Ok(Some(Ok(Message::Text(text)))) => text.as_bytes().to_vec(),
                            Ok(Some(Ok(Message::Close(_))) | Some(Err(_)) | None) | Err(_) => break,
                            Ok(Some(Ok(_))) => continue,
                        };
                        if tx.send(data).await.is_err() {
                            break;
                        }
                    }
                }
            }
        });
        Ok(client)
    }
}

/// Keeps the host registered, redialling with backoff, until told to stop.
async fn host(
    tunnel: AlmaRelayTunnel,
    incoming: mpsc::Sender<Connection>,
    status: watch::Sender<TunnelStatus>,
) {
    let mut attempt = 0;
    loop {
        match serve(&tunnel, &incoming, &status).await {
            End::Stop(reason) => {
                status.send_replace(TunnelStatus::Stopped { reason });
                return;
            }
            End::Retry { registered } => {
                if registered {
                    attempt = 0;
                }
                attempt += 1;
                status.send_replace(TunnelStatus::Retrying { attempt });
                tokio::time::sleep(backoff(attempt)).await;
            }
            End::Replaced => {
                // Usually this host's own earlier socket, left half-open by a
                // flaky network; a minute apart, two hosts with one code do
                // not fight over it.
                attempt = 0;
                status.send_replace(TunnelStatus::Retrying { attempt: 1 });
                tokio::time::sleep(MAX_BACKOFF).await;
            }
        }
    }
}

fn backoff(attempt: u32) -> Duration {
    Duration::from_secs(1u64 << attempt.saturating_sub(1).min(6)).min(MAX_BACKOFF)
}

enum End {
    Retry {
        registered: bool,
    },
    /// Another socket registered the same code.
    Replaced,
    Stop(String),
}

async fn connect(
    url: &str,
) -> Result<
    (
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        tokio_tungstenite::tungstenite::handshake::client::Response,
    ),
    String,
> {
    match tokio::time::timeout(CONNECT_TIMEOUT, tokio_tungstenite::connect_async(url)).await {
        Ok(result) => result.map_err(|error| error.to_string()),
        Err(_) => Err("timed out".into()),
    }
}

/// Ticks every [`PING_EVERY`], the first one a period from now.
fn pings() -> tokio::time::Interval {
    let start = tokio::time::Instant::now() + PING_EVERY;
    let mut interval = tokio::time::interval_at(start, PING_EVERY);
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    interval
}

/// One agent socket, from dial to close.
async fn serve(
    tunnel: &AlmaRelayTunnel,
    incoming: &mpsc::Sender<Connection>,
    status: &watch::Sender<TunnelStatus>,
) -> End {
    let url = format!(
        "{}/agent?th={}",
        tunnel.relay.trim_end_matches('/'),
        tunnel.code.token_hash()
    );
    let Ok((socket, _)) = connect(&url).await else {
        return End::Retry { registered: false };
    };
    let (mut sink, mut stream) = socket.split();
    let mut register = json!({
        "t": "register",
        "tokenHash": tunnel.code.token_hash(),
        "name": tunnel.name,
        "ver": env!("CARGO_PKG_VERSION"),
        "proto": PROTOCOL,
    });
    if let Some(key) = &tunnel.registration_key {
        register["key"] = json!(key);
    }
    if sink
        .send(Message::text(register.to_string()))
        .await
        .is_err()
    {
        return End::Retry { registered: false };
    }

    // Set once `registered` arrives.
    let mut proto: Option<u8> = None;
    let mut refusal: Option<String> = None;
    let mut sockets: HashMap<String, mpsc::Sender<Vec<u8>>> = HashMap::new();
    // Each bridged socket's outgoing messages; `None` when the host closed it.
    // A fresh channel per agent socket, so a stale connection can never write
    // into a later socket that reuses its id.
    let (out_tx, mut out_rx) = mpsc::channel::<(String, Option<Vec<u8>>)>(CONNECTION_DEPTH);
    let mut ping = pings();

    loop {
        let message = tokio::select! {
            _ = ping.tick() => {
                if sink.send(Message::Ping(Default::default())).await.is_err() {
                    return End::Retry { registered: proto.is_some() };
                }
                continue;
            }
            message = tokio::time::timeout(IDLE_TIMEOUT, stream.next()) => match message {
                Ok(Some(Ok(message))) => message,
                Ok(_) | Err(_) => return End::Retry { registered: proto.is_some() },
            },
            Some((id, data)) = out_rx.recv() => {
                let frame = match data {
                    Some(data) if proto >= Some(2) => Message::binary(encode_binary(WBIN, &id, &data)),
                    Some(data) => Message::text(json!({"t": "wmsg", "id": id, "b": STANDARD.encode(data)}).to_string()),
                    None if sockets.remove(&id).is_some() => {
                        Message::text(json!({"t": "wclose", "id": id, "code": 1000}).to_string())
                    }
                    None => continue,
                };
                if sink.send(frame).await.is_err() {
                    return End::Retry { registered: proto.is_some() };
                }
                continue;
            }
        };

        let mut replies = Vec::new();
        match message {
            Message::Binary(bytes) => {
                if let Some((kind, id, data)) = decode_binary(&bytes) {
                    if kind == WBIN || kind == WTEXT {
                        deliver(&mut sockets, &mut replies, id, data.to_vec());
                    }
                }
            }
            Message::Text(text) => match serde_json::from_str::<RelayFrame>(&text) {
                Ok(RelayFrame::Registered { proto: offered }) => {
                    proto = Some(offered.unwrap_or(1));
                    status.send_replace(TunnelStatus::Online);
                }
                Ok(RelayFrame::Error { message }) => refusal = Some(message),
                Ok(RelayFrame::Hreq { id }) => {
                    replies.push(json!({"t": "hres", "id": id, "status": 403, "headers": {}}));
                    replies.push(json!({"t": "hend", "id": id}));
                }
                Ok(RelayFrame::Wopen { id, path }) => {
                    if path.split('?').next() != Some(CLIENT_PATH) {
                        replies.push(json!({"t": "werr", "id": id, "message": "Not found"}));
                    } else {
                        let (upper, inner) = Connection::pair();
                        let (to_upper, mut from_upper) = inner.split();
                        sockets.insert(id.clone(), to_upper);
                        let out = out_tx.clone();
                        let forward_id = id.clone();
                        tokio::spawn(async move {
                            while let Some(data) = from_upper.recv().await {
                                if out.send((forward_id.clone(), Some(data))).await.is_err() {
                                    return;
                                }
                            }
                            let _ = out.send((forward_id, None)).await;
                        });
                        replies.push(json!({"t": "wopened", "id": id}));
                        if incoming.send(upper).await.is_err() {
                            return End::Stop("The tunnel was stopped".into());
                        }
                    }
                }
                Ok(RelayFrame::Wmsg { id, s, b }) => {
                    let data = match (s, b) {
                        (Some(text), _) => Some(text.into_bytes()),
                        (None, Some(b64)) => STANDARD.decode(b64).ok(),
                        (None, None) => None,
                    };
                    if let Some(data) = data {
                        deliver(&mut sockets, &mut replies, &id, data);
                    }
                }
                Ok(RelayFrame::Wclose { id }) => {
                    sockets.remove(&id);
                }
                Ok(RelayFrame::Other) | Err(_) => {}
            },
            Message::Close(frame) => {
                let code = frame.map(|frame| (u16::from(frame.code), frame.reason.to_string()));
                return close_outcome(code, refusal, proto.is_some());
            }
            _ => {}
        }
        for reply in replies {
            if sink.send(Message::text(reply.to_string())).await.is_err() {
                return End::Retry {
                    registered: proto.is_some(),
                };
            }
        }
    }
}

/// Hands a client's message to its connection. A connection that has fallen
/// a whole queue behind is closed rather than waited for: waiting would stall
/// every other client on this socket, and could deadlock against the same
/// connection's replies.
fn deliver(
    sockets: &mut HashMap<String, mpsc::Sender<Vec<u8>>>,
    replies: &mut Vec<serde_json::Value>,
    id: &str,
    data: Vec<u8>,
) {
    let Some(socket) = sockets.get(id) else {
        return;
    };
    if socket.try_send(data).is_err() {
        sockets.remove(id);
        replies.push(json!({"t": "wclose", "id": id, "code": 1008, "reason": "Too far behind"}));
    }
}

fn close_outcome(code: Option<(u16, String)>, refusal: Option<String>, registered: bool) -> End {
    let reason = |fallback: &str| refusal.clone().unwrap_or_else(|| fallback.to_string());
    match code.map(|(code, _)| code) {
        Some(4000) => End::Replaced,
        Some(4002) => End::Stop(reason("The relay rejected the token hash")),
        Some(4003) => End::Stop(reason("The relay registration key is wrong")),
        Some(4401) => End::Stop(reason("The relay requires a valid relay token")),
        _ => End::Retry { registered },
    }
}

#[derive(Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
enum RelayFrame {
    Registered {
        proto: Option<u8>,
    },
    Error {
        message: String,
    },
    Hreq {
        id: String,
    },
    Wopen {
        id: String,
        path: String,
    },
    Wmsg {
        id: String,
        s: Option<String>,
        b: Option<String>,
    },
    Wclose {
        id: String,
    },
    #[serde(other)]
    Other,
}

/// `[kind:u8][idLength:u8][id:utf8][payload]`
fn encode_binary(kind: u8, id: &str, payload: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(2 + id.len() + payload.len());
    frame.push(kind);
    frame.push(id.len() as u8);
    frame.extend_from_slice(id.as_bytes());
    frame.extend_from_slice(payload);
    frame
}

fn decode_binary(frame: &[u8]) -> Option<(u8, &str, &[u8])> {
    let (&kind, rest) = frame.split_first()?;
    let (&len, rest) = rest.split_first()?;
    let len = usize::from(len);
    if rest.len() < len {
        return None;
    }
    let id = std::str::from_utf8(&rest[..len]).ok()?;
    Some((kind, id, &rest[len..]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_frames_round_trip() {
        let frame = encode_binary(WBIN, "w12", &[0, 159, 146, 150]);
        assert_eq!(frame, [3, 3, b'w', b'1', b'2', 0, 159, 146, 150]);
        assert_eq!(
            decode_binary(&frame),
            Some((WBIN, "w12", &[0, 159, 146, 150][..]))
        );
        assert_eq!(
            decode_binary(&encode_binary(WTEXT, "w1", "héllo".as_bytes())),
            Some((WTEXT, "w1", "héllo".as_bytes()))
        );
        assert_eq!(decode_binary(&[3, 9, b'w']), None);
        assert_eq!(decode_binary(&[3]), None);
    }

    #[test]
    fn reads_relay_frames() {
        let frame = |text: &str| serde_json::from_str::<RelayFrame>(text).unwrap();
        assert!(matches!(
            frame(r#"{"t":"registered","proto":2}"#),
            RelayFrame::Registered { proto: Some(2) }
        ));
        assert!(matches!(
            frame(r#"{"t":"registered"}"#),
            RelayFrame::Registered { proto: None }
        ));
        assert!(matches!(
            frame(r#"{"t":"wopen","id":"w1","path":"/__loci__"}"#),
            RelayFrame::Wopen { .. }
        ));
        assert!(matches!(
            frame(r#"{"t":"wmsg","id":"w1","b":"AAE="}"#),
            RelayFrame::Wmsg {
                s: None,
                b: Some(_),
                ..
            }
        ));
        assert!(matches!(
            frame(r#"{"t":"hreq","id":"h1","method":"GET","path":"/","headers":{}}"#),
            RelayFrame::Hreq { .. }
        ));
        assert!(matches!(
            frame(r#"{"t":"pushed","id":"p1"}"#),
            RelayFrame::Other
        ));
    }

    #[test]
    fn stops_instead_of_redialling_when_the_relay_says_so() {
        assert!(matches!(
            close_outcome(Some((4000, String::new())), None, true),
            End::Replaced
        ));
        assert!(matches!(
            close_outcome(Some((4003, String::new())), Some("Invalid registration key".into()), false),
            End::Stop(reason) if reason == "Invalid registration key"
        ));
        assert!(matches!(
            close_outcome(Some((4401, String::new())), None, false),
            End::Stop(_)
        ));
        assert!(matches!(
            close_outcome(Some((1012, String::new())), None, true),
            End::Retry { registered: true }
        ));
        assert!(matches!(
            close_outcome(None, None, false),
            End::Retry { registered: false }
        ));
    }

    /// Against a real relay. Start one, then run with its address:
    /// `LOCI_TEST_RELAY=ws://127.0.0.1:<port> cargo test -p loci through_a_local_relay -- --ignored`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn end_to_end_through_a_local_relay() {
        use crate::remote::secure_channel::{accept, connect, tests::device};
        use tokio::time::timeout;

        let relay = std::env::var("LOCI_TEST_RELAY").expect("LOCI_TEST_RELAY");
        let wait = Duration::from_secs(10);
        let (host_key, client_key) = (device(), device());
        let tunnel = AlmaRelayTunnel {
            relay: relay.clone(),
            code: ConnectCode::generate(),
            name: "loci-test".into(),
            registration_key: std::env::var("LOCI_TEST_RELAY_KEY").ok(),
        };
        let mut listener = tunnel.listen();
        timeout(
            wait,
            listener.status.wait_for(|s| *s == TunnelStatus::Online),
        )
        .await
        .unwrap()
        .unwrap();

        let client = tunnel.dial().await.unwrap();
        let host = timeout(wait, listener.accept()).await.unwrap().unwrap();
        let (trust_host, trust_client) = ([host_key.verifying_key()], [client_key.verifying_key()]);
        let (client, host) = tokio::join!(
            connect(client, &tunnel.code, &client_key, &trust_host[..]),
            accept(host, &tunnel.code, &host_key, &trust_client[..])
        );
        let (mut client, mut host) = (client.unwrap(), host.unwrap());

        client.sender.send(b"hello").await.unwrap();
        assert_eq!(host.receiver.recv().await.unwrap().unwrap(), b"hello");
        // 3 MiB each way: split into 1 MiB records, whole again on arrival.
        let big: Vec<u8> = (0..3 * 1024 * 1024 + 11).map(|i| (i % 251) as u8).collect();
        let (sent, got) = tokio::join!(host.sender.send(&big), client.receiver.recv());
        sent.unwrap();
        assert_eq!(got.unwrap().unwrap(), big);
        let (sent, got) = tokio::join!(client.sender.send(&big), host.receiver.recv());
        sent.unwrap();
        assert_eq!(got.unwrap().unwrap(), big);

        // Plain HTTP to the host is refused.
        let http = format!(
            "{}/c/{}/anything",
            relay.replacen("ws", "http", 1),
            tunnel.code.routing_token()
        );
        let status = tokio::task::spawn_blocking(move || match ureq::get(&http).call() {
            Err(ureq::Error::Status(status, _)) => status,
            other => panic!(
                "expected an error status, got {:?}",
                other.map(|r| r.status())
            ),
        })
        .await
        .unwrap();
        assert_eq!(status, 403);

        // The host closing its end closes the client's.
        drop(host);
        assert_eq!(
            timeout(wait, client.receiver.recv()).await.unwrap(),
            Ok(None)
        );

        // A second host with the same code takes over; the first waits to try again.
        let _second = tunnel.listen();
        timeout(
            wait,
            listener
                .status
                .wait_for(|s| matches!(s, TunnelStatus::Retrying { .. })),
        )
        .await
        .unwrap()
        .unwrap();
    }

    /// The tunnel stays registered past Cloudflare's 100 s idle cutoff, as
    /// clients see it. Slow: `LOCI_TEST_RELAY=wss://… cargo test -p loci
    /// stays_online_while_idle -- --ignored`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn stays_online_while_idle() {
        let relay = std::env::var("LOCI_TEST_RELAY").expect("LOCI_TEST_RELAY");
        let tunnel = AlmaRelayTunnel {
            relay,
            code: ConnectCode::generate(),
            name: "loci-test".into(),
            registration_key: std::env::var("LOCI_TEST_RELAY_KEY").ok(),
        };
        let mut listener = tunnel.listen();
        listener
            .status
            .wait_for(|s| *s == TunnelStatus::Online)
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_secs(150)).await;
        assert_eq!(*listener.status.borrow(), TunnelStatus::Online);
        // Still the first socket: a redial would have passed through Retrying.
        assert!(!listener.status.has_changed().unwrap());
        let client = tunnel.dial().await.unwrap();
        assert!(
            tokio::time::timeout(Duration::from_secs(10), listener.accept())
                .await
                .unwrap()
                .is_some()
        );
        drop(client);
    }

    #[test]
    fn backs_off_exponentially_up_to_a_minute() {
        let delays: Vec<_> = (1..=8).map(|n| backoff(n).as_secs()).collect();
        assert_eq!(delays, [1, 2, 4, 8, 16, 32, 60, 60]);
    }
}
