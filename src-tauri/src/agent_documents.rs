//! Documents an agent wrote for the user to read: explanations, readings,
//! summaries. Each belongs to one agent and is named by an id the agent
//! chose, so writing the same id again revises it. Only the latest text is
//! kept. They are the agent's library, apart from the user's own notes.
//!
//! A source is a document the agent did not write: the text of a page it
//! saved to a file, taken in from that file with where it came from. A reply
//! cannot revise one, so what the user reads stays what was published; only
//! taking the file in again replaces it.
//!
//! So a library holds two kinds, told apart by `source_url`: first-hand
//! sources (with one) and the mentor's own guides (without). An id names one
//! kind for good: a guide cannot replace a source, nor a source a guide.

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::session_store::{now_millis, SessionStore};

const BODY_MAX: usize = 1024 * 1024;
const URL_MAX: usize = 2000;
const VERSION_MAX: usize = 80;

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentDocument {
    id: String,
    title: String,
    subject: Option<String>,
    /// `source` (someone else's text, with `source_url`) or `guide` (the mentor wrote it).
    kind: &'static str,
    /// Left out of listings, which only name the documents.
    #[serde(skip_serializing_if = "Option::is_none")]
    body: Option<String>,
    /// Where a source was published; absent on what the agent wrote itself.
    #[serde(skip_serializing_if = "Option::is_none")]
    source_url: Option<String>,
    /// The edition of a source, when it has one: "v1.34".
    #[serde(skip_serializing_if = "Option::is_none")]
    source_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    fetched_at: Option<i64>,
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

/// A guide the mentor wrote, from a file or given in full.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentGuideWrite {
    id: String,
    title: String,
    subject: Option<String>,
    path: Option<String>,
    body: Option<String>,
}

/// A source to take in: the file holding its text, and where it was published.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentDocumentImport {
    id: String,
    title: String,
    subject: Option<String>,
    path: String,
    source_url: String,
    version: Option<String>,
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
    )?;
    for column in [
        "source_url TEXT",
        "source_version TEXT",
        "fetched_at INTEGER",
    ] {
        let name = column.split(' ').next().unwrap_or_default();
        let present: i64 = conn.query_row(
            "SELECT COUNT(*) FROM pragma_table_info('agent_documents') WHERE name = ?1",
            [name],
            |row| row.get(0),
        )?;
        if present == 0 {
            conn.execute_batch(&format!("ALTER TABLE agent_documents ADD COLUMN {column};"))?;
        }
    }
    Ok(())
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

fn kind_of(source_url: &Option<String>) -> &'static str {
    if source_url.is_some() {
        "source"
    } else {
        "guide"
    }
}

/// Whether `id` is already in the library, and as which kind.
fn existing_kind(
    conn: &Connection,
    agent: &str,
    id: &str,
) -> rusqlite::Result<Option<&'static str>> {
    conn.query_row(
        "SELECT source_url FROM agent_documents WHERE agent_id = ?1 AND id = ?2",
        params![agent, id],
        |row| row.get::<_, Option<String>>(0),
    )
    .optional()
    .map(|found| found.map(|url| kind_of(&url)))
}

fn list(conn: &Connection, agent: &str) -> rusqlite::Result<Vec<AgentDocument>> {
    let mut statement = conn.prepare(
        "SELECT id, title, subject, source_url, source_version, fetched_at, created_at, updated_at
         FROM agent_documents WHERE agent_id = ?1 ORDER BY updated_at DESC, id",
    )?;
    let rows = statement.query_map([agent], |row| {
        Ok(AgentDocument {
            id: row.get(0)?,
            title: row.get(1)?,
            subject: row.get(2)?,
            body: None,
            kind: kind_of(&row.get::<_, Option<String>>(3)?),
            source_url: row.get(3)?,
            source_version: row.get(4)?,
            fetched_at: row.get(5)?,
            created_at: row.get(6)?,
            updated_at: row.get(7)?,
        })
    })?;
    rows.collect()
}

