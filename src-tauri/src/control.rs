//! Authenticated loopback transport. App windows own execution; callers never
//! receive arbitrary Tauri command access or direct database write access.
use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::process::Command;
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

use crate::cli_access;

const APP_TURN_INACTIVE: &str = "Loci app access is inactive. Call the CLI during an active agent turn. Retrying this request now will not enable access.";
const CANVAS_TURN_INACTIVE: &str = "Loci canvas access is only available while this session's agent turn is running. Retrying this request now will not enable access.";
const CANVAS_DISABLED: &str = "Loci's built-in Excalidraw canvas tools are turned off in Settings → MCP. Turning them on there applies from this session's next turn. Retrying this request now will not enable access.";
/// Asked by the app's own CLI: which stdio command runs a built-in MCP server.
/// The host answers it; a window never sees it.
const MCP_SERVER_ACTION: &str = "mcp.server";
const APP_REQUEST_MAX: usize = 262_144;
/// A canvas save carries drawing elements. The official Excalidraw MCP server
/// accepts 5 MB of them, so leave room for the JSON envelope around that.
const CANVAS_REQUEST_MAX: usize = 6 * 1024 * 1024;
/// The namespace of the `loci` CLI run from a terminal outside Loci.
const EXTERNAL_NAMESPACE: &str = "cli";
/// A command from a terminal may wait on a confirmation dialog.
const EXTERNAL_TIMEOUT: Duration = Duration::from_secs(120);
/// How long a terminal command waits for a window that is opening.
const WINDOW_READY_WAIT: Duration = Duration::from_secs(30);
const EXTERNAL_DISABLED: &str = "Command-line access to this Loci is turned off. Turn it on in Settings → General → Command line.";
const EXTERNAL_UNAUTHORIZED: &str = "The Loci token is missing or out of date. It is rotated from Settings → General → Command line.";
#[derive(Clone)]
struct Grant {
    window: String,
    session: String,
    token: String,
}

struct Pending {
    window: String,
    reply: mpsc::Sender<Value>,
}
struct ActiveTurn {
    window: String,
    app_allowed: bool,
    /// The built-in Excalidraw switch as it was when the turn started, so a
    /// change applies from the next turn and a running turn can finish.
    canvas_allowed: bool,
}

/// Access for the `loci` CLI outside Loci: one local token, kept in a file only
/// this user can read, and a switch the user can turn off.
#[derive(Default)]
struct External {
    enabled: bool,
    token: Option<String>,
}

#[derive(Default)]
struct Inner {
    app_grants: HashMap<String, Grant>,
    pending: HashMap<String, Pending>,
    active: HashMap<String, ActiveTurn>,
    external: External,
    /// Windows whose command listener is running.
    ready: HashSet<String>,
}

impl Inner {
    // Install a stable credential before spawning; every request still needs an opted-in turn.
    fn prepare_app_grant(&mut self, session: &str, window: &str) {
        let token = self
            .app_grants
            .get(session)
            .map(|grant| grant.token.clone())
            .unwrap_or_else(|| {
                format!(
                    "{}{}",
                    uuid::Uuid::new_v4().simple(),
                    uuid::Uuid::new_v4().simple()
                )
            });
        self.app_grants.insert(
            session.into(),
            Grant {
                window: window.into(),
                session: session.into(),
                token,
            },
        );
    }
    fn window_sessions(&self, label: &str) -> Vec<String> {
        let mut ids: Vec<String> = self
            .app_grants
            .values()
            .filter(|grant| grant.window == label)
            .map(|grant| grant.session.clone())
            .chain(
                self.active
                    .iter()
                    .filter(|(_, turn)| turn.window == label)
                    .map(|(id, _)| id.clone()),
            )
            .collect();
        ids.sort();
        ids.dedup();
        ids
    }
    fn close_window(&mut self, label: &str) -> Vec<String> {
        self.ready.remove(label);
        let ids = self.window_sessions(label);
        self.app_grants.retain(|id, _| !ids.contains(id));
        self.active.retain(|id, _| !ids.contains(id));
        self.pending.retain(|_, pending| {
            if pending.window != label {
                return true;
            }
            let _ = pending
                .reply
                .send(json!({"ok":false,"error":"Loci window closed"}));
            false
        });
        ids
    }
}

