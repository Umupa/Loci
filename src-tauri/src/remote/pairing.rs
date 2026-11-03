//! Pairing: a new device joins the host's group with a short code read off
//! the host's screen, instead of the group secret.
//!
//! The code has 8 Crockford base32 characters (40 bits), too few to be a key
//! itself: a relay that saw a handshake keyed by it could try every code
//! offline. So it only ever enters SPAKE2, which turns a shared password into
//! a strong key; someone without the code gets one guess per exchange, and a
//! recording of the exchange does not let anyone test a guess.
//!
//! # Rendezvous
//!
//! The host registers a temporary tunnel on its relay whose connection code
//! is HKDF of the code's first three characters; the device dials it. The
//! relay sees the routing token and could work those 15 bits out, which is
//! why they are all it gets: SPAKE2 runs on the whole code, so 25 unknown bits
//! remain against a single online guess.
//!
//! # Exchange
//!
//! `th = H("loci pair v1" || mb || ma)`; `K` is the SPAKE2 key (Ed25519
//! group, identities "loci pair host" and "loci pair client"); every key
//! below is `HKDF(-, K, label || th)`; `MAC` is HMAC-SHA256 over `th`;
//! `AEAD(k, n, m)` is AES-256-GCM with `th` as associated data and nonce `n`.
//!
//! ```text
//! 1. device -> host   mb                                   (33 bytes)
//! 2. host -> device   ma || MAC(k_confirm_host)            (65 bytes)
//! 3. device -> host   MAC(k_confirm_device)                (32 bytes)
//! 4. host -> device   AEAD(k_h2c, 0, invitation)           group secret, registry, host
//! 5. device -> host   AEAD(k_c2h, 0, {deviceId} | {error}) after joining the registry
//! 6. host -> device   AEAD(k_h2c, 1, "")                   the host has read the member list again
//! ```
//!
//! Each side refuses to go on unless the other's MAC verifies, so a wrong
//! code ends the exchange at step 2 or 3, before anything secret is sent.
//! The host serves one device per code: the first to arrive spends it,
//! whatever the outcome.

use std::future::Future;
use std::time::Duration;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::Aes256Gcm;
use hmac::{Hmac, Mac};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use spake2::{Ed25519Group, Identity, Password, Spake2};
use tokio::sync::watch;

use super::secure_channel::{derive, hash, nonce, ConnectCode, CLOSED_IN_HANDSHAKE};
use super::tunnel::{Connection, Listener, TunnelStatus};

/// How long a code waits for its device.
pub const LIFETIME: Duration = Duration::from_secs(10 * 60);
/// From the device's first message to the last, joining the registry included.
const EXCHANGE: Duration = Duration::from_secs(60);
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LEN: usize = 8;
const RENDEZVOUS_LEN: usize = 3;
const SPAKE_MESSAGE: usize = 33;
const CONFIRM: usize = 32;
const HOST: &[u8] = b"loci pair host";
const DEVICE: &[u8] = b"loci pair client";

pub const EXPIRED: &str = "The pairing code expired";
pub const WRONG_CODE: &str = "The pairing code is wrong or was already used";
pub const DEVICE_WRONG_CODE: &str = "The other device entered a wrong pairing code";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PairingCode(String);

impl PairingCode {
    pub fn generate() -> Self {
        let mut bytes = [0; CODE_LEN];
        OsRng.fill_bytes(&mut bytes);
        Self(
            bytes
                .iter()
                .map(|byte| ALPHABET[usize::from(byte & 31)] as char)
                .collect(),
        )
    }

    /// Takes the code as a person types it: any case, with spaces or dashes,
    /// and O, I or L for 0, 1 and 1.
    pub fn parse(text: &str) -> Result<Self, String> {
        let invalid = || "A pairing code has 8 letters and digits, like K7QM-2XPA".to_string();
        let mut code = String::with_capacity(CODE_LEN);
        for c in text.chars() {
            let c = match c.to_ascii_uppercase() {
                '-' => continue,
                c if c.is_whitespace() => continue,
                'O' => '0',
                'I' | 'L' => '1',
                c => c,
            };
            if !c.is_ascii() || !ALPHABET.contains(&(c as u8)) {
                return Err(invalid());
            }
            code.push(c);
        }
        if code.len() != CODE_LEN {
            return Err(invalid());
        }
        Ok(Self(code))
    }

