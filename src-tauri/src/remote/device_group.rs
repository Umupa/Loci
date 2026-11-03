//! Who belongs: a device group kept in the device registry
//! (`services/device-registry`). Every device that holds the group secret can
//! add devices and remove them; the registry only stores what the group key
//! signed, and every device re-verifies what it reads. The signing rules are
//! the registry's `src/protocol.mjs`, byte for byte.
//!
//! - Group signing key: Ed25519 seed `HKDF-SHA256(groupSecret, "", "loci-group-sign-v1")`;
//!   `groupId` is its public key, base64url.
//! - `deviceId`: base64url(SHA-256(raw device public key)), first 22 characters.
//! - Signatures cover `loci-registry-v1\n<type>\n<canonical JSON>`.
//! - A host's connection code is `HKDF-SHA256(groupSecret, "", "loci-connect-code-v1\n" || deviceId)`:
//!   every member can work it out, the registry and the relay cannot.

use std::collections::HashSet;
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tokio::sync::watch;

use super::secure_channel::{ConnectCode, TrustedDevices};

const PROTOCOL: &str = "loci-registry-v1";
const INVITE_PREFIX: &str = "loci-group:";
/// Heartbeats come every 30 s; a device silent for longer than this is offline.
const ONLINE_WITHIN_MS: i64 = 90_000;
/// The least time between refreshes a rejected device can trigger.
const REJECTED_REFRESH: Duration = Duration::from_secs(5);

/// What a group of devices offers, whoever keeps the list: this registry
/// now, a tailnet later.
pub trait Identity {
    /// The members as last verified.
    fn devices(&self) -> Vec<Device>;
    /// Adds this device under `name`. Blocks on the network.
    fn join(&self, name: &str) -> Result<(), String>;
    /// Removes a device for good. Blocks on the network.
    fn remove(&self, device_id: &str) -> Result<(), String>;
}

#[derive(Clone, Debug)]
pub struct Device {
    pub device_id: String,
    pub name: String,
    pub platform: String,
    pub added_at: i64,
    pub key: VerifyingKey,
    /// Unsigned hints from the registry, for display and routing only.
    pub last_seen: Option<i64>,
    pub route: Option<Route>,
}

impl Device {
    pub fn online(&self, now: i64) -> bool {
        self.last_seen
            .is_some_and(|seen| now - seen <= ONLINE_WITHIN_MS)
    }
}

/// How to reach a hosting device; it rides in the heartbeat's `route`. It
/// never carries the connection code, which members derive themselves.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Route {
    pub relay: String,
    pub token: String,
}

#[derive(Clone)]
pub struct Registry {
    pub url: String,
    /// `REGISTRY_KEY`, when the registry is gated.
    pub key: Option<String>,
}

pub struct DeviceGroup {
    secret: [u8; 32],
    group_key: SigningKey,
    pub group_id: String,
    device_key: SigningKey,
    pub device_id: String,
    registry: Registry,
    devices: RwLock<Vec<Device>>,
    refreshed: Mutex<Option<Instant>>,
    /// Ticks after every change to `devices`.
    changes: watch::Sender<()>,
}

impl DeviceGroup {
    pub fn new(secret: [u8; 32], device_key: SigningKey, registry: Registry) -> Self {
        let group_key = group_signing_key(&secret);
        Self {
            group_id: b64url(group_key.verifying_key().as_bytes()),
            device_id: device_id_for(&device_key.verifying_key()),
            secret,
            group_key,
            device_key,
            registry,
            devices: RwLock::new(Vec::new()),
            refreshed: Mutex::new(None),
            changes: watch::channel(()).0,
        }
    }

    /// The text a user copies to another device to let it join.
    pub fn invite(&self) -> String {
        let registry: String =
            url::form_urlencoded::byte_serialize(self.registry.url.as_bytes()).collect();
        format!(
            "{INVITE_PREFIX}{}?registry={registry}",
            b64url(&self.secret)
        )
    }

    /// The connection code of the member `device_id` when it hosts.
    pub fn connect_code(&self, device_id: &str) -> ConnectCode {
        let mut code = [0; 32];
        Hkdf::<Sha256>::new(None, &self.secret)
            .expand_multi_info(
                &[b"loci-connect-code-v1\n", device_id.as_bytes()],
                &mut code,
            )
            .expect("32 bytes is a valid HKDF length");
        ConnectCode::from_bytes(code)
    }

