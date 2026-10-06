use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
#[cfg(test)]
use serde_json::json;
use serde_json::Value;
use tauri::{AppHandle, Emitter, Manager, State};

pub struct SessionStore {
    conn: Mutex<Connection>,
    read_conn: Mutex<Option<Connection>>,
}

impl SessionStore {
    pub fn open(path: PathBuf) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let conn = Connection::open(&path).map_err(|e| e.to_string())?;
        conn.execute_batch("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
            .map_err(|e| e.to_string())?;
        migrate(&conn).map_err(|e| e.to_string())?;
        let read_conn = Connection::open(&path).map_err(|e| e.to_string())?;
        read_conn
            .execute_batch("PRAGMA query_only = ON; PRAGMA busy_timeout = 5000;")
            .map_err(|e| e.to_string())?;
        Ok(Self {
            conn: Mutex::new(conn),
            read_conn: Mutex::new(Some(read_conn)),
        })
    }

    #[cfg(test)]
    pub fn open_in_memory() -> Result<Self, String> {
        let conn = Connection::open_in_memory().map_err(|e| e.to_string())?;
        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(|e| e.to_string())?;
        migrate(&conn).map_err(|e| e.to_string())?;
        Ok(Self {
            conn: Mutex::new(conn),
            read_conn: Mutex::new(None),
        })
    }

    pub(crate) fn lock_conn(&self) -> Result<std::sync::MutexGuard<'_, Connection>, String> {
        self.conn
            .lock()
            .map_err(|_| "Session store is locked".into())
    }
}

pub fn init(app: &AppHandle) -> Result<(), String> {
    init_with(
        || app.path().app_data_dir().map_err(|e| e.to_string()),
        SessionStore::open,
        |store| {
            app.manage(store);
        },
    )
}

