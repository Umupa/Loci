//! Commands for the settings page and the device list: this device's remote
//! access settings, its device group and pairing. All of them act on this
//! device only.

use std::sync::Arc;
use std::time::Duration;

use rand_core::{OsRng, RngCore};
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager};

use super::alma_relay::AlmaRelayTunnel;
use super::device_group::{
    decode32, now_ms, parse_invite, Device, DeviceGroup, Identity, Registry,
};
use super::pairing::{self, PairingCode};
use super::tunnel::Tunnel;
use super::{
    apply, computer_name, delete_secret, device_name, host_page, identity, new_device_key,
    registry, remember_host, save_secret, update_menu, write_settings, Pairing, RemoteHost,
    Settings, BUILT_IN, GROUP_SECRET,
};

/// How long a device waits for the host's side of the pairing exchange.
const REDEEM_TIMEOUT: Duration = Duration::from_secs(60);

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|e| e.to_string())?
}

fn status(app: &AppHandle) -> Result<Value, String> {
    let host = app.state::<RemoteHost>();
    let mut inner = host.inner.lock().unwrap();
    let (key, group) = identity(app, &mut inner)?;
    Ok(json!({
        "deviceId": super::device_group::device_id_for(&key.verifying_key()),
        "name": device_name(&inner.settings),
        "registry": inner.settings.registry,
        "group": group.map(|group| json!({ "groupId": group.group_id, "invite": group.invite() })),
    }))
}

#[tauri::command]
pub fn remote_group_status(app: AppHandle) -> Result<Value, String> {
    status(&app)
}

#[tauri::command]
pub async fn remote_group_create(app: AppHandle, name: Option<String>) -> Result<Value, String> {
    let mut secret = [0; 32];
    OsRng.fill_bytes(&mut secret);
    join(&app, secret, None, name).await
}

#[tauri::command]
pub async fn remote_group_join(
    app: AppHandle,
    invite: String,
    name: Option<String>,
) -> Result<Value, String> {
    let (secret, registry) = parse_invite(&invite)?;
    let registry = registry.map(|url| Registry { url, key: None });
    join(&app, secret, registry, name).await
}

/// Adds this device to the group `secret` names, in `given` (a registry key
/// in it replaces the saved one) or the registry in the settings, and starts
/// using it.
async fn join(
    app: &AppHandle,
    secret: [u8; 32],
    given: Option<Registry>,
    name: Option<String>,
) -> Result<Value, String> {
    let host = app.state::<RemoteHost>();
    let (key, mut settings) = {
        let mut inner = host.inner.lock().unwrap();
        let (key, group) = identity(app, &mut inner)?;
        if group.is_some() {
            return Err("This device is already in a device group. Leave it first.".into());
        }
        (key, inner.settings.clone())
    };
    if let Some(given) = given {
        // The built-in registry stays built in, so its key stays out of remote.json.
        if BUILT_IN
            .registry()
            .is_some_and(|built_in| built_in.url == given.url)
        {
            settings.registry = None;
            settings.registry_key = None;
        } else {
            settings.registry = Some(given.url);
            if given.key.is_some() {
                settings.registry_key = given.key;
            }
        }
    }
    let registry: Registry = registry(&settings).ok_or("Set the device registry first")?;
    let name = name.unwrap_or_else(|| device_name(&settings));
    let group = Arc::new(DeviceGroup::new(secret, key.clone(), registry));
    let (joining, joined_as) = (group.clone(), name.clone());
    blocking(move || {
        joining.join(&joined_as)?;
        joining.refresh()
    })
    .await?;
    save_secret(app, GROUP_SECRET, &secret)?;
    settings.name = Some(name);
    write_settings(app, &settings)?;
    {
        let mut inner = host.inner.lock().unwrap();
        inner.settings = settings;
        inner.identity = Some((key, Some(group)));
    }
    apply(app);
    update_menu(app);
    status(app)
}

/// Removes this device from its group. The registry bans a removed key for
/// good, so the device also gets a new key, with which it could join again.
#[tauri::command]
pub async fn remote_group_leave(app: AppHandle) -> Result<Value, String> {
    let host = app.state::<RemoteHost>();
    let group = host
        .identity(&app)?
        .1
        .ok_or("This device is not in a device group")?;
    let leaving = group.clone();
    blocking(move || leaving.remove(&leaving.device_id)).await?;
    // What this device kept from the group's hosts goes with the group.
    if let Ok(data) = app.path().app_data_dir() {
        super::cache::clear(&super::cache::root(&data), None);
    }
    delete_secret(&app, GROUP_SECRET)?;
    let key = new_device_key(&app)?;
    host.inner.lock().unwrap().identity = Some((key, None));
    *host.pairing.lock().unwrap() = None;
    apply(&app);
    update_menu(&app);
    status(&app)
}