    /// `K7QM-2XPA`.
    pub fn to_text(&self) -> String {
        format!("{}-{}", &self.0[..4], &self.0[4..])
    }

    /// The connection code of the temporary tunnel where host and device
    /// meet. From the first characters only; see the module notes.
    pub fn rendezvous(&self) -> ConnectCode {
        ConnectCode::from_bytes(derive(
            None,
            &self.0.as_bytes()[..RENDEZVOUS_LEN],
            &[b"loci pairing rendezvous v1"],
        ))
    }

    fn password(&self) -> Password {
        Password::new(self.0.as_bytes())
    }
}

/// What the host gives a device that knew the code.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Invitation {
    /// The group secret, base64url.
    pub secret: String,
    pub registry: String,
    pub registry_key: Option<String>,
    /// The host's device id and name, to connect to it once joined.
    pub host: String,
    pub name: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Joined {
    device_id: Option<String>,
    error: Option<String>,
}

struct Keys {
    transcript: [u8; 32],
    confirm_host: [u8; 32],
    confirm_device: [u8; 32],
    h2c: Aes256Gcm,
    c2h: Aes256Gcm,
}

impl Keys {
    fn new(shared: &[u8], device_message: &[u8], host_message: &[u8]) -> Self {
        let transcript = hash(&[b"loci pair v1", device_message, host_message]);
        let key = |label: &[u8]| derive(None, shared, &[label, &transcript]);
        Self {
            transcript,
            confirm_host: key(b"loci pair confirm host"),
            confirm_device: key(b"loci pair confirm device"),
            h2c: Aes256Gcm::new(&key(b"loci pair h2c").into()),
            c2h: Aes256Gcm::new(&key(b"loci pair c2h").into()),
        }
    }

    fn mac(&self, key: &[u8; 32]) -> Hmac<Sha256> {
        let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(key).expect("HMAC takes any key");
        mac.update(&self.transcript);
        mac
    }

    fn seal(&self, cipher: &Aes256Gcm, counter: u64, message: &[u8]) -> Vec<u8> {
        cipher
            .encrypt(
                &nonce(counter),
                Payload {
                    msg: message,
                    aad: &self.transcript,
                },
            )
            .expect("AES-GCM seals any pairing message")
    }

    fn open(&self, cipher: &Aes256Gcm, counter: u64, sealed: &[u8]) -> Result<Vec<u8>, String> {
        cipher
            .decrypt(
                &nonce(counter),
                Payload {
                    msg: sealed,
                    aad: &self.transcript,
                },
            )
            .map_err(|_| "Malformed pairing message".to_string())
    }
}

/// Hosts one pairing on `listener`: waits up to `lifetime` for a device,
/// then runs the exchange with the first to arrive. Whatever happens, the
/// code is spent. `on_joined` runs once the device has joined, before the
/// host tells it so; returns the id the device joined as.
pub async fn host<F: Future<Output = ()>>(
    mut listener: Listener,
    code: &PairingCode,
    invitation: &Invitation,
    lifetime: Duration,
    on_joined: impl FnOnce(String) -> F,
) -> Result<String, String> {
    let mut status = listener.status.clone();
    let conn = tokio::select! {
        conn = listener.accept() => conn.ok_or("The pairing tunnel closed")?,
        reason = stopped(&mut status) => return Err(reason),
        _ = tokio::time::sleep(lifetime) => return Err(EXPIRED.into()),
    };
    // The listener lives until the end, since the device's connection runs
    // through it, but nobody else is accepted.
    tokio::time::timeout(EXCHANGE, offer(conn, code, invitation, on_joined))
        .await
        .map_err(|_| "The other device stopped answering".to_string())?
}