    pub fn find(&self, device_id: &str) -> Option<Device> {
        self.devices
            .read()
            .unwrap()
            .iter()
            .find(|device| device.device_id == device_id)
            .cloned()
    }

    /// Reads the registry and keeps only what verifies.
    pub fn refresh(&self) -> Result<(), String> {
        let list = self.request("GET", &format!("/g/{}/devices", self.group_id), None)?;
        self.apply_list(&list);
        Ok(())
    }

    fn apply_list(&self, list: &Value) {
        *self.devices.write().unwrap() = verify_list(&self.group_key.verifying_key(), list);
        *self.refreshed.lock().unwrap() = Some(Instant::now());
        self.changes.send_replace(());
    }

    /// Tells the registry this device is up, and how to reach it if it hosts.
    pub fn heartbeat(&self, route: Option<&Route>) -> Result<(), String> {
        let mut beat = json!({ "deviceId": self.device_id, "ts": now_ms() });
        if let Some(route) = route {
            beat["route"] = json!(serde_json::to_string(route).expect("a route serializes"));
        }
        let sig = sign(&self.device_key, "heartbeat", &beat);
        let path = format!("/g/{}/devices/{}/heartbeat", self.group_id, self.device_id);
        self.request("POST", &path, Some(json!({ "beat": beat, "sig": sig })))
            .map(|_| ())
    }

    fn request(&self, method: &str, path: &str, body: Option<Value>) -> Result<Value, String> {
        let url = format!("{}{path}", self.registry.url.trim_end_matches('/'));
        let mut request = ureq::request(method, &url).timeout(Duration::from_secs(10));
        if let Some(key) = &self.registry.key {
            request = request.set("Authorization", &format!("Bearer {key}"));
        }
        let response = match body {
            Some(body) => request
                .set("Content-Type", "application/json")
                .send_string(&body.to_string()),
            None => request.call(),
        };
        match response {
            Ok(response) => {
                let text = response.into_string().map_err(|e| e.to_string())?;
                serde_json::from_str(&text).map_err(|e| e.to_string())
            }
            Err(ureq::Error::Status(status, response)) => {
                let message = response
                    .into_string()
                    .ok()
                    .and_then(|text| serde_json::from_str::<Value>(&text).ok())
                    .and_then(|body| body["error"].as_str().map(str::to_owned))
                    .unwrap_or_else(|| format!("HTTP {status}"));
                Err(format!("The device registry refused: {message}"))
            }
            Err(error) => Err(format!("Could not reach the device registry: {error}")),
        }
    }
}

impl Identity for DeviceGroup {
    fn devices(&self) -> Vec<Device> {
        self.devices.read().unwrap().clone()
    }

    fn join(&self, name: &str) -> Result<(), String> {
        let record = json!({
            "deviceId": self.device_id,
            "name": name,
            "devicePubKey": b64url(self.device_key.verifying_key().as_bytes()),
            "platform": platform(),
            "addedAt": now_ms(),
        });
        let sig = sign(&self.group_key, "device", &record);
        let path = format!("/g/{}/devices/{}", self.group_id, self.device_id);
        self.request("PUT", &path, Some(json!({ "record": record, "sig": sig })))
            .map(|_| ())
    }

    fn remove(&self, device_id: &str) -> Result<(), String> {
        let removal = json!({ "deviceId": device_id, "removedAt": now_ms() });
        let sig = sign(&self.group_key, "removal", &removal);
        let path = format!("/g/{}/devices/{device_id}", self.group_id);
        self.request(
            "DELETE",
            &path,
            Some(json!({ "removal": removal, "sig": sig })),
        )?;
        // Untrusted from now, without waiting for the next refresh.
        self.devices
            .write()
            .unwrap()
            .retain(|device| device.device_id != device_id);
        self.changes.send_replace(());
        Ok(())
    }
}

/// The host's view: itself and the verified members.
impl TrustedDevices for Arc<DeviceGroup> {
    fn is_trusted(&self, device: &VerifyingKey) -> bool {
        *device == self.device_key.verifying_key()
            || self
                .devices
                .read()
                .unwrap()
                .iter()
                .any(|member| member.key == *device)
    }

