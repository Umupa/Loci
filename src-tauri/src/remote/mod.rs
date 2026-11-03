//! Remote access: another Loci reaches this one through a tunnel, over an
//! end-to-end encrypted channel, and uses it as if it were local. See
//! `gateway.rs` for what a connected device can send, `device_group.rs` for
//! who may connect.
//!
//! `remote.json` in the app data folder holds the settings, none of them
//! secret (all optional; off by default):
//!
//! ```json
//! {
//!   "enabled": true,
//!   "relay": "wss://relay.example.com",
//!   "registrationKey": "<relay registration key, if the relay wants one>",
//!   "registry": "https://loci-device-registry.example.workers.dev",
//!   "registryKey": "<REGISTRY_KEY, if the registry is gated>",
//!   "name": "MacBook",
//!   "hosts": [{ "deviceId": "…", "name": "MacBook", "lastConnected": 1762000000000 }],
//!   "autoConnect": true
//! }
//! ```
//!
//! The relay and registry fields are the user's own services. Without them,
//! a build made with `LOCI_RELAY_URL`, `LOCI_RELAY_KEY`, `LOCI_REGISTRY_URL`
//! and `LOCI_REGISTRY_KEY` in its environment uses those ([`BUILT_IN`]);
//! they never reach `remote.json` or the settings page.
//!
//! The device key and the group secret live in the system keychain (service
//! = the app identifier, accounts `remote-device-key` and
//! `remote-group-secret`), read only once remote access has been set up.

pub mod alma_relay;
pub mod cache;
pub mod client;
pub mod device_group;
pub mod gateway;
pub mod loopback;
pub mod pairing;
pub mod secure_channel;
pub mod session_master;
pub mod setup;
pub mod tunnel;

use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use ed25519_dalek::SigningKey;
use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::async_runtime::JoinHandle;
use tauri::ipc::{CallbackFn, InvokeBody, InvokeError, InvokeResponse, InvokeResponseBody};
use tauri::webview::InvokeRequest;
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

use alma_relay::AlmaRelayTunnel;
use device_group::{now_ms, DeviceGroup, Registry, Route};
use gateway::{Gateway, Reply, ReplyFuture};
use loopback::LoopbackTunnel;
use secure_channel::{ConnectCode, TrustedDevices};
use session_master::SessionMaster;
use tunnel::Tunnel;

const HOST_WINDOW: &str = "main";
const NO_WINDOW: &str = "The host window is not open";
const DEVICE_KEY: &str = "remote-device-key";
const GROUP_SECRET: &str = "remote-group-secret";
const HEARTBEAT: Duration = Duration::from_secs(30);
/// The member list is read again every this many heartbeats.
const REFRESH_EVERY: u32 = 2;

pub struct RemoteHost {
    pub master: Arc<SessionMaster>,
    /// Lets a window of this process connect as a client (development).
    pub loopback: LoopbackTunnel,
    inner: Mutex<Inner>,
    /// The pairing code on show, if any.
    pairing: Mutex<Option<Pairing>>,
}

/// A pairing code waiting for its device; dropping it takes the code back.
struct Pairing {
    code: String,
    expires_at: i64,
    task: JoinHandle<()>,
}

impl Drop for Pairing {
    fn drop(&mut self) {
        self.task.abort();
    }
}

#[derive(Default)]
struct Inner {
    settings: Settings,
    /// Read from the keychain on first need.
    identity: Option<(SigningKey, Option<Arc<DeviceGroup>>)>,
    serving: Option<Serving>,
}

/// A running gateway; dropping it stops the tunnels, closes every connection
/// and lets the machine sleep again.
struct Serving {
    gateway: Arc<Gateway>,
    route: Option<Route>,
    tasks: Vec<JoinHandle<()>>,
    _awake: Option<crate::power::KeepAwake>,
}

impl Drop for Serving {
    fn drop(&mut self) {
        for task in &self.tasks {
            task.abort();
        }
    }
}

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub enabled: bool,
    pub relay: Option<String>,
    pub registration_key: Option<String>,
    pub registry: Option<String>,
    pub registry_key: Option<String>,
    pub name: Option<String>,
    /// Hosts this device has connected to, most recent first.
    pub hosts: Vec<KnownHost>,
    /// Open the most recent host at launch. Unset until the first pairing,
    /// which turns it on.
    pub auto_connect: Option<bool>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KnownHost {
    pub device_id: String,
    pub name: String,
    pub last_connected: i64,
}