async fn stopped(status: &mut watch::Receiver<TunnelStatus>) -> String {
    let reason = status
        .wait_for(|status| matches!(status, TunnelStatus::Stopped { .. }))
        .await
        .ok()
        .map(|status| match &*status {
            TunnelStatus::Stopped { reason } => reason.clone(),
            _ => unreachable!("waited for Stopped"),
        });
    match reason {
        Some(reason) => format!("The relay refused the pairing tunnel: {reason}"),
        // The tunnel is gone without a word; the listener tells the rest.
        None => std::future::pending().await,
    }
}

async fn offer<F: Future<Output = ()>>(
    mut conn: Connection,
    code: &PairingCode,
    invitation: &Invitation,
    on_joined: impl FnOnce(String) -> F,
) -> Result<String, String> {
    let device_message = recv(&mut conn, Some(SPAKE_MESSAGE)).await?;
    let (spake, host_message) = Spake2::<Ed25519Group>::start_a(
        &code.password(),
        &Identity::new(HOST),
        &Identity::new(DEVICE),
    );
    let shared = spake
        .finish(&device_message)
        .map_err(|_| "Malformed pairing message")?;
    let keys = Keys::new(&shared, &device_message, &host_message);
    let mut confirm = host_message;
    confirm.extend(keys.mac(&keys.confirm_host).finalize().into_bytes());
    conn.send(confirm).await?;

    let proof = recv(&mut conn, Some(CONFIRM)).await?;
    keys.mac(&keys.confirm_device)
        .verify_slice(&proof)
        .map_err(|_| DEVICE_WRONG_CODE)?;
    let invitation = serde_json::to_vec(invitation).map_err(|e| e.to_string())?;
    conn.send(keys.seal(&keys.h2c, 0, &invitation)).await?;

    let joined = recv(&mut conn, None).await?;
    let joined: Joined = serde_json::from_slice(&keys.open(&keys.c2h, 0, &joined)?)
        .map_err(|_| "Malformed pairing message")?;
    let device_id = match joined {
        Joined {
            device_id: Some(id),
            ..
        } => id,
        Joined { error, .. } => {
            return Err(format!(
                "The other device could not join: {}",
                error.unwrap_or_default()
            ))
        }
    };
    on_joined(device_id.clone()).await;
    conn.send(keys.seal(&keys.h2c, 1, &[])).await?;
    // The answer is only queued; the tunnel must outlive it, so wait for the
    // device to hang up.
    let _ = conn.recv().await;
    Ok(device_id)
}

/// The device's side, from dialling the code's rendezvous: proves it knows
/// the code and receives the invitation. Join with it, then tell the host
/// through [`Redeemed::joined`].
pub async fn redeem(
    mut conn: Connection,
    code: &PairingCode,
) -> Result<(Invitation, Redeemed), String> {
    let (spake, device_message) = Spake2::<Ed25519Group>::start_b(
        &code.password(),
        &Identity::new(HOST),
        &Identity::new(DEVICE),
    );
    conn.send(device_message.clone()).await?;
    let answer = recv(&mut conn, Some(SPAKE_MESSAGE + CONFIRM)).await?;
    let (host_message, confirm) = answer.split_at(SPAKE_MESSAGE);
    let shared = spake
        .finish(host_message)
        .map_err(|_| "Malformed pairing message")?;
    let keys = Keys::new(&shared, &device_message, host_message);
    keys.mac(&keys.confirm_host)
        .verify_slice(confirm)
        .map_err(|_| WRONG_CODE)?;
    conn.send(
        keys.mac(&keys.confirm_device)
            .finalize()
            .into_bytes()
            .to_vec(),
    )
    .await?;
    let invitation = recv(&mut conn, None).await?;
    let invitation = serde_json::from_slice(&keys.open(&keys.h2c, 0, &invitation)?)
        .map_err(|_| "Malformed pairing message")?;
    Ok((invitation, Redeemed { conn, keys }))
}

/// A redeemed code whose host waits to hear how joining went.
pub struct Redeemed {
    conn: Connection,
    keys: Keys,
}

