//! Per-item reading state for community feeds. Lists are fetched live from
//! each provider; only what the reader did (seen reply count, stars) lives
//! here, keyed by provider and the provider's own item id.

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tauri::State;

use crate::session_store::{now_millis, SessionStore};

const PROVIDERS: [&str; 1] = ["v2ex"];
const ITEM_ID_MAX: usize = 128;
const SNAPSHOT_MAX: usize = 256 * 1024;
const MARK_MANY_MAX: usize = 500;
const SEEN_RETENTION_MS: i64 = 90 * 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FeedItemState {
    pub item_id: String,
    pub seen_count: Option<i64>,
    pub seen_at: Option<i64>,
    pub starred: bool,
    pub starred_at: Option<i64>,
    pub snapshot: Option<Value>,
}

pub fn ensure_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS feed_item_state (
           provider TEXT NOT NULL,
           item_id TEXT NOT NULL,
           seen_count INTEGER,
           seen_at INTEGER,
           starred INTEGER NOT NULL DEFAULT 0,
           starred_at INTEGER,
           snapshot_json TEXT,
           PRIMARY KEY (provider, item_id)
         );",
    )?;
    // Seen marks only matter while an item can still show up in a list.
    conn.execute(
        "DELETE FROM feed_item_state WHERE starred = 0 AND COALESCE(seen_at, 0) < ?1",
        [now_millis() - SEEN_RETENTION_MS],
    )?;
    Ok(())
}

fn validate(provider: &str, item_id: &str) -> Result<(), String> {
    if !PROVIDERS.contains(&provider) {
        return Err(format!("Unknown feed provider: {provider}"));
    }
    if item_id.is_empty() || item_id.len() > ITEM_ID_MAX {
        return Err("Invalid feed item id".into());
    }
    Ok(())
}

pub(crate) fn list_state(
    conn: &Connection,
    provider: &str,
) -> rusqlite::Result<Vec<FeedItemState>> {
    let mut stmt = conn.prepare(
        "SELECT item_id, seen_count, seen_at, starred, starred_at, snapshot_json
           FROM feed_item_state WHERE provider = ?1
          ORDER BY COALESCE(starred_at, seen_at) DESC",
    )?;
    let rows = stmt.query_map([provider], |row| {
        let snapshot: Option<String> = row.get(5)?;
        Ok(FeedItemState {
            item_id: row.get(0)?,
            seen_count: row.get(1)?,
            seen_at: row.get(2)?,
            starred: row.get::<_, i64>(3)? != 0,
            starred_at: row.get(4)?,
            snapshot: snapshot.and_then(|raw| serde_json::from_str(&raw).ok()),
        })
    })?;
    rows.collect()
}

pub(crate) fn mark_seen(
    conn: &Connection,
    provider: &str,
    item_id: &str,
    seen_count: i64,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO feed_item_state (provider, item_id, seen_count, seen_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (provider, item_id) DO UPDATE SET
           seen_count = MAX(COALESCE(seen_count, 0), excluded.seen_count),
           seen_at = excluded.seen_at",
        params![provider, item_id, seen_count, now_millis()],
    )?;
    Ok(())
}

pub(crate) fn set_starred(
    conn: &Connection,
    provider: &str,
    item_id: &str,
    starred: bool,
    snapshot: Option<&str>,
) -> rusqlite::Result<()> {
    if starred {
        conn.execute(
            "INSERT INTO feed_item_state (provider, item_id, starred, starred_at, snapshot_json)
             VALUES (?1, ?2, 1, ?3, ?4)
             ON CONFLICT (provider, item_id) DO UPDATE SET
               starred = 1, starred_at = excluded.starred_at,
               snapshot_json = COALESCE(excluded.snapshot_json, snapshot_json)",
            params![provider, item_id, now_millis(), snapshot],
        )?;
    } else {
        conn.execute(
            "UPDATE feed_item_state SET starred = 0, starred_at = NULL, snapshot_json = NULL
              WHERE provider = ?1 AND item_id = ?2",
            params![provider, item_id],
        )?;
    }
    Ok(())
}