/// The relay and registry a build carries, from its compile environment
/// (see `docs/releasing.md`). A public app gives them away to anyone who
/// looks; they gate the services, they do not protect a device.
pub struct BuiltIn {
    pub relay: Option<&'static str>,
    pub relay_key: Option<&'static str>,
    pub registry: Option<&'static str>,
    pub registry_key: Option<&'static str>,
}

pub const BUILT_IN: BuiltIn = BuiltIn {
    relay: option_env!("LOCI_RELAY_URL"),
    relay_key: option_env!("LOCI_RELAY_KEY"),
    registry: option_env!("LOCI_REGISTRY_URL"),
    registry_key: option_env!("LOCI_REGISTRY_KEY"),
};

/// A relay to use, with the registration key it wants.
#[derive(Clone, Debug, PartialEq)]
pub struct Service {
    pub url: String,
    pub key: Option<String>,
}

/// An empty variable (an Actions secret that was never set) is none.
fn given(value: Option<&'static str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(String::from)
}

impl BuiltIn {
    fn relay(&self) -> Option<Service> {
        Some(Service {
            url: normalize_relay(&given(self.relay)?).ok()?,
            key: given(self.relay_key),
        })
    }

    fn registry(&self) -> Option<Registry> {
        Some(Registry {
            url: given(self.registry)?,
            key: given(self.registry_key),
        })
    }
}

impl Settings {
    /// The relay hosts register on and pairing meets at: the user's own,
    /// with its own key, or the built-in one.
    pub fn relay_in(&self, built_in: &BuiltIn) -> Option<Service> {
        match &self.relay {
            Some(url) => Some(Service {
                url: url.clone(),
                key: self.registration_key.clone(),
            }),
            None => built_in.relay(),
        }
    }

    /// The registry the group lives in, chosen the same way.
    pub fn registry_in(&self, built_in: &BuiltIn) -> Option<Registry> {
        match &self.registry {
            Some(url) => Some(Registry {
                url: url.clone(),
                key: self.registry_key.clone(),
            }),
            None => built_in.registry(),
        }
    }

    /// What the gateway depends on: a change to anything else (the hosts
    /// this device remembers) leaves it running.
    fn serving(&self) -> impl PartialEq + '_ {
        (
            self.enabled,
            &self.relay,
            &self.registration_key,
            &self.registry,
            &self.registry_key,
            &self.name,
        )
    }

    /// The settings with the relay as the tunnel dials it, or why it cannot be.
    /// An empty relay is no relay.
    pub fn checked(mut self) -> Result<Self, String> {
        self.relay = self
            .relay
            .as_deref()
            .map(str::trim)
            .filter(|relay| !relay.is_empty())
            .map(normalize_relay)
            .transpose()?;
        Ok(self)
    }
}

/// A relay address as the tunnel dials it. A relay's page address works too:
/// `https://` becomes `wss://` and `http://` becomes `ws://`. Anything else
/// is refused rather than left to fail without a word.
pub fn normalize_relay(relay: &str) -> Result<String, String> {
    let relay = relay.trim().trim_end_matches('/');
    let Some((scheme, rest)) = relay.split_once("://") else {
        return Err(format!(
            "The relay address must start with wss:// or https://: {relay}"
        ));
    };
    let scheme = match scheme.to_ascii_lowercase().as_str() {
        "wss" | "https" => "wss",
        "ws" | "http" => "ws",
        other => {
            return Err(format!(
                "The relay address must start with wss:// or https://, not {other}://"
            ))
        }
    };
    if rest.is_empty() || rest.starts_with('/') {
        return Err(format!("The relay address has no host: {relay}"));
    }
    Ok(format!("{scheme}://{rest}"))
}

impl RemoteHost {
    pub fn gateway(&self) -> Option<Arc<Gateway>> {
        let inner = self.inner.lock().unwrap();
        inner
            .serving
            .as_ref()
            .map(|serving| serving.gateway.clone())
    }

    /// This device's key and its group, from the keychain on first use.
    pub fn identity(
        &self,
        app: &AppHandle,
    ) -> Result<(SigningKey, Option<Arc<DeviceGroup>>), String> {
        let mut inner = self.inner.lock().unwrap();
        identity(app, &mut inner)
    }
}