impl Redeemed {
    /// Tells the host the id this device joined as, or why it could not.
    /// After a join, waits until the host has read the member list again,
    /// so that it lets the first connection in.
    pub async fn joined(mut self, result: Result<&str, &str>) -> Result<(), String> {
        let joined = match result {
            Ok(id) => Joined {
                device_id: Some(id.into()),
                error: None,
            },
            Err(error) => Joined {
                device_id: None,
                error: Some(error.into()),
            },
        };
        let joined = serde_json::to_vec(&joined).map_err(|e| e.to_string())?;
        self.conn
            .send(self.keys.seal(&self.keys.c2h, 0, &joined))
            .await?;
        if result.is_err() {
            return Ok(());
        }
        let ready = recv(&mut self.conn, None).await?;
        self.keys.open(&self.keys.h2c, 1, &ready).map(|_| ())
    }
}

async fn recv(conn: &mut Connection, len: Option<usize>) -> Result<Vec<u8>, String> {
    let message = conn.recv().await.ok_or(CLOSED_IN_HANDSHAKE)?;
    if len.is_some_and(|len| message.len() != len) {
        return Err("Malformed pairing message".into());
    }
    Ok(message)
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;
    use crate::remote::loopback::LoopbackTunnel;
    use crate::remote::tunnel::Tunnel;

    fn invitation() -> Invitation {
        Invitation {
            secret: "c2VjcmV0LXNlY3JldC1zZWNyZXQtc2VjcmV0LXNlY3I".into(),
            registry: "https://registry.example".into(),
            registry_key: Some("gate".into()),
            host: "host-id".into(),
            name: "Laptop".into(),
        }
    }

    #[test]
    fn reads_a_code_the_way_people_type_it() {
        let code = PairingCode::parse("K7QM-2XPA").unwrap();
        assert_eq!(code.to_text(), "K7QM-2XPA");
        for typed in ["k7qm2xpa", " K7QM 2XPA ", "k7qm-2xpa", "K7QM--2XPA"] {
            assert_eq!(PairingCode::parse(typed).unwrap(), code, "{typed}");
        }
        assert_eq!(
            PairingCode::parse("oOiI-lL00").unwrap().to_text(),
            "0011-1100"
        );
        for wrong in ["K7QM-2XP", "K7QM-2XPAA", "K7QM-2XPU", "K7QM-2XPÄ", ""] {
            assert!(PairingCode::parse(wrong).is_err(), "{wrong}");
        }
        let generated = PairingCode::generate();
        assert_eq!(PairingCode::parse(&generated.to_text()).unwrap(), generated);
    }

    #[test]
    fn the_relay_sees_only_the_first_characters_of_the_code() {
        let token = |code: &str| {
            PairingCode::parse(code)
                .unwrap()
                .rendezvous()
                .routing_token()
        };
        assert_eq!(token("K7QM-2XPA"), token("K7Q0-0000"));
        assert_ne!(token("K7QM-2XPA"), token("K7RM-2XPA"));
    }

    /// Hosts `code` on `tunnel` and redeems `typed`, joining as "device-id".
    async fn pair(
        tunnel: &LoopbackTunnel,
        code: &PairingCode,
        typed: &PairingCode,
        lifetime: Duration,
    ) -> (Result<String, String>, Result<Invitation, String>, bool) {
        let refreshed = Arc::new(Mutex::new(false));
        let on_joined = {
            let refreshed = refreshed.clone();
            move |_| async move { *refreshed.lock().unwrap() = true }
        };
        let listener = tunnel.listen();
        let offered = invitation();
        let device = async {
            let conn = tunnel.dial().await?;
            let (invitation, redeemed) = redeem(conn, typed).await?;
            redeemed.joined(Ok("device-id")).await?;
            Ok(invitation)
        };
        let (hosted, redeemed) =
            tokio::join!(host(listener, code, &offered, lifetime, on_joined), device);
        let refreshed = *refreshed.lock().unwrap();
        (hosted, redeemed, refreshed)
    }

    #[tokio::test]
    async fn the_right_code_brings_the_invitation_across() {
        let tunnel = LoopbackTunnel::default();
        let code = PairingCode::generate();
        let (hosted, redeemed, refreshed) = pair(&tunnel, &code, &code, LIFETIME).await;
        assert_eq!(hosted.unwrap(), "device-id");
        assert_eq!(redeemed.unwrap(), invitation());
        assert!(refreshed, "the host read the list before answering");
        // Used once: nobody waits on it any more.
        assert!(tunnel.dial().await.is_err());
    }

    #[tokio::test]
    async fn a_wrong_code_fails_and_spends_the_code() {
        let tunnel = LoopbackTunnel::default();
        let code = PairingCode::parse("K7QM-2XPA").unwrap();
        let typo = PairingCode::parse("K7QM-2XPB").unwrap();
        let (hosted, redeemed, refreshed) = pair(&tunnel, &code, &typo, LIFETIME).await;
        assert_eq!(redeemed.unwrap_err(), WRONG_CODE);
        assert!(hosted.is_err());
        assert!(!refreshed);
        assert!(tunnel.dial().await.is_err(), "the code is spent");
    }

    #[tokio::test]
    async fn an_unused_code_expires() {
        let tunnel = LoopbackTunnel::default();
        let code = PairingCode::generate();
        let hosted = host(
            tunnel.listen(),
            &code,
            &invitation(),
            Duration::from_millis(50),
            |_| async {},
        )
        .await;
        assert_eq!(hosted.unwrap_err(), EXPIRED);
        assert!(tunnel.dial().await.is_err());
    }

    /// Joins a device and a host through a middle that keeps every message.
    fn recorded() -> (Connection, Connection, Arc<Mutex<Vec<Vec<u8>>>>) {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let (device, middle_a) = Connection::pair();
        let (middle_b, host) = Connection::pair();
        let (a_tx, a_rx) = middle_a.split();
        let (b_tx, b_rx) = middle_b.split();
        for (mut rx, tx) in [(a_rx, b_tx), (b_rx, a_tx)] {
            let seen = seen.clone();
            tokio::spawn(async move {
                while let Some(message) = rx.recv().await {
                    seen.lock().unwrap().push(message.clone());
                    if tx.send(message).await.is_err() {
                        break;
                    }
                }
            });
        }
        (device, host, seen)
    }

    #[tokio::test]
    async fn a_recording_of_the_exchange_does_not_test_a_guess() {
        let code = PairingCode::generate();
        let (device, host_end, seen) = recorded();
        let offered = invitation();
        let (hosted, redeemed) =
            tokio::join!(offer(host_end, &code, &offered, |_| async {}), async {
                let (invitation, redeemed) = redeem(device, &code).await?;
                redeemed.joined(Ok("device-id")).await?;
                Ok::<_, String>(invitation)
            });
        hosted.unwrap();
        redeemed.unwrap();

        let seen = seen.lock().unwrap().clone();
        assert_eq!(seen.len(), 6);
        // Before the key is confirmed, only SPAKE2 elements and a MAC under
        // the SPAKE2 key cross; nothing after is readable without that key.
        assert_eq!(seen[0].len(), SPAKE_MESSAGE);
        assert_eq!(seen[1].len(), SPAKE_MESSAGE + CONFIRM);
        assert_eq!(seen[2].len(), CONFIRM);
        let all = seen.concat();
        let invitation = invitation();
        for secret in [
            code.0.as_bytes(),
            invitation.secret.as_bytes(),
            invitation.registry.as_bytes(),
        ] {
            assert!(!all.windows(secret.len()).any(|w| w == secret));
        }

        // Even the right code, tried against the recording, gives a key that
        // does not match the MAC: checking a guess takes a live exchange.
        let (guess, _) = Spake2::<Ed25519Group>::start_b(
            &code.password(),
            &Identity::new(HOST),
            &Identity::new(DEVICE),
        );
        let (host_message, confirm) = seen[1].split_at(SPAKE_MESSAGE);
        let shared = guess.finish(host_message).unwrap();
        let keys = Keys::new(&shared, &seen[0], host_message);
        assert!(keys.mac(&keys.confirm_host).verify_slice(confirm).is_err());
    }
}
