//! End-to-end encryption between two Loci devices, on top of any tunnel.
//!
//! Each device holds an Ed25519 device key. Both ends also know the
//! connection code, a 256-bit secret the host generated. The handshake gives
//! forward secrecy (fresh X25519 keys per connection), authenticates both
//! devices by signature, and mixes the code into every key, so a relay, or
//! anyone without the code, sees only ciphertext and cannot impersonate either
//! end.
//!
//! # Handshake
//!
//! `||` is concatenation; `H` is SHA-256; `HKDF(salt, ikm, info)` is
//! HKDF-SHA256 with 32 bytes of output; `psk = HKDF(-, code, "loci handshake psk v1")`.
//! `AEAD(k, aad, m)` is AES-256-GCM with a zero nonce (each handshake key
//! seals exactly one message).
//!
//! ```text
//! 1. client -> host   msg1 = 0x01 || ec                      (33 bytes)
//!                     ec: client's ephemeral X25519 public key
//! 2. host -> client   msg2 = eh || AEAD(k_h, th1, dh || sig_h)   (144 bytes)
//!                     eh: host's ephemeral key; dh: host's device key
//!                     th1 = H("loci hs v1" || msg1 || eh)
//!                     ss = X25519(eh, ec), refused if all zero
//!                     k_h = HKDF(psk, ss, "loci hs h2c" || th1)
//!                     sig_h = Ed25519(dh, "loci host" || th1)
//! 3. client -> host   msg3 = AEAD(k_c, th2, dc || sig_c)     (112 bytes)
//!                     th2 = H(th1 || msg2)
//!                     k_c = HKDF(psk, ss, "loci hs c2h" || th1)
//!                     sig_c = Ed25519(dc, "loci client" || th2)
//! ```
//!
//! The client refuses the host unless `msg2` opens (right code), `sig_h`
//! verifies and `dh` is trusted; the host does the same for `msg3`. Then
//! `th3 = H(th2 || msg3)` and each direction gets its own key:
//! `HKDF(psk, ss, "loci c2h" || th3)` and `HKDF(psk, ss, "loci h2c" || th3)`.
//! The host's first record is empty and means "accepted": the client counts
//! as connected only once it arrives, since a host that turns the client
//! away after `msg3` just closes.
//!
//! # Records
//!
//! After the handshake every tunnel message is one record:
//! `AES-256-GCM(key, nonce = 0u32 || counter_u64_be, flag || data)`. The
//! counter is implicit and counts up from 0 in each direction, so a replayed,
//! dropped, reordered or altered record fails to open and ends the channel.
//! A message longer than [`RECORD_DATA`] is split into records with `flag = 1`
//! on all but the last, which keeps every tunnel message far below the relay's
//! 24 MiB limit.
//!
//! AES-256-GCM rather than ChaCha20-Poly1305: both hosts and clients are
//! desktops with AES instructions, where it is the faster of the two, and it is
//! what the design calls for. Nonce reuse cannot happen: keys are fresh per
//! connection and per direction, and counters never repeat.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
use tokio::sync::mpsc;
use x25519_dalek::{EphemeralSecret, PublicKey};

use super::tunnel::Connection;

const VERSION: u8 = 1;
/// What the client sees when the host turns it away.
pub const CLOSED_IN_HANDSHAKE: &str = "Connection closed during the handshake";
/// Plaintext bytes per record.
pub const RECORD_DATA: usize = 1024 * 1024;
/// Largest message either side accepts after reassembly.
pub const MAX_MESSAGE: usize = 64 * 1024 * 1024;
const TAG: usize = 16;
const MSG1: usize = 1 + 32;
const MSG2: usize = 32 + 32 + 64 + TAG;
const MSG3: usize = 32 + 64 + TAG;

/// The secret a host shares with the devices that may reach it.
#[derive(Clone)]
pub struct ConnectCode([u8; 32]);

impl ConnectCode {
    pub fn generate() -> Self {
        let mut code = [0; 32];
        OsRng.fill_bytes(&mut code);
        Self(code)
    }

    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    pub fn parse(text: &str) -> Result<Self, String> {
        let bytes = URL_SAFE_NO_PAD
            .decode(text.trim())
            .map_err(|_| "Invalid connection code")?;
        Ok(Self(
            bytes.try_into().map_err(|_| "Invalid connection code")?,
        ))
    }

    pub fn to_text(&self) -> String {
        URL_SAFE_NO_PAD.encode(self.0)
    }

    /// What clients put in the relay URL: a one-way derivation of the code,
    /// so the relay, which sees it, learns nothing that opens the channel.
    pub fn routing_token(&self) -> String {
        URL_SAFE_NO_PAD.encode(derive(None, &self.0, &[b"loci routing token v1"]))
    }