fn identity(
    app: &AppHandle,
    inner: &mut Inner,
) -> Result<(SigningKey, Option<Arc<DeviceGroup>>), String> {
    if inner.identity.is_none() {
        let device_key = match load_secret(app, DEVICE_KEY)? {
            Some(key) => SigningKey::from_bytes(&key),
            None => new_device_key(app)?,
        };
        let group = match (load_secret(app, GROUP_SECRET)?, registry(&inner.settings)) {
            (Some(secret), Some(registry)) => Some(Arc::new(DeviceGroup::new(
                secret,
                device_key.clone(),
                registry,
            ))),
            _ => None,
        };
        inner.identity = Some((device_key, group));
    }
    Ok(inner.identity.clone().expect("loaded above"))
}

fn registry(settings: &Settings) -> Option<Registry> {
    settings.registry_in(&BUILT_IN)
}

fn device_name(settings: &Settings) -> String {
    settings
        .name
        .clone()
        .or_else(computer_name)
        .unwrap_or_else(|| "Loci".into())
}

/// The name the system gives this computer, as in Sharing settings.
fn computer_name() -> Option<String> {
    static NAME: OnceLock<Option<String>> = OnceLock::new();
    NAME.get_or_init(|| {
        #[cfg(target_os = "macos")]
        let name = std::process::Command::new("scutil")
            .args(["--get", "ComputerName"])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned());
        #[cfg(not(target_os = "macos"))]
        let name = std::env::var("COMPUTERNAME")
            .or_else(|_| std::env::var("HOSTNAME"))
            .ok();
        name.filter(|name| !name.is_empty())
    })
    .clone()
}

/// Keeps `device_id` first among the hosts this device has connected to.
fn remember_host(app: &AppHandle, device_id: &str, name: &str) {
    let host = app.state::<RemoteHost>();
    let mut inner = host.inner.lock().unwrap();
    let mut settings = inner.settings.clone();
    settings.hosts.retain(|known| known.device_id != device_id);
    settings.hosts.insert(
        0,
        KnownHost {
            device_id: device_id.into(),
            name: name.into(),
            last_connected: now_ms(),
        },
    );
    match write_settings(app, &settings) {
        Ok(()) => inner.settings = settings,
        Err(error) => eprintln!("Remote access could not remember {name}: {error}"),
    }
}

/// The page of a window connected to the group member `device_id`.
pub fn host_page(device_id: &str) -> String {
    format!("index.html?remote=device:{device_id}")
}

/// Lists in File → Connect To the members this device can open now.
fn update_menu(app: &AppHandle) {
    let group = {
        let host = app.state::<RemoteHost>();
        let inner = host.inner.lock().unwrap();
        inner.identity.as_ref().and_then(|(_, group)| group.clone())
    };
    let now = now_ms();
    let hosts = group
        .map(|group| {
            use device_group::Identity;
            group
                .devices()
                .into_iter()
                .filter(|device| {
                    device.device_id != group.device_id
                        && device.online(now)
                        && device.route.is_some()
                })
                .map(|device| (device.device_id, device.name))
                .collect()
        })
        .unwrap_or_default();
    crate::menu::set_hosts(app, hosts);
}

/// At launch, opens the host this device last connected to, if it asked to
/// and the host is there; otherwise does nothing, without a word.
async fn reconnect_last(app: AppHandle) {
    let last = {
        let host = app.state::<RemoteHost>();
        let inner = host.inner.lock().unwrap();
        let settings = &inner.settings;
        settings
            .hosts
            .first()
            .filter(|_| settings.auto_connect == Some(true))
            .map(|known| known.device_id.clone())
    };
    let Some(device_id) = last else { return };
    let Ok((_, Some(group))) = app.state::<RemoteHost>().identity(&app) else {
        return;
    };
    let refreshing = group.clone();
    let _ = tauri::async_runtime::spawn_blocking(move || refreshing.refresh()).await;
    let reachable = group
        .find(&device_id)
        .is_some_and(|host| host.online(now_ms()) && host.route.is_some());
    if reachable {
        let _ = crate::window::open_new_window(&app, Some(&host_page(&device_id)));
    }
}

fn keychain(app: &AppHandle, account: &str) -> Result<keyring::Entry, String> {
    keyring::Entry::new(&app.config().identifier, account).map_err(|e| e.to_string())
}

fn load_secret(app: &AppHandle, account: &str) -> Result<Option<[u8; 32]>, String> {
    match keychain(app, account)?.get_password() {
        Ok(text) => device_group::decode32(&text)
            .map(Some)
            .ok_or_else(|| format!("The keychain item {account} is damaged")),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(error) => Err(format!("Could not read the keychain: {error}")),
    }
}