fn device_json(device: &Device, self_id: &str, now: i64) -> Value {
    let is_self = device.device_id == self_id;
    let online = is_self || device.online(now);
    json!({
        "deviceId": device.device_id,
        "name": device.name,
        "platform": device.platform,
        "addedAt": device.added_at,
        "lastSeen": device.last_seen,
        "online": online,
        "isSelf": is_self,
        "connectable": !is_self && online && device.route.is_some(),
    })
}

fn listing(group: &DeviceGroup) -> Vec<Value> {
    let now = now_ms();
    group
        .devices()
        .iter()
        .map(|device| device_json(device, &group.device_id, now))
        .collect()
}

#[tauri::command]
pub async fn remote_devices_list(
    app: AppHandle,
    refresh: Option<bool>,
) -> Result<Vec<Value>, String> {
    let Some(group) = app.state::<RemoteHost>().identity(&app)?.1 else {
        return Ok(Vec::new());
    };
    if refresh.unwrap_or(false) {
        let refreshing = group.clone();
        blocking(move || refreshing.refresh()).await?;
    }
    update_menu(&app);
    Ok(listing(&group))
}

#[tauri::command]
pub async fn remote_device_remove(app: AppHandle, device_id: String) -> Result<Vec<Value>, String> {
    let group = app
        .state::<RemoteHost>()
        .identity(&app)?
        .1
        .ok_or("This device is not in a device group")?;
    if device_id == group.device_id {
        return Err("To take this device out of the group, leave the group".into());
    }
    let removing = group.clone();
    let removed = device_id.clone();
    blocking(move || removing.remove(&device_id)).await?;
    if let Ok(data) = app.path().app_data_dir() {
        super::cache::clear(&super::cache::root(&data), Some(&removed));
    }
    update_menu(&app);
    Ok(listing(&group))
}

/// The saved settings, plus which services this build carries (whether, not
/// what) and the name used when none is set.
fn settings_json(settings: &Settings) -> Value {
    let mut value = serde_json::to_value(settings).expect("settings serialize");
    value["builtIn"] = json!({
        "relay": BUILT_IN.relay().is_some(),
        "registry": BUILT_IN.registry().is_some(),
    });
    value["defaultName"] = json!(computer_name().unwrap_or_else(|| "Loci".into()));
    value
}

#[tauri::command]
pub fn remote_settings_get(app: AppHandle) -> Value {
    let host = app.state::<RemoteHost>();
    let settings = host.inner.lock().unwrap().settings.clone();
    settings_json(&settings)
}

/// Merges `settings` (any of the fields; `null` clears one) into the saved
/// settings, then starts or stops remote access to match.
#[tauri::command]
pub fn remote_settings_set(app: AppHandle, settings: Value) -> Result<Value, String> {
    let host = app.state::<RemoteHost>();
    let (updated, restart) = {
        let mut inner = host.inner.lock().unwrap();
        let mut merged = serde_json::to_value(&inner.settings).map_err(|e| e.to_string())?;
        for (key, value) in settings.as_object().ok_or("Settings must be an object")? {
            merged[key] = value.clone();
        }
        let updated = serde_json::from_value::<Settings>(merged)
            .map_err(|e| e.to_string())?
            .checked()?;
        write_settings(&app, &updated)?;
        let registry_changed = (&updated.registry, &updated.registry_key)
            != (&inner.settings.registry, &inner.settings.registry_key);
        if registry_changed {
            // The group lives in the registry: open it again from there.
            inner.identity = None;
        }
        let restart = updated.serving() != inner.settings.serving();
        inner.settings = updated.clone();
        (updated, restart)
    };
    if restart {
        apply(&app);
    }
    Ok(settings_json(&updated))
}

fn pairing_json(pairing: &Pairing) -> Value {
    json!({ "code": pairing.code, "expiresAt": pairing.expires_at })
}

/// The pairing code on show, or `null`.
#[tauri::command]
pub fn remote_pairing_status(app: AppHandle) -> Value {
    let host = app.state::<RemoteHost>();
    let pairing = host.pairing.lock().unwrap();
    pairing.as_ref().map_or(Value::Null, pairing_json)
}

