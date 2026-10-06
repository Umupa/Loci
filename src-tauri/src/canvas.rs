use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::session_store::{validate_id, SessionStore};

const TITLE_MAX: usize = 200;
const DATA_MAX: usize = 50_000_000;
const TAG_MAX: usize = 48;
const TAGS_MAX: usize = 20;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Canvas {
    pub id: String,
    pub title: String,
    pub data_json: String,
    pub tags: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CanvasUpsert {
    pub id: String,
    pub title: String,
    pub data_json: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub cwd: Option<String>,
}

pub fn ensure_canvases_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS canvases (
           id TEXT PRIMARY KEY,
           title TEXT NOT NULL DEFAULT '',
           data_json TEXT NOT NULL DEFAULT '{\"elements\":[],\"appState\":{},\"files\":{}}',
           tags_json TEXT NOT NULL DEFAULT '[]',
           cwd TEXT,
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS canvases_updated_idx
           ON canvases (updated_at DESC, id);",
    )
}

#[tauri::command(async)]
pub fn canvas_list(store: State<'_, SessionStore>) -> Result<Vec<Canvas>, String> {
    let conn = store.lock_conn()?;
    list_canvases(&conn).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn canvas_get(store: State<'_, SessionStore>, id: String) -> Result<Option<Canvas>, String> {
    validate_id(&id, "canvas")?;
    let conn = store.lock_conn()?;
    get_canvas(&conn, &id).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn canvas_upsert(
    store: State<'_, SessionStore>,
    canvas: CanvasUpsert,
) -> Result<Canvas, String> {
    validate_id(&canvas.id, "canvas")?;
    if canvas.title.len() > TITLE_MAX {
        return Err("Canvas title is too long".into());
    }
    if canvas.data_json.len() > DATA_MAX {
        return Err("Canvas data is too large".into());
    }
    let conn = store.lock_conn()?;
    upsert_canvas(&conn, &canvas).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn canvas_delete(store: State<'_, SessionStore>, id: String) -> Result<(), String> {
    validate_id(&id, "canvas")?;
    let conn = store.lock_conn()?;
    conn.execute("DELETE FROM canvases WHERE id = ?1", params![id])
        .map(|_| ())
        .map_err(|e| e.to_string())
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn normalize_tags(tags: &[String]) -> Vec<String> {
    let mut out: Vec<String> = tags
        .iter()
        .map(|t| {
            t.to_lowercase()
                .replace(' ', "-")
                .chars()
                .take(TAG_MAX)
                .collect::<String>()
        })
        .filter(|t| !t.is_empty())
        .collect();
    out.dedup();
    out.truncate(TAGS_MAX);
    out
}

fn list_canvases(conn: &Connection) -> rusqlite::Result<Vec<Canvas>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, data_json, tags_json, cwd, created_at, updated_at
         FROM canvases
         ORDER BY updated_at DESC, id ASC",
    )?;
    let rows = stmt.query_map([], read_canvas)?;
    rows.collect()
}

fn get_canvas(conn: &Connection, id: &str) -> rusqlite::Result<Option<Canvas>> {
    conn.query_row(
        "SELECT id, title, data_json, tags_json, cwd, created_at, updated_at
         FROM canvases WHERE id = ?1",
        params![id],
        read_canvas,
    )
    .optional()
}

fn upsert_canvas(conn: &Connection, canvas: &CanvasUpsert) -> rusqlite::Result<Canvas> {
    let title = canvas
        .title
        .trim()
        .chars()
        .take(TITLE_MAX)
        .collect::<String>();
    let tags = normalize_tags(&canvas.tags);
    let tags_json = serde_json::to_string(&tags)
        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
    let cwd = canvas
        .cwd
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let now = now_millis();

    let existing = get_canvas(conn, &canvas.id)?;
    let (created_at, updated_at) = if let Some(ref ex) = existing {
        let changed = title != ex.title || canvas.data_json != ex.data_json || tags != ex.tags;
        (ex.created_at, if changed { now } else { ex.updated_at })
    } else {
        (now, now)
    };

    conn.execute(
        "INSERT INTO canvases (id, title, data_json, tags_json, cwd, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           data_json = excluded.data_json,
           tags_json = excluded.tags_json,
           cwd = COALESCE(excluded.cwd, canvases.cwd),
           updated_at = excluded.updated_at",
        params![
            canvas.id,
            title,
            canvas.data_json,
            tags_json,
            cwd,
            created_at,
            updated_at
        ],
    )?;

    get_canvas(conn, &canvas.id)?.ok_or(rusqlite::Error::QueryReturnedNoRows)
}

fn read_canvas(row: &rusqlite::Row<'_>) -> rusqlite::Result<Canvas> {
    let tags_json: String = row.get(3)?;
    let tags: Vec<String> = serde_json::from_str(&tags_json).unwrap_or_default();
    Ok(Canvas {
        id: row.get(0)?,
        title: row.get(1)?,
        data_json: row.get(2)?,
        tags,
        cwd: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}