fn save_secret(app: &AppHandle, account: &str, secret: &[u8; 32]) -> Result<(), String> {
    keychain(app, account)?
        .set_password(&device_group::b64url(secret))
        .map_err(|e| format!("Could not write to the keychain: {e}"))
}

fn delete_secret(app: &AppHandle, account: &str) -> Result<(), String> {
    match keychain(app, account)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(error) => Err(format!("Could not write to the keychain: {error}")),
    }
}

fn new_device_key(app: &AppHandle) -> Result<SigningKey, String> {
    let key = SigningKey::generate(&mut OsRng);
    save_secret(app, DEVICE_KEY, &key.to_bytes())?;
    Ok(key)
}

pub fn init(app: &AppHandle) {
    let settings = read_settings(app).unwrap_or_else(|error| {
        eprintln!("Remote access is off: {error}");
        None
    });
    let configured = settings.is_some();
    app.manage(RemoteHost {
        master: Arc::new(SessionMaster::new(emit_to_host_window(app.clone()))),
        loopback: LoopbackTunnel::default(),
        inner: Mutex::new(Inner {
            settings: settings.unwrap_or_default(),
            ..Inner::default()
        }),
        pairing: Mutex::new(None),
    });
    app.manage(client::RemoteClients::default());
    // Leave the keychain alone until remote access has been set up.
    if configured {
        apply(app);
        tauri::async_runtime::spawn(reconnect_last(app.clone()));
    }
    let app = app.clone();
    tauri::async_runtime::spawn(async move { keep_in_touch(app).await });
}

/// Heartbeats, and reads the member list every other beat, while in a group.
async fn keep_in_touch(app: AppHandle) {
    let mut beat = 0u32;
    loop {
        let (group, route) = {
            let host = app.state::<RemoteHost>();
            let inner = host.inner.lock().unwrap();
            let group = inner.identity.as_ref().and_then(|(_, group)| group.clone());
            (group, inner.serving.as_ref().and_then(|s| s.route.clone()))
        };
        if let Some(group) = group {
            let refresh = beat.is_multiple_of(REFRESH_EVERY);
            let _ = tauri::async_runtime::spawn_blocking(move || {
                let _ = group.heartbeat(route.as_ref());
                if refresh {
                    let _ = group.refresh();
                }
            })
            .await;
            update_menu(&app);
        }
        beat = beat.wrapping_add(1);
        tokio::time::sleep(HEARTBEAT).await;
    }
}

fn settings_path(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    Ok(app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("remote.json"))
}

/// `None` when remote access was never set up.
fn read_settings(app: &AppHandle) -> Result<Option<Settings>, String> {
    let path = settings_path(app)?;
    match std::fs::read_to_string(&path) {
        Ok(text) => serde_json::from_str::<Settings>(&text)
            .map_err(|e| e.to_string())
            .and_then(Settings::checked)
            .map(Some)
            .map_err(|e| format!("{}: {e}", path.display())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("{}: {error}", path.display())),
    }
}

fn write_settings(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let path = settings_path(app)?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    std::fs::write(&path, text).map_err(|e| format!("{}: {e}", path.display()))
}

/// Starts or stops the gateway to match the settings and identity, and tells
/// every window.
fn apply(app: &AppHandle) {
    let host = app.state::<RemoteHost>();
    let enabled = {
        let mut inner = host.inner.lock().unwrap();
        inner.serving = None;
        if inner.settings.enabled {
            let started = identity(app, &mut inner)
                .and_then(|(key, group)| start(app, &inner.settings, &host, key, group));
            match started {
                Ok(serving) => inner.serving = Some(serving),
                Err(error) => eprintln!("Remote access could not start: {error}"),
            }
        }
        inner.serving.is_some()
    };
    let _ = app.emit("remote-status-changed", json!({ "enabled": enabled }));
}