    /// What the host registers with: the relay keeps only this.
    pub fn token_hash(&self) -> String {
        Sha256::digest(self.routing_token().as_bytes())
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }

    fn psk(&self) -> [u8; 32] {
        derive(None, &self.0, &[b"loci handshake psk v1"])
    }
}

/// Which devices the host lets in, and which hosts a client accepts. The
/// device group answers this; tests use a slice of keys.
pub trait TrustedDevices {
    fn is_trusted(&self, device: &VerifyingKey) -> bool;
    /// The host turned `device` away; a list that may be stale can refresh.
    fn on_rejected(&self, _device: &VerifyingKey) {}
    /// Ticks whenever the answer to `is_trusted` may have changed, so the
    /// host can drop connections it no longer trusts. `None`: it never does.
    fn changes(&self) -> Option<tokio::sync::watch::Receiver<()>> {
        None
    }
}

impl TrustedDevices for [VerifyingKey] {
    fn is_trusted(&self, device: &VerifyingKey) -> bool {
        self.contains(device)
    }
}

impl TrustedDevices for Vec<VerifyingKey> {
    fn is_trusted(&self, device: &VerifyingKey) -> bool {
        self.contains(device)
    }
}

pub struct SecureChannel {
    /// The other end's device key.
    pub peer: VerifyingKey,
    pub sender: SecureSender,
    pub receiver: SecureReceiver,
}

pub struct SecureSender {
    tx: mpsc::Sender<Vec<u8>>,
    cipher: Aes256Gcm,
    counter: u64,
}

pub struct SecureReceiver {
    rx: mpsc::Receiver<Vec<u8>>,
    cipher: Aes256Gcm,
    counter: u64,
    partial: Vec<u8>,
}

/// Runs the client side of the handshake over `conn`.
pub async fn connect(
    conn: Connection,
    code: &ConnectCode,
    me: &SigningKey,
    trusted: &(impl TrustedDevices + ?Sized),
) -> Result<SecureChannel, String> {
    client_handshake(conn, code, me, me.verifying_key(), trusted).await
}

/// `claimed` is the device key the client presents; only tests pass one that
/// differs from `me`.
async fn client_handshake(
    mut conn: Connection,
    code: &ConnectCode,
    me: &SigningKey,
    claimed: VerifyingKey,
    trusted: &(impl TrustedDevices + ?Sized),
) -> Result<SecureChannel, String> {
    let psk = code.psk();
    let secret = EphemeralSecret::random_from_rng(OsRng);
    let mut msg1 = vec![VERSION];
    msg1.extend_from_slice(PublicKey::from(&secret).as_bytes());
    conn.send(msg1.clone()).await?;

    let msg2 = recv_exact(&mut conn, MSG2).await?;
    let host_ephemeral: [u8; 32] = msg2[..32].try_into().unwrap();
    let shared = secret.diffie_hellman(&PublicKey::from(host_ephemeral));
    if !shared.was_contributory() {
        return Err("Handshake failed".into());
    }
    let th1 = hash(&[b"loci hs v1", &msg1, &host_ephemeral]);
    let host_key = derive(Some(&psk), shared.as_bytes(), &[b"loci hs h2c", &th1]);
    let opened = open(&host_key, &th1, &msg2[32..])
        .map_err(|_| "Handshake failed: wrong connection code")?;
    let peer = verify_identity(&opened, &[b"loci host", &th1])?;
    if !trusted.is_trusted(&peer) {
        return Err("The host is not a trusted device".into());
    }

    let th2 = hash(&[&th1, &msg2]);
    let mut identity = claimed.to_bytes().to_vec();
    identity.extend_from_slice(&me.sign(&[&b"loci client"[..], &th2].concat()).to_bytes());
    let client_key = derive(Some(&psk), shared.as_bytes(), &[b"loci hs c2h", &th1]);
    let msg3 = seal(&client_key, &th2, &identity);
    conn.send(msg3.clone()).await?;

    let th3 = hash(&[&th2, &msg3]);
    let c2h = derive(Some(&psk), shared.as_bytes(), &[b"loci c2h", &th3]);
    let h2c = derive(Some(&psk), shared.as_bytes(), &[b"loci h2c", &th3]);
    let mut channel = channel(conn, peer, &c2h, &h2c);
    match channel.receiver.recv().await? {
        Some(accepted) if accepted.is_empty() => Ok(channel),
        Some(_) => Err("Malformed handshake message".into()),
        None => Err(CLOSED_IN_HANDSHAKE.into()),
    }
}

