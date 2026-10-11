//! X (Twitter) inside Loci: a borderless child window laid over the Feeds
//! surface, signed in with the user's own account.
//!
//! It is a separate window rather than a child webview of the workspace
//! window on purpose. Adding a second webview to a window makes Tauri stop
//! treating it as a `WebviewWindow`, which breaks every command that takes one
//! (quit handshake, reminders, window controls) and reroutes drag-drop events.
//! A parented window moves with its owner and leaves the workspace untouched.
//!
//! x.com is remote content: no capability covers it, so it has no IPC access.
//! Loci reads from it only through `eval_with_callback`.

use std::collections::HashMap;
use std::sync::{mpsc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::webview::NewWindowResponse;
use tauri::{
    AppHandle, LogicalPosition, LogicalSize, Manager, Url, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder, Window, WindowEvent,
};

const ORIGIN: &str = "https://x.com";
const LABEL_PREFIX: &str = "x-feed-";
const CAPTURE_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_POSTS: usize = 40;
const MAX_POST_CHARS: usize = 4_000;
const MAX_SELECTION_CHARS: usize = 20_000;
/// WKWebView's default user agent has no Safari token, and x.com treats it
/// as an unsupported browser.
#[cfg(target_os = "macos")]
const USER_AGENT: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";

/// Hosts that may open in the overlay itself; anything else goes to the
/// system browser.
const X_HOSTS: [&str; 3] = ["x.com", "twitter.com", "t.co"];

#[derive(Debug, Clone, Copy, Deserialize, PartialEq)]
pub struct OverlayBounds {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct XPost {
    #[serde(default)]
    pub author: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub link: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct XCapture {
    pub url: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub selection: String,
    #[serde(default)]
    pub posts: Vec<XPost>,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum XFeedAction {
    Back,
    Forward,
    Reload,
}

/// Last bounds per overlay, relative to the owner's content area, so the
/// overlay can follow its owner when it moves.
#[derive(Default)]
pub struct XFeedState {
    bounds: Mutex<HashMap<String, OverlayBounds>>,
    /// Held across look-up-then-create, so overlapping shows (React mounts
    /// effects twice in development) can't each build an overlay.
    lifecycle: Mutex<()>,
}

/// Reads posts from x.com's DOM. On a status page that's the thread; elsewhere
/// it's the posts on screen. Selected text wins when there is some.
const CAPTURE_SCRIPT: &str = r#"(() => {
  const clip = (value, limit) => value.length > limit ? value.slice(0, limit) + "…" : value;
  const selection = String(window.getSelection() || "").trim();
  const articles = [...document.querySelectorAll('article[data-testid="tweet"]')];
  const onScreen = articles.filter((article) => {
    const rect = article.getBoundingClientRect();
    return rect.bottom > 0 && rect.top < window.innerHeight;
  });
  const thread = /\/status\/\d+/.test(location.pathname);
  const posts = (thread ? articles : onScreen).slice(0, __MAX_POSTS__).map((article) => {
    const name = article.querySelector('[data-testid="User-Name"]');
    const body = article.querySelector('[data-testid="tweetText"]');
    const time = article.querySelector("time");
    return {
      author: name ? name.innerText.replace(/\s*\n+\s*/g, " ").trim() : "",
      text: body ? clip(body.innerText.trim(), __MAX_POST_CHARS__) : "",
      time: time ? time.getAttribute("datetime") || "" : "",
      link: time && time.closest("a") ? time.closest("a").href : "",
    };
  }).filter((post) => post.text || post.author);
  return JSON.stringify({ url: location.href, title: document.title, selection: clip(selection, __MAX_SELECTION_CHARS__), posts });
})()"#;

fn capture_script() -> String {
    CAPTURE_SCRIPT
        .replace("__MAX_POSTS__", &MAX_POSTS.to_string())
        .replace("__MAX_POST_CHARS__", &MAX_POST_CHARS.to_string())
        .replace("__MAX_SELECTION_CHARS__", &MAX_SELECTION_CHARS.to_string())
}

fn overlay_label(owner: &str) -> String {
    format!("{LABEL_PREFIX}{owner}")
}

fn is_x_host(url: &Url) -> bool {
    url.host_str().is_some_and(|host| {
        X_HOSTS
            .iter()
            .any(|allowed| host == *allowed || host.ends_with(&format!(".{allowed}")))
    })
}

/// Only in-app paths are accepted, so the overlay can't be pointed elsewhere.
fn x_url(path: &str) -> Result<Url, String> {
    if !path.starts_with('/') || path.starts_with("//") {
        return Err("X paths must start with a single /".into());
    }
    Url::parse(&format!("{ORIGIN}{path}")).map_err(|_| "Invalid X path".to_string())
}

/// Top-left of the owner's content area in logical screen coordinates.
/// Window and WebviewWindow share these methods but no trait, hence the macro.
macro_rules! content_origin {
    ($owner:expr) => {{
        let owner = $owner;
        owner
            .scale_factor()
            .and_then(|scale| {
                owner
                    .inner_position()
                    .map(|position| position.to_logical::<f64>(scale))
            })
            .map_err(|e| e.to_string())
    }};
}

fn place(
    overlay: &WebviewWindow,
    origin: LogicalPosition<f64>,
    bounds: OverlayBounds,
) -> Result<(), String> {
    overlay
        .set_position(LogicalPosition::new(
            origin.x + bounds.x,
            origin.y + bounds.y,
        ))
        .map_err(|e| e.to_string())?;
    overlay
        .set_size(LogicalSize::new(
            bounds.width.max(1.0),
            bounds.height.max(1.0),
        ))
        .map_err(|e| e.to_string())
}

fn validate_bounds(bounds: OverlayBounds) -> Result<OverlayBounds, String> {
    let finite = [bounds.x, bounds.y, bounds.width, bounds.height]
        .iter()
        .all(|value| value.is_finite());
    if !finite || bounds.width < 0.0 || bounds.height < 0.0 {
        return Err("Invalid X overlay bounds".into());
    }
    Ok(bounds)
}

fn remember(app: &AppHandle, label: &str, bounds: OverlayBounds) {
    if let Ok(mut map) = app.state::<XFeedState>().bounds.lock() {
        map.insert(label.to_string(), bounds);
    }
}

fn create_overlay(
    app: &AppHandle,
    owner: &Window,
    label: &str,
    bounds: OverlayBounds,
    url: Url,
) -> Result<WebviewWindow, String> {
    let owner_webview = app
        .get_webview_window(owner.label())
        .ok_or("X can only open inside a workspace window")?;
    let origin: LogicalPosition<f64> = content_origin!(owner)?;
    let builder = WebviewWindowBuilder::new(app, label, WebviewUrl::External(url))
        .title("X")
        .parent(&owner_webview)
        .map_err(|e| e.to_string())?
        .decorations(false)
        .shadow(false)
        .resizable(false)
        .skip_taskbar(true)
        .position(origin.x + bounds.x, origin.y + bounds.y)
        .inner_size(bounds.width.max(1.0), bounds.height.max(1.0))
        .on_new_window(|url, _features| {
            // Links in posts open in new tabs on x.com; send them to the
            // system browser instead of spawning stray windows.
            let _ = open::that_detached(url.as_str());
            NewWindowResponse::Deny
        });
    #[cfg(target_os = "macos")]
    let builder = builder.user_agent(USER_AGENT);
    let overlay = builder.build().map_err(|e| e.to_string())?;

    // macOS moves child windows with their parent; other platforms need help.
    let handle = app.clone();
    let overlay_label = label.to_string();
    owner.on_window_event(move |event| match event {
        WindowEvent::Moved(_)
        | WindowEvent::Resized(_)
        | WindowEvent::ScaleFactorChanged { .. } => {
            follow_owner(&handle, &overlay_label);
        }
        WindowEvent::Destroyed => {
            if let Some(overlay) = handle.get_webview_window(&overlay_label) {
                let _ = overlay.destroy();
            }
        }
        _ => {}
    });
    Ok(overlay)
}

fn follow_owner(app: &AppHandle, label: &str) {
    let Some(overlay) = app.get_webview_window(label) else {
        return;
    };
    if !overlay.is_visible().unwrap_or(false) {
        return;
    }
    let Some(owner) = label
        .strip_prefix(LABEL_PREFIX)
        .and_then(|owner| app.get_webview_window(owner))
    else {
        return;
    };
    let bounds = app
        .state::<XFeedState>()
        .bounds
        .lock()
        .ok()
        .and_then(|map| map.get(label).copied());
    if let (Some(bounds), Ok(origin)) = (bounds, content_origin!(&owner)) {
        let _ = place(&overlay, origin, bounds);
    }
}

fn overlay_for(app: &AppHandle, owner: &Window) -> Result<WebviewWindow, String> {
    app.get_webview_window(&overlay_label(owner.label()))
        .ok_or_else(|| "X is not open".into())
}

/// Show the overlay over `bounds` (logical px, relative to the owner's
/// content area), creating it on first use.
#[tauri::command]
pub async fn x_feed_show(
    app: AppHandle,
    window: Window,
    bounds: OverlayBounds,
    path: Option<String>,
) -> Result<(), String> {
    let bounds = validate_bounds(bounds)?;
    let label = overlay_label(window.label());
    remember(&app, &label, bounds);
    let state = app.state::<XFeedState>();
    let _lifecycle = state.lifecycle.lock().map_err(|_| "X overlay is locked")?;
    match app.get_webview_window(&label) {
        Some(overlay) => {
            place(&overlay, content_origin!(&window)?, bounds)?;
            if let Some(path) = path {
                overlay.navigate(x_url(&path)?).map_err(|e| e.to_string())?;
            }
            overlay.show().map_err(|e| e.to_string())
        }
        None => {
            let url = x_url(path.as_deref().unwrap_or("/home"))?;
            create_overlay(&app, &window, &label, bounds, url).map(|_| ())
        }
    }
}

#[tauri::command]
pub async fn x_feed_set_bounds(
    app: AppHandle,
    window: Window,
    bounds: OverlayBounds,
) -> Result<(), String> {
    let bounds = validate_bounds(bounds)?;
    let label = overlay_label(window.label());
    remember(&app, &label, bounds);
    match app.get_webview_window(&label) {
        Some(overlay) => place(&overlay, content_origin!(&window)?, bounds),
        None => Ok(()),
    }
}

#[tauri::command]
pub async fn x_feed_hide(app: AppHandle, window: Window) -> Result<(), String> {
    let state = app.state::<XFeedState>();
    let _lifecycle = state.lifecycle.lock().map_err(|_| "X overlay is locked")?;
    match app.get_webview_window(&overlay_label(window.label())) {
        Some(overlay) => overlay.hide().map_err(|e| e.to_string()),
        None => Ok(()),
    }
}

#[tauri::command]
pub async fn x_feed_navigate(app: AppHandle, window: Window, path: String) -> Result<(), String> {
    let url = x_url(&path)?;
    overlay_for(&app, &window)?
        .navigate(url)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn x_feed_action(
    app: AppHandle,
    window: Window,
    action: XFeedAction,
) -> Result<(), String> {
    let overlay = overlay_for(&app, &window)?;
    match action {
        XFeedAction::Back => overlay.eval("history.back()"),
        XFeedAction::Forward => overlay.eval("history.forward()"),
        XFeedAction::Reload => overlay.reload(),
    }
    .map_err(|e| e.to_string())
}

/// The page's URL, title, selection and visible posts, for Add to Chat.
#[tauri::command]
pub async fn x_feed_capture(app: AppHandle, window: Window) -> Result<XCapture, String> {
    let overlay = overlay_for(&app, &window)?;
    let (tx, rx) = mpsc::channel();
    overlay
        .eval_with_callback(capture_script(), move |result| {
            let _ = tx.send(result);
        })
        .map_err(|e| e.to_string())?;
    let raw = tauri::async_runtime::spawn_blocking(move || rx.recv_timeout(CAPTURE_TIMEOUT))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|_| "X didn't respond. Wait for the page to load and try again.".to_string())?;
    let capture = parse_capture(&raw)?;
    let url = Url::parse(&capture.url).map_err(|_| "X returned an invalid page URL")?;
    if !is_x_host(&url) {
        return Err("The X panel is showing a page outside x.com".into());
    }
    Ok(capture)
}

/// The script returns a JSON string; the bridge may hand it back as that
/// string or JSON-encoded once more, depending on the platform.
fn parse_capture(raw: &str) -> Result<XCapture, String> {
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|_| "Could not read the X page".to_string())?;
    let value = match value {
        serde_json::Value::String(inner) => {
            serde_json::from_str(&inner).map_err(|_| "Could not read the X page".to_string())?
        }
        other => other,
    };
    let mut capture: XCapture =
        serde_json::from_value(value).map_err(|_| "Could not read the X page".to_string())?;
    capture.posts.truncate(MAX_POSTS);
    for post in &mut capture.posts {
        truncate_chars(&mut post.text, MAX_POST_CHARS);
    }
    truncate_chars(&mut capture.selection, MAX_SELECTION_CHARS);
    Ok(capture)
}

fn truncate_chars(text: &mut String, limit: usize) {
    if let Some((index, _)) = text.char_indices().nth(limit) {
        text.truncate(index);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_stay_on_x() {
        assert_eq!(x_url("/home").unwrap().as_str(), "https://x.com/home");
        assert_eq!(
            x_url("/search?q=rust&f=live").unwrap().as_str(),
            "https://x.com/search?q=rust&f=live"
        );
        assert!(x_url("//evil.example/a").is_err());
        assert!(x_url("https://evil.example").is_err());
        assert!(x_url("home").is_err());
        // `@` in the path must not turn into userinfo for another host.
        assert_eq!(x_url("/@evil.example").unwrap().host_str(), Some("x.com"));
    }

    #[test]
    fn x_hosts_match_subdomains_only() {
        assert!(is_x_host(&Url::parse("https://x.com/home").unwrap()));
        assert!(is_x_host(
            &Url::parse("https://mobile.twitter.com/a").unwrap()
        ));
        assert!(!is_x_host(&Url::parse("https://notx.com/").unwrap()));
        assert!(!is_x_host(
            &Url::parse("https://x.com.evil.example/").unwrap()
        ));
    }

    #[test]
    fn capture_accepts_plain_and_double_encoded_json() {
        let inner = r#"{"url":"https://x.com/a/status/1","title":"t","selection":"","posts":[{"author":"A @a","text":"hi","time":"","link":""}]}"#;
        let plain = parse_capture(inner).unwrap();
        let encoded = parse_capture(&serde_json::to_string(inner).unwrap()).unwrap();
        assert_eq!(plain, encoded);
        assert_eq!(plain.posts[0].text, "hi");
    }

    #[test]
    fn capture_caps_sizes() {
        let long = "字".repeat(MAX_POST_CHARS + 10);
        let raw =
            serde_json::json!({ "url": "https://x.com/", "posts": [{ "text": long }] }).to_string();
        let capture = parse_capture(&raw).unwrap();
        assert_eq!(capture.posts[0].text.chars().count(), MAX_POST_CHARS);
    }

    #[test]
    fn bounds_must_be_finite_and_positive() {
        let ok = OverlayBounds {
            x: 0.0,
            y: 40.0,
            width: 600.0,
            height: 400.0,
        };
        assert!(validate_bounds(ok).is_ok());
        assert!(validate_bounds(OverlayBounds {
            width: f64::NAN,
            ..ok
        })
        .is_err());
        assert!(validate_bounds(OverlayBounds { height: -1.0, ..ok }).is_err());
    }
}