fn start(
    app: &AppHandle,
    settings: &Settings,
    host: &RemoteHost,
    device_key: SigningKey,
    group: Option<Arc<DeviceGroup>>,
) -> Result<Serving, String> {
    // In a group, members can work the code out; alone, nobody else needs it.
    let code = match &group {
        Some(group) => group.connect_code(&group.device_id),
        None => ConnectCode::generate(),
    };
    let trusted: Box<dyn TrustedDevices + Send + Sync> = match &group {
        Some(group) => Box::new(group.clone()),
        None => Box::new(vec![device_key.verifying_key()]),
    };
    let invoke_app = app.clone();
    let gateway = Arc::new(Gateway {
        master: host.master.clone(),
        invoke: Box::new(move |cmd, args| invoke_command(invoke_app.clone(), cmd, args)),
        save_upload: Box::new(|name, bytes| {
            Box::pin(async move {
                let saved = tauri::async_runtime::spawn_blocking(move || {
                    crate::fs::save_uploaded_file(&name, &bytes)
                })
                .await
                .map_err(|e| e.to_string())??;
                Ok(Reply::Json(json!(saved)))
            })
        }),
        code: code.clone(),
        device_key,
        trusted,
    });

    let loopback = host.loopback.clone();
    let serving = gateway.clone();
    let mut tasks = vec![tauri::async_runtime::spawn(async move {
        serving.run(loopback.listen()).await
    })];
    let mut route = None;
    match (settings.relay_in(&BUILT_IN), &group) {
        (Some(relay), Some(_)) => {
            route = Some(Route {
                relay: relay.url.clone(),
                token: code.routing_token(),
            });
            let relay = AlmaRelayTunnel {
                relay: relay.url,
                code,
                name: device_name(settings),
                registration_key: relay.key,
            };
            let serving = gateway.clone();
            tasks.push(tauri::async_runtime::spawn(async move {
                serving.run(relay.listen()).await
            }));
        }
        (Some(_), None) => eprintln!("Remote access: the relay needs a device group; relay off"),
        _ => {}
    }
    let awake = crate::power::KeepAwake::start()
        .map_err(|error| eprintln!("Remote access cannot keep this machine awake: {error}"))
        .ok();
    Ok(Serving {
        gateway,
        route,
        tasks,
        _awake: awake,
    })
}

fn emit_to_host_window(app: AppHandle) -> session_master::Emit {
    Box::new(move |event| {
        if app.get_webview_window(HOST_WINDOW).is_none() {
            return Err(NO_WINDOW.into());
        }
        app.emit_to(HOST_WINDOW, "loci-remote-intent", event)
            .map_err(|e| e.to_string())
    })
}

/// Runs a registered command as if the host window had invoked it: the
/// request goes through the app's own invoke handler, so arguments, state,
/// the workspace-reset guard and the ACL behave exactly as for the webview,
/// and every command in the catalog works without a line of glue.
fn invoke_command(app: AppHandle, cmd: String, args: Value) -> ReplyFuture {
    Box::pin(async move {
        let window = app.get_webview_window(HOST_WINDOW).ok_or(NO_WINDOW)?;
        let url = window.url().map_err(|e| e.to_string())?;
        // The reset guard admits only requests with a ticket, and is told when
        // each one ends, as `src/platform/tauri/core.ts` does.
        let ticket = uuid::Uuid::new_v4().to_string();
        let mut headers = tauri::http::HeaderMap::new();
        headers.insert(
            "x-loci-request-id",
            ticket.parse().expect("a UUID is a valid header value"),
        );
        let request = InvokeRequest {
            cmd,
            callback: CallbackFn(0),
            error: CallbackFn(1),
            url,
            body: InvokeBody::Json(args),
            headers,
            invoke_key: app.invoke_key().to_owned(),
        };
        let (tx, rx) = tokio::sync::oneshot::channel();
        // Synchronous commands run inside `on_message`.
        tauri::async_runtime::spawn_blocking(move || {
            window.on_message(
                request,
                Box::new(move |_, _, response, _, _| {
                    let _ = tx.send(response);
                }),
            )
        });
        let response = rx
            .await
            .map_err(|_| "The command did not answer".to_string());
        crate::reset::workspace_reset_request_finished(app.state(), ticket);
        match response? {
            InvokeResponse::Ok(InvokeResponseBody::Json(json)) => serde_json::from_str(&json)
                .map(Reply::Json)
                .map_err(|e| e.to_string()),
            InvokeResponse::Ok(InvokeResponseBody::Raw(bytes)) => Ok(Reply::Bytes(bytes)),
            InvokeResponse::Err(InvokeError(Value::String(error))) => Err(error),
            InvokeResponse::Err(InvokeError(error)) => Err(error.to_string()),
        }
    })
}