pub struct ControlHost {
    endpoint: String,
    inner: Arc<Mutex<Inner>>,
    identifier: String,
    version: String,
    /// `<app data>/control`; absent when the data folder is unknown.
    control_dir: Option<PathBuf>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    token: String,
    namespace: String,
    action: String,
    input: Value,
    request_id: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Event {
    id: String,
    namespace: String,
    session_id: String,
    request_id: String,
    action: String,
    input: Value,
}
/// `app` is the Loci app CLI and needs an agent turn's grant. `canvas` is the
/// built-in Excalidraw server: every session may draw while the switch in
/// Settings is on, but only on its own project's canvases and only while its
/// turn runs. The server is reached the same way whether an agent CLI
/// attached it over MCP or calls it through the app's CLI.
fn request_grant(host: &Inner, namespace: &str, token: &str) -> Result<Grant, String> {
    if !matches!(namespace, "app" | "canvas") {
        return Err("Unknown control namespace".into());
    }
    let grant = host
        .app_grants
        .values()
        .find(|grant| grant.token == token)
        .cloned()
        .ok_or("Connection revoked or unauthorized")?;
    let turn = host
        .active
        .get(&grant.session)
        .filter(|turn| turn.window == grant.window);
    match namespace {
        "canvas" if turn.is_some_and(|turn| turn.canvas_allowed) => Ok(grant),
        "canvas" if turn.is_some() => Err(CANVAS_DISABLED.into()),
        "canvas" => Err(CANVAS_TURN_INACTIVE.into()),
        _ if turn.is_some_and(|turn| turn.app_allowed) => Ok(grant),
        _ => Err(APP_TURN_INACTIVE.into()),
    }
}

/// A terminal's request: allowed while the switch is on and the token matches.
/// Agents' turn tokens never pass here, and this token passes nowhere else.
fn external_access(host: &Inner, token: &str) -> Result<(), (&'static str, &'static str)> {
    if !host.external.enabled {
        return Err((EXTERNAL_DISABLED, "disabled"));
    }
    match &host.external.token {
        Some(expected) if cli_access::same_secret(expected, token) => Ok(()),
        _ => Err((EXTERNAL_UNAUTHORIZED, "unauthorized")),
    }
}

/// The window that runs a terminal's command: the main window, else another
/// that is listening.
fn pick_window(ready: &HashSet<String>) -> Option<String> {
    if ready.contains("main") {
        return Some("main".into());
    }
    ready.iter().min().cloned()
}

fn request_size_error(namespace: &str, bytes: usize) -> Option<&'static str> {
    if bytes > CANVAS_REQUEST_MAX {
        Some("Request exceeds 6 MiB")
    } else if namespace != "canvas" && bytes > APP_REQUEST_MAX {
        Some("Request exceeds 256 KiB")
    } else {
        None
    }
}

pub fn init(app: &AppHandle) -> Result<(), String> {
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let endpoint = listener
        .local_addr()
        .map_err(|e| e.to_string())?
        .to_string();
    let identifier = app.config().identifier.clone();
    let version = app.package_info().version.to_string();
    let control_dir = app
        .path()
        .app_data_dir()
        .ok()
        .map(|dir| cli_access::control_dir(&dir));
    let mut inner = Inner::default();
    if let Some(dir) = &control_dir {
        match publish_endpoint(dir, &endpoint, &identifier, &version) {
            Ok(external) => inner.external = external,
            Err(error) => eprintln!("Loci command-line access is unavailable: {error}"),
        }
    }
    let inner = Arc::new(Mutex::new(inner));
    app.manage(ControlHost {
        endpoint,
        inner: inner.clone(),
        identifier,
        version,
        control_dir,
    });
    let app = app.clone();
    std::thread::spawn(move || {
        // Limit concurrent readers, including unauthenticated sockets.
        let (tx, rx) = mpsc::sync_channel::<TcpStream>(32);
        let rx = Arc::new(Mutex::new(rx));
        for _ in 0..8 {
            let rx = rx.clone();
            let app = app.clone();
            let inner = inner.clone();
            std::thread::spawn(move || loop {
                let stream = match rx.lock() {
                    Ok(rx) => rx.recv(),
                    Err(_) => return,
                };
                let Ok(stream) = stream else { return };
                serve(stream, &app, &inner);
            });
        }
        for stream in listener.incoming().flatten() {
            let _ = tx.try_send(stream);
        }
    });
    Ok(())
}

