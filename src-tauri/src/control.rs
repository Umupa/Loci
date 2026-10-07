//! Authenticated loopback transport. App windows own execution; callers never
//! receive arbitrary Tauri command access or direct database write access.
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::process::Command;
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

const APP_TURN_INACTIVE: &str = "Loci app access is inactive. Use /operator once in this thread to enable it, then call the CLI during an active agent turn. Retrying this request now will not enable access.";
const CANVAS_TURN_INACTIVE: &str = "Loci canvas access is only available while this session's agent turn is running. Retrying this request now will not enable access.";
const APP_REQUEST_MAX: usize = 262_144;
/// A canvas save carries drawing elements. The official Excalidraw MCP server
/// accepts 5 MB of them, so leave room for the JSON envelope around that.
const CANVAS_REQUEST_MAX: usize = 6 * 1024 * 1024;
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
}

#[derive(Default)]
struct Inner {
    app_grants: HashMap<String, Grant>,
    pending: HashMap<String, Pending>,
    active: HashMap<String, ActiveTurn>,
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
/// `app` is the /operator CLI and needs the thread's opt-in. `canvas` is the
/// built-in Excalidraw MCP: every session may draw, but only on its own
/// project's canvases and only while its turn runs.
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
        "canvas" if turn.is_some() => Ok(grant),
        "canvas" => Err(CANVAS_TURN_INACTIVE.into()),
        _ if turn.is_some_and(|turn| turn.app_allowed) => Ok(grant),
        _ => Err(APP_TURN_INACTIVE.into()),
    }
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
    let inner = Arc::new(Mutex::new(Inner::default()));
    app.manage(ControlHost {
        endpoint,
        inner: inner.clone(),
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
        let id = uuid::Uuid::new_v4().to_string();
        let (tx, rx) = mpsc::channel();
        let grant = {
            let mut host = inner.lock().map_err(|_| "Control service unavailable")?;
            let grant = request_grant(&host, &request.namespace, &request.token)?;
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
            grant
        };
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
        if error == APP_TURN_INACTIVE || error == CANVAS_TURN_INACTIVE {
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
        },
    );
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
pub fn configure_child(app: &AppHandle, session_id: &str, cmd: &mut Command) {
    cmd.env_remove("LOCI_APP_ENDPOINT")
        .env_remove("LOCI_APP_TOKEN");
    let Some(host) = app.try_state::<ControlHost>() else {
        return;
    };
    if let Ok(inner) = host.inner.lock() {
        if let Some(grant) = inner.app_grants.get(session_id) {
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
    fn canvas_access_needs_an_active_turn_but_not_the_operator_opt_in() {
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
            },
        );
        assert_eq!(
            request_grant(&inner, "canvas", &token).unwrap().session,
            "session"
        );
        // Drawing does not widen what the operator CLI may do.
        assert!(request_grant(&inner, "app", &token).is_err());
        assert!(request_grant(&inner, "canvas", "wrong-token").is_err());
        inner.active.get_mut("session").unwrap().window = "other".into();
        assert!(request_grant(&inner, "canvas", &token).is_err());
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