    /// A device that joined since the last refresh knocks: look again, so its
    /// next attempt gets in.
    fn on_rejected(&self, _device: &VerifyingKey) {
        let recent = self
            .refreshed
            .lock()
            .unwrap()
            .is_some_and(|at| at.elapsed() < REJECTED_REFRESH);
        if !recent {
            let group = self.clone();
            tokio::task::spawn_blocking(move || group.refresh());
        }
    }

    fn changes(&self) -> Option<watch::Receiver<()>> {
        Some(self.changes.subscribe())
    }
}

/// Parses `loci-group:<secret>[?registry=<url>]`.
pub fn parse_invite(text: &str) -> Result<([u8; 32], Option<String>), String> {
    let invalid = || "That is not a Loci group key".to_string();
    let rest = text
        .trim()
        .strip_prefix(INVITE_PREFIX)
        .ok_or_else(invalid)?;
    let (secret, query) = rest.split_once('?').unwrap_or((rest, ""));
    let secret = URL_SAFE_NO_PAD
        .decode(secret)
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or_else(invalid)?;
    let registry = url::form_urlencoded::parse(query.as_bytes())
        .find(|(key, _)| key == "registry")
        .map(|(_, value)| value.into_owned());
    Ok((secret, registry))
}

/// The devices in a registry listing whose records the group key signed,
/// whose ids match their keys, and that no signed removal names.
pub fn verify_list(group: &VerifyingKey, list: &Value) -> Vec<Device> {
    let removed: HashSet<&str> = list["removals"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|entry| verify(group, "removal", &entry["removal"], &entry["sig"]))
        .filter_map(|entry| entry["removal"]["deviceId"].as_str())
        .collect();
    list["devices"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            let record = &entry["record"];
            if !verify(group, "device", record, &entry["sig"]) {
                return None;
            }
            let device_id = record["deviceId"].as_str()?;
            let key = decode32(record["devicePubKey"].as_str()?)?;
            let key = VerifyingKey::from_bytes(&key).ok()?;
            if device_id_for(&key) != device_id || removed.contains(device_id) {
                return None;
            }
            Some(Device {
                device_id: device_id.to_owned(),
                name: record["name"].as_str()?.to_owned(),
                platform: record["platform"].as_str()?.to_owned(),
                added_at: record["addedAt"].as_i64()?,
                key,
                last_seen: entry["lastSeen"].as_i64(),
                route: entry["route"]
                    .as_str()
                    .and_then(|route| serde_json::from_str(route).ok()),
            })
        })
        .collect()
}

pub fn group_signing_key(secret: &[u8; 32]) -> SigningKey {
    let mut seed = [0; 32];
    Hkdf::<Sha256>::new(None, secret)
        .expand(b"loci-group-sign-v1", &mut seed)
        .expect("32 bytes is a valid HKDF length");
    SigningKey::from_bytes(&seed)
}

pub fn device_id_for(key: &VerifyingKey) -> String {
    let mut id = b64url(&Sha256::digest(key.as_bytes()));
    id.truncate(22);
    id
}

/// JSON with object keys sorted and no whitespace, as the registry signs it.
pub fn canonical_json(value: &Value) -> String {
    match value {
        Value::Array(items) => {
            let items: Vec<_> = items.iter().map(canonical_json).collect();
            format!("[{}]", items.join(","))
        }
        Value::Object(map) => {
            let mut keys: Vec<_> = map.keys().collect();
            keys.sort();
            let entries: Vec<_> = keys
                .into_iter()
                .map(|key| {
                    format!(
                        "{}:{}",
                        Value::from(key.as_str()),
                        canonical_json(&map[key])
                    )
                })
                .collect();
            format!("{{{}}}", entries.join(","))
        }
        other => other.to_string(),
    }
}

fn signing_message(kind: &str, payload: &Value) -> Vec<u8> {
    format!("{PROTOCOL}\n{kind}\n{}", canonical_json(payload)).into_bytes()
}

fn sign(key: &SigningKey, kind: &str, payload: &Value) -> String {
    b64url(&key.sign(&signing_message(kind, payload)).to_bytes())
}

