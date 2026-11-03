//! Commands for the settings page and the device list: this device's remote
//! access settings and its device group. All of them act on this device only.

use std::sync::Arc;

use rand_core::{OsRng, RngCore};
use serde_json::{json, Value};
use tauri::{AppHandle, Manager};

use super::device_group::{now_ms, parse_invite, Device, DeviceGroup, Identity, Registry};
use super::{
    apply, delete_secret, device_name, identity, new_device_key, registry, save_secret,
    write_settings, RemoteHost, Settings, GROUP_SECRET,
};

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
    join(&app, secret, registry, name).await
}

/// Adds this device to the group `secret` names, in `registry` or the one
/// in the settings, and starts using it.
async fn join(
    app: &AppHandle,
    secret: [u8; 32],
    invite_registry: Option<String>,
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
    if invite_registry.is_some() {
        settings.registry = invite_registry;
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
    apply(&app);
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
    Ok(listing(&group))
}

#[tauri::command]
pub fn remote_settings_get(app: AppHandle) -> Value {
    let host = app.state::<RemoteHost>();
    let settings = host.inner.lock().unwrap().settings.clone();
    serde_json::to_value(settings).expect("settings serialize")
}

/// Merges `settings` (any of the fields; `null` clears one) into the saved
/// settings, then starts or stops remote access to match.
#[tauri::command]
pub fn remote_settings_set(app: AppHandle, settings: Value) -> Result<Value, String> {
    let host = app.state::<RemoteHost>();
    let updated = {
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
        inner.settings = updated.clone();
        updated
    };
    apply(&app);
    serde_json::to_value(updated).map_err(|e| e.to_string())
}
