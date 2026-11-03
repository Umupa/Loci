//! A tunnel carries opaque byte messages between a host and its clients. The
//! host side hands each client that reaches it to the layer above as a
//! [`Connection`]; the client side gets one from [`Tunnel::dial`]. What the
//! bytes mean (the secure channel, then the gateway's frames) is not the
//! tunnel's business, so relay, loopback and a later tailnet tunnel are
//! interchangeable.

use std::future::Future;

use serde::Serialize;
use tokio::sync::{mpsc, watch};
use tokio::task::JoinHandle;

/// Messages either side may queue before the sender waits.
pub const CONNECTION_DEPTH: usize = 256;

pub trait Tunnel {
    /// Starts hosting: clients arrive on the listener until it is dropped.
    /// Call it inside a Tokio runtime.
    fn listen(&self) -> Listener;
    /// Opens a connection to the host, as a client.
    fn dial(&self) -> impl Future<Output = Result<Connection, String>> + Send;
}

/// One client's two-way message stream. Dropping either end closes both
/// directions: the other end's `recv` returns `None` and its `send` fails.
pub struct Connection {
    tx: mpsc::Sender<Vec<u8>>,
    rx: mpsc::Receiver<Vec<u8>>,
}

impl Connection {
    /// Two ends joined to each other.
    pub fn pair() -> (Connection, Connection) {
        let (a_tx, a_rx) = mpsc::channel(CONNECTION_DEPTH);
        let (b_tx, b_rx) = mpsc::channel(CONNECTION_DEPTH);
        (
            Connection { tx: a_tx, rx: b_rx },
            Connection { tx: b_tx, rx: a_rx },
        )
    }

    pub async fn send(&self, message: Vec<u8>) -> Result<(), String> {
        self.tx
            .send(message)
            .await
            .map_err(|_| "Connection closed".to_string())
    }

    /// The next message, or `None` once the other end has closed.
    pub async fn recv(&mut self) -> Option<Vec<u8>> {
        self.rx.recv().await
    }

    pub fn close(self) {}

    /// The halves, for reading and writing from different tasks.
    pub fn split(self) -> (mpsc::Sender<Vec<u8>>, mpsc::Receiver<Vec<u8>>) {
        (self.tx, self.rx)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "state", rename_all = "camelCase")]
pub enum TunnelStatus {
    Connecting,
    Online,
    /// Lost or never reached the tunnel; trying again.
    Retrying {
        attempt: u32,
    },
    /// Gave up for good, for example because another host took the code.
    Stopped {
        reason: String,
    },
}

/// The host side of a running tunnel. Dropping it stops the tunnel.
pub struct Listener {
    pub status: watch::Receiver<TunnelStatus>,
    incoming: mpsc::Receiver<Connection>,
    task: Option<JoinHandle<()>>,
}

impl Listener {
    pub(super) fn new(
        incoming: mpsc::Receiver<Connection>,
        status: watch::Receiver<TunnelStatus>,
        task: Option<JoinHandle<()>>,
    ) -> Self {
        Self {
            status,
            incoming,
            task,
        }
    }

    /// The next client, or `None` once the tunnel has stopped.
    pub async fn accept(&mut self) -> Option<Connection> {
        self.incoming.recv().await
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        if let Some(task) = &self.task {
            task.abort();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn closing_one_end_closes_both_directions() {
        let (a, mut b) = Connection::pair();
        a.send(b"hi".to_vec()).await.unwrap();
        assert_eq!(b.recv().await.as_deref(), Some(&b"hi"[..]));
        a.close();
        assert_eq!(b.recv().await, None);
        assert!(b.send(vec![1]).await.is_err());
    }
}