/// Tells the `loci` CLI where this run listens, and readies its token.
fn publish_endpoint(
    dir: &std::path::Path,
    endpoint: &str,
    identifier: &str,
    version: &str,
) -> Result<External, String> {
    cli_access::ensure_private_dir(dir)?;
    cli_access::write_endpoint(
        dir,
        &cli_access::Endpoint {
            endpoint: endpoint.into(),
            pid: std::process::id(),
            version: version.into(),
            identifier: identifier.into(),
        },
    )?;
    if !cli_access::access_enabled(dir) {
        cli_access::remove_token(dir);
        return Ok(External::default());
    }
    Ok(External {
        enabled: true,
        token: Some(cli_access::ensure_token(dir)?),
    })
}

/// The app is quitting: a terminal should hear "not running", not time out.
pub fn shutdown(app: &AppHandle) {
    if let Some(dir) = app
        .try_state::<ControlHost>()
        .and_then(|host| host.control_dir.clone())
    {
        cli_access::remove_endpoint(&dir, std::process::id());
    }
}

fn external_failure(error: &str, code: &str) -> Value {
    json!({"ok": false, "error": error, "code": code})
}

/// A window to run the command in. Without one listening, the main window
/// is shown or opened and the command waits for it.
fn external_window(app: &AppHandle, inner: &Arc<Mutex<Inner>>) -> Result<String, String> {
    let ready =
        |inner: &Arc<Mutex<Inner>>| inner.lock().ok().and_then(|host| pick_window(&host.ready));
    if let Some(label) = ready(inner) {
        if let Some(window) = app.get_webview_window(&label) {
            if !window.is_visible().unwrap_or(true) {
                let _ = window.show();
            }
        }
        return Ok(label);
    }
    crate::window::show_hidden_or_open_new(app)?;
    let started = std::time::Instant::now();
    while started.elapsed() < WINDOW_READY_WAIT {
        if let Some(label) = ready(inner) {
            return Ok(label);
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Err("No Loci window is ready to run the command".into())
}

fn serve_external(app: &AppHandle, inner: &Arc<Mutex<Inner>>, request: Request) -> Value {
    let host = app.state::<ControlHost>();
    {
        let Ok(guard) = inner.lock() else {
            return external_failure("Control service unavailable", "failed");
        };
        if let Err((error, code)) = external_access(&guard, &request.token) {
            return external_failure(error, code);
        }
    }
    match request.action.as_str() {
        "status" => {
            return json!({"ok": true, "result": {
                "running": true,
                "identifier": host.identifier,
                "version": host.version,
                "pid": std::process::id(),
                "externalAccess": true,
            }})
        }
        "cli.rotate-token" | "cli.disable" => {
            let Some(dir) = host.control_dir.clone() else {
                return external_failure("Loci has no data folder", "failed");
            };
            let Ok(mut guard) = inner.lock() else {
                return external_failure("Control service unavailable", "failed");
            };
            if request.action == "cli.disable" {
                if let Err(error) = cli_access::set_access_enabled(&dir, false) {
                    return external_failure(&error, "failed");
                }
                cli_access::remove_token(&dir);
                guard.external = External::default();
                return json!({"ok": true, "result": {"enabled": false}});
            }
            return match cli_access::rotate_token(&dir) {
                Ok(token) => {
                    guard.external.token = Some(token);
                    json!({"ok": true, "result": {"rotated": true}})
                }
                Err(error) => external_failure(&error, "failed"),
            };
        }
        _ => {}
    }
    let window = match external_window(app, inner) {
        Ok(window) => window,
        Err(error) => return external_failure(&error, "not_running"),
    };
    let id = uuid::Uuid::new_v4().to_string();
    let (tx, rx) = mpsc::channel();
    {
        let Ok(mut guard) = inner.lock() else {
            return external_failure("Control service unavailable", "failed");
        };
        if guard.pending.len() >= 24 {
            return external_failure("Too many pending control requests", "busy");
        }
        guard.pending.insert(
            id.clone(),
            Pending {
                window: window.clone(),
                reply: tx,
            },
        );
    }
    let event = Event {
        id: id.clone(),
        namespace: request.namespace,
        session_id: String::new(),
        request_id: request.request_id,
        action: request.action,
        input: request.input,
    };
    let response = if app
        .emit_to(window.as_str(), "loci-control-request", event)
        .is_err()
    {
        external_failure("Loci executor is unavailable", "not_running")
    } else {
        rx.recv_timeout(EXTERNAL_TIMEOUT).unwrap_or_else(|_| {
            external_failure(
                "Loci did not answer in time. Retry with the same request ID.",
                "timeout",
            )
        })
    };
    if let Ok(mut guard) = inner.lock() {
        guard.pending.remove(&id);
    }
    response
}

fn serve(mut stream: TcpStream, app: &AppHandle, inner: &Arc<Mutex<Inner>>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(3)));
    let result = (|| -> Result<Value, String> {
        let mut raw = String::new();
        BufReader::new(&mut stream)
            .take(CANVAS_REQUEST_MAX as u64 + 1)
            .read_line(&mut raw)
            .map_err(|e| e.to_string())?;
        if let Some(error) = request_size_error("canvas", raw.len()) {
            return Err(error.into());
        }
        let request: Request = serde_json::from_str(&raw).map_err(|_| "Invalid control request")?;
        if let Some(error) = request_size_error(&request.namespace, raw.len()) {
            return Err(error.into());
        }
        if !request.input.is_object()
            || request.request_id.is_empty()
            || request.request_id.len() > 128
        {
            return Err("Invalid input or request ID".into());
        }
        if request.namespace == EXTERNAL_NAMESPACE {
            // Read without a timeout: a command may wait for a dialog.
            return Ok(serve_external(app, inner, request));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let (tx, rx) = mpsc::channel();
        let hosted = request.action == MCP_SERVER_ACTION && request.namespace == "canvas";
        let grant = {
            let mut host = inner.lock().map_err(|_| "Control service unavailable")?;
            let grant = request_grant(&host, &request.namespace, &request.token)?;
            if !hosted {
                if host.pending.len() >= 24 {
                    return Err("Too many pending control requests".into());
                }
                host.pending.insert(
                    id.clone(),
                    Pending {
                        window: grant.window.clone(),
                        reply: tx,
                    },
                );
            }
            grant
        };
        if hosted {
            // Looking up the runtime can take a moment; the lock is released.
            let server = crate::canvas_mcp::canvas_server(app)?;
            return Ok(json!({"ok": true, "result": server}));
        }
        let event = Event {
            id: id.clone(),
            namespace: request.namespace,
            session_id: grant.session,
            request_id: request.request_id,
            action: request.action,
            input: request.input,
        };
        let delivered = app.emit_to(grant.window.as_str(), "loci-control-request", event);
        let result = if delivered.is_err() {
            Err("Loci executor is unavailable".into())
        } else {
            rx.recv_timeout(Duration::from_secs(35))
                .map_err(|_| "Control request timed out. Retry with the same request ID.".into())
        };
        if let Ok(mut host) = inner.lock() {
            host.pending.remove(&id);
        }
        result
    })();
    let response = result.unwrap_or_else(|error| {
        if error == APP_TURN_INACTIVE || error == CANVAS_TURN_INACTIVE || error == CANVAS_DISABLED {
            json!({"ok": false, "error": error, "retryable": false})
        } else {
            json!({"ok": false, "error": error})
        }
    });
    let _ = writeln!(stream, "{response}");
}
#[tauri::command]
pub fn control_authorize_turn(
    window: WebviewWindow,
    host: State<'_, ControlHost>,
    session_id: String,
    cwd: String,
    app_access: bool,
    canvas_access: bool,
) -> Result<(), String> {
    let cwd = std::fs::canonicalize(crate::fs::expand_home(&cwd)).map_err(|e| e.to_string())?;
    if !cwd.is_dir() {
        return Err("Choose a project folder first".into());
    }
    let mut inner = host
        .inner
        .lock()
        .map_err(|_| "Control service unavailable")?;
    inner.prepare_app_grant(&session_id, window.label());
    inner.active.insert(
        session_id,
        ActiveTurn {
            window: window.label().into(),
            app_allowed: app_access,
            canvas_allowed: canvas_access,
        },
    );
    Ok(())
}

/// A window's command listener is running; terminal commands may go to it.
#[tauri::command]
pub fn control_window_ready(window: WebviewWindow, host: State<'_, ControlHost>) {
    if let Ok(mut inner) = host.inner.lock() {
        inner.ready.insert(window.label().into());
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CliAccess {
    enabled: bool,
    identifier: String,
    executable: Option<String>,
    token_path: Option<String>,
}

fn cli_access_view(host: &ControlHost) -> CliAccess {
    let enabled = host
        .inner
        .lock()
        .map(|inner| inner.external.enabled)
        .unwrap_or(false);
    CliAccess {
        enabled,
        identifier: host.identifier.clone(),
        executable: std::env::current_exe()
            .ok()
            .map(|path| path.to_string_lossy().into_owned()),
        token_path: host.control_dir.as_ref().map(|dir| {
            dir.join(cli_access::TOKEN_FILE)
                .to_string_lossy()
                .into_owned()
        }),
    }
}

#[tauri::command]
pub fn cli_access_status(host: State<'_, ControlHost>) -> CliAccess {
    cli_access_view(&host)
}

/// Turns command-line access on or off. Off removes the token, so a token
/// copied earlier stops working too.
#[tauri::command]
pub fn cli_access_set(host: State<'_, ControlHost>, enabled: bool) -> Result<CliAccess, String> {
    let dir = host.control_dir.clone().ok_or("Loci has no data folder")?;
    {
        let mut inner = host
            .inner
            .lock()
            .map_err(|_| "Control service unavailable")?;
        cli_access::set_access_enabled(&dir, enabled)?;
        if enabled {
            inner.external = External {
                enabled: true,
                token: Some(cli_access::ensure_token(&dir)?),
            };
        } else {
            cli_access::remove_token(&dir);
            inner.external = External::default();
        }
    }
    Ok(cli_access_view(&host))
}

/// A new token; the old one stops working at once.
#[tauri::command]
pub fn cli_access_rotate(host: State<'_, ControlHost>) -> Result<(), String> {
    let dir = host.control_dir.clone().ok_or("Loci has no data folder")?;
    let mut inner = host
        .inner
        .lock()
        .map_err(|_| "Control service unavailable")?;
    if !inner.external.enabled {
        return Err("Turn command-line access on first".into());
    }
    inner.external.token = Some(cli_access::rotate_token(&dir)?);
    Ok(())
}

#[tauri::command]
pub fn control_turn_finished(host: State<'_, ControlHost>, session_id: String) {
    if let Ok(mut inner) = host.inner.lock() {
        inner.active.remove(&session_id);
    }
}

pub fn window_closed(app: &AppHandle, label: &str) {
    let host = app.state::<ControlHost>();
    let ids = {
        let Ok(inner) = host.inner.lock() else { return };
        inner.window_sessions(label)
    };
    for id in &ids {
        let _ = crate::harness::harness_kill(app.state(), id.clone());
    }
    if let Ok(mut inner) = host.inner.lock() {
        inner.close_window(label);
    };
}
/// A provider may start its process under a generation-scoped id
/// (`<session>#<n>`, as Antigravity does). The credential belongs to the
/// session that owns the process, whatever generation it is.
fn owning_session(child_id: &str) -> &str {
    child_id
        .split_once('#')
        .map_or(child_id, |(session, _)| session)
}

pub fn configure_child(app: &AppHandle, session_id: &str, cmd: &mut Command) {
    cmd.env_remove("LOCI_APP_ENDPOINT")
        .env_remove("LOCI_APP_TOKEN");
    let Some(host) = app.try_state::<ControlHost>() else {
        return;
    };
    if let Ok(inner) = host.inner.lock() {
        if let Some(grant) = inner.app_grants.get(owning_session(session_id)) {
            cmd.env("LOCI_APP_ENDPOINT", &host.endpoint)
                .env("LOCI_APP_TOKEN", &grant.token);
        }
    };
}

#[tauri::command]
pub fn app_cli_path() -> Result<String, String> {
    std::env::current_exe()
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn control_reply(
    window: WebviewWindow,
    host: State<'_, ControlHost>,
    id: String,
    response: Value,
) -> Result<(), String> {
    let mut inner = host
        .inner
        .lock()
        .map_err(|_| "Control service unavailable")?;
    if inner
        .pending
        .get(&id)
        .is_some_and(|p| p.window == window.label())
    {
        if let Some(pending) = inner.pending.remove(&id) {
            let _ = pending.reply.send(response);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn app_token_survives_turns_but_requires_active_opt_in() {
        let mut inner = Inner::default();
        inner.prepare_app_grant("session", "main");
        let token = inner.app_grants["session"].token.clone();
        assert!(request_grant(&inner, "app", &token).is_err());
        inner.active.insert(
            "session".into(),
            ActiveTurn {
                window: "main".into(),
                app_allowed: false,
                canvas_allowed: true,
            },
        );
        assert!(request_grant(&inner, "app", &token).is_err());
        inner.prepare_app_grant("session", "main");
        assert_eq!(inner.app_grants["session"].token, token);
        inner.active.get_mut("session").unwrap().app_allowed = true;
        assert!(request_grant(&inner, "app", &token).is_ok());
        assert!(request_grant(&inner, "other", &token).is_err());
        inner.active.get_mut("session").unwrap().window = "other".into();
        assert!(request_grant(&inner, "app", &token).is_err());
        inner.active.remove("session");
        assert!(request_grant(&inner, "app", &token).is_err());
    }
    #[test]
    fn canvas_access_needs_an_active_turn_but_not_app_access() {
        let mut inner = Inner::default();
        inner.prepare_app_grant("session", "main");
        let token = inner.app_grants["session"].token.clone();
        assert_eq!(
            request_grant(&inner, "canvas", &token).err().as_deref(),
            Some(CANVAS_TURN_INACTIVE)
        );
        inner.active.insert(
            "session".into(),
            ActiveTurn {
                window: "main".into(),
                app_allowed: false,
                canvas_allowed: true,
            },
        );
        assert_eq!(
            request_grant(&inner, "canvas", &token).unwrap().session,
            "session"
        );
        // Drawing does not widen what the app CLI may do.
        assert!(request_grant(&inner, "app", &token).is_err());
        assert!(request_grant(&inner, "canvas", "wrong-token").is_err());
        inner.active.get_mut("session").unwrap().window = "other".into();
        assert!(request_grant(&inner, "canvas", &token).is_err());
    }
    #[test]
    fn the_canvas_switch_is_fixed_for_a_turn_and_refuses_when_off() {
        let mut inner = Inner::default();
        inner.prepare_app_grant("session", "main");
        let token = inner.app_grants["session"].token.clone();
        inner.active.insert(
            "session".into(),
            ActiveTurn {
                window: "main".into(),
                app_allowed: true,
                canvas_allowed: false,
            },
        );
        // Off means off however the agent reaches the server, MCP or CLI.
        assert_eq!(
            request_grant(&inner, "canvas", &token).err().as_deref(),
            Some(CANVAS_DISABLED)
        );
        // The switch is about drawing only.
        assert!(request_grant(&inner, "app", &token).is_ok());
        // The next turn carries the new value; nothing changes mid-turn.
        inner.active.get_mut("session").unwrap().canvas_allowed = true;
        assert!(request_grant(&inner, "canvas", &token).is_ok());
    }
    #[test]
    fn a_generation_scoped_process_uses_its_sessions_credential() {
        assert_eq!(owning_session("session"), "session");
        assert_eq!(owning_session("session#0"), "session");
        assert_eq!(owning_session("session#12"), "session");
        let mut inner = Inner::default();
        inner.prepare_app_grant("session", "main");
        assert!(inner.app_grants.contains_key(owning_session("session#3")));
        assert!(!inner.app_grants.contains_key(owning_session("other#3")));
    }
    #[test]
    fn terminal_and_turn_tokens_never_open_each_others_doors() {
        let mut inner = Inner::default();
        inner.prepare_app_grant("session", "main");
        inner.active.insert(
            "session".into(),
            ActiveTurn {
                window: "main".into(),
                app_allowed: true,
                canvas_allowed: true,
            },
        );
        let turn_token = inner.app_grants["session"].token.clone();
        let external = cli_access::new_token();
        inner.external = External {
            enabled: true,
            token: Some(external.clone()),
        };
        assert!(external_access(&inner, &external).is_ok());
        assert_eq!(
            external_access(&inner, &turn_token).unwrap_err().1,
            "unauthorized"
        );
        assert!(request_grant(&inner, "app", &external).is_err());
        assert!(request_grant(&inner, "canvas", &external).is_err());
        assert!(request_grant(&inner, "cli", &turn_token).is_err());
        inner.external.enabled = false;
        assert_eq!(
            external_access(&inner, &external).unwrap_err().1,
            "disabled"
        );
        inner.external = External {
            enabled: true,
            token: None,
        };
        assert_eq!(external_access(&inner, "").unwrap_err().1, "unauthorized");
    }
    #[test]
    fn terminal_commands_go_to_the_main_window_first() {
        let mut ready = HashSet::new();
        assert_eq!(pick_window(&ready), None);
        ready.insert("window-2".to_string());
        ready.insert("window-1".to_string());
        assert_eq!(pick_window(&ready).as_deref(), Some("window-1"));
        ready.insert("main".to_string());
        assert_eq!(pick_window(&ready).as_deref(), Some("main"));
        let mut inner = Inner {
            ready,
            ..Default::default()
        };
        inner.close_window("main");
        assert_eq!(pick_window(&inner.ready).as_deref(), Some("window-1"));
    }
    #[test]
    fn only_canvas_requests_may_exceed_the_cli_limit() {
        assert!(request_size_error("app", APP_REQUEST_MAX).is_none());
        assert!(request_size_error("app", APP_REQUEST_MAX + 1).is_some());
        assert!(request_size_error("canvas", APP_REQUEST_MAX + 1).is_none());
        assert!(request_size_error("canvas", CANVAS_REQUEST_MAX + 1).is_some());
        assert!(request_size_error("other", APP_REQUEST_MAX + 1).is_some());
    }
    #[test]
    fn closing_a_window_revokes_only_owned_grants_and_pending_requests() {
        let mut inner = Inner::default();
        for (id, window) in [("session", "closing"), ("other", "open")] {
            inner.prepare_app_grant(id, window);
            inner.active.insert(
                id.into(),
                ActiveTurn {
                    window: window.into(),
                    app_allowed: true,
                    canvas_allowed: true,
                },
            );
        }
        let token = inner.app_grants["session"].token.clone();
        let (reply, response) = mpsc::channel();
        inner.pending.insert(
            "pending".into(),
            Pending {
                window: "closing".into(),
                reply,
            },
        );
        let (reply, other_response) = mpsc::channel();
        inner.pending.insert(
            "other-pending".into(),
            Pending {
                window: "open".into(),
                reply,
            },
        );
        assert_eq!(inner.close_window("closing"), ["session"]);
        assert_eq!(inner.active.len(), 1);
        assert_eq!(inner.app_grants.len(), 1);
        assert!(request_grant(&inner, "app", &token).is_err());
        assert_eq!(response.try_recv().unwrap()["ok"], false);
        assert!(other_response.try_recv().is_err());
        assert!(inner.pending.contains_key("other-pending"));
        assert!(inner.close_window("closing").is_empty());
    }
}