// Keep the complete startup path here so the transcript-read test covers it.
fn init_with(
    data_dir: impl FnOnce() -> Result<PathBuf, String>,
    open: impl FnOnce(PathBuf) -> Result<SessionStore, String>,
    manage: impl FnOnce(SessionStore),
) -> Result<(), String> {
    let store = open(data_dir()?.join("loci.db"))?;
    manage(store);
    Ok(())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionUpsert {
    pub id: String,
    pub cwd: String,
    pub harness: String,
    pub model: String,
    pub model_settings: Value,
    pub runtime_mode: String,
    pub title: String,
    #[serde(default)]
    pub provider_session_id: Option<String>,
    #[serde(default)]
    pub provider_account_id: Option<String>,
    pub blocks: Value,
    /// Last context-window reading reported by the harness, if any.
    #[serde(default)]
    pub context_used: Option<i64>,
    #[serde(default)]
    pub context_window: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSummary {
    pub id: String,
    pub cwd: String,
    pub harness: String,
    pub model: String,
    pub runtime_mode: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_session_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    #[serde(default)]
    pub archived: bool,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub draft: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionRecord {
    pub id: String,
    pub cwd: String,
    pub harness: String,
    pub model: String,
    pub model_settings: Value,
    pub runtime_mode: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_account_id: Option<String>,
    pub blocks: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context_used: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context_window: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[tauri::command(async)]
pub fn session_upsert(
    store: State<'_, SessionStore>,
    session: SessionUpsert,
) -> Result<SessionSummary, String> {
    validate_id(&session.id, "session")?;
    if session.cwd.trim().is_empty() {
        return Err("cwd is required".into());
    }
    if let Some(provider_session_id) = &session.provider_session_id {
        if !provider_session_id.is_empty() {
            validate_id(provider_session_id, "provider session")?;
        }
    }
    if let Some(provider_account_id) = &session.provider_account_id {
        if !provider_account_id.is_empty() {
            validate_id(provider_account_id, "provider account")?;
        }
    }
    if !session.model_settings.is_object() {
        return Err("modelSettings must be an object".into());
    }
    if !session.blocks.is_array() {
        return Err("blocks must be an array".into());
    }

    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    let summary = upsert_session(&conn, &session).map_err(|e| e.to_string())?;
    Ok(summary)
}

fn generated_image_paths(blocks: &Value) -> Vec<String> {
    blocks
        .as_array()
        .into_iter()
        .flatten()
        .filter(|block| block.get("role").and_then(Value::as_str) == Some("image"))
        .filter_map(|block| {
            block
                .get("image")
                .and_then(|image| image.get("path"))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .collect()
}

#[tauri::command(async)]
pub fn session_list_by_project(
    store: State<'_, SessionStore>,
    cwd: String,
) -> Result<Vec<SessionSummary>, String> {
    if cwd.trim().is_empty() {
        return Err("cwd is required".into());
    }
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    list_by_project(&conn, &cwd).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn session_rebase_project(
    store: State<'_, SessionStore>,
    from_cwd: String,
    to_cwd: String,
) -> Result<(), String> {
    if from_cwd.trim().is_empty() || to_cwd.trim().is_empty() {
        return Err("project paths are required".into());
    }
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    rebase_project(&conn, &from_cwd, &to_cwd).map_err(|error| error.to_string())
}

fn rebase_project(conn: &Connection, from_cwd: &str, to_cwd: &str) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE sessions SET cwd = ?2 WHERE cwd = ?1",
        params![from_cwd, to_cwd],
    )?;
    Ok(())
}

#[tauri::command(async)]
pub fn session_get(
    store: State<'_, SessionStore>,
    session_id: String,
) -> Result<Option<SessionRecord>, String> {
    validate_id(&session_id, "session")?;
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    get_session(&conn, &session_id).map_err(|e| e.to_string())
}

const MAX_SEARCH_SCAN: usize = 400;
const MAX_CONVERSATION_HITS: usize = 40;
const MAX_MESSAGE_HITS: usize = 40;
const SNIPPET_RADIUS: usize = 42;
const SEARCH_PROGRESS_INTERVAL: usize = 1_000;
const MAX_SEARCH_BUFFER_BYTES: usize = 8 * 1024 * 1024;
static SESSION_SEARCH_TOKENS: Mutex<Option<HashMap<String, Arc<AtomicU64>>>> = Mutex::new(None);

#[derive(Clone)]
struct SessionSearchToken {
    owner: String,
    counter: Arc<AtomicU64>,
    generation: u64,
}

impl SessionSearchToken {
    fn is_current(&self) -> bool {
        self.counter.load(Ordering::Acquire) == self.generation
    }
}

fn begin_session_search(owner: &str) -> Option<SessionSearchToken> {
    if owner.is_empty() {
        return None;
    }
    let mut tokens = SESSION_SEARCH_TOKENS.lock().ok()?;
    let tokens = tokens.get_or_insert_with(HashMap::new);
    let counter = tokens
        .entry(owner.to_string())
        .or_insert_with(|| Arc::new(AtomicU64::new(0)))
        .clone();
    let generation = counter.fetch_add(1, Ordering::AcqRel).wrapping_add(1);
    Some(SessionSearchToken {
        owner: owner.to_string(),
        counter,
        generation,
    })
}

/// Release the entry a finished search was holding, on every exit path.
///
/// Every search runs under a fresh `searchOwner` (`SearchView` mints a UUID per
/// keystroke), so an entry left behind is never reused or overwritten — it just
/// accumulates for the life of the process. A plain call after the search would
/// not do: the search returns through `?` on any SQLite error, and `SearchView`
/// swallows the rejection, so the error path is the common case, not the rare
/// one. `Drop` covers the early return and the unwind both.
struct SessionSearchRelease(Option<SessionSearchToken>);

impl Drop for SessionSearchRelease {
    fn drop(&mut self) {
        end_session_search(self.0.as_ref());
    }
}

/// The generation check happens under the map lock, not before it.
///
/// `begin_session_search` bumps the counter while holding that same lock, so
/// checking `is_current` outside the critical section leaves a window: a newer
/// search can register in between, and since both tokens share one `Arc`, the
/// `ptr_eq` test cannot tell them apart. Removing the entry then would strip
/// the live search of its registration, leaving it running and impossible to
/// cancel. The superseded search must leave the newer counter alone, so the
/// whole decision has to be atomic with respect to registration.
fn end_session_search(token: Option<&SessionSearchToken>) {
    let Some(token) = token else {
        return;
    };
    let Ok(mut tokens) = SESSION_SEARCH_TOKENS.lock() else {
        return;
    };
    let ours = tokens
        .as_ref()
        .and_then(|tokens| tokens.get(&token.owner))
        .is_some_and(|registered| Arc::ptr_eq(registered, &token.counter) && token.is_current());
    if ours {
        if let Some(tokens) = tokens.as_mut() {
            tokens.remove(&token.owner);
        }
    }
}

#[cfg(test)]
fn session_search_token_registered(owner: &str) -> bool {
    SESSION_SEARCH_TOKENS
        .lock()
        .ok()
        .and_then(|tokens| tokens.as_ref().map(|tokens| tokens.contains_key(owner)))
        .unwrap_or(false)
}

fn cancel_owned_session_search(owner: &str) {
    if owner.is_empty() {
        return;
    }
    if let Ok(mut tokens) = SESSION_SEARCH_TOKENS.lock() {
        if let Some(counter) = tokens.as_mut().and_then(|tokens| tokens.remove(owner)) {
            counter.fetch_add(1, Ordering::AcqRel);
        }
    }
}

fn session_search_is_current(token: Option<&SessionSearchToken>) -> bool {
    token.is_none_or(SessionSearchToken::is_current)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSearchOptions {
    pub query: String,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub include_archived: bool,
    #[serde(default)]
    pub search_owner: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SessionSearchHit {
    pub kind: String,
    pub session_id: String,
    pub cwd: String,
    pub harness: String,
    pub title: String,
    pub updated_at: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub block_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    pub preview: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SessionSearchResult {
    pub hits: Vec<SessionSearchHit>,
    pub truncated: bool,
}

#[tauri::command(async)]
pub fn session_search(
    store: State<'_, SessionStore>,
    options: SessionSearchOptions,
) -> Result<SessionSearchResult, String> {
    search_store(&store, &options)
}

fn search_store(
    store: &SessionStore,
    options: &SessionSearchOptions,
) -> Result<SessionSearchResult, String> {
    let token = begin_session_search(&options.search_owner);
    let release = SessionSearchRelease(token.clone());
    let result = {
        let read_conn = store
            .read_conn
            .lock()
            .map_err(|_| "Session read store is locked")?;
        if let Some(conn) = read_conn.as_ref() {
            search_sessions_with_connection(conn, options, token.as_ref())?
        } else {
            let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
            search_sessions_with_connection(&conn, options, token.as_ref())?
        }
    };
    drop(release);
    if session_search_is_current(token.as_ref()) {
        Ok(result)
    } else {
        Ok(SessionSearchResult {
            hits: Vec::new(),
            truncated: false,
        })
    }
}

#[tauri::command(async)]
pub fn cancel_session_search(search_owner: String) {
    cancel_owned_session_search(&search_owner);
}

#[tauri::command(async)]
pub fn session_delete(
    app: AppHandle,
    store: State<'_, SessionStore>,
    session_id: String,
    mut image_paths: Vec<String>,
) -> Result<(), String> {
    validate_id(&session_id, "session")?;
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    let persisted_paths = get_session(&conn, &session_id)
        .ok()
        .flatten()
        .map(|record| generated_image_paths(&record.blocks))
        .unwrap_or_default();
    image_paths.extend(persisted_paths);
    delete_session(&conn, &session_id).map_err(|e| e.to_string())?;
    drop(conn);
    if !image_paths.is_empty() {
        if let Err(error) = crate::fs::delete_generated_images_sync(&app, &image_paths) {
            eprintln!("Generated image cleanup will need a retry: {error}");
        }
    }
    let _ = app.emit(crate::reminders::CHANGED, ());
    Ok(())
}

#[tauri::command(async)]
pub fn session_set_archived(
    store: State<'_, SessionStore>,
    session_id: String,
    archived: bool,
) -> Result<(), String> {
    validate_id(&session_id, "session")?;
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    set_archived(&conn, &session_id, archived).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn session_set_pinned(
    store: State<'_, SessionStore>,
    session_id: String,
    pinned: bool,
) -> Result<(), String> {
    validate_id(&session_id, "session")?;
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    set_pinned(&conn, &session_id, pinned).map_err(|e| e.to_string())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InFlightSession {
    pub session_id: String,
    pub cwd: String,
}

#[tauri::command(async)]
pub fn session_set_in_flight(
    store: State<'_, SessionStore>,
    sessions: Vec<InFlightSession>,
) -> Result<(), String> {
    for session in &sessions {
        validate_id(&session.session_id, "session")?;
        if session.cwd.trim().is_empty() {
            return Err("cwd is required".into());
        }
    }
    let mut conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    replace_in_flight(&mut conn, &sessions).map_err(|e| e.to_string())
}

/// Read the quit snapshot without clearing it. Vite/dev reloads must not
/// consume the only copy.
#[tauri::command(async)]
pub fn session_list_in_flight(
    store: State<'_, SessionStore>,
) -> Result<Vec<InFlightSession>, String> {
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    list_in_flight(&conn).map_err(|e| e.to_string())
}

/// Read and clear the quit snapshot so a restored window cannot take it twice.
#[tauri::command(async)]
pub fn session_take_in_flight(
    store: State<'_, SessionStore>,
) -> Result<Vec<InFlightSession>, String> {
    let mut conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    take_in_flight(&mut conn).map_err(|e| e.to_string())
}

const WORKSPACE_SNAPSHOT_MAX_BYTES: usize = 2_000_000;

#[tauri::command(async)]
pub fn workspace_set_snapshot(
    store: State<'_, SessionStore>,
    snapshot: Value,
) -> Result<(), String> {
    if !snapshot.is_object() {
        return Err("workspace snapshot must be an object".into());
    }
    let json = serde_json::to_string(&snapshot).map_err(|e| e.to_string())?;
    if json.len() > WORKSPACE_SNAPSHOT_MAX_BYTES {
        return Err("workspace snapshot is too large".into());
    }
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    set_workspace_snapshot(&conn, &json).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn workspace_get_snapshot(store: State<'_, SessionStore>) -> Result<Option<Value>, String> {
    let conn = store.conn.lock().map_err(|_| "Session store is locked")?;
    let json = get_workspace_snapshot(&conn).map_err(|e| e.to_string())?;
    match json {
        None => Ok(None),
        Some(raw) => serde_json::from_str(&raw).map_err(|e| e.to_string()),
    }
}
fn migrate(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY, cwd TEXT NOT NULL, harness TEXT NOT NULL,
      model TEXT NOT NULL, model_settings TEXT NOT NULL DEFAULT '{}',
      runtime_mode TEXT NOT NULL, title TEXT NOT NULL, provider_session_id TEXT,
      blocks_json TEXT NOT NULL DEFAULT '[]', created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL, context_used INTEGER, context_window INTEGER,
      archived INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0,
      has_user_message INTEGER NOT NULL DEFAULT 0, provider_account_id TEXT,
      is_draft INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS sessions_cwd_updated_idx ON sessions (cwd, updated_at DESC);
    CREATE INDEX IF NOT EXISTS sessions_cwd_cover_idx
      ON sessions (cwd, has_user_message, updated_at DESC, id, harness,
                   model, runtime_mode, title, provider_session_id, created_at,
                   archived, pinned, is_draft);
    CREATE TABLE IF NOT EXISTS in_flight_sessions (
      session_id TEXT PRIMARY KEY, cwd TEXT NOT NULL, sort_index INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS workspace_snapshot (
      id INTEGER PRIMARY KEY CHECK (id = 1), snapshot_json TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );",
    )?;
    crate::notes::ensure_notes_table(conn)?;
    crate::reminders::ensure_table(conn)?;
    conn.execute(
        "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, ?1)",
        [now_millis()],
    )?;
    Ok(())
}

fn upsert_session(conn: &Connection, session: &SessionUpsert) -> rusqlite::Result<SessionSummary> {
    let now = now_millis();
    let model_settings = serde_json::to_string(&session.model_settings)
        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
    let blocks_json = serde_json::to_string(&session.blocks)
        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
    let provider_session_id = session
        .provider_session_id
        .as_ref()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty());
    let provider_account_id = session
        .provider_account_id
        .as_ref()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty());
    let has_user_message = has_user_block(&session.blocks);
    let is_draft = has_draft_block(&session.blocks);

    let existing: Option<(i64, i64, String, i64, i64)> = conn
        .query_row(
            "SELECT created_at, updated_at, blocks_json, archived, pinned FROM sessions WHERE id = ?1",
            params![session.id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
        )
        .optional()?;
    let created_at = existing
        .as_ref()
        .map(|(value, _, _, _, _)| *value)
        .unwrap_or(now);
    let updated_at = match &existing {
        Some((_, prev_updated, prev_blocks, _, _)) if json_eq(prev_blocks, &session.blocks) => {
            *prev_updated
        }
        _ => now,
    };
    let archived = existing
        .as_ref()
        .map(|(_, _, _, value, _)| *value != 0)
        .unwrap_or(false);
    let pinned = existing
        .as_ref()
        .map(|(_, _, _, _, value)| *value != 0)
        .unwrap_or(false);

    conn.execute(
        "INSERT INTO sessions (
           id, cwd, harness, model, model_settings, runtime_mode, title,
           provider_session_id, blocks_json, created_at, updated_at,
           context_used, context_window, has_user_message, provider_account_id, is_draft
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
         ON CONFLICT(id) DO UPDATE SET
           cwd = excluded.cwd, harness = excluded.harness, model = excluded.model,
           model_settings = excluded.model_settings, runtime_mode = excluded.runtime_mode,
           title = excluded.title, provider_session_id = excluded.provider_session_id,
           blocks_json = excluded.blocks_json, updated_at = excluded.updated_at,
           context_used = excluded.context_used, context_window = excluded.context_window,
           has_user_message = excluded.has_user_message,
           provider_account_id = excluded.provider_account_id, is_draft = excluded.is_draft",
        params![
            session.id,
            session.cwd,
            session.harness,
            session.model,
            model_settings,
            session.runtime_mode,
            session.title,
            provider_session_id,
            blocks_json,
            created_at,
            updated_at,
            session.context_used,
            session.context_window,
            i64::from(has_user_message),
            provider_account_id,
            i64::from(is_draft)
        ],
    )?;
    Ok(SessionSummary {
        id: session.id.clone(),
        cwd: session.cwd.clone(),
        harness: session.harness.clone(),
        model: session.model.clone(),
        runtime_mode: session.runtime_mode.clone(),
        title: session.title.clone(),
        provider_session_id: provider_session_id.map(str::to_owned),
        created_at,
        updated_at,
        archived,
        pinned,
        draft: is_draft,
    })
}

struct SearchProgressGuard<'a>(&'a Connection);

impl Drop for SearchProgressGuard<'_> {
    fn drop(&mut self) {
        let _ = self.0.progress_handler(1, None::<fn() -> bool>);
    }
}

#[cfg(test)]
fn search_sessions(
    conn: &Connection,
    options: &SessionSearchOptions,
) -> Result<SessionSearchResult, String> {
    let token = begin_session_search(&options.search_owner);
    let _release = SessionSearchRelease(token.clone());
    search_sessions_with_connection(conn, options, token.as_ref())
}

fn search_sessions_sql(include_archived: bool, cwd_scoped: bool) -> String {
    let mut sql = String::from(
        "SELECT id, cwd, harness, title, updated_at, archived,
                CASE WHEN octet_length(blocks_json) <= ?2
                     THEN blocks_json ELSE NULL END
         FROM sessions",
    );
    if !cwd_scoped {
        // Keep metadata reads inside the covering index so oversized transcripts
        // are not loaded before the byte budget can reject them.
        sql.push_str(" INDEXED BY sessions_cwd_cover_idx");
    }
    sql.push_str(
        " WHERE has_user_message = 1
            AND (LOWER(title) LIKE LOWER(?1) ESCAPE '\\'
                 OR CASE WHEN octet_length(blocks_json) <= ?2
                         THEN LOWER(blocks_json) LIKE LOWER(?1) ESCAPE '\\'
                         ELSE 0 END)",
    );
    if !include_archived {
        sql.push_str(" AND archived = 0");
    }
    if cwd_scoped {
        sql.push_str(" AND cwd = ?3");
        sql.push_str(" ORDER BY updated_at DESC, id ASC LIMIT ?4");
    } else {
        sql.push_str(" ORDER BY updated_at DESC, id ASC LIMIT ?3");
    }
    sql
}

fn search_sessions_with_connection(
    conn: &Connection,
    options: &SessionSearchOptions,
    token: Option<&SessionSearchToken>,
) -> Result<SessionSearchResult, String> {
    let query = options.query.trim();
    if query.is_empty() {
        return Ok(SessionSearchResult {
            hits: Vec::new(),
            truncated: false,
        });
    }
    let needle = query.to_lowercase();
    let pattern = like_pattern(query);
    let cwd = options
        .cwd
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());

    let budget = MAX_SEARCH_BUFFER_BYTES as i64;
    let sql = search_sessions_sql(options.include_archived, cwd.is_some());

    let mut statement = conn.prepare(&sql).map_err(|e| e.to_string())?;
    let limit = (MAX_SEARCH_SCAN as i64) + 1;
    let mut rows = if let Some(cwd) = cwd {
        statement
            .query(params![pattern, budget, cwd, limit])
            .map_err(|e| e.to_string())?
    } else {
        statement
            .query(params![pattern, budget, limit])
            .map_err(|e| e.to_string())?
    };

    let progress_token = token.cloned();
    conn.progress_handler(
        SEARCH_PROGRESS_INTERVAL as i32,
        Some(move || !session_search_is_current(progress_token.as_ref())),
    )
    .map_err(|e| e.to_string())?;
    let _progress_guard = SearchProgressGuard(conn);
    let mut conversations = Vec::new();
    let mut messages = Vec::new();
    let mut scanned = 0usize;
    let mut truncated = false;
    loop {
        if !session_search_is_current(token) {
            return Ok(SessionSearchResult {
                hits: Vec::new(),
                truncated: false,
            });
        }
        let row = match rows.next() {
            Ok(None) => break,
            Ok(Some(row)) => row,
            Err(_) if !session_search_is_current(token) => {
                return Ok(SessionSearchResult {
                    hits: Vec::new(),
                    truncated: false,
                });
            }
            Err(error) => return Err(error.to_string()),
        };
        scanned += 1;
        if scanned > MAX_SEARCH_SCAN {
            truncated = true;
            break;
        }

        let id: String = row.get(0).map_err(|e| e.to_string())?;
        let cwd: String = row.get(1).map_err(|e| e.to_string())?;
        let harness: String = row.get(2).map_err(|e| e.to_string())?;
        let title: String = row.get(3).map_err(|e| e.to_string())?;
        let updated_at: i64 = row.get(4).map_err(|e| e.to_string())?;
        let title_hit = title.to_lowercase().contains(&needle);
        if title_hit && conversations.len() < MAX_CONVERSATION_HITS {
            conversations.push(SessionSearchHit {
                kind: "conversation".into(),
                session_id: id.clone(),
                cwd: cwd.clone(),
                harness: harness.clone(),
                title: title.clone(),
                updated_at,
                block_id: None,
                role: None,
                preview: String::new(),
            });
        }

        if messages.len() >= MAX_MESSAGE_HITS {
            if title_hit {
                continue;
            }
            if conversations.len() >= MAX_CONVERSATION_HITS {
                truncated = true;
                break;
            }
            continue;
        }

        let blocks_raw = match row.get_ref(6).map_err(|e| e.to_string())? {
            rusqlite::types::ValueRef::Null => {
                truncated = true;
                continue;
            }
            value => {
                String::from_utf8_lossy(value.as_bytes().map_err(|e| e.to_string())?).into_owned()
            }
        };
        let Ok(blocks) = serde_json::from_str::<Value>(&blocks_raw) else {
            continue;
        };
        for hit in block_hits(&blocks, &needle) {
            messages.push(SessionSearchHit {
                kind: "message".into(),
                session_id: id.clone(),
                cwd: cwd.clone(),
                harness: harness.clone(),
                title: title.clone(),
                updated_at,
                block_id: Some(hit.0),
                role: Some(hit.1),
                preview: hit.2,
            });
            if messages.len() >= MAX_MESSAGE_HITS {
                truncated = true;
                break;
            }
        }
    }

    if conversations.len() >= MAX_CONVERSATION_HITS {
        truncated = true;
    }
    let mut hits = conversations;
    hits.extend(messages);
    Ok(SessionSearchResult { hits, truncated })
}

fn like_pattern(query: &str) -> String {
    let mut out = String::from("%");
    for ch in query.chars().take(200) {
        match ch {
            '%' | '_' | '\\' => {
                out.push('\\');
                out.push(ch);
            }
            _ => out.push(ch),
        }
    }
    out.push('%');
    out
}

fn block_hits(blocks: &Value, needle: &str) -> Vec<(String, String, String)> {
    let Some(items) = blocks.as_array() else {
        return Vec::new();
    };
    let mut hits = Vec::new();
    for block in items {
        let role = block
            .get("role")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if !matches!(
            role,
            "user" | "assistant" | "tool" | "tasks" | "plan" | "image"
        ) {
            continue;
        }
        let id = block
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        if id.is_empty() {
            continue;
        }
        for text in block_texts(block) {
            if !text.to_lowercase().contains(needle) {
                continue;
            }
            hits.push((id.clone(), role.to_string(), snippet_around(&text, needle)));
            break;
        }
    }
    hits
}

fn block_texts(block: &Value) -> Vec<String> {
    let mut texts = Vec::new();
    push_text(&mut texts, block.get("text"));
    if let Some(image) = block.get("image") {
        push_text(&mut texts, image.get("name"));
        push_text(&mut texts, image.get("alt"));
    }
    if let Some(tool) = block.get("tool") {
        push_text(&mut texts, tool.get("title"));
        push_text(&mut texts, tool.get("detail"));
        if let Some(preview) = tool.get("preview") {
            push_text(&mut texts, preview.get("query"));
            push_text(&mut texts, preview.get("path"));
            push_text(&mut texts, preview.get("output"));
            push_text(&mut texts, preview.get("title"));
        }
    }
    texts
}

fn push_text(texts: &mut Vec<String>, value: Option<&Value>) {
    if let Some(text) = value.and_then(Value::as_str) {
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            texts.push(trimmed.to_string());
        }
    }
}

fn snippet_around(text: &str, needle: &str) -> String {
    let compact = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let lower = compact.to_lowercase();
    let Some(index) = lower.find(needle) else {
        if compact.chars().count() <= SNIPPET_RADIUS * 2 {
            return compact;
        }
        return format!(
            "{}…",
            compact.chars().take(SNIPPET_RADIUS * 2).collect::<String>()
        );
    };
    let start = floor_char_boundary(&compact, index.saturating_sub(SNIPPET_RADIUS));
    let end = ceil_char_boundary(
        &compact,
        (index + needle.len() + SNIPPET_RADIUS).min(compact.len()),
    );
    let mut snippet = compact[start..end].trim().to_string();
    if start > 0 {
        snippet = format!("…{snippet}");
    }
    if end < compact.len() {
        snippet = format!("{snippet}…");
    }
    snippet
}

fn floor_char_boundary(text: &str, mut index: usize) -> usize {
    if index >= text.len() {
        return text.len();
    }
    while index > 0 && !text.is_char_boundary(index) {
        index -= 1;
    }
    index
}

fn ceil_char_boundary(text: &str, mut index: usize) -> usize {
    if index >= text.len() {
        return text.len();
    }
    while index < text.len() && !text.is_char_boundary(index) {
        index += 1;
    }
    index
}
fn list_by_project(conn: &Connection, cwd: &str) -> rusqlite::Result<Vec<SessionSummary>> {
    let mut statement = conn.prepare(
        "SELECT id, cwd, harness, model, runtime_mode, title, provider_session_id,
                created_at, updated_at, archived, pinned, is_draft
         FROM sessions WHERE cwd = ?1 AND has_user_message = 1
         ORDER BY updated_at DESC, id ASC",
    )?;
    let rows = statement.query_map(params![cwd], |row| {
        Ok(SessionSummary {
            id: row.get(0)?,
            cwd: row.get(1)?,
            harness: row.get(2)?,
            model: row.get(3)?,
            runtime_mode: row.get(4)?,
            title: row.get(5)?,
            provider_session_id: row.get(6)?,
            created_at: row.get(7)?,
            updated_at: row.get(8)?,
            archived: row.get::<_, i64>(9)? != 0,
            pinned: row.get::<_, i64>(10)? != 0,
            draft: row.get::<_, i64>(11)? != 0,
        })
    })?;
    rows.collect()
}

/// Mirrors the sidebar's notion of a listable session: a transcript that the
/// user has actually said something in.
fn has_user_block(blocks: &Value) -> bool {
    blocks.as_array().is_some_and(|blocks| {
        blocks
            .iter()
            .any(|block| block.get("role").and_then(Value::as_str) == Some("user"))
    })
}

fn has_draft_block(blocks: &Value) -> bool {
    blocks.as_array().is_some_and(|blocks| {
        blocks.iter().any(|block| {
            block.get("role").and_then(Value::as_str) == Some("user")
                && block.get("draft").and_then(Value::as_bool) == Some(true)
        })
    })
}

fn json_eq(raw: &str, incoming: &Value) -> bool {
    match serde_json::from_str::<Value>(raw) {
        Ok(previous) => previous == *incoming,
        Err(_) => false,
    }
}
fn delete_session(conn: &Connection, session_id: &str) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM sessions WHERE id = ?1", [session_id])?;
    Ok(())
}

fn set_archived(conn: &Connection, session_id: &str, archived: bool) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE sessions SET archived = ?1 WHERE id = ?2",
        params![if archived { 1 } else { 0 }, session_id],
    )?;
    Ok(())
}

fn set_pinned(conn: &Connection, session_id: &str, pinned: bool) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE sessions SET pinned = ?1 WHERE id = ?2",
        params![if pinned { 1 } else { 0 }, session_id],
    )?;
    Ok(())
}

fn get_session(conn: &Connection, session_id: &str) -> rusqlite::Result<Option<SessionRecord>> {
    conn.query_row(
        "SELECT id, cwd, harness, model, model_settings, runtime_mode, title,
                provider_session_id, blocks_json, created_at, updated_at,
                context_used, context_window, provider_account_id
         FROM sessions
         WHERE id = ?1",
        params![session_id],
        |row| {
            let model_settings_raw: String = row.get(4)?;
            let blocks_raw: String = row.get(8)?;
            let model_settings = serde_json::from_str(&model_settings_raw).map_err(|e| {
                rusqlite::Error::FromSqlConversionFailure(
                    4,
                    rusqlite::types::Type::Text,
                    Box::new(e),
                )
            })?;
            let blocks = serde_json::from_str(&blocks_raw).map_err(|e| {
                rusqlite::Error::FromSqlConversionFailure(
                    8,
                    rusqlite::types::Type::Text,
                    Box::new(e),
                )
            })?;
            Ok(SessionRecord {
                id: row.get(0)?,
                cwd: row.get(1)?,
                harness: row.get(2)?,
                model: row.get(3)?,
                model_settings,
                runtime_mode: row.get(5)?,
                title: row.get(6)?,
                provider_session_id: row.get(7)?,
                blocks,
                context_used: row.get(11)?,
                context_window: row.get(12)?,
                provider_account_id: row.get(13)?,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
            })
        },
    )
    .optional()
}

fn list_in_flight(conn: &Connection) -> rusqlite::Result<Vec<InFlightSession>> {
    let mut statement = conn.prepare(
        "SELECT session_id, cwd FROM in_flight_sessions ORDER BY sort_index ASC, session_id ASC",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(InFlightSession {
            session_id: row.get(0)?,
            cwd: row.get(1)?,
        })
    })?;
    rows.collect()
}

