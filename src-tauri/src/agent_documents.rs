//! Documents an agent wrote for the user to read: explanations, readings,
//! summaries. Each belongs to one agent and is named by an id the agent
//! chose, so writing the same id again revises it. Only the latest text is
//! kept. They are the agent's library, apart from the user's own notes.

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::session_store::{now_millis, SessionStore};

const BODY_MAX: usize = 1024 * 1024;

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentDocument {
    id: String,
    title: String,
    subject: Option<String>,
    /// Left out of listings, which only name the documents.
    #[serde(skip_serializing_if = "Option::is_none")]
    body: Option<String>,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentDocumentUpsert {
    id: String,
    title: String,
    subject: Option<String>,
    body: String,
}

pub(crate) fn ensure_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS agent_documents (
           agent_id TEXT NOT NULL,
           id TEXT NOT NULL,
           title TEXT NOT NULL,
           subject TEXT,
           body TEXT NOT NULL,
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL,
           PRIMARY KEY (agent_id, id)
         );",
    )
}

/// Agent ids are UUIDs; document ids are slugs the app made from a title.
fn valid_key(value: &str, max: usize) -> bool {
    !value.is_empty()
        && value.chars().count() <= max
        && !value.starts_with('.')
        && value
            .chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '_')
}

fn list(conn: &Connection, agent: &str) -> rusqlite::Result<Vec<AgentDocument>> {
    let mut statement = conn.prepare(
        "SELECT id, title, subject, created_at, updated_at FROM agent_documents
         WHERE agent_id = ?1 ORDER BY updated_at DESC, id",
    )?;
    let rows = statement.query_map([agent], |row| {
        Ok(AgentDocument {
            id: row.get(0)?,
            title: row.get(1)?,
            subject: row.get(2)?,
            body: None,
            created_at: row.get(3)?,
            updated_at: row.get(4)?,
        })
    })?;
    rows.collect()
}

fn get(conn: &Connection, agent: &str, id: &str) -> rusqlite::Result<Option<AgentDocument>> {
    conn.query_row(
        "SELECT id, title, subject, body, created_at, updated_at FROM agent_documents
         WHERE agent_id = ?1 AND id = ?2",
        params![agent, id],
        |row| {
            Ok(AgentDocument {
                id: row.get(0)?,
                title: row.get(1)?,
                subject: row.get(2)?,
                body: Some(row.get(3)?),
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
            })
        },
    )
    .optional()
}

/// Writes the document, keeping when it was first made. Unchanged text leaves
/// its date alone, so re-reading a chat does not reorder the library.
fn upsert(
    conn: &Connection,
    agent: &str,
    document: &AgentDocumentUpsert,
    now: i64,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO agent_documents (agent_id, id, title, subject, body, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
         ON CONFLICT(agent_id, id) DO UPDATE SET
           title = excluded.title, subject = excluded.subject, body = excluded.body,
           updated_at = excluded.updated_at
         WHERE title IS NOT excluded.title OR subject IS NOT excluded.subject
            OR body IS NOT excluded.body",
        params![
            agent,
            document.id,
            document.title,
            document.subject,
            document.body,
            now
        ],
    )?;
    Ok(())
}

fn delete(conn: &Connection, agent: &str, id: Option<&str>) -> rusqlite::Result<()> {
    match id {
        Some(id) => conn.execute(
            "DELETE FROM agent_documents WHERE agent_id = ?1 AND id = ?2",
            params![agent, id],
        )?,
        None => conn.execute("DELETE FROM agent_documents WHERE agent_id = ?1", [agent])?,
    };
    Ok(())
}

fn check(agent: &str, id: Option<&str>) -> Result<(), String> {
    if !valid_key(agent, 64) {
        return Err("Not an agent id".into());
    }
    if id.is_some_and(|id| !valid_key(id, 80)) {
        return Err("Not a document id".into());
    }
    Ok(())
}