/// Shows a new pairing code for another device to type in, and waits for
/// it on the relay. Creates the device group first if there is none, and
/// turns remote access on, since the device will connect right after. The
/// outcome arrives as `remote-pairing-changed`.
#[tauri::command]
pub async fn remote_pairing_start(app: AppHandle) -> Result<Value, String> {
    let host = app.state::<RemoteHost>();
    let relay = host
        .inner
        .lock()
        .unwrap()
        .settings
        .relay_in(&BUILT_IN)
        .ok_or("Set a relay under Advanced first")?;
    let group = match host.identity(&app)?.1 {
        Some(group) => group,
        None => {
            let mut secret = [0; 32];
            OsRng.fill_bytes(&mut secret);
            join(&app, secret, None, None).await?;
            host.identity(&app)?
                .1
                .ok_or("Could not create a device group")?
        }
    };
    let settings = {
        let mut inner = host.inner.lock().unwrap();
        if !inner.settings.enabled {
            let mut settings = inner.settings.clone();
            settings.enabled = true;
            write_settings(&app, &settings)?;
            inner.settings = settings;
        }
        inner.settings.clone()
    };
    if host.gateway().is_none() {
        apply(&app);
    }

    let code = PairingCode::generate();
    let name = device_name(&settings);
    let invitation = group.invitation(&name);
    let tunnel = AlmaRelayTunnel {
        relay: relay.url,
        code: code.rendezvous(),
        name: format!("{name} (pairing)"),
        registration_key: relay.key,
    };
    let text = code.to_text();
    let (task_app, task_text) = (app.clone(), text.clone());
    let task = tauri::async_runtime::spawn(async move {
        let refreshing = group.clone();
        let result = pairing::host(
            tunnel.listen(),
            &code,
            &invitation,
            pairing::LIFETIME,
            |_| async move {
                let _ = tauri::async_runtime::spawn_blocking(move || refreshing.refresh()).await;
            },
        )
        .await;
        let event = match result {
            Ok(device_id) => json!({
                "state": "paired",
                "deviceId": device_id,
                "name": group.find(&device_id).map(|device| device.name),
            }),
            Err(error) if error == pairing::EXPIRED => json!({ "state": "expired" }),
            Err(error) => json!({ "state": "failed", "error": error }),
        };
        let host = task_app.state::<RemoteHost>();
        // Taken out last: dropping it ends this task.
        let finished = host
            .pairing
            .lock()
            .unwrap()
            .take_if(|pairing| pairing.code == task_text);
        update_menu(&task_app);
        let _ = task_app.emit("remote-pairing-changed", event);
        drop(finished);
    });
    let pairing = Pairing {
        code: text,
        expires_at: now_ms() + pairing::LIFETIME.as_millis() as i64,
        task,
    };
    let shown = pairing_json(&pairing);
    *host.pairing.lock().unwrap() = Some(pairing);
    Ok(shown)
}

/// Takes the pairing code back.
#[tauri::command]
pub fn remote_pairing_cancel(app: AppHandle) {
    let host = app.state::<RemoteHost>();
    let cancelled = host.pairing.lock().unwrap().take();
    drop(cancelled);
}

/// Joins the group of the computer showing `code`, remembers that computer
/// and opens a window connected to it. Returns the computer's `deviceId`
/// and `name`.
#[tauri::command]
pub async fn remote_pairing_redeem(
    app: AppHandle,
    code: String,
    name: Option<String>,
) -> Result<Value, String> {
    let code = PairingCode::parse(&code)?;
    let host = app.state::<RemoteHost>();
    if host.identity(&app)?.1.is_some() {
        return Err(
            "This device is already in a device group. Leave it under Advanced first.".into(),
        );
    }
    let relay = host
        .inner
        .lock()
        .unwrap()
        .settings
        .relay_in(&BUILT_IN)
        .ok_or("Set a relay under Advanced first")?;
    let tunnel = AlmaRelayTunnel {
        relay: relay.url,
        code: code.rendezvous(),
        name: String::new(),
        registration_key: None,
    };
    let conn = tunnel.dial().await.map_err(|error| {
        // The relay answers 502 when nobody registered the code's tunnel.
        if error.contains("502") {
            "No computer is showing that pairing code. Check it, or make a new one.".to_string()
        } else {
            error
        }
    })?;
    let (invitation, redeemed) = tokio::time::timeout(REDEEM_TIMEOUT, pairing::redeem(conn, &code))
        .await
        .map_err(|_| "The other computer stopped answering".to_string())??;
    let secret = decode32(&invitation.secret).ok_or("Malformed pairing message")?;
    let registry = Registry {
        url: invitation.registry.clone(),
        key: invitation.registry_key.clone(),
    };
    let joined = join(&app, secret, Some(registry), name).await;
    let reply = match &joined {
        Ok(status) => Ok(status["deviceId"].as_str().unwrap_or_default()),
        Err(error) => Err(error.as_str()),
    };
    tokio::time::timeout(REDEEM_TIMEOUT, redeemed.joined(reply))
        .await
        .map_err(|_| "The other computer stopped answering".to_string())??;
    joined?;

    remember_host(&app, &invitation.host, &invitation.name);
    {
        let mut inner = host.inner.lock().unwrap();
        if inner.settings.auto_connect.is_none() {
            let mut settings = inner.settings.clone();
            settings.auto_connect = Some(true);
            if write_settings(&app, &settings).is_ok() {
                inner.settings = settings;
            }
        }
    }
    crate::window::open_new_window(&app, Some(&host_page(&invitation.host)))?;
    Ok(json!({ "deviceId": invitation.host, "name": invitation.name }))
}