fn get(conn: &Connection, agent: &str, id: &str) -> rusqlite::Result<Option<AgentDocument>> {
    conn.query_row(
        "SELECT id, title, subject, body, source_url, source_version, fetched_at, created_at, updated_at
         FROM agent_documents WHERE agent_id = ?1 AND id = ?2",
        params![agent, id],
        |row| {
            Ok(AgentDocument {
                id: row.get(0)?,
                title: row.get(1)?,
                subject: row.get(2)?,
                body: Some(row.get(3)?),
                kind: kind_of(&row.get::<_, Option<String>>(4)?),
                source_url: row.get(4)?,
                source_version: row.get(5)?,
                fetched_at: row.get(6)?,
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
            })
        },
    )
    .optional()
}

/// Writes the document, keeping when it was first made. Unchanged text leaves
/// its date alone, so re-reading a chat does not reorder the library. A source
/// with this id is refused and left as it is.
fn upsert(
    conn: &Connection,
    agent: &str,
    document: &AgentDocumentUpsert,
    now: i64,
) -> Result<(), String> {
    if existing_kind(conn, agent, &document.id).map_err(|e| e.to_string())? == Some("source") {
        return Err(format!(
            "{} is a first-hand source; a guide cannot replace it. Give the guide another id",
            document.id
        ));
    }
    conn.execute(
        "INSERT INTO agent_documents (agent_id, id, title, subject, body, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
         ON CONFLICT(agent_id, id) DO UPDATE SET
           title = excluded.title, subject = excluded.subject, body = excluded.body,
           updated_at = excluded.updated_at
         WHERE agent_documents.source_url IS NULL
           AND (title IS NOT excluded.title OR subject IS NOT excluded.subject
            OR body IS NOT excluded.body)",
        params![
            agent,
            document.id,
            document.title,
            document.subject,
            document.body,
            now
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// Takes a source in, replacing whatever had this id. The text is the file's,
/// byte for byte.
fn import(
    conn: &Connection,
    agent: &str,
    source: &AgentDocumentImport,
    body: &str,
    now: i64,
) -> Result<(), String> {
    if existing_kind(conn, agent, &source.id).map_err(|e| e.to_string())? == Some("guide") {
        return Err(format!(
            "{} is the mentor's guide; a source cannot replace it. Give the source another id",
            source.id
        ));
    }
    conn.execute(
        "INSERT INTO agent_documents
           (agent_id, id, title, subject, body, source_url, source_version, fetched_at, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, ?8)
         ON CONFLICT(agent_id, id) DO UPDATE SET
           title = excluded.title, subject = excluded.subject, body = excluded.body,
           source_url = excluded.source_url, source_version = excluded.source_version,
           fetched_at = excluded.fetched_at, updated_at = excluded.updated_at",
        params![
            agent,
            source.id,
            source.title.trim(),
            source.subject,
            body,
            source.source_url,
            source.version,
            now
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

fn check_title(title: &str) -> Result<(), String> {
    if title.trim().is_empty() || title.chars().count() > 200 {
        return Err("A document needs a title of at most 200 characters".into());
    }
    Ok(())
}

/// The file a source is taken from: an absolute path to UTF-8 text.
fn source_text(path: &str) -> Result<String, String> {
    let path = std::path::Path::new(path);
    if !path.is_absolute() {
        return Err("path must be an absolute path to the saved file".into());
    }
    let size = std::fs::metadata(path)
        .map_err(|e| format!("Could not read {}: {e}", path.display()))?
        .len();
    if size > BODY_MAX as u64 {
        return Err("The file is too large for one document; split it by chapter".into());
    }
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("Could not read {} as UTF-8 text: {e}", path.display()))?;
    if text.trim().is_empty() {
        return Err("The file is empty".into());
    }
    Ok(text)
}

fn check_source(source: &AgentDocumentImport) -> Result<(), String> {
    check_title(&source.title)?;
    let url = source.source_url.as_str();
    if !(url.starts_with("https://") || url.starts_with("http://"))
        || url.len() > URL_MAX
        || url.chars().any(char::is_whitespace)
    {
        return Err("sourceUrl must be the http(s) address the text was published at".into());
    }
    if source
        .version
        .as_ref()
        .is_some_and(|v| v.trim().is_empty() || v.chars().count() > VERSION_MAX)
    {
        return Err("version must be a short label such as v1.34".into());
    }
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
    check_title(&document.title)?;
    let conn = store.lock_conn()?;
    upsert(&conn, &agent, &document, now_millis())
}

/// The text of a guide: the file at `path`, or `body`, exactly one of them.
fn guide_text(guide: &AgentGuideWrite) -> Result<String, String> {
    match (&guide.path, &guide.body) {
        (Some(path), None) => source_text(path),
        (None, Some(body)) if body.len() > BODY_MAX => {
            Err("The guide is too large; split it".into())
        }
        (None, Some(body)) if body.trim().is_empty() => Err("The guide is empty".into()),
        (None, Some(body)) => Ok(body.clone()),
        _ => Err("Give the guide's text as path (an absolute file) or body, not both".into()),
    }
}

/// Saves a guide the mentor wrote and returns it without its text.
fn write_guide(
    conn: &Connection,
    agent: &str,
    guide: &AgentGuideWrite,
    now: i64,
) -> Result<AgentDocument, String> {
    check_title(&guide.title)?;
    let body = guide_text(guide)?;
    let document = AgentDocumentUpsert {
        id: guide.id.clone(),
        title: guide.title.trim().to_string(),
        subject: guide.subject.clone(),
        body,
    };
    upsert(conn, agent, &document, now)?;
    let mut saved = get(conn, agent, &guide.id)
        .map_err(|e| e.to_string())?
        .ok_or("The saved guide is missing")?;
    saved.body = None;
    Ok(saved)
}

/// Saves a guide the mentor wrote (no `sourceUrl`): it is listed apart from first-hand sources.
#[tauri::command(async)]
pub fn agent_documents_write_guide(
    store: State<'_, SessionStore>,
    agent: String,
    guide: AgentGuideWrite,
) -> Result<AgentDocument, String> {
    check(&agent, Some(&guide.id))?;
    let conn = store.lock_conn()?;
    write_guide(&conn, &agent, &guide, now_millis())
}

/// Takes a saved file into the library as a source and returns it without its text.
#[tauri::command(async)]
pub fn agent_documents_import(
    store: State<'_, SessionStore>,
    agent: String,
    source: AgentDocumentImport,
) -> Result<AgentDocument, String> {
    check(&agent, Some(&source.id))?;
    check_source(&source)?;
    let body = source_text(&source.path)?;
    let conn = store.lock_conn()?;
    import(&conn, &agent, &source, &body, now_millis())?;
    let mut saved = get(&conn, &agent, &source.id)
        .map_err(|e| e.to_string())?
        .ok_or("The saved document is missing")?;
    saved.body = None;
    Ok(saved)
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

    fn source(id: &str, path: &str) -> AgentDocumentImport {
        AgentDocumentImport {
            id: id.into(),
            title: "Pod Lifecycle".into(),
            subject: Some("Kubernetes".into()),
            path: path.into(),
            source_url: "https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/".into(),
            version: Some("v1.34".into()),
        }
    }

    #[test]
    fn a_source_keeps_where_it_came_from_and_a_reply_cannot_revise_it() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        import(
            &conn,
            "agent-a",
            &source("pod-lifecycle", "/x"),
            "original",
            10,
        )
        .unwrap();
        let refused = upsert(
            &conn,
            "agent-a",
            &document("pod-lifecycle", "Rewritten", "summary"),
            20,
        )
        .unwrap_err();
        assert!(refused.contains("first-hand source"), "{refused}");
        let saved = get(&conn, "agent-a", "pod-lifecycle").unwrap().unwrap();
        assert_eq!(saved.body.as_deref(), Some("original"));
        assert_eq!(saved.title, "Pod Lifecycle");
        assert_eq!(saved.source_version.as_deref(), Some("v1.34"));
        assert_eq!((saved.fetched_at, saved.updated_at), (Some(10), 10));
        // Taking the file in again is how a source changes.
        import(
            &conn,
            "agent-a",
            &source("pod-lifecycle", "/x"),
            "newer",
            30,
        )
        .unwrap();
        let again = get(&conn, "agent-a", "pod-lifecycle").unwrap().unwrap();
        assert_eq!(again.body.as_deref(), Some("newer"));
        assert_eq!((again.created_at, again.fetched_at), (10, Some(30)));
        assert!(list(&conn, "agent-a").unwrap()[0].source_url.is_some());
    }

    #[test]
    fn a_source_is_read_from_an_absolute_text_file_with_a_web_address() {
        let dir = std::env::temp_dir().join(format!("loci-source-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("pods.md");
        std::fs::write(&file, "# Pods\n\nText.\n").unwrap();
        assert_eq!(
            source_text(file.to_str().unwrap()).unwrap(),
            "# Pods\n\nText.\n"
        );
        assert!(source_text("pods.md").is_err());
        assert!(source_text(dir.join("missing.md").to_str().unwrap()).is_err());
        std::fs::write(&file, "  \n").unwrap();
        assert!(source_text(file.to_str().unwrap()).is_err());
        std::fs::remove_dir_all(&dir).unwrap();

        assert!(check_source(&source("pods", "/x")).is_ok());
        for url in [
            "",
            "file:///etc/passwd",
            "kubernetes.io/docs",
            "https://a b",
        ] {
            let mut bad = source("pods", "/x");
            bad.source_url = url.into();
            assert!(check_source(&bad).is_err(), "{url}");
        }
    }

    fn guide(id: &str, body: Option<&str>, path: Option<&str>) -> AgentGuideWrite {
        AgentGuideWrite {
            id: id.into(),
            title: " Reading guide ".into(),
            subject: None,
            path: path.map(Into::into),
            body: body.map(Into::into),
        }
    }

    #[test]
    fn a_guide_is_listed_as_the_mentors_own_and_never_takes_a_sources_id() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let saved = write_guide(
            &conn,
            "agent-a",
            &guide("k8s-guide", Some("# Read this first"), None),
            10,
        )
        .unwrap();
        assert_eq!(
            (saved.kind, saved.title.as_str(), saved.body.is_none()),
            ("guide", "Reading guide", true)
        );
        assert_eq!(saved.source_url, None);
        import(&conn, "agent-a", &source("pods", "/x"), "original", 20).unwrap();
        let kinds: Vec<_> = list(&conn, "agent-a")
            .unwrap()
            .iter()
            .map(|d| (d.id.clone(), d.kind))
            .collect();
        assert_eq!(
            kinds,
            [
                ("pods".to_string(), "source"),
                ("k8s-guide".to_string(), "guide")
            ]
        );
        // Neither kind replaces the other under one id.
        assert!(write_guide(&conn, "agent-a", &guide("pods", Some("mine"), None), 30).is_err());
        assert_eq!(
            get(&conn, "agent-a", "pods")
                .unwrap()
                .unwrap()
                .body
                .as_deref(),
            Some("original")
        );
        let refused =
            import(&conn, "agent-a", &source("k8s-guide", "/x"), "theirs", 40).unwrap_err();
        assert!(refused.contains("mentor's guide"), "{refused}");
        assert_eq!(
            get(&conn, "agent-a", "k8s-guide").unwrap().unwrap().kind,
            "guide"
        );
        // A guide is revised by writing it again.
        write_guide(
            &conn,
            "agent-a",
            &guide("k8s-guide", Some("# Read this second"), None),
            50,
        )
        .unwrap();
        assert_eq!(
            get(&conn, "agent-a", "k8s-guide")
                .unwrap()
                .unwrap()
                .body
                .as_deref(),
            Some("# Read this second")
        );
    }

    #[test]
    fn a_guides_text_comes_from_exactly_one_of_path_or_body() {
        let dir = std::env::temp_dir().join(format!("loci-guide-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("guide.md");
        std::fs::write(&file, "# Guide\n").unwrap();
        assert_eq!(
            guide_text(&guide("g", None, file.to_str())).unwrap(),
            "# Guide\n"
        );
        assert_eq!(guide_text(&guide("g", Some("text"), None)).unwrap(), "text");
        assert!(guide_text(&guide("g", None, None)).is_err());
        assert!(guide_text(&guide("g", Some("text"), file.to_str())).is_err());
        assert!(guide_text(&guide("g", Some("  "), None)).is_err());
        assert!(guide_text(&guide("g", None, Some("guide.md"))).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
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
