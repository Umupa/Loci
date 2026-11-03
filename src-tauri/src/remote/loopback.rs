//! A tunnel inside one process: two windows of the same Loci, or a test, act
//! as host and client. It still runs the secure channel on top, so the code
//! path is the one a relay or tailnet client takes.

use std::sync::{Arc, Mutex};

use tokio::sync::{mpsc, watch};

use super::tunnel::{Connection, Listener, Tunnel, TunnelStatus, CONNECTION_DEPTH};

#[derive(Clone, Default)]
pub struct LoopbackTunnel {
    host: Arc<Mutex<Option<mpsc::Sender<Connection>>>>,
}

impl Tunnel for LoopbackTunnel {
    fn listen(&self) -> Listener {
        let (tx, rx) = mpsc::channel(CONNECTION_DEPTH);
        *self.host.lock().unwrap() = Some(tx);
        let (_, status) = watch::channel(TunnelStatus::Online);
        Listener::new(rx, status, None)
    }

    async fn dial(&self) -> Result<Connection, String> {
        let host = self.host.lock().unwrap().clone();
        let host = host.ok_or("No host is listening")?;
        let (client, server) = Connection::pair();
        host.send(server)
            .await
            .map_err(|_| "No host is listening".to_string())?;
        Ok(client)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_dialled_connection_reaches_the_listener() {
        let tunnel = LoopbackTunnel::default();
        assert!(tunnel.dial().await.is_err());
        let mut listener = tunnel.listen();
        let mut client = tunnel.dial().await.unwrap();
        let mut host = listener.accept().await.unwrap();
        client.send(b"ping".to_vec()).await.unwrap();
        assert_eq!(host.recv().await.unwrap(), b"ping");
        host.send(b"pong".to_vec()).await.unwrap();
        assert_eq!(client.recv().await.unwrap(), b"pong");
        drop(listener);
        assert!(tunnel.dial().await.is_err());
    }
}