/// Runs the host side of the handshake over `conn`. Callers bound it with a
/// timeout: a client that stops halfway would otherwise hold it forever.
pub async fn accept(
    mut conn: Connection,
    code: &ConnectCode,
    me: &SigningKey,
    trusted: &(impl TrustedDevices + ?Sized),
) -> Result<SecureChannel, String> {
    let psk = code.psk();
    let msg1 = recv_exact(&mut conn, MSG1).await?;
    if msg1[0] != VERSION {
        return Err("Unsupported handshake version".into());
    }
    let client_ephemeral: [u8; 32] = msg1[1..].try_into().unwrap();
    let secret = EphemeralSecret::random_from_rng(OsRng);
    let ephemeral = PublicKey::from(&secret);
    let shared = secret.diffie_hellman(&PublicKey::from(client_ephemeral));
    if !shared.was_contributory() {
        return Err("Handshake failed".into());
    }
    let th1 = hash(&[b"loci hs v1", &msg1, ephemeral.as_bytes()]);
    let mut identity = me.verifying_key().to_bytes().to_vec();
    identity.extend_from_slice(&me.sign(&[&b"loci host"[..], &th1].concat()).to_bytes());
    let host_key = derive(Some(&psk), shared.as_bytes(), &[b"loci hs h2c", &th1]);
    let mut msg2 = ephemeral.as_bytes().to_vec();
    msg2.extend(seal(&host_key, &th1, &identity));
    conn.send(msg2.clone()).await?;

    let th2 = hash(&[&th1, &msg2]);
    let msg3 = recv_exact(&mut conn, MSG3).await?;
    let client_key = derive(Some(&psk), shared.as_bytes(), &[b"loci hs c2h", &th1]);
    let opened =
        open(&client_key, &th2, &msg3).map_err(|_| "Handshake failed: wrong connection code")?;
    let peer = verify_identity(&opened, &[b"loci client", &th2])?;
    if !trusted.is_trusted(&peer) {
        trusted.on_rejected(&peer);
        return Err("The device is not trusted".into());
    }

    let th3 = hash(&[&th2, &msg3]);
    let c2h = derive(Some(&psk), shared.as_bytes(), &[b"loci c2h", &th3]);
    let h2c = derive(Some(&psk), shared.as_bytes(), &[b"loci h2c", &th3]);
    let mut channel = channel(conn, peer, &h2c, &c2h);
    channel.sender.send(&[]).await?;
    Ok(channel)
}

impl SecureSender {
    pub async fn send(&mut self, message: &[u8]) -> Result<(), String> {
        let mut chunks = message.chunks(RECORD_DATA).peekable();
        if chunks.peek().is_none() {
            return self.send_record(0, &[]).await;
        }
        while let Some(chunk) = chunks.next() {
            let more = u8::from(chunks.peek().is_some());
            self.send_record(more, chunk).await?;
        }
        Ok(())
    }

    async fn send_record(&mut self, flag: u8, data: &[u8]) -> Result<(), String> {
        let mut plain = Vec::with_capacity(1 + data.len());
        plain.push(flag);
        plain.extend_from_slice(data);
        let record = self
            .cipher
            .encrypt(&nonce(self.counter), &plain[..])
            .map_err(|_| "Encryption failed")?;
        self.counter += 1;
        self.tx
            .send(record)
            .await
            .map_err(|_| "Connection closed".to_string())
    }
}

impl SecureReceiver {
    /// The next whole message, `Ok(None)` once the peer has closed, or an
    /// error for a record that does not open; the channel is unusable after.
    pub async fn recv(&mut self) -> Result<Option<Vec<u8>>, String> {
        loop {
            let Some(record) = self.rx.recv().await else {
                return if self.partial.is_empty() {
                    Ok(None)
                } else {
                    Err("Connection closed mid-message".into())
                };
            };
            let plain = self
                .cipher
                .decrypt(&nonce(self.counter), &record[..])
                .map_err(|_| "Rejected a record that was altered, replayed or out of order")?;
            self.counter += 1;
            let (&flag, data) = plain.split_first().ok_or("Malformed record")?;
            if self.partial.len() + data.len() > MAX_MESSAGE {
                return Err("Message too large".into());
            }
            self.partial.extend_from_slice(data);
            if flag == 0 {
                return Ok(Some(std::mem::take(&mut self.partial)));
            }
        }
    }
}