fn replace_in_flight(conn: &mut Connection, sessions: &[InFlightSession]) -> rusqlite::Result<()> {
    let tx = conn.transaction()?;
    tx.execute("DELETE FROM in_flight_sessions", [])?;
    {
        let mut insert = tx.prepare(
            "INSERT INTO in_flight_sessions (session_id, cwd, sort_index)
             VALUES (?1, ?2, ?3)",
        )?;
        for (index, session) in sessions.iter().enumerate() {
            insert.execute(params![session.session_id, session.cwd, index as i64])?;
        }
    }
    tx.commit()?;
    Ok(())
}

fn take_in_flight(conn: &mut Connection) -> rusqlite::Result<Vec<InFlightSession>> {
    let tx = conn.transaction()?;
    let sessions = {
        let mut statement = tx.prepare(
            "SELECT session_id, cwd FROM in_flight_sessions ORDER BY sort_index ASC, session_id ASC",
        )?;
        let rows = statement.query_map([], |row| {
            Ok(InFlightSession {
                session_id: row.get(0)?,
                cwd: row.get(1)?,
            })
        })?;
        rows.collect::<rusqlite::Result<Vec<_>>>()?
    };
    tx.execute("DELETE FROM in_flight_sessions", [])?;
    tx.commit()?;
    Ok(sessions)
}

