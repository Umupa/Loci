//! V2EX client. Public lists come from the v1 JSON API; a personal access
//! token unlocks the v2 API (notifications, paged node topics). Requests run
//! natively so the webview CSP stays closed to third-party hosts.

use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

const BASE: &str = "https://www.v2ex.com";
const HTTP_TIMEOUT: Duration = Duration::from_secs(12);
const MAX_RESPONSE_BYTES: u64 = 8 * 1024 * 1024;
const USER_AGENT: &str = "Mozilla/5.0 (compatible; Loci/1.0)";
const TOKEN_FILE: &str = "v2ex-token";
const TOKEN_MAX: usize = 256;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct V2exMember {
    pub username: String,
    pub avatar: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct V2exNode {
    pub name: String,
    pub title: String,
    pub avatar: Option<String>,
    pub topics: Option<u64>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct V2exTopic {
    pub id: u64,
    pub title: String,
    pub url: String,
    pub content: String,
    pub node: Option<V2exNode>,
    pub member: Option<V2exMember>,
    pub replies: u64,
    pub created: i64,
    pub last_touched: i64,
    pub last_reply_by: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct V2exReply {
    pub id: u64,
    pub content: String,
    pub member: Option<V2exMember>,
    pub created: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct V2exNotification {
    pub id: u64,
    pub text: String,
    pub payload: String,
    pub topic_id: Option<u64>,
    pub member: Option<String>,
    pub created: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct V2exStatus {
    pub connected: bool,
    pub member: Option<V2exMember>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum V2exListSource {
    Hot,
    Latest,
    Node { name: String },
}

// Wire shapes. Every field is optional: v1 and v2 disagree on which
// fields they send, and the API omits null members on deleted accounts.

#[derive(Deserialize, Default)]
struct RawMember {
    username: Option<String>,
    avatar: Option<String>,
    avatar_large: Option<String>,
    avatar_normal: Option<String>,
}

#[derive(Deserialize, Default)]
struct RawNode {
    name: Option<String>,
    title: Option<String>,
    avatar: Option<String>,
    avatar_large: Option<String>,
    topics: Option<u64>,
}

#[derive(Deserialize)]
struct RawTopic {
    id: u64,
    title: Option<String>,
    url: Option<String>,
    content: Option<String>,
    node: Option<RawNode>,
    member: Option<RawMember>,
    replies: Option<u64>,
    created: Option<i64>,
    last_touched: Option<i64>,
    last_reply_by: Option<String>,
}

#[derive(Deserialize)]
struct RawReply {
    id: u64,
    content: Option<String>,
    member: Option<RawMember>,
    created: Option<i64>,
}

#[derive(Deserialize)]
struct RawNotification {
    id: u64,
    text: Option<String>,
    payload: Option<String>,
    member: Option<RawMember>,
    created: Option<i64>,
}

#[derive(Deserialize)]
struct Envelope<T> {
    success: Option<bool>,
    message: Option<String>,
    result: Option<T>,
}

impl RawMember {
    fn into_member(self) -> Option<V2exMember> {
        let username = self.username.filter(|name| !name.is_empty())?;
        let avatar = self
            .avatar_large
            .or(self.avatar_normal)
            .or(self.avatar)
            .map(absolute_url);
        Some(V2exMember { username, avatar })
    }
}

impl RawNode {
    fn into_node(self) -> Option<V2exNode> {
        let name = self.name.filter(|name| !name.is_empty())?;
        Some(V2exNode {
            title: self.title.unwrap_or_else(|| name.clone()),
            name,
            avatar: self.avatar_large.or(self.avatar).map(absolute_url),
            topics: self.topics,
        })
    }
}

impl RawTopic {
    fn into_topic(self, fallback_node: Option<&V2exNode>) -> V2exTopic {
        let node = self
            .node
            .and_then(RawNode::into_node)
            .or_else(|| fallback_node.cloned());
        V2exTopic {
            id: self.id,
            title: self.title.unwrap_or_default(),
            url: self.url.unwrap_or_else(|| format!("{BASE}/t/{}", self.id)),
            content: normalize_newlines(&self.content.unwrap_or_default()),
            node,
            member: self.member.and_then(RawMember::into_member),
            replies: self.replies.unwrap_or(0),
            created: self.created.unwrap_or(0),
            last_touched: self.last_touched.or(self.created).unwrap_or(0),
            last_reply_by: self.last_reply_by.filter(|name| !name.is_empty()),
        }
    }
}

fn absolute_url(url: String) -> String {
    if url.starts_with("//") {
        format!("https:{url}")
    } else if url.starts_with('/') {
        format!("{BASE}{url}")
    } else {
        url
    }
}

fn normalize_newlines(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

pub(crate) fn validate_node_name(name: &str) -> Result<(), String> {
    let ok = !name.is_empty()
        && name.len() <= 64
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-');
    if ok {
        Ok(())
    } else {
        Err("Invalid V2EX node name".into())
    }
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(HTTP_TIMEOUT)
        .redirects(2)
        .build()
}

fn get_json<T: DeserializeOwned>(path: &str, token: Option<&str>) -> Result<T, String> {
    let url = format!("{BASE}{path}");
    let mut request = agent()
        .get(&url)
        .set("Accept", "application/json")
        .set("User-Agent", USER_AGENT);
    if let Some(token) = token {
        request = request.set("Authorization", &format!("Bearer {token}"));
    }
    let response = match request.call() {
        Ok(response) => response,
        Err(ureq::Error::Status(401, _)) => {
            return Err("V2EX rejected the access token. Check it in Feeds settings.".into())
        }
        Err(ureq::Error::Status(403, response)) | Err(ureq::Error::Status(429, response)) => {
            return Err(rate_limit_message(&response))
        }
        Err(ureq::Error::Status(404, _)) => return Err("Not found on V2EX".into()),
        Err(ureq::Error::Status(status, _)) => {
            return Err(format!("V2EX request failed ({status})"))
        }
        Err(_) => return Err("Could not reach V2EX".into()),
    };
    let mut bytes = Vec::new();
    response
        .into_reader()
        .take(MAX_RESPONSE_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "Could not read the V2EX response".to_string())?;
    if bytes.len() as u64 > MAX_RESPONSE_BYTES {
        return Err("V2EX response is too large".into());
    }
    serde_json::from_slice(&bytes).map_err(|_| "V2EX returned an unexpected response".into())
}

fn rate_limit_message(response: &ureq::Response) -> String {
    let remaining = response.header("X-Rate-Limit-Remaining");
    if remaining == Some("0") {
        "V2EX rate limit reached (600 requests per hour). Try again later.".into()
    } else {
        "V2EX refused the request".into()
    }
}

fn get_v2<T: DeserializeOwned>(path: &str, token: &str) -> Result<T, String> {
    let envelope: Envelope<T> = get_json(&format!("/api/v2{path}"), Some(token))?;
    if envelope.success == Some(false) {
        return Err(envelope
            .message
            .unwrap_or_else(|| "V2EX request failed".into()));
    }
    envelope
        .result
        .ok_or_else(|| "V2EX returned an empty response".into())
}

// Token storage: a 0600 file in app data, never in the SQLite store, so
// exporting or syncing the database never carries the credential.

fn token_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    Ok(dir.join(TOKEN_FILE))
}

fn read_token(app: &AppHandle) -> Option<String> {
    let path = token_path(app).ok()?;
    let token = std::fs::read_to_string(path).ok()?;
    let token = token.trim();
    (!token.is_empty()).then(|| token.to_string())
}

fn write_token(app: &AppHandle, token: &str) -> Result<(), String> {
    use std::io::Write;

    let path = token_path(app)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let temp = path.with_extension("tmp");
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temp).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|e| e.to_string())?;
    }
    file.write_all(token.as_bytes())
        .map_err(|e| e.to_string())?;
    drop(file);
    std::fs::rename(&temp, &path).map_err(|e| e.to_string())
}

fn validate_token(token: &str) -> Result<(), String> {
    let ok = !token.is_empty()
        && token.len() <= TOKEN_MAX
        && token.chars().all(|c| c.is_ascii_graphic());
    if ok {
        Ok(())
    } else {
        Err("That doesn't look like a V2EX access token".into())
    }
}

fn fetch_member(token: &str) -> Result<V2exMember, String> {
    let member: RawMember = get_v2("/member", token)?;
    member
        .into_member()
        .ok_or_else(|| "V2EX returned no member for this token".into())
}

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn v2ex_status(app: AppHandle, verify: bool) -> Result<V2exStatus, String> {
    let Some(token) = read_token(&app) else {
        return Ok(V2exStatus {
            connected: false,
            member: None,
        });
    };
    if !verify {
        return Ok(V2exStatus {
            connected: true,
            member: None,
        });
    }
    let member = blocking(move || fetch_member(&token)).await?;
    Ok(V2exStatus {
        connected: true,
        member: Some(member),
    })
}

#[tauri::command]
pub async fn v2ex_set_token(app: AppHandle, token: String) -> Result<V2exStatus, String> {
    let token = token.trim().to_string();
    validate_token(&token)?;
    let checked = token.clone();
    let member = blocking(move || fetch_member(&checked)).await?;
    write_token(&app, &token)?;
    Ok(V2exStatus {
        connected: true,
        member: Some(member),
    })
}

#[tauri::command]
pub fn v2ex_clear_token(app: AppHandle) -> Result<(), String> {
    let path = token_path(&app)?;
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

#[tauri::command]
pub async fn v2ex_topics(
    app: AppHandle,
    source: V2exListSource,
    page: Option<u32>,
) -> Result<Vec<V2exTopic>, String> {
    let token = read_token(&app);
    let page = page.unwrap_or(1).clamp(1, 500);
    blocking(move || list_topics(&source, page, token.as_deref())).await
}

fn list_topics(
    source: &V2exListSource,
    page: u32,
    token: Option<&str>,
) -> Result<Vec<V2exTopic>, String> {
    let (raw, fallback): (Vec<RawTopic>, Option<V2exNode>) = match source {
        V2exListSource::Hot | V2exListSource::Latest if page > 1 => return Ok(Vec::new()),
        V2exListSource::Hot => (get_json("/api/topics/hot.json", None)?, None),
        V2exListSource::Latest => (get_json("/api/topics/latest.json", None)?, None),
        V2exListSource::Node { name } => {
            validate_node_name(name)?;
            let node = V2exNode {
                name: name.clone(),
                title: name.clone(),
                avatar: None,
                topics: None,
            };
            // v1 returns one unpaged batch; v2 pages but needs a token.
            let raw = match token {
                Some(token) => get_v2(&format!("/nodes/{name}/topics?p={page}"), token)?,
                None if page > 1 => return Ok(Vec::new()),
                None => get_json(&format!("/api/topics/show.json?node_name={name}"), None)?,
            };
            (raw, Some(node))
        }
    };
    Ok(raw
        .into_iter()
        .map(|topic| topic.into_topic(fallback.as_ref()))
        .collect())
}

#[tauri::command]
pub async fn v2ex_topic(id: u64) -> Result<V2exTopic, String> {
    blocking(move || {
        let mut topics: Vec<RawTopic> = get_json(&format!("/api/topics/show.json?id={id}"), None)?;
        topics
            .pop()
            .map(|topic| topic.into_topic(None))
            .ok_or_else(|| "Topic not found on V2EX".into())
    })
    .await
}

#[tauri::command]
pub async fn v2ex_replies(id: u64) -> Result<Vec<V2exReply>, String> {
    blocking(move || {
        let replies: Vec<RawReply> =
            get_json(&format!("/api/replies/show.json?topic_id={id}"), None)?;
        Ok(replies
            .into_iter()
            .map(|reply| V2exReply {
                id: reply.id,
                content: normalize_newlines(&reply.content.unwrap_or_default()),
                member: reply.member.and_then(RawMember::into_member),
                created: reply.created.unwrap_or(0),
            })
            .collect())
    })
    .await
}

#[tauri::command]
pub async fn v2ex_node(name: String) -> Result<V2exNode, String> {
    validate_node_name(&name)?;
    blocking(move || {
        let node: RawNode = get_json(&format!("/api/nodes/show.json?name={name}"), None)?;
        node.into_node()
            .ok_or_else(|| format!("No V2EX node named \"{name}\""))
    })
    .await
}

#[tauri::command]
pub async fn v2ex_notifications(
    app: AppHandle,
    page: Option<u32>,
) -> Result<Vec<V2exNotification>, String> {
    let token = read_token(&app).ok_or("Add a V2EX access token to see notifications")?;
    let page = page.unwrap_or(1).clamp(1, 500);
    blocking(move || {
        let raw: Vec<RawNotification> = get_v2(&format!("/notifications?p={page}"), &token)?;
        Ok(raw.into_iter().map(into_notification).collect())
    })
    .await
}

fn into_notification(raw: RawNotification) -> V2exNotification {
    let html = raw.text.unwrap_or_default();
    V2exNotification {
        id: raw.id,
        topic_id: topic_id_in(&html),
        text: html_to_text(&html),
        payload: normalize_newlines(&raw.payload.unwrap_or_default()),
        member: raw
            .member
            .and_then(|member| member.username)
            .filter(|name| !name.is_empty()),
        created: raw.created.unwrap_or(0),
    }
}

/// First `/t/<id>` link in a notification's HTML.
fn topic_id_in(html: &str) -> Option<u64> {
    let start = html.find("/t/")? + 3;
    let digits: String = html[start..]
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    digits.parse().ok()
}

/// Notification text is a short HTML fragment; keep its words, drop markup.
fn html_to_text(html: &str) -> String {
    let mut text = String::with_capacity(html.len());
    let mut in_tag = false;
    for c in html.chars() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            _ if !in_tag => text.push(c),
            _ => {}
        }
    }
    let text = text
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&");
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notification_text_strips_markup_and_finds_topic() {
        let raw = RawNotification {
            id: 7,
            text: Some(
                "<a href=\"/member/alice\"><strong>alice</strong></a> 在 <a href=\"/t/1247772#reply4\" class=\"topic-link\">Rust &amp; Tauri</a> 里回复了你"
                    .into(),
            ),
            payload: Some("hi\r\nthere".into()),
            member: Some(RawMember {
                username: Some("alice".into()),
                ..RawMember::default()
            }),
            created: Some(1),
        };
        let notification = into_notification(raw);
        assert_eq!(notification.text, "alice 在 Rust & Tauri 里回复了你");
        assert_eq!(notification.topic_id, Some(1247772));
        assert_eq!(notification.payload, "hi\nthere");
        assert_eq!(notification.member.as_deref(), Some("alice"));
    }

    #[test]
    fn topic_falls_back_to_requested_node_and_absolute_avatars() {
        let raw: RawTopic = serde_json::from_str(
            r#"{"id": 5, "title": "t", "content": "a\r\nb", "replies": 3, "created": 10,
                "member": {"username": "bob", "avatar_large": "//cdn.v2ex.com/a.png"}}"#,
        )
        .unwrap();
        let node = V2exNode {
            name: "python".into(),
            title: "Python".into(),
            avatar: None,
            topics: None,
        };
        let topic = raw.into_topic(Some(&node));
        assert_eq!(topic.url, "https://www.v2ex.com/t/5");
        assert_eq!(topic.content, "a\nb");
        assert_eq!(topic.node.unwrap().name, "python");
        assert_eq!(topic.last_touched, 10);
        let member = topic.member.unwrap();
        assert_eq!(member.avatar.as_deref(), Some("https://cdn.v2ex.com/a.png"));
    }

    #[test]
    fn node_names_are_restricted_to_url_safe_slugs() {
        assert!(validate_node_name("python").is_ok());
        assert!(validate_node_name("ai-tools_2").is_ok());
        assert!(validate_node_name("").is_err());
        assert!(validate_node_name("../member").is_err());
        assert!(validate_node_name("a?b=c").is_err());
    }

    /// Hits the real API: `cargo test -- --ignored v2ex_live`.
    #[test]
    #[ignore]
    fn v2ex_live_lists_topics_and_replies() {
        let hot = list_topics(&V2exListSource::Hot, 1, None).unwrap();
        assert!(!hot.is_empty());
        assert!(hot
            .iter()
            .all(|topic| topic.node.is_some() && !topic.title.is_empty()));
        let node = list_topics(
            &V2exListSource::Node {
                name: "python".into(),
            },
            1,
            None,
        )
        .unwrap();
        assert!(node
            .iter()
            .all(|topic| topic.node.as_ref().unwrap().name == "python"));
        let busiest = hot.iter().max_by_key(|topic| topic.replies).unwrap();
        let replies: Vec<RawReply> = get_json(
            &format!("/api/replies/show.json?topic_id={}", busiest.id),
            None,
        )
        .unwrap();
        assert!(!replies.is_empty());
    }

    #[test]
    fn list_source_parses_tagged_json() {
        let node: V2exListSource =
            serde_json::from_str(r#"{"kind": "node", "name": "qna"}"#).unwrap();
        assert!(matches!(node, V2exListSource::Node { name } if name == "qna"));
        let hot: V2exListSource = serde_json::from_str(r#"{"kind": "hot"}"#).unwrap();
        assert!(matches!(hot, V2exListSource::Hot));
    }
}
