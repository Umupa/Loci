//! Which mentors this install knows, and the half of each one that is not
//! portable: its conversation, its place on the rail and a few local flags.
//! Who the mentor is (name, look, workdir, defaults) is in its `mentor.json`.

use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{Map, Value};

use super::format;
use super::fsio::write_atomic;
use super::paths::MENTOR_FILE;

#[derive(Debug, Clone, PartialEq)]
pub struct MentorRecord {
    pub id: String,
    pub folder: PathBuf,
    pub session_id: Option<String>,
    pub position: i64,
    /// `accessMigrated`, `showStartedSessionsInSidebar`, `useSidebarFolders`.
    pub local: Map<String, Value>,
    /// Set once its 0.3 data is in its folder; until then it reads the old tables.
    pub migrated_at: Option<i64>,
    pub added_at: i64,
}

fn read(row: &rusqlite::Row<'_>) -> rusqlite::Result<MentorRecord> {
    let folder: String = row.get(1)?;
    let local: String = row.get(4)?;
    Ok(MentorRecord {
        id: row.get(0)?,
        folder: PathBuf::from(folder),
        session_id: row.get(2)?,
        position: row.get(3)?,
        local: match serde_json::from_str(&local) {
            Ok(Value::Object(map)) => map,
            _ => Map::new(),
        },
        migrated_at: row.get(5)?,
        added_at: row.get(6)?,
    })
}

const COLUMNS: &str = "id, folder, session_id, position, local_json, migrated_at, added_at";

pub fn get(conn: &Connection, id: &str) -> rusqlite::Result<Option<MentorRecord>> {
    conn.query_row(
        &format!("SELECT {COLUMNS} FROM mentors WHERE id = ?1"),
        [id],
        read,
    )
    .optional()
}

pub fn list(conn: &Connection) -> rusqlite::Result<Vec<MentorRecord>> {
    let mut statement = conn.prepare(&format!(
        "SELECT {COLUMNS} FROM mentors ORDER BY position, added_at, id"
    ))?;
    let rows = statement.query_map([], read)?;
    rows.collect()
}

pub fn upsert(conn: &Connection, record: &MentorRecord) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO mentors (id, folder, session_id, position, local_json, migrated_at, added_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(id) DO UPDATE SET folder = excluded.folder, session_id = excluded.session_id,
           position = excluded.position, local_json = excluded.local_json,
           migrated_at = excluded.migrated_at",
        params![
            record.id,
            record.folder.to_string_lossy(),
            record.session_id,
            record.position,
            Value::Object(record.local.clone()).to_string(),
            record.migrated_at,
            record.added_at
        ],
    )?;
    Ok(())
}

pub fn remove(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM mentors WHERE id = ?1", [id])?;
    Ok(())
}

/// The folder of a mentor whose content lives in files.
pub fn active_folder(conn: &Connection, id: &str) -> rusqlite::Result<Option<PathBuf>> {
    Ok(get(conn, id)?
        .filter(|record| record.migrated_at.is_some())
        .map(|record| record.folder))
}

/// Who the mentor is, from its folder.
pub fn read_identity(folder: &Path) -> Result<Map<String, Value>, String> {
    let path = folder.join(MENTOR_FILE);
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    format::parse_mentor(&text)
}

/// Writes `mentor.json` unless it already says exactly this, or was written
/// by a newer Loci. Returns whether it wrote.
pub fn write_identity(folder: &Path, identity: &Map<String, Value>) -> Result<bool, String> {
    let path = folder.join(MENTOR_FILE);
    if let Ok(current) = read_identity(folder) {
        if format::mentor_is_newer(&current) {
            return Ok(false);
        }
        if &current == identity {
            return Ok(false);
        }
    }
    write_atomic(&path, format::render_mentor(identity)?.as_bytes())?;
    Ok(true)
}

/// A workdir of the user's choosing, when the mentor has one; otherwise its
/// folder is its workdir.
pub fn custom_workdir(folder: &Path, identity: &Map<String, Value>) -> Option<PathBuf> {
    identity
        .get("workdir")
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .filter(|path| path.is_absolute() && path != folder)
}