fn channel(
    conn: Connection,
    peer: VerifyingKey,
    send: &[u8; 32],
    recv: &[u8; 32],
) -> SecureChannel {
    let (tx, rx) = conn.split();
    SecureChannel {
        peer,
        sender: SecureSender {
            tx,
            cipher: Aes256Gcm::new(send.into()),
            counter: 0,
        },
        receiver: SecureReceiver {
            rx,
            cipher: Aes256Gcm::new(recv.into()),
            counter: 0,
            partial: Vec::new(),
        },
    }
}

async fn recv_exact(conn: &mut Connection, len: usize) -> Result<Vec<u8>, String> {
    let message = conn.recv().await.ok_or(CLOSED_IN_HANDSHAKE)?;
    if message.len() != len {
        return Err("Malformed handshake message".into());
    }
    Ok(message)
}

/// `key || signature` -> the key, if the signature over `signed` verifies.
fn verify_identity(opened: &[u8], signed: &[&[u8]]) -> Result<VerifyingKey, String> {
    let key: [u8; 32] = opened[..32].try_into().unwrap();
    let signature: [u8; 64] = opened[32..].try_into().unwrap();
    let key = VerifyingKey::from_bytes(&key).map_err(|_| "Invalid device key")?;
    key.verify_strict(&signed.concat(), &Signature::from_bytes(&signature))
        .map_err(|_| "The device key does not match its signature")?;
    Ok(key)
}

fn derive(salt: Option<&[u8]>, ikm: &[u8], info: &[&[u8]]) -> [u8; 32] {
    let mut out = [0; 32];
    Hkdf::<Sha256>::new(salt, ikm)
        .expand_multi_info(info, &mut out)
        .expect("32 bytes is a valid HKDF length");
    out
}

fn hash(parts: &[&[u8]]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    for part in parts {
        hasher.update(part);
    }
    hasher.finalize().into()
}

fn nonce(counter: u64) -> Nonce<aes_gcm::aead::consts::U12> {
    let mut bytes = [0; 12];
    bytes[4..].copy_from_slice(&counter.to_be_bytes());
    bytes.into()
}

fn seal(key: &[u8; 32], aad: &[u8], message: &[u8]) -> Vec<u8> {
    Aes256Gcm::new(key.into())
        .encrypt(&nonce(0), Payload { msg: message, aad })
        .expect("AES-GCM seals any handshake-sized message")
}

