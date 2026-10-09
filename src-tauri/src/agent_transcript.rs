//! An agent's conversation never ends, so its older turns are moved out of
//! the session's own transcript into pages here. The session keeps a recent
//! window that stays cheap to save and render; a page is read back only when
//! the user scrolls up or the agent reads its own history.
//!
//! A page holds whole turns, oldest page first. It is keyed by the id of its
//! first block, so archiving the same turns twice after a crash between the
//! two writes keeps one copy. Pages go with their session when it is deleted.

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use tauri::State;

use crate::session_store::{now_millis, validate_id, SessionStore};

/// Larger than any page the app writes; this only stops a runaway write.
const PAGE_MAX_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptPage {
    /// Position among the session's pages; pass it as `before` for the one older.
    seq: i64,
    /// The page's blocks, as the JSON array the app archived.
    blocks_json: String,
    /// Whether an older page exists.
    has_older: bool,
}

pub(crate) fn ensure_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS agent_transcript_pages (
           session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
           seq INTEGER NOT NULL,
           first_block_id TEXT NOT NULL,
           blocks_json TEXT NOT NULL,
           archived_at INTEGER NOT NULL,
           PRIMARY KEY (session_id, seq),
           UNIQUE (session_id, first_block_id)
         );",
    )
}

/// Adds the page after the session's newest one. Archiving turns that start
/// where an existing page does replaces that page when it holds at least as
/// much: a first attempt whose session was never trimmed is superseded by the
/// longer one that follows, and a plain repeat changes nothing.
fn append(
    conn: &mut Connection,
    session_id: &str,
    first_block_id: &str,
    blocks_json: &str,
    now: i64,
) -> rusqlite::Result<i64> {
    let tx = conn.transaction()?;
    let existing: Option<(i64, i64)> = tx
        .query_row(
            "SELECT seq, length(blocks_json) FROM agent_transcript_pages
             WHERE session_id = ?1 AND first_block_id = ?2",
            params![session_id, first_block_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;
    if let Some((seq, length)) = existing {
        if blocks_json.chars().count() as i64 > length {
            tx.execute(
                "UPDATE agent_transcript_pages SET blocks_json = ?3, archived_at = ?4
                 WHERE session_id = ?1 AND seq = ?2",
                params![session_id, seq, blocks_json, now],
            )?;
            tx.commit()?;
        }
        return Ok(seq);
    }
    let seq: i64 = tx.query_row(
        "SELECT COALESCE(MAX(seq), 0) + 1 FROM agent_transcript_pages WHERE session_id = ?1",
        [session_id],
        |row| row.get(0),
    )?;
    tx.execute(
        "INSERT INTO agent_transcript_pages
         (session_id, seq, first_block_id, blocks_json, archived_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![session_id, seq, first_block_id, blocks_json, now],
    )?;
    tx.commit()?;
    Ok(seq)
}

/// The newest page older than `before`, or the newest of all.
fn page(
    conn: &Connection,
    session_id: &str,
    before: Option<i64>,
) -> rusqlite::Result<Option<TranscriptPage>> {
    conn.query_row(
        "SELECT seq, blocks_json,
                EXISTS (SELECT 1 FROM agent_transcript_pages older
                        WHERE older.session_id = page.session_id AND older.seq < page.seq)
         FROM agent_transcript_pages page
         WHERE session_id = ?1 AND (?2 IS NULL OR seq < ?2)
         ORDER BY seq DESC LIMIT 1",
        params![session_id, before],
        |row| {
            Ok(TranscriptPage {
                seq: row.get(0)?,
                blocks_json: row.get(1)?,
                has_older: row.get(2)?,
            })
        },
    )
    .optional()
}

fn clear(conn: &Connection, session_id: &str) -> rusqlite::Result<()> {
    conn.execute(
        "DELETE FROM agent_transcript_pages WHERE session_id = ?1",
        [session_id],
    )?;
    Ok(())
}

#[tauri::command(async)]
pub fn agent_transcript_append(
    store: State<'_, SessionStore>,
    session_id: String,
    first_block_id: String,
    blocks_json: String,
) -> Result<i64, String> {
    validate_id(&session_id, "session")?;
    if first_block_id.is_empty() || first_block_id.len() > 512 {
        return Err("Not a block id".into());
    }
    if blocks_json.len() > PAGE_MAX_BYTES {
        return Err("The page is too large".into());
    }
    let parsed: serde_json::Value =
        serde_json::from_str(&blocks_json).map_err(|e| e.to_string())?;
    if !parsed.as_array().is_some_and(|blocks| !blocks.is_empty()) {
        return Err("A page is a non-empty array of blocks".into());
    }
    let mut conn = store.lock_conn()?;
    append(
        &mut conn,
        &session_id,
        &first_block_id,
        &blocks_json,
        now_millis(),
    )
    .map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn agent_transcript_page(
    store: State<'_, SessionStore>,
    session_id: String,
    before: Option<i64>,
) -> Result<Option<TranscriptPage>, String> {
    validate_id(&session_id, "session")?;
    let conn = store.lock_conn()?;
    page(&conn, &session_id, before).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn agent_transcript_clear(
    store: State<'_, SessionStore>,
    session_id: String,
) -> Result<(), String> {
    validate_id(&session_id, "session")?;
    let conn = store.lock_conn()?;
    clear(&conn, &session_id).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seed(conn: &Connection, id: &str) {
        conn.execute(
            "INSERT INTO sessions (id, cwd, harness, model, runtime_mode, title,
             created_at, updated_at, has_user_message) VALUES (?1, '/home/me', 'codex', '',
             'auto', 'An agent', 1, 1, 1)",
            [id],
        )
        .unwrap();
    }

    #[test]
    fn pages_read_back_newest_first_and_say_when_there_is_more() {
        let store = SessionStore::open_in_memory().unwrap();
        let mut conn = store.lock_conn().unwrap();
        seed(&conn, "chat");
        assert_eq!(page(&conn, "chat", None).unwrap(), None);
        assert_eq!(append(&mut conn, "chat", "u1", "[1]", 10).unwrap(), 1);
        assert_eq!(append(&mut conn, "chat", "u9", "[2]", 20).unwrap(), 2);
        let newest = page(&conn, "chat", None).unwrap().unwrap();
        assert_eq!(
            (newest.seq, newest.blocks_json.as_str(), newest.has_older),
            (2, "[2]", true)
        );
        let older = page(&conn, "chat", Some(newest.seq)).unwrap().unwrap();
        assert_eq!(
            (older.seq, older.blocks_json.as_str(), older.has_older),
            (1, "[1]", false)
        );
        assert_eq!(page(&conn, "chat", Some(1)).unwrap(), None);
    }

    #[test]
    fn archiving_from_the_same_turn_again_keeps_one_page_with_the_longer_content() {
        let store = SessionStore::open_in_memory().unwrap();
        let mut conn = store.lock_conn().unwrap();
        seed(&conn, "chat");
        assert_eq!(append(&mut conn, "chat", "u1", "[1, 2]", 10).unwrap(), 1);
        // A plain repeat, or a shorter attempt, changes nothing.
        assert_eq!(append(&mut conn, "chat", "u1", "[1, 2]", 20).unwrap(), 1);
        assert_eq!(append(&mut conn, "chat", "u1", "[1]", 20).unwrap(), 1);
        assert_eq!(
            page(&conn, "chat", None).unwrap().unwrap().blocks_json,
            "[1, 2]"
        );
        // The session was never trimmed, so the next attempt reaches further.
        assert_eq!(append(&mut conn, "chat", "u1", "[1, 2, 3]", 30).unwrap(), 1);
        let only = page(&conn, "chat", None).unwrap().unwrap();
        assert_eq!(
            (only.blocks_json.as_str(), only.has_older),
            ("[1, 2, 3]", false)
        );
    }

    #[test]
    fn pages_belong_to_their_session_and_go_with_it() {
        let store = SessionStore::open_in_memory().unwrap();
        let mut conn = store.lock_conn().unwrap();
        seed(&conn, "chat");
        seed(&conn, "other");
        append(&mut conn, "chat", "u1", "[1]", 10).unwrap();
        append(&mut conn, "other", "u1", "[7]", 10).unwrap();
        assert_eq!(
            page(&conn, "other", None).unwrap().unwrap().blocks_json,
            "[7]"
        );
        clear(&conn, "other").unwrap();
        assert_eq!(page(&conn, "other", None).unwrap(), None);
        conn.execute("DELETE FROM sessions WHERE id = 'chat'", [])
            .unwrap();
        assert_eq!(page(&conn, "chat", None).unwrap(), None);
    }
}
