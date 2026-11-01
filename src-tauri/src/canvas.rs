use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::mentor_store::{self, format, index, paths::Kind, MentorCtx};
use crate::session_store::{validate_id, SessionStore};

const TITLE_MAX: usize = 200;
const DATA_MAX: usize = 50_000_000;
const TAG_MAX: usize = 48;
const TAGS_MAX: usize = 20;
const CHECKPOINT_ID_MAX: usize = 128;
const REVISION_CONFLICT: &str = "Canvas changed since it was read; retry the update.";

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
    /// Revision read before deriving a scene change; absent for legacy writes.
    #[serde(default)]
    pub expected_updated_at: Option<i64>,
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

// ---------------------------------------------------------------------------
// Canvases a mentor drew into its library (`loci-agent://<id>`) are files in
// its folder: canvases/<id>.excalidraw. Checkpoints stay in SQLite. Project
// canvases, and those of mentors not migrated yet, stay in the table.

const AGENT_SCOPE: &str = "loci-agent://";

fn canvas_from_row(row: index::Row) -> Canvas {
    Canvas {
        tags: row
            .meta
            .get("tags")
            .and_then(|v| v.as_array())
            .map(|tags| {
                tags.iter()
                    .filter_map(|t| t.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default(),
        cwd: Some(format!("{AGENT_SCOPE}{}", row.agent_id)),
        title: row.title,
        data_json: row.body.unwrap_or_else(|| "{}".into()),
        id: row.id,
        created_at: row.created_at,
        updated_at: row.updated_at,
    }
}

fn file_canvas(conn: &Connection, id: &str) -> Result<Option<(MentorCtx, Canvas)>, String> {
    let Some(row) = index::find(conn, Kind::Canvas, id).map_err(|e| e.to_string())? else {
        return Ok(None);
    };
    let Some(ctx) = mentor_store::ctx_for(conn, &row.agent_id)? else {
        return Ok(None);
    };
    Ok(mentor_store::current(conn, &ctx, Kind::Canvas, id)?.map(|row| (ctx, canvas_from_row(row))))
}

/// The mentor whose folder a canvas with this scope goes to, if it has one.
fn scope_ctx(conn: &Connection, cwd: Option<&str>) -> Result<Option<MentorCtx>, String> {
    match cwd.and_then(|cwd| cwd.trim().strip_prefix(AGENT_SCOPE)) {
        Some(agent) => mentor_store::ctx_for(conn, agent),
        None => Ok(None),
    }
}

fn file_save_canvas(
    conn: &Connection,
    ctx: &MentorCtx,
    existing: Option<Canvas>,
    canvas: &CanvasUpsert,
) -> Result<Canvas, String> {
    if let Some(expected) = canvas.expected_updated_at {
        if existing.as_ref().map(|c| c.updated_at) != Some(expected) {
            return Err(REVISION_CONFLICT.into());
        }
    }
    if let Some(checkpoint) = &canvas.checkpoint {
        let owner: Option<String> = conn
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
    let now = now_millis();
    let (created_at, updated_at) = match &existing {
        Some(ex) => (
            ex.created_at,
            now.max(
                ex.updated_at
                    .checked_add(1)
                    .ok_or("Canvas timestamp overflow")?,
            ),
        ),
        None => (now, now),
    };
    let meta = format::CanvasMeta {
        title: Some(canvas.title.trim().chars().take(TITLE_MAX).collect()),
        tags: normalize_tags(&canvas.tags),
        created_at: Some(created_at),
        updated_at: Some(updated_at),
    };
    let text = format::render_canvas(&meta, &canvas.data_json)?;
    let row = mentor_store::write_content(conn, ctx, Kind::Canvas, &canvas.id, &text)?;
    if let Some(checkpoint) = &canvas.checkpoint {
        bind_checkpoint(conn, &canvas.id, checkpoint).map_err(|e| e.to_string())?;
    }
    Ok(canvas_from_row(row))
}

fn legacy_visible(conn: &Connection, canvas: &Canvas) -> Result<bool, String> {
    let agent = canvas
        .cwd
        .as_deref()
        .and_then(|cwd| cwd.strip_prefix(AGENT_SCOPE));
    mentor_store::legacy_visible(conn, agent, canvas.updated_at)
}

#[tauri::command(async)]
pub fn canvas_list(store: State<'_, SessionStore>) -> Result<Vec<Canvas>, String> {
    let conn = store.lock_conn()?;
    let mut canvases = Vec::new();
    for canvas in list_canvases(&conn).map_err(|e| e.to_string())? {
        if legacy_visible(&conn, &canvas)? {
            canvases.push(canvas);
        }
    }
    for row in index::all(&conn, Kind::Canvas).map_err(|e| e.to_string())? {
        canvases.push(canvas_from_row(row));
    }
    canvases.sort_by(|a, b| b.updated_at.cmp(&a.updated_at).then(a.id.cmp(&b.id)));
    Ok(canvases)
}

#[tauri::command(async)]
pub fn canvas_get(store: State<'_, SessionStore>, id: String) -> Result<Option<Canvas>, String> {
    validate_id(&id, "canvas")?;
    let conn = store.lock_conn()?;
    if let Some((_, canvas)) = file_canvas(&conn, &id)? {
        return Ok(Some(canvas));
    }
    match get_canvas(&conn, &id).map_err(|e| e.to_string())? {
        Some(canvas) if legacy_visible(&conn, &canvas)? => Ok(Some(canvas)),
        _ => Ok(None),
    }
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
    if let Some((ctx, existing)) = file_canvas(&conn, &canvas.id)? {
        return file_save_canvas(&conn, &ctx, Some(existing), &canvas);
    }
    let legacy = get_canvas(&conn, &canvas.id).map_err(|e| e.to_string())?;
    let scope = legacy
        .as_ref()
        .and_then(|c| c.cwd.clone())
        .or_else(|| canvas.cwd.clone());
    if let Some(ctx) = scope_ctx(&conn, scope.as_deref())? {
        if canvas.expected_updated_at.is_some() && legacy.is_none() {
            return Err(REVISION_CONFLICT.into());
        }
        return file_save_canvas(&conn, &ctx, None, &canvas);
    }
    save_canvas(&conn, &canvas)
}

#[tauri::command(async)]
pub fn canvas_delete(store: State<'_, SessionStore>, id: String) -> Result<(), String> {
    validate_id(&id, "canvas")?;
    let conn = store.lock_conn()?;
    if let Some((ctx, _)) = file_canvas(&conn, &id)? {
        mentor_store::remove_content(&conn, &ctx, Kind::Canvas, &id)?;
        conn.execute(
            "DELETE FROM canvas_checkpoints WHERE canvas_id = ?1",
            params![id],
        )
        .map_err(|e| e.to_string())?;
        return Ok(());
    }
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
    if let Some(expected) = canvas.expected_updated_at {
        let current: Option<i64> = tx
            .query_row(
                "SELECT updated_at FROM canvases WHERE id = ?1",
                params![canvas.id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        // Missing means the drawing was deleted after the caller read it.
        // A guarded update must never silently recreate it.
        if current != Some(expected) {
            return Err(REVISION_CONFLICT.into());
        }
    }
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
    let legacy: Option<String> = conn
        .query_row(
            "SELECT id FROM canvases WHERE id = ?1",
            params![checkpoint_id],
            |row| row.get(0),
        )
        .optional()?;
    if legacy.is_some() {
        return Ok(legacy);
    }
    Ok(index::find(conn, Kind::Canvas, checkpoint_id)?.map(|row| row.id))
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
        // Timestamps also identify revisions. Two writes in one millisecond
        // (or a backwards clock adjustment) must still invalidate stale reads.
        let next = ex
            .updated_at
            .checked_add(1)
            .ok_or(rusqlite::Error::InvalidQuery)?;
        (ex.created_at, now.max(next))
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
            expected_updated_at: None,
            checkpoint: checkpoint.map(|(id, baseline)| CheckpointBind {
                id: id.into(),
                baseline_json: baseline.into(),
            }),
        }
    }

    #[test]
    fn concurrent_snapshot_updates_cannot_overwrite_each_other() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let original = save_canvas(&conn, &upsert("drawing", &scene("base"), None)).unwrap();
        let mut first = upsert("drawing", &scene("first"), Some(("first-cp", "{}")));
        first.expected_updated_at = Some(original.updated_at);
        let mut stale = upsert("drawing", &scene("stale"), Some(("stale-cp", "{}")));
        stale.expected_updated_at = Some(original.updated_at);

        let saved = save_canvas(&conn, &first).unwrap();
        assert_eq!(
            save_canvas(&conn, &stale).unwrap_err(),
            "Canvas changed since it was read; retry the update."
        );
        assert_eq!(
            get_canvas(&conn, "drawing").unwrap().unwrap().data_json,
            saved.data_json
        );
        assert_eq!(checkpoint_canvas(&conn, "stale-cp").unwrap(), None);
        assert_eq!(
            latest_checkpoint(&conn, "drawing")
                .unwrap()
                .unwrap()
                .checkpoint_id,
            "first-cp"
        );

        stale.expected_updated_at = Some(saved.updated_at);
        assert_eq!(
            save_canvas(&conn, &stale).unwrap().data_json,
            scene("stale")
        );
    }

    #[test]
    fn guarded_updates_do_not_recreate_deleted_drawings() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let original = save_canvas(&conn, &upsert("drawing", &scene("base"), None)).unwrap();
        let mut stale = upsert("drawing", &scene("stale"), Some(("stale-cp", "{}")));
        stale.expected_updated_at = Some(original.updated_at);
        delete_canvas(&conn, "drawing").unwrap();

        assert_eq!(
            save_canvas(&conn, &stale).unwrap_err(),
            "Canvas changed since it was read; retry the update."
        );
        assert!(get_canvas(&conn, "drawing").unwrap().is_none());
        assert_eq!(checkpoint_canvas(&conn, "stale-cp").unwrap(), None);
    }

    #[test]
    fn revisions_advance_even_when_the_clock_has_not_advanced() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        save_canvas(&conn, &upsert("drawing", &scene("base"), None)).unwrap();
        // Make this deterministic without racing the wall clock or sleeping.
        let previous = now_millis() + 60_000;
        conn.execute(
            "UPDATE canvases SET updated_at = ?1 WHERE id = 'drawing'",
            [previous],
        )
        .unwrap();
        let mut update = upsert("drawing", &scene("changed"), None);
        update.expected_updated_at = Some(previous);
        let first = save_canvas(&conn, &update).unwrap();
        assert_eq!(first.updated_at, previous + 1);
        update.expected_updated_at = Some(first.updated_at);
        let second = save_canvas(&conn, &update).unwrap();
        assert_eq!(second.updated_at, first.updated_at + 1);
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

    #[test]
    fn a_mentors_canvases_are_excalidraw_files_with_guarded_revisions() {
        use crate::mentor_store::testing::{register, temp_dir};
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp_dir("canvases");
        register(&conn, "agent", &folder);
        let ctx = scope_ctx(&conn, Some("loci-agent://agent"))
            .unwrap()
            .unwrap();
        assert!(scope_ctx(&conn, Some("/repo")).unwrap().is_none());
        let upsert = |data: &str, expected: Option<i64>, checkpoint: Option<&str>| CanvasUpsert {
            id: "k1".into(),
            title: "Overview".into(),
            data_json: data.into(),
            tags: vec!["KVM".into()],
            cwd: Some("loci-agent://agent".into()),
            expected_updated_at: expected,
            checkpoint: checkpoint.map(|id| CheckpointBind {
                id: id.into(),
                baseline_json: "{}".into(),
            }),
        };
        let first = file_save_canvas(
            &conn,
            &ctx,
            None,
            &upsert(
                r#"{"elements":[],"appState":{},"files":{}}"#,
                None,
                Some("cp1"),
            ),
        )
        .unwrap();
        assert_eq!(first.cwd.as_deref(), Some("loci-agent://agent"));
        let file: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(folder.join("canvases/k1.excalidraw")).unwrap(),
        )
        .unwrap();
        assert_eq!(file["type"], "excalidraw");
        assert_eq!(file["loci"]["title"], "Overview");
        assert_eq!(
            checkpoint_canvas(&conn, "cp1").unwrap().as_deref(),
            Some("k1")
        );
        assert_eq!(
            checkpoint_canvas(&conn, "k1").unwrap().as_deref(),
            Some("k1")
        );

        let (_, read) = file_canvas(&conn, "k1").unwrap().unwrap();
        assert_eq!(read.updated_at, first.updated_at);
        let second = file_save_canvas(
            &conn,
            &ctx,
            Some(read.clone()),
            &upsert(r#"{"elements":[{"id":"a"}]}"#, Some(read.updated_at), None),
        )
        .unwrap();
        assert!(second.updated_at > first.updated_at);
        // A stale revision is refused.
        let (_, now) = file_canvas(&conn, "k1").unwrap().unwrap();
        assert_eq!(
            file_save_canvas(
                &conn,
                &ctx,
                Some(now),
                &upsert("{}", Some(first.updated_at), None)
            )
            .unwrap_err(),
            REVISION_CONFLICT
        );
        std::fs::remove_dir_all(folder).unwrap();
    }
}