fn open(key: &[u8; 32], aad: &[u8], sealed: &[u8]) -> Result<Vec<u8>, aes_gcm::Error> {
    Aes256Gcm::new(key.into()).decrypt(&nonce(0), Payload { msg: sealed, aad })
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;

    pub fn device() -> SigningKey {
        SigningKey::generate(&mut OsRng)
    }

    struct Setup {
        code: ConnectCode,
        host: SigningKey,
        client: SigningKey,
    }

    impl Setup {
        fn new() -> Self {
            Self {
                code: ConnectCode::generate(),
                host: device(),
                client: device(),
            }
        }
    }

    /// Runs both sides at once over a joined pair.
    async fn handshake(
        s: &Setup,
        client_code: &ConnectCode,
        host_trusts: &[VerifyingKey],
        client_trusts: &[VerifyingKey],
    ) -> (Result<SecureChannel, String>, Result<SecureChannel, String>) {
        let (c, h) = Connection::pair();
        tokio::join!(
            connect(c, client_code, &s.client, client_trusts),
            accept(h, &s.code, &s.host, host_trusts)
        )
    }

    #[tokio::test]
    async fn devices_that_trust_each_other_talk_both_ways() {
        let s = Setup::new();
        let (client, host) = handshake(
            &s,
            &s.code,
            &[s.client.verifying_key()],
            &[s.host.verifying_key()],
        )
        .await;
        let (mut client, mut host) = (client.unwrap(), host.unwrap());
        assert_eq!(host.peer, s.client.verifying_key());
        assert_eq!(client.peer, s.host.verifying_key());

        client.sender.send(b"hello host").await.unwrap();
        assert_eq!(host.receiver.recv().await.unwrap().unwrap(), b"hello host");
        host.sender.send(b"").await.unwrap();
        assert_eq!(client.receiver.recv().await.unwrap().unwrap(), b"");

        // Larger than one record: split on the way, whole on arrival.
        let big: Vec<u8> = (0..RECORD_DATA * 2 + 7).map(|i| i as u8).collect();
        let (sent, got) = tokio::join!(host.sender.send(&big), client.receiver.recv());
        sent.unwrap();
        assert_eq!(got.unwrap().unwrap(), big);

        drop(client);
        assert_eq!(host.receiver.recv().await.unwrap(), None);
    }

    #[tokio::test]
    async fn a_wrong_connection_code_fails_both_sides() {
        let s = Setup::new();
        let (client, host) = handshake(
            &s,
            &ConnectCode::generate(),
            &[s.client.verifying_key()],
            &[s.host.verifying_key()],
        )
        .await;
        assert!(client.err().unwrap().contains("wrong connection code"));
        assert!(host.is_err());
    }

    #[tokio::test]
    async fn the_host_refuses_a_device_outside_the_group() {
        let s = Setup::new();
        let (_, host) = handshake(
            &s,
            &s.code,
            &[device().verifying_key()],
            &[s.host.verifying_key()],
        )
        .await;
        assert_eq!(host.err().unwrap(), "The device is not trusted");
    }

    #[tokio::test]
    async fn the_client_refuses_an_unknown_host() {
        let s = Setup::new();
        let (client, host) = handshake(
            &s,
            &s.code,
            &[s.client.verifying_key()],
            &[device().verifying_key()],
        )
        .await;
        assert_eq!(client.err().unwrap(), "The host is not a trusted device");
        assert!(host.is_err());
    }

    #[tokio::test]
    async fn the_host_refuses_a_device_key_the_client_does_not_hold() {
        let s = Setup::new();
        let impostor = device();
        let (c, h) = Connection::pair();
        let trusted = [s.client.verifying_key()];
        let host_key = [s.host.verifying_key()];
        let (_, host) = tokio::join!(
            client_handshake(
                c,
                &s.code,
                &impostor,
                s.client.verifying_key(),
                &host_key[..]
            ),
            accept(h, &s.code, &s.host, &trusted[..])
        );
        assert_eq!(
            host.err().unwrap(),
            "The device key does not match its signature"
        );
    }

    /// A client whose messages pass through `tamper` once the handshake is done.
    async fn tampered_channel(
        tamper: impl Fn(Vec<u8>) -> Vec<Vec<u8>> + Send + 'static,
    ) -> (SecureChannel, SecureChannel) {
        let s = Setup::new();
        let (c, wire_in) = Connection::pair();
        let (wire_out, h) = Connection::pair();
        let (out_tx, mut out_rx) = wire_out.split();
        let (in_tx, mut in_rx) = wire_in.split();
        tokio::spawn(async move {
            let mut seen = 0;
            while let Some(message) = in_rx.recv().await {
                seen += 1;
                let forwarded = if seen > 2 {
                    tamper(message)
                } else {
                    vec![message]
                };
                for message in forwarded {
                    out_tx.send(message).await.unwrap();
                }
            }
        });
        tokio::spawn(async move {
            while let Some(message) = out_rx.recv().await {
                if in_tx.send(message).await.is_err() {
                    break;
                }
            }
        });
        let (host_key, client_key) = ([s.host.verifying_key()], [s.client.verifying_key()]);
        let (client, host) = tokio::join!(
            connect(c, &s.code, &s.client, &host_key[..]),
            accept(h, &s.code, &s.host, &client_key[..])
        );
        (client.unwrap(), host.unwrap())
    }

    #[tokio::test]
    async fn an_altered_record_is_rejected() {
        let (mut client, mut host) = tampered_channel(|mut m| {
            m[3] ^= 1;
            vec![m]
        })
        .await;
        client.sender.send(b"transfer").await.unwrap();
        assert!(host.receiver.recv().await.is_err());
    }

    #[tokio::test]
    async fn a_replayed_record_is_rejected() {
        let (mut client, mut host) = tampered_channel(|m| vec![m.clone(), m]).await;
        client.sender.send(b"once").await.unwrap();
        assert_eq!(host.receiver.recv().await.unwrap().unwrap(), b"once");
        assert!(host.receiver.recv().await.is_err());
    }

    #[tokio::test]
    async fn a_reordered_record_is_rejected() {
        let held = std::sync::Mutex::new(None::<Vec<u8>>);
        let (mut client, mut host) = tampered_channel(move |m| {
            let mut held = held.lock().unwrap();
            match held.take() {
                None => {
                    *held = Some(m);
                    vec![]
                }
                Some(first) => vec![m, first],
            }
        })
        .await;
        client.sender.send(b"one").await.unwrap();
        client.sender.send(b"two").await.unwrap();
        assert!(host.receiver.recv().await.is_err());
    }

    #[test]
    fn the_routing_token_is_a_valid_relay_token_and_not_the_code() {
        let code = ConnectCode::generate();
        let token = code.routing_token();
        assert_eq!(token.len(), 43);
        assert!(token
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_'));
        assert_ne!(token, code.to_text());
        assert_eq!(code.token_hash().len(), 64);
        assert_eq!(
            ConnectCode::parse(&code.to_text()).unwrap().routing_token(),
            token
        );
        assert!(ConnectCode::parse("short").is_err());
    }
}