fn verify(key: &VerifyingKey, kind: &str, payload: &Value, sig: &Value) -> bool {
    let Some(sig) = sig
        .as_str()
        .and_then(|sig| URL_SAFE_NO_PAD.decode(sig).ok())
    else {
        return false;
    };
    let Ok(sig) = <[u8; 64]>::try_from(sig) else {
        return false;
    };
    payload.is_object()
        && key
            .verify_strict(
                &signing_message(kind, payload),
                &Signature::from_bytes(&sig),
            )
            .is_ok()
}

pub fn b64url(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

pub fn decode32(text: &str) -> Option<[u8; 32]> {
    URL_SAFE_NO_PAD.decode(text).ok()?.try_into().ok()
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_millis() as i64)
}

fn platform() -> &'static str {
    match std::env::consts::OS {
        "macos" => "macOS",
        "windows" => "Windows",
        "linux" => "Linux",
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::remote::secure_channel::{accept, connect, tests::device};
    use crate::remote::tunnel::Connection;

    /// The bytes 0..32, as in `services/device-registry/test/protocol.test.mjs`.
    fn fixed() -> [u8; 32] {
        std::array::from_fn(|i| i as u8)
    }

    fn registry() -> Registry {
        Registry {
            url: "http://127.0.0.1:1".into(),
            key: None,
        }
    }

    #[test]
    fn matches_the_registry_test_vectors() {
        let group = group_signing_key(&fixed());
        assert_eq!(
            b64url(group.verifying_key().as_bytes()),
            "ExRtSEDuWwz95AeKeMbsJ8_8BLBzRTU4aZ-UExezVuc"
        );
        let device = SigningKey::from_bytes(&fixed());
        assert_eq!(
            b64url(device.verifying_key().as_bytes()),
            "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"
        );
        assert_eq!(
            device_id_for(&device.verifying_key()),
            "Vkdap1RjR0wChd9dvyvKtz"
        );

        // Signatures made by the registry's helpers (Ed25519 is deterministic).
        let record = json!({
            "deviceId": "Vkdap1RjR0wChd9dvyvKtz",
            "name": "Fixed",
            "devicePubKey": "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg",
            "platform": "macOS",
            "addedAt": 1_760_000_000_000_i64,
        });
        assert_eq!(
            canonical_json(&record),
            r#"{"addedAt":1760000000000,"deviceId":"Vkdap1RjR0wChd9dvyvKtz","devicePubKey":"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg","name":"Fixed","platform":"macOS"}"#
        );
        assert_eq!(
            sign(&group, "device", &record),
            "Cvl5--2ZwEb-2N151xye85jBWXZsheTagq1T7FCEcBLLLzoZPp45HyiwO_6opWucLKgaNiVifOikiudsMtKgDg"
        );
        let removal =
            json!({"deviceId": "Vkdap1RjR0wChd9dvyvKtz", "removedAt": 1_760_000_000_001_i64});
        assert_eq!(
            sign(&group, "removal", &removal),
            "8BFQGM6c1QghwfNPdeisvbQH8nOLMI0K5YRJr2jwcbbpodRaEfcjyl3hTe0V2lj29qi-miVhCqhO5wH-GL2KAw"
        );
        let beat = json!({"deviceId": "Vkdap1RjR0wChd9dvyvKtz", "ts": 1_760_000_000_002_i64, "route": "r"});
        assert_eq!(
            sign(&device, "heartbeat", &beat),
            "_knmBelFk56N0fMfgWQKQ9t7TzzcwO-f00MGsGVRzcuStea1WCUL8XpUe7GxL3Ba1ivSSofKFMRXfpwLd_bGAg"
        );
    }

    #[test]
    fn canonical_json_matches_the_registry() {
        let cases = [
            (
                json!({"b": 1, "a": {"d": 2, "c": [3, {"z": 1, "y": 2}]}}),
                r#"{"a":{"c":[3,{"y":2,"z":1}],"d":2},"b":1}"#,
            ),
            (json!({"b": 1, "10": 2, "2": 3}), r#"{"10":2,"2":3,"b":1}"#),
            (json!({"b": null}), r#"{"b":null}"#),
            (json!([null, 1, "x"]), r#"[null,1,"x"]"#),
            (json!("a\nb"), r#""a\nb""#),
        ];
        for (value, expected) in cases {
            assert_eq!(canonical_json(&value), expected);
        }
        assert_eq!(
            String::from_utf8(signing_message("device", &json!({"b": 1, "a": 2}))).unwrap(),
            "loci-registry-v1\ndevice\n{\"a\":2,\"b\":1}"
        );
    }

    /// A registry listing entry for `key`, signed by `group`.
    fn entry(group: &SigningKey, key: &SigningKey, name: &str) -> Value {
        let record = json!({
            "deviceId": device_id_for(&key.verifying_key()),
            "name": name,
            "devicePubKey": b64url(key.verifying_key().as_bytes()),
            "platform": "macOS",
            "addedAt": 1,
        });
        let route = serde_json::to_string(&Route {
            relay: "wss://r".into(),
            token: "t".into(),
        })
        .unwrap();
        json!({"record": record, "sig": sign(group, "device", &record), "lastSeen": 5, "route": route})
    }

    fn removal(group: &SigningKey, key: &SigningKey) -> Value {
        let removal = json!({"deviceId": device_id_for(&key.verifying_key()), "removedAt": 2});
        json!({"removal": removal, "sig": sign(group, "removal", &removal)})
    }

    #[test]
    fn keeps_only_devices_the_group_vouches_for() {
        let group = group_signing_key(&[3; 32]);
        let (good, forged, mismatched, removed, wrongly_removed) =
            (device(), device(), device(), device(), device());
        let mut mismatch = entry(&group, &mismatched, "Mismatch");
        mismatch["record"]["devicePubKey"] = json!(b64url(device().verifying_key().as_bytes()));
        mismatch["sig"] = json!(sign(&group, "device", &mismatch["record"]));
        let mut fake_removal = removal(&group_signing_key(&[4; 32]), &wrongly_removed);
        fake_removal["removal"]["removedAt"] = json!(3);
        let list = json!({
            "devices": [
                entry(&group, &good, "Good"),
                entry(&group_signing_key(&[4; 32]), &forged, "Forged"),
                mismatch,
                entry(&group, &removed, "Removed"),
                entry(&group, &wrongly_removed, "Kept"),
            ],
            "removals": [removal(&group, &removed), fake_removal],
        });
        let devices = verify_list(&group.verifying_key(), &list);
        let names: Vec<_> = devices.iter().map(|d| d.name.as_str()).collect();
        assert_eq!(names, ["Good", "Kept"]);
        assert_eq!(
            devices[0].route,
            Some(Route {
                relay: "wss://r".into(),
                token: "t".into()
            })
        );
        assert_eq!(devices[0].last_seen, Some(5));
    }

    #[test]
    fn every_member_derives_the_same_connection_code() {
        let secret = [9; 32];
        let host = DeviceGroup::new(secret, device(), registry());
        let client = DeviceGroup::new(secret, device(), registry());
        let outsider = DeviceGroup::new([8; 32], device(), registry());
        let code = |group: &DeviceGroup| group.connect_code(&host.device_id).to_text();
        assert_eq!(code(&host), code(&client));
        assert_ne!(code(&host), code(&outsider));
        assert_ne!(code(&host), host.connect_code(&client.device_id).to_text());
    }

    #[test]
    fn an_invite_round_trips() {
        let group = DeviceGroup::new(
            [5; 32],
            device(),
            Registry {
                url: "https://loci-device-registry.example.workers.dev".into(),
                key: None,
            },
        );
        let invite = group.invite();
        assert!(invite.starts_with("loci-group:"));
        let (secret, registry) = parse_invite(&format!(" {invite}\n")).unwrap();
        assert_eq!(secret, [5; 32]);
        assert_eq!(
            registry.as_deref(),
            Some("https://loci-device-registry.example.workers.dev")
        );
        assert_eq!(
            parse_invite(&format!("loci-group:{}", b64url(&[5; 32])))
                .unwrap()
                .1,
            None
        );
        assert!(parse_invite("loci-group:short").is_err());
        assert!(parse_invite("hello").is_err());
    }

    #[tokio::test]
    async fn the_host_turns_away_a_removed_device() {
        let secret = [7; 32];
        let group_key = group_signing_key(&secret);
        let (host_key, member) = (device(), device());
        let host = Arc::new(DeviceGroup::new(secret, host_key.clone(), registry()));
        // Freshly refreshed, so a rejection does not go to the (absent) registry.
        host.apply_list(&json!({"devices": [entry(&group_key, &host_key, "Host"), entry(&group_key, &member, "Member")]}));

        let handshake = |trusted: Arc<DeviceGroup>| {
            let (member, host_key) = (member.clone(), host_key.clone());
            let code = trusted.connect_code(&trusted.device_id);
            async move {
                let (c, h) = Connection::pair();
                let trusted_host = [host_key.verifying_key()];
                let (_, host) = tokio::join!(
                    connect(c, &code, &member, &trusted_host[..]),
                    accept(h, &code, &host_key, &trusted)
                );
                host.map(|channel| channel.peer)
            }
        };
        assert_eq!(handshake(host.clone()).await, Ok(member.verifying_key()));

        host.apply_list(&json!({
            "devices": [entry(&group_key, &host_key, "Host"), entry(&group_key, &member, "Member")],
            "removals": [removal(&group_key, &member)],
        }));
        assert_eq!(
            handshake(host.clone()).await,
            Err("The device is not trusted".to_string())
        );
    }

    #[tokio::test]
    async fn removing_a_device_closes_its_open_connection() {
        use crate::remote::gateway::{Gateway, Reply};
        use crate::remote::session_master::tests::recording;
        use crate::remote::session_master::FEED_BUFFER_BYTES;

        let secret = [6; 32];
        let group_key = group_signing_key(&secret);
        let (host_key, member) = (device(), device());
        let members = json!({"devices": [entry(&group_key, &host_key, "Host"), entry(&group_key, &member, "Member")]});
        let host = Arc::new(DeviceGroup::new(secret, host_key.clone(), registry()));
        host.apply_list(&members);
        let (master, intents) = recording(FEED_BUFFER_BYTES);
        let code = host.connect_code(&host.device_id);
        let gateway = Arc::new(Gateway {
            master: master.clone(),
            invoke: Box::new(|_, _| Box::pin(async { Ok(Reply::Json(json!("ok"))) })),
            save_upload: Box::new(|_, _| {
                Box::pin(async { Ok(Reply::Json(json!("/host/upload"))) })
            }),
            code: code.clone(),
            device_key: host_key.clone(),
            trusted: Box::new(host.clone()),
        });
        let (c, h) = Connection::pair();
        tokio::spawn(gateway.serve(h));
        let mut client = connect(c, &code, &member, &[host_key.verifying_key()][..])
            .await
            .unwrap();
        let send = |frame: Value| frame.to_string().into_bytes();

        // An intent the window has not answered yet.
        client
            .sender
            .send(&send(json!({"t": "call", "id": 1, "cmd": "session.stop", "args": ["s1"], "requestId": "r-1"})))
            .await
            .unwrap();
        while !master.is_pending("r-1") {
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        let asked = intents.lock().unwrap()[0].clone();

        // A refresh that keeps the member keeps the connection.
        host.apply_list(&members);
        client
            .sender
            .send(&send(
                json!({"t": "call", "id": 2, "cmd": "notes_list", "args": {}}),
            ))
            .await
            .unwrap();
        let reply: Value =
            serde_json::from_slice(&client.receiver.recv().await.unwrap().unwrap()).unwrap();
        assert_eq!(reply["id"], 2);

        // The list that removes it ends the connection at once.
        host.apply_list(&json!({
            "devices": [entry(&group_key, &host_key, "Host"), entry(&group_key, &member, "Member")],
            "removals": [removal(&group_key, &member)],
        }));
        let closed = tokio::time::timeout(Duration::from_secs(1), client.receiver.recv()).await;
        assert_eq!(closed.expect("closed within a second"), Ok(None));
        assert!(!master.is_pending("r-1"));
        let cleared = loop {
            let found = intents
                .lock()
                .unwrap()
                .iter()
                .find(|event| event.name == "session.view")
                .cloned();
            if let Some(event) = found {
                break event;
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        };
        assert_eq!(cleared.args, json!([[]]));
        assert_eq!(cleared.connection_id, asked.connection_id);
    }
}