#[tauri::command(async)]
pub fn agent_documents_list(
    store: State<'_, SessionStore>,
    agent: String,
) -> Result<Vec<AgentDocument>, String> {
    check(&agent, None)?;
    let conn = store.lock_conn()?;
    list(&conn, &agent).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn agent_documents_get(
    store: State<'_, SessionStore>,
    agent: String,
    id: String,
) -> Result<Option<AgentDocument>, String> {
    check(&agent, Some(&id))?;
    let conn = store.lock_conn()?;
    get(&conn, &agent, &id).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn agent_documents_upsert(
    store: State<'_, SessionStore>,
    agent: String,
    document: AgentDocumentUpsert,
) -> Result<(), String> {
    check(&agent, Some(&document.id))?;
    if document.body.len() > BODY_MAX {
        return Err("The document is too large".into());
    }
    if document.title.trim().is_empty() || document.title.chars().count() > 200 {
        return Err("A document needs a title of at most 200 characters".into());
    }
    let conn = store.lock_conn()?;
    upsert(&conn, &agent, &document, now_millis()).map_err(|e| e.to_string())
}

/// Removes one document, or with no id every document of an agent that is gone.
#[tauri::command(async)]
pub fn agent_documents_delete(
    store: State<'_, SessionStore>,
    agent: String,
    id: Option<String>,
) -> Result<(), String> {
    check(&agent, id.as_deref())?;
    let conn = store.lock_conn()?;
    delete(&conn, &agent, id.as_deref()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn document(id: &str, title: &str, body: &str) -> AgentDocumentUpsert {
        AgentDocumentUpsert {
            id: id.into(),
            title: title.into(),
            subject: Some("Kubernetes".into()),
            body: body.into(),
        }
    }

    #[test]
    fn writing_the_same_id_again_revises_it_and_keeps_when_it_was_made() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        upsert(&conn, "agent-a", &document("pods", "Pods", "v1"), 10).unwrap();
        upsert(
            &conn,
            "agent-a",
            &document("pods", "Pods, revised", "v2"),
            20,
        )
        .unwrap();
        let saved = get(&conn, "agent-a", "pods").unwrap().unwrap();
        assert_eq!(saved.title, "Pods, revised");
        assert_eq!(saved.body.as_deref(), Some("v2"));
        assert_eq!((saved.created_at, saved.updated_at), (10, 20));
        // The same text again is not a revision.
        upsert(
            &conn,
            "agent-a",
            &document("pods", "Pods, revised", "v2"),
            30,
        )
        .unwrap();
        assert_eq!(
            get(&conn, "agent-a", "pods").unwrap().unwrap().updated_at,
            20
        );
    }

    #[test]
    fn a_library_lists_its_own_documents_newest_first_without_their_text() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        upsert(&conn, "agent-a", &document("pods", "Pods", "a"), 10).unwrap();
        upsert(&conn, "agent-a", &document("services", "Services", "b"), 20).unwrap();
        upsert(&conn, "agent-b", &document("pods", "Other", "c"), 30).unwrap();
        let listed = list(&conn, "agent-a").unwrap();
        assert_eq!(
            listed.iter().map(|d| d.id.as_str()).collect::<Vec<_>>(),
            ["services", "pods"]
        );
        assert!(listed.iter().all(|d| d.body.is_none()));
        assert_eq!(get(&conn, "agent-a", "missing").unwrap(), None);
    }

    #[test]
    fn deleting_takes_one_document_or_all_of_an_agents() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        upsert(&conn, "agent-a", &document("pods", "Pods", "a"), 10).unwrap();
        upsert(&conn, "agent-a", &document("services", "Services", "b"), 20).unwrap();
        upsert(&conn, "agent-b", &document("pods", "Other", "c"), 30).unwrap();
        delete(&conn, "agent-a", Some("pods")).unwrap();
        assert_eq!(list(&conn, "agent-a").unwrap().len(), 1);
        delete(&conn, "agent-a", None).unwrap();
        assert!(list(&conn, "agent-a").unwrap().is_empty());
        assert_eq!(list(&conn, "agent-b").unwrap().len(), 1);
    }

    #[test]
    fn ids_cannot_name_anything_but_a_document() {
        assert!(check(
            "815dafb0-4e66-4224-a3a1-43a8e34f9f97",
            Some("service-是什么")
        )
        .is_ok());
        for id in ["", "../x", "a/b", ".hidden", "a b"] {
            assert!(check("agent", Some(id)).is_err(), "{id}");
        }
        assert!(check("../agent", None).is_err());
    }
}
