use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::session_store::{validate_id, SessionStore};

const TITLE_MAX: usize = 200;
const DATA_MAX: usize = 50_000_000;
const TAG_MAX: usize = 48;
const TAGS_MAX: usize = 20;
const CHECKPOINT_ID_MAX: usize = 128;

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
    /// Set when an agent drew this scene through the Excalidraw MCP.
    #[serde(default)]
    pub checkpoint: Option<CheckpointBind>,
}

/// An Excalidraw MCP checkpoint id, saved together with the scene it produced.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckpointBind {
    pub id: String,
    /// What the agent left on the canvas, for reporting the user's later edits.
    #[serde(default)]
    pub baseline_json: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CanvasCheckpoint {
    pub checkpoint_id: String,
    pub canvas_id: String,
    pub baseline_json: String,
    pub created_at: i64,
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
           ON canvases (updated_at DESC, id);
         -- The official Excalidraw MCP issues a new checkpoint id per drawing
         -- call. Each id names the canvas it drew on, so an agent can resume
         -- from that canvas's current content after edits or a restart.
         CREATE TABLE IF NOT EXISTS canvas_checkpoints (
           checkpoint_id TEXT PRIMARY KEY,
           canvas_id TEXT NOT NULL,
           baseline_json TEXT NOT NULL DEFAULT '',
           created_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS canvas_checkpoints_canvas_idx
           ON canvas_checkpoints (canvas_id, created_at DESC);",
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
    if let Some(checkpoint) = &canvas.checkpoint {
        validate_id(&checkpoint.id, "checkpoint")?;
        if checkpoint.id.len() > CHECKPOINT_ID_MAX || checkpoint.baseline_json.len() > DATA_MAX {
            return Err("Canvas checkpoint is too large".into());
        }
    }
    let conn = store.lock_conn()?;
    save_canvas(&conn, &canvas)
}

#[tauri::command(async)]
pub fn canvas_delete(store: State<'_, SessionStore>, id: String) -> Result<(), String> {
    validate_id(&id, "canvas")?;
    let conn = store.lock_conn()?;
    delete_canvas(&conn, &id).map_err(|e| e.to_string())
}

/// The canvas a checkpoint id refers to. A canvas id is its own checkpoint, so
/// drawings the user made by hand can be continued by an agent too.
#[tauri::command(async)]
pub fn canvas_checkpoint_canvas(
    store: State<'_, SessionStore>,
    checkpoint_id: String,
) -> Result<Option<String>, String> {
    if validate_id(&checkpoint_id, "checkpoint").is_err() {
        return Ok(None);
    }
    let conn = store.lock_conn()?;
    checkpoint_canvas(&conn, &checkpoint_id).map_err(|e| e.to_string())
}

/// The newest checkpoint an agent saved for this canvas.
#[tauri::command(async)]
pub fn canvas_checkpoint_latest(
    store: State<'_, SessionStore>,
    canvas_id: String,
) -> Result<Option<CanvasCheckpoint>, String> {
    validate_id(&canvas_id, "canvas")?;
    let conn = store.lock_conn()?;
    latest_checkpoint(&conn, &canvas_id).map_err(|e| e.to_string())
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

/// Saves the scene and its checkpoint together: an agent must never be told a
/// checkpoint id that the next call cannot find.
fn save_canvas(conn: &Connection, canvas: &CanvasUpsert) -> Result<Canvas, String> {
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    if let Some(checkpoint) = &canvas.checkpoint {
        let owner: Option<String> = tx
            .query_row(
                "SELECT canvas_id FROM canvas_checkpoints WHERE checkpoint_id = ?1",
                params![checkpoint.id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if owner.is_some_and(|owner| owner != canvas.id) {
            return Err("Checkpoint already belongs to another drawing".into());
        }
    }
    let saved = upsert_canvas(&tx, canvas).map_err(|e| e.to_string())?;
    if let Some(checkpoint) = &canvas.checkpoint {
        bind_checkpoint(&tx, &canvas.id, checkpoint).map_err(|e| e.to_string())?;
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(saved)
}

fn bind_checkpoint(
    conn: &Connection,
    canvas_id: &str,
    checkpoint: &CheckpointBind,
) -> rusqlite::Result<()> {
    // Only the newest baseline is compared against; older ones are dead weight.
    conn.execute(
        "UPDATE canvas_checkpoints SET baseline_json = ''
         WHERE canvas_id = ?1 AND checkpoint_id <> ?2",
        params![canvas_id, checkpoint.id],
    )?;
    conn.execute(
        "INSERT INTO canvas_checkpoints (checkpoint_id, canvas_id, baseline_json, created_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(checkpoint_id) DO UPDATE SET
           baseline_json = excluded.baseline_json,
           created_at = excluded.created_at",
        params![
            checkpoint.id,
            canvas_id,
            checkpoint.baseline_json,
            now_millis()
        ],
    )?;
    Ok(())
}

fn checkpoint_canvas(conn: &Connection, checkpoint_id: &str) -> rusqlite::Result<Option<String>> {
    let bound: Option<String> = conn
        .query_row(
            "SELECT canvas_id FROM canvas_checkpoints WHERE checkpoint_id = ?1",
            params![checkpoint_id],
            |row| row.get(0),
        )
        .optional()?;
    if bound.is_some() {
        return Ok(bound);
    }
    conn.query_row(
        "SELECT id FROM canvases WHERE id = ?1",
        params![checkpoint_id],
        |row| row.get(0),
    )
    .optional()
}

fn latest_checkpoint(
    conn: &Connection,
    canvas_id: &str,
) -> rusqlite::Result<Option<CanvasCheckpoint>> {
    conn.query_row(
        "SELECT checkpoint_id, canvas_id, baseline_json, created_at
         FROM canvas_checkpoints WHERE canvas_id = ?1
         ORDER BY created_at DESC, rowid DESC LIMIT 1",
        params![canvas_id],
        |row| {
            Ok(CanvasCheckpoint {
                checkpoint_id: row.get(0)?,
                canvas_id: row.get(1)?,
                baseline_json: row.get(2)?,
                created_at: row.get(3)?,
            })
        },
    )
    .optional()
}

fn delete_canvas(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    let tx = conn.unchecked_transaction()?;
    tx.execute(
        "DELETE FROM canvas_checkpoints WHERE canvas_id = ?1",
        params![id],
    )?;
    tx.execute("DELETE FROM canvases WHERE id = ?1", params![id])?;
    tx.commit()
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

#[cfg(test)]
mod tests {
    use super::*;

    fn scene(marker: &str) -> String {
        format!(r#"{{"elements":[{{"id":"{marker}"}}],"appState":{{}},"files":{{}}}}"#)
    }

    fn upsert(id: &str, data_json: &str, checkpoint: Option<(&str, &str)>) -> CanvasUpsert {
        CanvasUpsert {
            id: id.into(),
            title: "Drawing".into(),
            data_json: data_json.into(),
            tags: Vec::new(),
            cwd: Some("/project".into()),
            checkpoint: checkpoint.map(|(id, baseline)| CheckpointBind {
                id: id.into(),
                baseline_json: baseline.into(),
            }),
        }
    }

    #[test]
    fn every_checkpoint_of_a_canvas_resolves_to_it_and_survives_a_restart() {
        let dir = std::env::temp_dir().join(format!("loci-canvas-{}", uuid::Uuid::new_v4()));
        let path = dir.join("loci.db");
        {
            let store = SessionStore::open(path.clone()).unwrap();
            let conn = store.lock_conn().unwrap();
            save_canvas(
                &conn,
                &upsert("drawing", &scene("first"), Some(("cp1", "{}"))),
            )
            .unwrap();
            save_canvas(
                &conn,
                &upsert("drawing", &scene("second"), Some(("cp2", "{\"a\":1}"))),
            )
            .unwrap();
            // A manual save in between does not touch the bindings.
            save_canvas(&conn, &upsert("drawing", &scene("manual"), None)).unwrap();
        }
        // A new process sees the same canvas behind both ids.
        let store = SessionStore::open(path).unwrap();
        let conn = store.lock_conn().unwrap();
        for id in ["cp1", "cp2", "drawing"] {
            assert_eq!(
                checkpoint_canvas(&conn, id).unwrap().as_deref(),
                Some("drawing")
            );
        }
        assert_eq!(checkpoint_canvas(&conn, "unknown").unwrap(), None);
        assert_eq!(
            get_canvas(&conn, "drawing").unwrap().unwrap().data_json,
            scene("manual")
        );
        let latest = latest_checkpoint(&conn, "drawing").unwrap().unwrap();
        assert_eq!(latest.checkpoint_id, "cp2");
        assert_eq!(latest.baseline_json, "{\"a\":1}");
        // Superseded baselines are dropped; their ids keep resolving.
        let old: String = conn
            .query_row(
                "SELECT baseline_json FROM canvas_checkpoints WHERE checkpoint_id = 'cp1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(old, "");
        drop(conn);
        drop(store);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_checkpoint_cannot_move_to_another_canvas_and_the_scene_is_not_saved() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        save_canvas(&conn, &upsert("first", &scene("a"), Some(("cp", "")))).unwrap();
        save_canvas(&conn, &upsert("second", &scene("b"), None)).unwrap();
        let error =
            save_canvas(&conn, &upsert("second", &scene("stolen"), Some(("cp", "")))).unwrap_err();
        assert!(error.contains("another drawing"));
        assert_eq!(
            get_canvas(&conn, "second").unwrap().unwrap().data_json,
            scene("b")
        );
        assert_eq!(
            checkpoint_canvas(&conn, "cp").unwrap().as_deref(),
            Some("first")
        );
        // Re-saving the same checkpoint on its own canvas is an update.
        save_canvas(&conn, &upsert("first", &scene("again"), Some(("cp", "{}")))).unwrap();
        assert_eq!(
            get_canvas(&conn, "first").unwrap().unwrap().data_json,
            scene("again")
        );
    }

    #[test]
    fn deleting_a_canvas_forgets_its_checkpoints() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        save_canvas(&conn, &upsert("drawing", &scene("a"), Some(("cp", "")))).unwrap();
        save_canvas(&conn, &upsert("other", &scene("b"), Some(("kept", "")))).unwrap();
        delete_canvas(&conn, "drawing").unwrap();
        assert_eq!(checkpoint_canvas(&conn, "cp").unwrap(), None);
        assert_eq!(checkpoint_canvas(&conn, "drawing").unwrap(), None);
        assert_eq!(latest_checkpoint(&conn, "drawing").unwrap(), None);
        assert_eq!(
            checkpoint_canvas(&conn, "kept").unwrap().as_deref(),
            Some("other")
        );
    }
}