#[tauri::command(async)]
pub fn feeds_state_list(
    store: State<'_, SessionStore>,
    provider: String,
) -> Result<Vec<FeedItemState>, String> {
    validate(&provider, "-")?;
    let conn = store.lock_conn()?;
    list_state(&conn, &provider).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn feeds_mark_seen(
    store: State<'_, SessionStore>,
    provider: String,
    item_id: String,
    seen_count: i64,
) -> Result<(), String> {
    validate(&provider, &item_id)?;
    let conn = store.lock_conn()?;
    mark_seen(&conn, &provider, &item_id, seen_count.max(0)).map_err(|e| e.to_string())
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeenMark {
    pub item_id: String,
    pub seen_count: i64,
}

/// "Mark all as read": one transaction for the whole visible list.
#[tauri::command(async)]
pub fn feeds_mark_seen_many(
    store: State<'_, SessionStore>,
    provider: String,
    items: Vec<SeenMark>,
) -> Result<(), String> {
    if items.len() > MARK_MANY_MAX {
        return Err("Too many feed items at once".into());
    }
    for item in &items {
        validate(&provider, &item.item_id)?;
    }
    let mut conn = store.lock_conn()?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    for item in &items {
        mark_seen(&tx, &provider, &item.item_id, item.seen_count.max(0))
            .map_err(|e| e.to_string())?;
    }
    tx.commit().map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn feeds_set_starred(
    store: State<'_, SessionStore>,
    provider: String,
    item_id: String,
    starred: bool,
    snapshot: Option<Value>,
) -> Result<(), String> {
    validate(&provider, &item_id)?;
    let snapshot = snapshot
        .map(|value| serde_json::to_string(&value).map_err(|e| e.to_string()))
        .transpose()?;
    if snapshot
        .as_ref()
        .is_some_and(|raw| raw.len() > SNAPSHOT_MAX)
    {
        return Err("Feed item snapshot is too large".into());
    }
    let conn = store.lock_conn()?;
    set_starred(&conn, &provider, &item_id, starred, snapshot.as_deref()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conn() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        ensure_table(&conn).unwrap();
        conn
    }

    #[test]
    fn seen_count_never_moves_backwards() {
        let conn = conn();
        mark_seen(&conn, "v2ex", "1", 12).unwrap();
        mark_seen(&conn, "v2ex", "1", 4).unwrap();
        let state = list_state(&conn, "v2ex").unwrap();
        assert_eq!(state.len(), 1);
        assert_eq!(state[0].seen_count, Some(12));
        assert!(!state[0].starred);
    }

    #[test]
    fn starring_keeps_seen_state_and_unstarring_drops_snapshot() {
        let conn = conn();
        mark_seen(&conn, "v2ex", "1", 3).unwrap();
        set_starred(&conn, "v2ex", "1", true, Some(r#"{"title":"t"}"#)).unwrap();
        let state = &list_state(&conn, "v2ex").unwrap()[0];
        assert!(state.starred);
        assert_eq!(state.seen_count, Some(3));
        assert_eq!(state.snapshot.as_ref().unwrap()["title"], "t");

        set_starred(&conn, "v2ex", "1", false, None).unwrap();
        let state = &list_state(&conn, "v2ex").unwrap()[0];
        assert!(!state.starred);
        assert!(state.snapshot.is_none());
        assert_eq!(state.seen_count, Some(3));
    }

    #[test]
    fn providers_are_isolated() {
        let conn = conn();
        mark_seen(&conn, "v2ex", "1", 1).unwrap();
        assert!(list_state(&conn, "legacy").unwrap().is_empty());
        assert!(validate("x", "1").is_err());
        assert!(validate("hn", "1").is_err());
        assert!(validate("v2ex", "").is_err());
    }
}