fn set_workspace_snapshot(conn: &Connection, json: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO workspace_snapshot (id, snapshot_json, updated_at)
         VALUES (1, ?1, ?2)
         ON CONFLICT(id) DO UPDATE SET
           snapshot_json = excluded.snapshot_json,
           updated_at = excluded.updated_at",
        params![json, now_millis()],
    )?;
    Ok(())
}

fn get_workspace_snapshot(conn: &Connection) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT snapshot_json FROM workspace_snapshot WHERE id = 1",
        [],
        |row| row.get(0),
    )
    .optional()
}

pub(crate) fn validate_id(value: &str, label: &str) -> Result<(), String> {
    if value.is_empty()
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(format!("Invalid {label} id"));
    }
    Ok(())
}

pub(crate) fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::hooks::{AuthAction, Authorization};
    use std::sync::atomic::AtomicUsize;

    fn sample(id: &str, cwd: &str, title: &str) -> SessionUpsert {
        SessionUpsert {
            id: id.into(),
            cwd: cwd.into(),
            harness: "codex".into(),
            model: "gpt-5".into(),
            model_settings: json!({ "thinking": "high" }),
            runtime_mode: "supervised".into(),
            title: title.into(),
            provider_session_id: Some("provider-session-1".into()),
            provider_account_id: None,
            blocks: json!([{ "id": "b1", "role": "user", "text": "hello" }]),
            context_used: None,
            context_window: None,
        }
    }

    #[test]
    fn startup_does_not_read_saved_transcripts() {
        let data_dir = std::env::temp_dir().join(format!(
            "loci-startup-transcripts-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = data_dir.join("loci.db");
        {
            let store = SessionStore::open(path.clone()).unwrap();
            let conn = store.lock_conn().unwrap();
            conn.execute(
                "INSERT INTO sessions (
                   id, cwd, harness, model, runtime_mode, title,
                   blocks_json, created_at, updated_at
                 ) VALUES ('large', '/tmp', 'codex', 'test', 'supervised', 'Large', ?1, 1, 1)",
                ["x".repeat(8_000_000)],
            )
            .unwrap();
        }

        let transcript_reads = Arc::new(AtomicUsize::new(0));
        let reads = Arc::clone(&transcript_reads);
        let mut managed = None;
        init_with(
            || Ok(data_dir.clone()),
            |requested_path| {
                assert_eq!(requested_path, path);
                let store = SessionStore::open(requested_path)?;
                store
                    .lock_conn()?
                    .authorizer(Some(move |context: rusqlite::hooks::AuthContext<'_>| {
                        if matches!(
                            context.action,
                            AuthAction::Read {
                                table_name: "sessions",
                                column_name: "blocks_json"
                            }
                        ) {
                            reads.fetch_add(1, Ordering::Relaxed);
                            Authorization::Deny
                        } else {
                            Authorization::Allow
                        }
                    }))
                    .map_err(|error| error.to_string())?;
                Ok(store)
            },
            |store| managed = Some(store),
        )
        .unwrap();
        assert_eq!(transcript_reads.load(Ordering::Relaxed), 0);
        drop(managed);
        let _ = std::fs::remove_dir_all(data_dir);
    }

    #[test]
    fn upsert_tracks_whether_a_user_has_spoken() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut quiet = sample("s1", "/tmp/a", "Quiet");
        quiet.blocks = json!([{ "id": "b1", "role": "assistant", "text": "hi" }]);
        upsert_session(&conn, &quiet).unwrap();
        assert!(list_by_project(&conn, "/tmp/a").unwrap().is_empty());

        // The flag has to follow the transcript, not just the first write.
        quiet.blocks = json!([
            { "id": "b1", "role": "assistant", "text": "hi" },
            { "id": "b2", "role": "user", "text": "hello" }
        ]);
        upsert_session(&conn, &quiet).unwrap();
        assert_eq!(list_by_project(&conn, "/tmp/a").unwrap().len(), 1);
    }

    #[test]
    fn draft_marker_round_trips_through_session_summaries() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut session = sample("s1", "/tmp/a", "Draft");
        session.blocks = json!([
            { "id": "b1", "role": "user", "text": "start" },
            { "id": "b2", "role": "assistant", "text": "done" },
            { "id": "b3", "role": "user", "text": "hello", "draft": true }
        ]);

        let saved = upsert_session(&conn, &session).unwrap();
        assert!(saved.draft);
        assert!(list_by_project(&conn, "/tmp/a").unwrap()[0].draft);

        session.blocks = json!([
            { "id": "b1", "role": "user", "text": "start" },
            { "id": "b2", "role": "assistant", "text": "done" },
            { "id": "b3", "role": "user", "text": "hello" }
        ]);
        let sent = upsert_session(&conn, &session).unwrap();
        assert!(!sent.draft);
        assert!(!list_by_project(&conn, "/tmp/a").unwrap()[0].draft);
    }

    #[test]
    fn upsert_preserves_created_at_and_updates_fields() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let first = upsert_session(&conn, &sample("s1", "/tmp/a", "First")).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        let mut next = sample("s1", "/tmp/a", "Updated");
        next.provider_session_id = Some("acp-session-2".into());
        next.blocks = json!([
            { "id": "b1", "role": "user", "text": "hello" },
            { "id": "b2", "role": "assistant", "text": "world" }
        ]);
        let second = upsert_session(&conn, &next).unwrap();
        assert_eq!(second.created_at, first.created_at);
        assert!(second.updated_at > first.updated_at);
        assert_eq!(second.title, "Updated");
        assert_eq!(second.provider_session_id.as_deref(), Some("acp-session-2"));
    }

    #[test]
    fn context_usage_round_trips() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut row = sample("s1", "/tmp/a", "First");
        row.context_used = Some(29_821);
        row.context_window = Some(1_000_000);
        upsert_session(&conn, &row).unwrap();
        let stored = get_session(&conn, "s1").unwrap().unwrap();
        assert_eq!(stored.context_used, Some(29_821));
        assert_eq!(stored.context_window, Some(1_000_000));
    }

    #[test]
    fn context_usage_is_absent_until_a_harness_reports() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "First")).unwrap();
        let stored = get_session(&conn, "s1").unwrap().unwrap();
        assert_eq!(stored.context_used, None);
        assert_eq!(stored.context_window, None);
    }

    #[test]
    fn upsert_same_blocks_keeps_updated_at() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let first = upsert_session(&conn, &sample("s1", "/tmp/a", "First")).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        let mut next = sample("s1", "/tmp/a", "First");
        next.model = "gpt-5.4".into();
        let second = upsert_session(&conn, &next).unwrap();
        assert_eq!(second.updated_at, first.updated_at);
        assert_eq!(second.model, "gpt-5.4");
    }

    #[test]
    fn list_by_project_filters_and_orders() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "A1")).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        upsert_session(&conn, &sample("s2", "/tmp/a", "A2")).unwrap();
        upsert_session(&conn, &sample("s3", "/tmp/b", "B1")).unwrap();
        let mut empty = sample("s4", "/tmp/a", "Empty");
        empty.blocks = json!([]);
        upsert_session(&conn, &empty).unwrap();
        let listed = list_by_project(&conn, "/tmp/a").unwrap();
        assert_eq!(listed.len(), 2);
        assert_eq!(listed[0].id, "s2");
        assert_eq!(listed[1].id, "s1");
    }

    #[test]
    fn delete_removes_session() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "First")).unwrap();
        delete_session(&conn, "s1").unwrap();
        assert!(get_session(&conn, "s1").unwrap().is_none());
        assert!(list_by_project(&conn, "/tmp/a").unwrap().is_empty());
    }

    #[test]
    fn archive_round_trips_and_survives_upsert() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "First")).unwrap();
        set_archived(&conn, "s1", true).unwrap();
        let listed = list_by_project(&conn, "/tmp/a").unwrap();
        assert!(listed[0].archived);
        let mut next = sample("s1", "/tmp/a", "Updated");
        next.blocks = json!([
            { "id": "b1", "role": "user", "text": "hello" },
            { "id": "b2", "role": "assistant", "text": "world" }
        ]);
        let summary = upsert_session(&conn, &next).unwrap();
        assert!(summary.archived);
        assert_eq!(summary.title, "Updated");
        set_archived(&conn, "s1", false).unwrap();
        let listed = list_by_project(&conn, "/tmp/a").unwrap();
        assert!(!listed[0].archived);
    }

    #[test]
    fn pin_round_trips_and_survives_upsert() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "First")).unwrap();
        set_pinned(&conn, "s1", true).unwrap();
        let listed = list_by_project(&conn, "/tmp/a").unwrap();
        assert!(listed[0].pinned);
        let mut next = sample("s1", "/tmp/a", "Updated");
        next.blocks = json!([
            { "id": "b1", "role": "user", "text": "hello" },
            { "id": "b2", "role": "assistant", "text": "world" }
        ]);
        let summary = upsert_session(&conn, &next).unwrap();
        assert!(summary.pinned);
        assert_eq!(summary.title, "Updated");
        set_pinned(&conn, "s1", false).unwrap();
        let listed = list_by_project(&conn, "/tmp/a").unwrap();
        assert!(!listed[0].pinned);
    }

    #[test]
    fn get_round_trips_blocks_provider_session_and_account() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut session = sample("s1", "/tmp/a", "First");
        session.provider_account_id = Some("account-work".into());
        upsert_session(&conn, &session).unwrap();
        let record = get_session(&conn, "s1").unwrap().unwrap();
        assert_eq!(record.id, "s1");
        assert_eq!(
            record.provider_session_id.as_deref(),
            Some("provider-session-1")
        );
        assert_eq!(record.provider_account_id.as_deref(), Some("account-work"));
        assert_eq!(record.model_settings["thinking"], "high");
        assert_eq!(record.blocks.as_array().unwrap().len(), 1);
        assert_eq!(record.blocks[0]["text"], "hello");
    }

    #[test]
    fn rebase_project_moves_saved_sessions_to_the_renamed_path() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("moved", "/tmp/old", "Moved")).unwrap();
        upsert_session(&conn, &sample("other", "/tmp/other", "Other")).unwrap();

        rebase_project(&conn, "/tmp/old", "/tmp/new").unwrap();

        assert!(list_by_project(&conn, "/tmp/old").unwrap().is_empty());
        assert_eq!(list_by_project(&conn, "/tmp/new").unwrap()[0].id, "moved");
        assert_eq!(list_by_project(&conn, "/tmp/other").unwrap()[0].id, "other");
    }

    #[test]
    fn in_flight_set_take_is_ordered_and_destructive() {
        let store = SessionStore::open_in_memory().unwrap();
        let mut conn = store.conn.lock().unwrap();
        replace_in_flight(
            &mut conn,
            &[
                InFlightSession {
                    session_id: "s2".into(),
                    cwd: "/tmp/b".into(),
                },
                InFlightSession {
                    session_id: "s1".into(),
                    cwd: "/tmp/a".into(),
                },
            ],
        )
        .unwrap();
        let first = take_in_flight(&mut conn).unwrap();
        assert_eq!(first.len(), 2);
        assert_eq!(first[0].session_id, "s2");
        assert_eq!(first[0].cwd, "/tmp/b");
        assert_eq!(first[1].session_id, "s1");
        let second = take_in_flight(&mut conn).unwrap();
        assert!(second.is_empty());
    }

    #[test]
    fn in_flight_list_does_not_clear() {
        let store = SessionStore::open_in_memory().unwrap();
        let mut conn = store.conn.lock().unwrap();
        replace_in_flight(
            &mut conn,
            &[InFlightSession {
                session_id: "s1".into(),
                cwd: "/tmp/a".into(),
            }],
        )
        .unwrap();
        let listed = list_in_flight(&conn).unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].session_id, "s1");
        let listed_again = list_in_flight(&conn).unwrap();
        assert_eq!(listed_again.len(), 1);
    }

    #[test]
    fn in_flight_replace_clears_previous() {
        let store = SessionStore::open_in_memory().unwrap();
        let mut conn = store.conn.lock().unwrap();
        replace_in_flight(
            &mut conn,
            &[InFlightSession {
                session_id: "old".into(),
                cwd: "/tmp/old".into(),
            }],
        )
        .unwrap();
        replace_in_flight(&mut conn, &[]).unwrap();
        assert!(take_in_flight(&mut conn).unwrap().is_empty());
    }

    #[test]
    fn workspace_snapshot_round_trips_and_replaces() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        set_workspace_snapshot(&conn, r#"{"tabs":[{"id":"t1"}]}"#).unwrap();
        let first = get_workspace_snapshot(&conn).unwrap().unwrap();
        assert!(first.contains("t1"));
        set_workspace_snapshot(&conn, r#"{"tabs":[{"id":"t2"}]}"#).unwrap();
        let second = get_workspace_snapshot(&conn).unwrap().unwrap();
        assert!(second.contains("t2"));
        assert!(!second.contains("t1"));
    }

    #[test]
    fn session_search_uses_a_query_only_read_connection() {
        let path = std::env::temp_dir().join(format!(
            "loci-session-read-conn-{}-{}.db",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let store = SessionStore::open(path.clone()).unwrap();
        upsert_session(
            &store.conn.lock().unwrap(),
            &sample("s1", "/tmp/a", "Searchable title"),
        )
        .unwrap();

        let read_conn = store.read_conn.lock().unwrap();
        let conn = read_conn.as_ref().unwrap();
        let result = search_sessions_with_connection(
            conn,
            &SessionSearchOptions {
                query: "Searchable".into(),
                cwd: None,
                include_archived: false,
                search_owner: String::new(),
            },
            None,
        )
        .unwrap();

        assert!(result.hits.iter().any(|hit| hit.session_id == "s1"));
        assert!(conn
            .execute("UPDATE sessions SET title = 'nope' WHERE id = 's1'", [])
            .is_err());
        drop(read_conn);
        drop(store);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(path.with_extension("db-wal"));
        let _ = std::fs::remove_file(path.with_extension("db-shm"));
    }

    #[test]
    fn oversized_transcript_keeps_title_hit_without_hiding_older_messages() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut small = sample("small", "/tmp/a", "Needle title");
        small.blocks = json!([{ "id": "small", "role": "user", "text": "needle" }]);
        upsert_session(&conn, &small).unwrap();
        let mut huge = sample("huge", "/tmp/a", "Needle title");
        huge.blocks = json!([{
            "id": "huge",
            "role": "user",
            "text": "needle ".repeat(1_500_000),
        }]);
        upsert_session(&conn, &huge).unwrap();
        conn.execute("UPDATE sessions SET updated_at = 1 WHERE id = 'small'", [])
            .unwrap();
        conn.execute("UPDATE sessions SET updated_at = 2 WHERE id = 'huge'", [])
            .unwrap();

        let result = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "needle".into(),
                cwd: None,
                include_archived: false,
                search_owner: String::new(),
            },
        )
        .unwrap();

        assert!(result.truncated);
        assert!(result
            .hits
            .iter()
            .any(|hit| hit.session_id == "huge" && hit.kind == "conversation"));
        assert!(!result
            .hits
            .iter()
            .any(|hit| hit.session_id == "huge" && hit.kind == "message"));
        assert!(result
            .hits
            .iter()
            .any(|hit| hit.session_id == "small" && hit.kind == "message"));
    }

    #[test]
    fn session_search_without_a_cwd_avoids_the_sessions_table() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let sql = format!("EXPLAIN QUERY PLAN {}", search_sessions_sql(false, false));
        let mut statement = conn.prepare(&sql).unwrap();
        let plan: Vec<String> = statement
            .query_map(
                params!["%needle%", MAX_SEARCH_BUFFER_BYTES as i64, 401i64],
                |row| row.get::<_, String>(3),
            )
            .unwrap()
            .map(|row| row.unwrap())
            .collect();
        assert!(plan
            .iter()
            .any(|step| step.contains("USING INDEX sessions_cwd_cover_idx")));
        for step in &plan {
            if step.contains("sessions") {
                assert!(step.contains("USING INDEX"), "table access: {step}");
            }
        }
    }

    #[test]
    fn a_new_session_search_supersedes_the_same_owner() {
        let owner = "session-search-owner-test";
        let first = begin_session_search(owner).unwrap();
        assert!(first.is_current());
        let second = begin_session_search(owner).unwrap();
        assert!(!first.is_current());
        assert!(second.is_current());
        cancel_owned_session_search(owner);
        assert!(!second.is_current());
    }

    #[test]
    fn a_completed_session_search_releases_its_token() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "Needle title")).unwrap();
        drop(conn);
        let owner = "completed-session-search-owner";

        let result = search_store(
            &store,
            &SessionSearchOptions {
                query: "Needle".into(),
                cwd: None,
                include_archived: false,
                search_owner: owner.into(),
            },
        )
        .unwrap();

        assert!(result
            .hits
            .iter()
            .any(|hit| hit.session_id == "s1" && hit.kind == "conversation"));
        assert!(!session_search_token_registered(owner));
    }

    #[test]
    fn a_superseded_session_search_does_not_release_the_newer_token() {
        let owner = "superseded-release-owner";
        let first = begin_session_search(owner).unwrap();
        let second = begin_session_search(owner).unwrap();

        end_session_search(Some(&first));

        assert!(session_search_token_registered(owner));
        assert!(!first.is_current());
        assert!(second.is_current());
        cancel_owned_session_search(owner);
    }

    #[test]
    fn cancelling_one_session_search_does_not_cancel_another() {
        let first = begin_session_search("first-session-owner").unwrap();
        let second = begin_session_search("second-session-owner").unwrap();

        cancel_owned_session_search("first-session-owner");

        assert!(!first.is_current());
        assert!(second.is_current());
    }

    #[test]
    fn a_superseded_session_search_returns_no_hits() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "Searchable title")).unwrap();
        let owner = "superseded-session-search-test";
        let stale = begin_session_search(owner).unwrap();
        begin_session_search(owner);
        let options = SessionSearchOptions {
            query: "Searchable".into(),
            cwd: None,
            include_archived: false,
            search_owner: owner.into(),
        };

        let result = search_sessions_with_connection(&conn, &options, Some(&stale)).unwrap();

        assert!(result.hits.is_empty());
        assert!(!result.truncated);
        // The progress handler belongs to the search, not the shared connection.
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM sessions", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
        cancel_owned_session_search(owner);
    }

    #[test]
    fn a_failed_session_search_releases_its_token() {
        let store = SessionStore::open_in_memory().unwrap();
        // Point the read connection at a database with no schema, so the search
        // fails inside SQLite. That error return is the path that used to skip
        // the release, and `SearchView` swallows the rejection.
        *store.read_conn.lock().unwrap() = Some(Connection::open_in_memory().unwrap());
        let owner = "failed-session-search-owner";

        let error = search_store(
            &store,
            &SessionSearchOptions {
                query: "Needle".into(),
                cwd: None,
                include_archived: false,
                search_owner: owner.into(),
            },
        );

        assert!(error.is_err(), "a search with no schema must fail");
        assert!(!session_search_token_registered(owner));
    }

    #[test]
    fn a_test_helper_session_search_releases_its_token() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "Needle title")).unwrap();
        let owner = "helper-session-search-owner";

        let result = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "Needle".into(),
                cwd: None,
                include_archived: false,
                search_owner: owner.into(),
            },
        )
        .unwrap();

        assert!(result
            .hits
            .iter()
            .any(|hit| hit.session_id == "s1" && hit.kind == "conversation"));
        assert!(!session_search_token_registered(owner));
    }

    #[test]
    fn search_uses_top_level_user_blocks_for_the_materialized_filter() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut session = sample("s1", "/tmp/a", "Unrelated title");
        session.blocks = json!([
            { "id": "t1", "role": "tool", "text": "wrapper", "tool": {
                "preview": { "output": "nested role: user needle" }
            } }
        ]);
        upsert_session(&conn, &session).unwrap();

        let result = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "needle".into(),
                cwd: None,
                include_archived: false,
                search_owner: String::new(),
            },
        )
        .unwrap();

        assert!(result.hits.is_empty());
    }

    #[test]
    fn search_finds_title_and_message_hits() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        let mut session = sample("s1", "/tmp/a", "Fix sidebar search");
        session.blocks = json!([
            { "id": "u1", "role": "user", "text": "Please search the sidebar filter chips" },
            { "id": "a1", "role": "assistant", "text": "I will look through the explorer next." }
        ]);
        upsert_session(&conn, &session).unwrap();
        upsert_session(&conn, &sample("s2", "/tmp/b", "Unrelated title")).unwrap();

        let result = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "sidebar".into(),
                cwd: None,
                include_archived: false,
                search_owner: String::new(),
            },
        )
        .unwrap();
        let kinds: Vec<_> = result
            .hits
            .iter()
            .map(|hit| {
                (
                    hit.kind.as_str(),
                    hit.session_id.as_str(),
                    hit.block_id.as_deref(),
                )
            })
            .collect();
        assert!(kinds.contains(&("conversation", "s1", None)));
        assert!(kinds.contains(&("message", "s1", Some("u1"))));
        assert!(!result.hits.iter().any(|hit| hit.session_id == "s2"));
    }

    #[test]
    fn search_respects_cwd_and_skips_archived() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "Search project a")).unwrap();
        upsert_session(&conn, &sample("s2", "/tmp/b", "Search project b")).unwrap();
        set_archived(&conn, "s1", true).unwrap();

        let scoped = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "Search project".into(),
                cwd: Some("/tmp/a".into()),
                include_archived: false,
                search_owner: String::new(),
            },
        )
        .unwrap();
        assert!(scoped.hits.is_empty());

        let with_archived = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "Search project".into(),
                cwd: Some("/tmp/a".into()),
                include_archived: true,
                search_owner: String::new(),
            },
        )
        .unwrap();
        assert!(with_archived
            .hits
            .iter()
            .any(|hit| hit.session_id == "s1" && hit.kind == "conversation"));

        let other = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "Search project".into(),
                cwd: Some("/tmp/b".into()),
                include_archived: false,
                search_owner: String::new(),
            },
        )
        .unwrap();
        assert!(other.hits.iter().any(|hit| hit.session_id == "s2"));
    }

    #[test]
    fn search_empty_query_is_empty() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.conn.lock().unwrap();
        upsert_session(&conn, &sample("s1", "/tmp/a", "Anything")).unwrap();
        let result = search_sessions(
            &conn,
            &SessionSearchOptions {
                query: "   ".into(),
                cwd: None,
                include_archived: false,
                search_owner: String::new(),
            },
        )
        .unwrap();
        assert!(result.hits.is_empty());
        assert!(!result.truncated);
    }
}
