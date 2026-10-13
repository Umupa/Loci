//! Source-backed learning and PDF annotations.
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::session_store::{now_millis, SessionStore};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Source {
    id: String,
    title: String,
    quote: String,
    #[serde(flatten)]
    location: SourceLocation,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum SourceLocation {
    File {
        path: String,
        lines: Option<[u32; 2]>,
    },
    Pdf {
        #[serde(rename = "documentId")]
        document_id: String,
        path: String,
        anchors: Vec<PdfAnchor>,
        #[serde(rename = "annotationId", skip_serializing_if = "Option::is_none")]
        annotation_id: Option<String>,
    },
    Web {
        url: String,
    },
    Conversation {
        #[serde(rename = "sessionId")]
        session_id: String,
        #[serde(rename = "blockId")]
        block_id: String,
    },
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct PdfRect {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct PdfAnchor {
    page: u32,
    rects: Vec<PdfRect>,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Discussion {
    session_id: String,
    block_id: String,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadingDocument {
    id: String,
    path: String,
    title: String,
    fingerprint: String,
    created_at: i64,
    updated_at: i64,
}
#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Annotation {
    id: String,
    document_id: String,
    source: Source,
    anchors: Vec<PdfAnchor>,
    note: String,
    discussions: Vec<Discussion>,
    created_at: i64,
    updated_at: i64,
}
pub(crate) fn ensure_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS learning_sources (
      id TEXT PRIMARY KEY, source_json TEXT NOT NULL, created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS reading_documents (
      id TEXT PRIMARY KEY, path TEXT NOT NULL, title TEXT NOT NULL, fingerprint TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(path,fingerprint));
    CREATE TABLE IF NOT EXISTS pdf_annotations (
      id TEXT PRIMARY KEY, document_id TEXT NOT NULL, source_id TEXT NOT NULL,
      anchors_json TEXT NOT NULL, note TEXT NOT NULL, discussions_json TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS pdf_annotations_document ON pdf_annotations(document_id);",
    )
}

fn key(id: &str, max: usize) -> Result<(), String> {
    if id.is_empty()
        || id.chars().count() > max
        || !id
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, '-' | '_'))
    {
        return Err("Invalid learning resource id".into());
    }
    Ok(())
}
fn block_key(id: &str) -> Result<(), String> {
    if id.is_empty() || id.len() > 512 || id.chars().any(char::is_control) {
        return Err("Invalid source message id".into());
    }
    Ok(())
}
fn encode<T: Serialize>(value: &T) -> Result<String, String> {
    serde_json::to_string(value).map_err(|e| e.to_string())
}
fn decode<T: serde::de::DeserializeOwned>(value: String) -> rusqlite::Result<T> {
    serde_json::from_str(&value).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(e))
    })
}
fn anchors_valid(anchors: &[PdfAnchor]) -> Result<(), String> {
    if anchors.is_empty() || anchors.len() > 128 {
        return Err("A PDF selection needs page anchors".into());
    }
    for anchor in anchors {
        if anchor.page == 0 || anchor.rects.len() > 2048 {
            return Err("Invalid PDF selection".into());
        }
        for rect in &anchor.rects {
            if ![rect.x, rect.y, rect.width, rect.height]
                .iter()
                .all(|v| v.is_finite() && *v >= 0.0 && *v <= 1.0)
                || rect.width == 0.0
                || rect.height == 0.0
                || rect.x + rect.width > 1.000_001
                || rect.y + rect.height > 1.000_001
            {
                return Err("Invalid PDF highlight rectangle".into());
            }
        }
    }
    Ok(())
}
fn check_source(source: &Source) -> Result<(), String> {
    key(&source.id, 128)?;
    if source.title.trim().is_empty()
        || source.title.chars().count() > 512
        || source.quote.len() > 256 * 1024
    {
        return Err("Invalid source text".into());
    }
    match &source.location {
        SourceLocation::File { path, lines } => {
            if !std::path::Path::new(path).is_absolute() {
                return Err("Source files need an absolute path".into());
            }
            if lines.is_some_and(|[first, last]| first == 0 || last < first) {
                return Err("Invalid source lines".into());
            }
        }
        SourceLocation::Pdf {
            document_id,
            path,
            anchors,
            annotation_id,
        } => {
            key(document_id, 128)?;
            if !std::path::Path::new(path).is_absolute() {
                return Err("PDF sources need an absolute path".into());
            }
            anchors_valid(anchors)?;
            if let Some(id) = annotation_id {
                key(id, 128)?;
            }
        }
        SourceLocation::Web { url } => {
            let url = url::Url::parse(url).map_err(|_| "Invalid source URL")?;
            if !matches!(url.scheme(), "http" | "https")
                || url.host_str().is_none()
                || !url.username().is_empty()
                || url.password().is_some()
            {
                return Err("Sources require a public HTTP URL without credentials".into());
            }
        }
        SourceLocation::Conversation {
            session_id,
            block_id,
        } => {
            key(session_id, 128)?;
            block_key(block_id)?;
        }
    }
    Ok(())
}
fn put_source(conn: &Connection, source: &Source) -> Result<(), String> {
    check_source(source)?;
    conn.execute(
        "INSERT INTO learning_sources(id,source_json,created_at) VALUES(?1,?2,?3)
      ON CONFLICT(id) DO UPDATE SET source_json=excluded.source_json",
        params![source.id, encode(source)?, now_millis()],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}
fn source(conn: &Connection, id: &str) -> rusqlite::Result<Option<Source>> {
    conn.query_row(
        "SELECT source_json FROM learning_sources WHERE id=?1",
        [id],
        |r| decode(r.get(0)?),
    )
    .optional()
}
#[tauri::command(async)]
pub fn learning_source_register(
    store: State<'_, SessionStore>,
    source: Source,
) -> Result<Source, String> {
    put_source(&*store.lock_conn()?, &source)?;
    Ok(source)
}
#[tauri::command(async)]
pub fn learning_source_get(
    store: State<'_, SessionStore>,
    id: String,
) -> Result<Option<Source>, String> {
    key(&id, 128)?;
    source(&*store.lock_conn()?, &id).map_err(|e| e.to_string())
}

fn document_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ReadingDocument> {
    Ok(ReadingDocument {
        id: row.get(0)?,
        path: row.get(1)?,
        title: row.get(2)?,
        fingerprint: row.get(3)?,
        created_at: row.get(4)?,
        updated_at: row.get(5)?,
    })
}
fn document(conn: &Connection, id: &str) -> rusqlite::Result<Option<ReadingDocument>> {
    conn.query_row(
        "SELECT id,path,title,fingerprint,created_at,updated_at FROM reading_documents WHERE id=?1",
        [id],
        document_row,
    )
    .optional()
}
fn document_path(path: &str) -> Result<String, String> {
    let path = std::path::Path::new(path)
        .canonicalize()
        .map_err(|e| e.to_string())?;
    if !path.is_file() {
        return Err("Choose a PDF file".into());
    }
    Ok(crate::fs::path_to_js(&path))
}
fn register_document(
    conn: &Connection,
    path: &str,
    fingerprint: &str,
    title: &str,
) -> Result<ReadingDocument, String> {
    if fingerprint.is_empty()
        || fingerprint.len() > 256
        || title.trim().is_empty()
        || title.chars().count() > 512
    {
        return Err("Invalid PDF document".into());
    }
    let existing = conn.query_row("SELECT id,path,title,fingerprint,created_at,updated_at FROM reading_documents WHERE path=?1 AND fingerprint=?2",params![path,fingerprint],document_row).optional().map_err(|e|e.to_string())?;
    if let Some(found) = existing {
        return Ok(found);
    }
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_millis();
    conn.execute("INSERT INTO reading_documents(id,path,title,fingerprint,created_at,updated_at) VALUES(?1,?2,?3,?4,?5,?5)",params![id,path,title,fingerprint,now]).map_err(|e|e.to_string())?;
    document(conn, &id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "PDF registration failed".into())
}
#[tauri::command(async)]
pub fn learning_document_register(
    store: State<'_, SessionStore>,
    path: String,
    fingerprint: String,
    title: String,
) -> Result<ReadingDocument, String> {
    register_document(
        &*store.lock_conn()?,
        &document_path(&path)?,
        &fingerprint,
        &title,
    )
}
#[tauri::command(async)]
pub fn learning_document_get(
    store: State<'_, SessionStore>,
    id: String,
) -> Result<Option<ReadingDocument>, String> {
    key(&id, 128)?;
    document(&*store.lock_conn()?, &id).map_err(|e| e.to_string())
}
#[tauri::command(async)]
pub fn learning_document_find(
    store: State<'_, SessionStore>,
    path: String,
) -> Result<Option<ReadingDocument>, String> {
    store.lock_conn()?.query_row("SELECT id,path,title,fingerprint,created_at,updated_at FROM reading_documents WHERE path=?1 ORDER BY updated_at DESC LIMIT 1",[path],document_row).optional().map_err(|e|e.to_string())
}
#[tauri::command(async)]
pub fn learning_document_relocate(
    store: State<'_, SessionStore>,
    id: String,
    path: String,
    fingerprint: String,
) -> Result<ReadingDocument, String> {
    key(&id, 128)?;
    let path = document_path(&path)?;
    let conn = store.lock_conn()?;
    let old = document(&conn, &id)
        .map_err(|e| e.to_string())?
        .ok_or("This PDF record no longer exists")?;
    if old.fingerprint != fingerprint {
        return Err("This is a different PDF version; existing highlights were not moved".into());
    }
    conn.execute(
        "UPDATE reading_documents SET path=?1,updated_at=?2 WHERE id=?3",
        params![path, now_millis(), id],
    )
    .map_err(|e| e.to_string())?;
    document(&conn, &id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "PDF relocation failed".into())
}
fn annotation_row(conn: &Connection, row: &rusqlite::Row<'_>) -> rusqlite::Result<Annotation> {
    let source_id: String = row.get(2)?;
    let found = source(conn, &source_id)?.ok_or(rusqlite::Error::QueryReturnedNoRows)?;
    Ok(Annotation {
        id: row.get(0)?,
        document_id: row.get(1)?,
        source: found,
        anchors: decode(row.get(3)?)?,
        note: row.get(4)?,
        discussions: decode(row.get(5)?)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}
fn annotations(conn: &Connection, document_id: &str) -> rusqlite::Result<Vec<Annotation>> {
    let mut statement=conn.prepare("SELECT id,document_id,source_id,anchors_json,note,discussions_json,created_at,updated_at FROM pdf_annotations WHERE document_id=?1 ORDER BY created_at,id")?;
    let rows = statement.query_map([document_id], |row| annotation_row(conn, row))?;
    rows.collect()
}
fn put_annotation(conn: &Connection, annotation: &Annotation) -> Result<(), String> {
    key(&annotation.id, 128)?;
    key(&annotation.document_id, 128)?;
    anchors_valid(&annotation.anchors)?;
    if annotation.anchors.iter().any(|a| a.rects.is_empty()) {
        return Err("A highlight needs selected text rectangles".into());
    }
    if annotation.note.len() > 64 * 1024 {
        return Err("The annotation is too large".into());
    }
    if document(conn, &annotation.document_id)
        .map_err(|e| e.to_string())?
        .is_none()
    {
        return Err("The PDF is not registered".into());
    }
    match &annotation.source.location {
        SourceLocation::Pdf { document_id, .. } if document_id == &annotation.document_id => {}
        _ => return Err("The annotation must refer to its PDF".into()),
    }
    put_source(conn, &annotation.source)?;
    let now = now_millis();
    conn.execute("INSERT INTO pdf_annotations(id,document_id,source_id,anchors_json,note,discussions_json,created_at,updated_at)
      VALUES(?1,?2,?3,?4,?5,?6,?7,?7) ON CONFLICT(id) DO UPDATE SET note=excluded.note,updated_at=excluded.updated_at",
      params![annotation.id,annotation.document_id,annotation.source.id,encode(&annotation.anchors)?,annotation.note,encode(&annotation.discussions)?,now]).map_err(|e|e.to_string())?;
    Ok(())
}
#[tauri::command(async)]
pub fn learning_annotations_list(
    store: State<'_, SessionStore>,
    document_id: String,
) -> Result<Vec<Annotation>, String> {
    key(&document_id, 128)?;
    annotations(&*store.lock_conn()?, &document_id).map_err(|e| e.to_string())
}
#[tauri::command(async)]
pub fn learning_annotation_upsert(
    store: State<'_, SessionStore>,
    annotation: Annotation,
) -> Result<Annotation, String> {
    let conn = store.lock_conn()?;
    put_annotation(&conn, &annotation)?;
    annotations(&conn, &annotation.document_id)
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|a| a.id == annotation.id)
        .ok_or_else(|| "Annotation could not be saved".into())
}
#[tauri::command(async)]
pub fn learning_annotation_delete(
    store: State<'_, SessionStore>,
    id: String,
) -> Result<(), String> {
    key(&id, 128)?;
    store
        .lock_conn()?
        .execute("DELETE FROM pdf_annotations WHERE id=?1", [id])
        .map_err(|e| e.to_string())?;
    Ok(())
}
fn link_discussion(conn: &Connection, id: &str, discussion: Discussion) -> Result<(), String> {
    key(id, 128)?;
    key(&discussion.session_id, 128)?;
    block_key(&discussion.block_id)?;
    let raw: Option<String> = conn
        .query_row(
            "SELECT discussions_json FROM pdf_annotations WHERE id=?1",
            [id],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;
    // Deleting a highlight keeps its original discussion usable.
    let Some(raw) = raw else {
        return Ok(());
    };
    let mut discussions: Vec<Discussion> = decode(raw).map_err(|e| e.to_string())?;
    if !discussions.contains(&discussion) {
        discussions.push(discussion);
    }
    conn.execute(
        "UPDATE pdf_annotations SET discussions_json=?1,updated_at=?2 WHERE id=?3",
        params![encode(&discussions)?, now_millis(), id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}
#[tauri::command(async)]
pub fn learning_annotation_link(
    store: State<'_, SessionStore>,
    id: String,
    session_id: String,
    block_id: String,
) -> Result<(), String> {
    link_discussion(
        &*store.lock_conn()?,
        &id,
        Discussion {
            session_id,
            block_id,
        },
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn annotation_discussions_survive_note_edits_and_deleted_highlights_keep_sources() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let doc = register_document(&conn, "/books/test.pdf", "fingerprint", "Test").unwrap();
        let anchors = vec![PdfAnchor {
            page: 2,
            rects: vec![PdfRect {
                x: 0.1,
                y: 0.2,
                width: 0.3,
                height: 0.05,
            }],
        }];
        let mut annotation = Annotation {
            id: "annotation".into(),
            document_id: doc.id.clone(),
            source: Source {
                id: "source".into(),
                title: "Test".into(),
                quote: "Selected paragraph".into(),
                location: SourceLocation::Pdf {
                    document_id: doc.id.clone(),
                    path: doc.path,
                    anchors: anchors.clone(),
                    annotation_id: Some("annotation".into()),
                },
            },
            anchors,
            note: String::new(),
            discussions: vec![],
            created_at: 0,
            updated_at: 0,
        };
        put_annotation(&conn, &annotation).unwrap();
        let discussion = Discussion {
            session_id: "chat".into(),
            block_id: "question".into(),
        };
        link_discussion(&conn, "annotation", discussion.clone()).unwrap();
        link_discussion(&conn, "annotation", discussion).unwrap();
        annotation.note = "My understanding".into();
        put_annotation(&conn, &annotation).unwrap();
        assert_eq!(annotations(&conn, &doc.id).unwrap()[0].discussions.len(), 1);
        conn.execute("DELETE FROM pdf_annotations WHERE id='annotation'", [])
            .unwrap();
        assert!(source(&conn, "source").unwrap().is_some());
    }
    #[test]
    fn invalid_sources_and_geometry_are_rejected() {
        assert!(check_source(&Source {
            id: "source".into(),
            title: "Web".into(),
            quote: String::new(),
            location: SourceLocation::Web {
                url: "javascript:alert(1)".into()
            }
        })
        .is_err());
        assert!(anchors_valid(&[PdfAnchor {
            page: 1,
            rects: vec![PdfRect {
                x: 0.9,
                y: 0.0,
                width: 0.2,
                height: 0.1
            }]
        }])
        .is_err());
    }
}