/// The session master answers only the host window.
fn host_window(window: &WebviewWindow) -> Result<(), String> {
    if window.label() == HOST_WINDOW {
        Ok(())
    } else {
        Err("Only the main window drives sessions".into())
    }
}

#[tauri::command]
pub fn remote_status(host: State<'_, RemoteHost>) -> Value {
    json!({ "enabled": host.gateway().is_some() })
}

#[tauri::command]
pub fn remote_session_publish(
    window: WebviewWindow,
    host: State<'_, RemoteHost>,
    feed: Value,
) -> Result<(), String> {
    host_window(&window)?;
    host.master.publish(&feed)
}

#[tauri::command]
pub fn remote_intent_reply(
    window: WebviewWindow,
    host: State<'_, RemoteHost>,
    request_id: String,
    ok: bool,
    value: Option<Value>,
    error: Option<String>,
) -> Result<(), String> {
    host_window(&window)?;
    let result = if ok {
        Ok(value.unwrap_or(Value::Null))
    } else {
        Err(error.unwrap_or_else(|| "The host window could not do that".into()))
    };
    host.master.reply(&request_id, result);
    Ok(())
}

pub fn window_closed(app: &AppHandle, label: &str) {
    client::window_closed(app, label);
    if label == HOST_WINDOW {
        if let Some(host) = app.try_state::<RemoteHost>() {
            host.master.window_closed();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dials_a_relay_given_by_its_page_address() {
        for (given, dialed) in [
            ("https://relay.example.com", "wss://relay.example.com"),
            ("HTTPS://relay.example.com/", "wss://relay.example.com"),
            ("http://127.0.0.1:8787", "ws://127.0.0.1:8787"),
            (
                "wss://relay.example.com/base",
                "wss://relay.example.com/base",
            ),
            ("  ws://localhost:8787  ", "ws://localhost:8787"),
        ] {
            assert_eq!(normalize_relay(given).unwrap(), dialed, "{given}");
        }
    }

    #[test]
    fn refuses_a_relay_it_could_not_dial() {
        for given in [
            "ftp://relay.example.com",
            "relay.example.com",
            "https://",
            "wss:///path",
        ] {
            assert!(normalize_relay(given).is_err(), "{given}");
        }
    }

    #[test]
    fn checks_the_relay_in_settings_and_takes_an_empty_one_as_none() {
        let with = |relay: &str| Settings {
            relay: Some(relay.into()),
            ..Settings::default()
        };
        assert_eq!(
            with("https://r.example")
                .checked()
                .unwrap()
                .relay
                .as_deref(),
            Some("wss://r.example")
        );
        assert_eq!(with("  ").checked().unwrap().relay, None);
        assert!(with("file:///etc").checked().is_err());
        assert_eq!(Settings::default().checked().unwrap().relay, None);
    }

    const NONE: BuiltIn = BuiltIn {
        relay: None,
        relay_key: None,
        registry: None,
        registry_key: None,
    };

    #[test]
    fn uses_the_built_in_services_unless_the_user_names_their_own() {
        let built_in = BuiltIn {
            relay: Some("https://relay.example"),
            relay_key: Some("relay-gate"),
            registry: Some("https://registry.example"),
            registry_key: Some("registry-gate"),
        };
        let mut settings = Settings::default();
        assert_eq!(
            settings.relay_in(&built_in),
            Some(Service {
                url: "wss://relay.example".into(),
                key: Some("relay-gate".into())
            })
        );
        let registry = settings.registry_in(&built_in).unwrap();
        assert_eq!(
            (registry.url.as_str(), registry.key.as_deref()),
            ("https://registry.example", Some("registry-gate"))
        );

        // The user's own address goes with the user's own key, never the built-in one.
        settings.relay = Some("wss://mine.example".into());
        settings.registry = Some("https://mine.example".into());
        assert_eq!(
            settings.relay_in(&built_in),
            Some(Service {
                url: "wss://mine.example".into(),
                key: None
            })
        );
        assert_eq!(settings.registry_in(&built_in).unwrap().key, None);
    }

    #[test]
    fn a_build_without_services_or_with_empty_ones_needs_the_user_to_fill_them() {
        let empty = BuiltIn {
            relay: Some(" "),
            relay_key: Some(""),
            registry: Some(""),
            registry_key: None,
        };
        for built_in in [NONE, empty] {
            assert_eq!(Settings::default().relay_in(&built_in), None);
            assert!(Settings::default().registry_in(&built_in).is_none());
        }
    }
}
