//! Source-backed learning and reading annotations.
//!
//! One annotation table serves every reader. It started as PDF-only
//! (`pdf_annotations`) and was widened in place: a row names its target (a PDF,
//! a library document or a text file) and, for text, a quote anchor. Older
//! builds list by `document_id`, so they keep seeing exactly their PDF rows.
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
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<TextAnchor>,
        #[serde(
            rename = "annotationId",
            default,
            skip_serializing_if = "Option::is_none"
        )]
        annotation_id: Option<String>,
    },
    Pdf {
        #[serde(rename = "documentId")]
        document_id: String,
        path: String,
        anchors: Vec<PdfAnchor>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<TextAnchor>,
        #[serde(rename = "annotationId", skip_serializing_if = "Option::is_none")]
        annotation_id: Option<String>,
    },
    /// A passage of a document in an agent's library.
    Document {
        #[serde(rename = "agentId")]
        agent_id: String,
        #[serde(rename = "documentId")]
        document_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        url: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        section: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<TextAnchor>,
        #[serde(
            rename = "annotationId",
            default,
            skip_serializing_if = "Option::is_none"
        )]
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
/// A passage of text found again by its words: the quote with a little context,
/// where it was (a hint), the headings above it and, in a text file, its lines.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TextAnchor {
    exact: String,
    #[serde(default)]
    prefix: String,
    #[serde(default)]
    suffix: String,
    #[serde(default)]
    start: u64,
    #[serde(default)]
    end: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    headings: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    lines: Option<[u32; 2]>,
}
/// What an annotation marks.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AnnotationTarget {
    Pdf {
        #[serde(rename = "documentId")]
        document_id: String,
    },
    Document {
        #[serde(rename = "agentId")]
        agent_id: String,
        #[serde(rename = "documentId")]
        document_id: String,
    },
    File {
        path: String,
    },
}
impl AnnotationTarget {
    fn kind(&self) -> &'static str {
        match self {
            Self::Pdf { .. } => "pdf",
            Self::Document { .. } => "document",
            Self::File { .. } => "file",
        }
    }
    fn key(&self) -> String {
        match self {
            Self::Pdf { document_id } => document_id.clone(),
            Self::Document {
                agent_id,
                document_id,
            } => format!("{agent_id}/{document_id}"),
            Self::File { path } => path.clone(),
        }
    }
    fn from_row(kind: &str, key: &str, document_id: &str) -> Option<Self> {
        match kind {
            "document" => {
                let (agent_id, document_id) = key.split_once('/')?;
                Some(Self::Document {
                    agent_id: agent_id.into(),
                    document_id: document_id.into(),
                })
            }
            "file" => Some(Self::File { path: key.into() }),
            _ => Some(Self::Pdf {
                document_id: if key.is_empty() { document_id } else { key }.into(),
            }),
        }
    }
    fn check(&self) -> Result<(), String> {
        match self {
            Self::Pdf { document_id } => key(document_id, 128),
            Self::Document {
                agent_id,
                document_id,
            } => {
                key(agent_id, 128)?;
                key(document_id, 128)
            }
            Self::File { path } => {
                if !std::path::Path::new(path).is_absolute() || path.len() > 4096 {
                    return Err("Annotated files need an absolute path".into());
                }
                Ok(())
            }
        }
    }
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
    /// The PDF's record, for PDF marks; empty for the others.
    #[serde(default)]
    document_id: String,
    /// Absent in what older builds send: then it is the PDF `document_id` names.
    #[serde(default)]
    target: Option<AnnotationTarget>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    anchor: Option<TextAnchor>,
    source: Source,
    #[serde(default)]
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
    )?;
    // Widened in place for every reader; nothing is rewritten or dropped.
    for column in [
        "target_kind TEXT NOT NULL DEFAULT 'pdf'",
        "target_key TEXT NOT NULL DEFAULT ''",
        "anchor_json TEXT",
    ] {
        let name = column.split(' ').next().unwrap_or_default();
        let present: i64 = conn.query_row(
            "SELECT COUNT(*) FROM pragma_table_info('pdf_annotations') WHERE name = ?1",
            [name],
            |row| row.get(0),
        )?;
        if present == 0 {
            conn.execute_batch(&format!("ALTER TABLE pdf_annotations ADD COLUMN {column};"))?;
        }
    }
    conn.execute_batch(
        "UPDATE pdf_annotations SET target_key=document_id WHERE target_kind='pdf' AND target_key='';
    CREATE INDEX IF NOT EXISTS annotations_target ON pdf_annotations(target_kind,target_key);",
    )
}
fn anchor_valid(anchor: &TextAnchor) -> Result<(), String> {
    if anchor.exact.trim().is_empty()
        || anchor.exact.len() > 8 * 1024
        || anchor.prefix.len() > 1024
        || anchor.suffix.len() > 1024
        || anchor.end < anchor.start
        || anchor
            .headings
            .as_ref()
            .is_some_and(|h| h.len() > 8 || h.iter().any(|t| t.len() > 512))
        || anchor
            .lines
            .is_some_and(|[first, last]| first == 0 || last < first)
    {
        return Err("Invalid text anchor".into());
    }
    Ok(())
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
        SourceLocation::File {
            path,
            lines,
            anchor,
            annotation_id,
        } => {
            if !std::path::Path::new(path).is_absolute() {
                return Err("Source files need an absolute path".into());
            }
            if lines.is_some_and(|[first, last]| first == 0 || last < first) {
                return Err("Invalid source lines".into());
            }
            if let Some(anchor) = anchor {
                anchor_valid(anchor)?;
            }
            if let Some(id) = annotation_id {
                key(id, 128)?;
            }
        }
        SourceLocation::Document {
            agent_id,
            document_id,
            url,
            section,
            anchor,
            annotation_id,
        } => {
            key(agent_id, 128)?;
            key(document_id, 128)?;
            if url.as_ref().is_some_and(|u| {
                url::Url::parse(u)
                    .map(|u| !matches!(u.scheme(), "http" | "https"))
                    .unwrap_or(true)
            }) {
                return Err("Invalid source URL".into());
            }
            if section.as_ref().is_some_and(|s| s.chars().count() > 512) {
                return Err("Invalid source section".into());
            }
            if let Some(anchor) = anchor {
                anchor_valid(anchor)?;
            }
            if let Some(id) = annotation_id {
                key(id, 128)?;
            }
        }
        SourceLocation::Pdf {
            document_id,
            path,
            anchors,
            anchor,
            annotation_id,
        } => {
            if let Some(anchor) = anchor {
                anchor_valid(anchor)?;
            }
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
const ANNOTATION_COLUMNS: &str = "id,document_id,source_id,anchors_json,note,discussions_json,created_at,updated_at,target_kind,target_key,anchor_json";
fn annotation_row(conn: &Connection, row: &rusqlite::Row<'_>) -> rusqlite::Result<Annotation> {
    let source_id: String = row.get(2)?;
    let found = source(conn, &source_id)?.ok_or(rusqlite::Error::QueryReturnedNoRows)?;
    let document_id: String = row.get(1)?;
    let kind: String = row.get(8)?;
    let target_key: String = row.get(9)?;
    let anchor: Option<String> = row.get(10)?;
    Ok(Annotation {
        id: row.get(0)?,
        target: if kind == MENTOR_FILE_KIND {
            Some(AnnotationTarget::File {
                path: resolve_mentor_file(conn, &target_key),
            })
        } else {
            AnnotationTarget::from_row(&kind, &target_key, &document_id)
        },
        document_id,
        anchor: anchor.map(decode).transpose()?,
        source: found,
        anchors: decode(row.get(3)?)?,
        note: row.get(4)?,
        discussions: decode(row.get(5)?)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}
fn annotations(conn: &Connection, document_id: &str) -> rusqlite::Result<Vec<Annotation>> {
    let mut statement = conn.prepare(&format!(
        "SELECT {ANNOTATION_COLUMNS} FROM pdf_annotations WHERE document_id=?1 AND target_kind='pdf' ORDER BY created_at,id"
    ))?;
    let rows = statement.query_map([document_id], |row| annotation_row(conn, row))?;
    rows.collect()
}
/// Marks on a file inside a mentor's folder are kept as `mentorFile`
/// `<agent>/<path in the folder>`, so they follow the folder when it is
/// exported, imported or moved. Older marks keyed by absolute path still show.
const MENTOR_FILE_KIND: &str = "mentorFile";

fn mentor_file_key(conn: &Connection, path: &str) -> Option<String> {
    let path = std::path::Path::new(path);
    crate::mentor_store::registry::list(conn)
        .ok()?
        .into_iter()
        .filter(|record| record.migrated_at.is_some())
        .find_map(|record| {
            let rel = path
                .strip_prefix(&record.folder)
                .ok()?
                .to_str()?
                .to_string();
            (!rel.is_empty()).then(|| format!("{}/{rel}", record.id))
        })
}

fn resolve_mentor_file(conn: &Connection, key: &str) -> String {
    key.split_once('/')
        .and_then(|(agent, rel)| {
            crate::mentor_store::registry::active_folder(conn, agent)
                .ok()
                .flatten()
                .map(|folder| folder.join(rel).to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| key.to_string())
}

/// Where a target's marks are stored: its own kind and key, except a file
/// in a mentor's folder.
fn storage_key(conn: &Connection, target: &AnnotationTarget) -> (String, String) {
    if let AnnotationTarget::File { path } = target {
        if let Some(key) = mentor_file_key(conn, path) {
            return (MENTOR_FILE_KIND.into(), key);
        }
    }
    (target.kind().into(), target.key())
}

fn annotations_for(
    conn: &Connection,
    target: &AnnotationTarget,
) -> rusqlite::Result<Vec<Annotation>> {
    let (kind, key) = storage_key(conn, target);
    let mut statement = conn.prepare(&format!(
        "SELECT {ANNOTATION_COLUMNS} FROM pdf_annotations
         WHERE (target_kind=?1 AND target_key=?2) OR (target_kind=?3 AND target_key=?4)
         ORDER BY created_at,id"
    ))?;
    let rows = statement.query_map(params![kind, key, target.kind(), target.key()], |row| {
        annotation_row(conn, row)
    })?;
    rows.collect()
}
fn annotation_by_id(conn: &Connection, id: &str) -> rusqlite::Result<Option<Annotation>> {
    conn.query_row(
        &format!("SELECT {ANNOTATION_COLUMNS} FROM pdf_annotations WHERE id=?1"),
        [id],
        |row| annotation_row(conn, row),
    )
    .optional()
}
fn library_document_exists(
    conn: &Connection,
    agent_id: &str,
    document_id: &str,
) -> Result<bool, String> {
    if let Some(ctx) = crate::mentor_store::ctx_for(conn, agent_id)? {
        use crate::mentor_store::paths::Kind;
        for kind in [Kind::Source, Kind::Guide] {
            if crate::mentor_store::current(conn, &ctx, kind, document_id)?.is_some() {
                return Ok(true);
            }
        }
        return Ok(false);
    }
    conn.query_row(
        "SELECT COUNT(*) FROM agent_documents WHERE agent_id=?1 AND id=?2",
        params![agent_id, document_id],
        |row| row.get::<_, i64>(0),
    )
    .map(|count| count > 0)
    .map_err(|e| e.to_string())
}
fn put_annotation(conn: &Connection, annotation: &Annotation) -> Result<(), String> {
    key(&annotation.id, 128)?;
    if annotation.note.len() > 64 * 1024 {
        return Err("The annotation is too large".into());
    }
    if let Some(anchor) = &annotation.anchor {
        anchor_valid(anchor)?;
    }
    let target = annotation
        .target
        .clone()
        .unwrap_or_else(|| AnnotationTarget::Pdf {
            document_id: annotation.document_id.clone(),
        });
    target.check()?;
    let document_id = match &target {
        AnnotationTarget::Pdf { document_id } => {
            if !annotation.document_id.is_empty() && &annotation.document_id != document_id {
                return Err("The annotation must refer to its PDF".into());
            }
            anchors_valid(&annotation.anchors)?;
            if annotation.anchors.iter().any(|a| a.rects.is_empty()) {
                return Err("A highlight needs selected text rectangles".into());
            }
            if document(conn, document_id)
                .map_err(|e| e.to_string())?
                .is_none()
            {
                return Err("The PDF is not registered".into());
            }
            match &annotation.source.location {
                SourceLocation::Pdf {
                    document_id: source_document,
                    ..
                } if source_document == document_id => {}
                _ => return Err("The annotation must refer to its PDF".into()),
            }
            document_id.clone()
        }
        AnnotationTarget::Document {
            agent_id,
            document_id,
        } => {
            if annotation.anchor.is_none() || !annotation.anchors.is_empty() {
                return Err("A document highlight needs a text anchor".into());
            }
            if !library_document_exists(conn, agent_id, document_id)? {
                return Err("That document is not in the library".into());
            }
            match &annotation.source.location {
                SourceLocation::Document {
                    agent_id: a,
                    document_id: d,
                    ..
                } if a == agent_id && d == document_id => {}
                _ => return Err("The annotation must refer to its document".into()),
            }
            String::new()
        }
        AnnotationTarget::File { path } => {
            if annotation.anchor.is_none() || !annotation.anchors.is_empty() {
                return Err("A file highlight needs a text anchor".into());
            }
            match &annotation.source.location {
                SourceLocation::File { path: p, .. } if p == path => {}
                _ => return Err("The annotation must refer to its file".into()),
            }
            String::new()
        }
    };
    put_source(conn, &annotation.source)?;
    let (target_kind, target_key) = storage_key(conn, &target);
    let now = now_millis();
    let anchor = annotation.anchor.as_ref().map(encode).transpose()?;
    conn.execute("INSERT INTO pdf_annotations(id,document_id,source_id,anchors_json,note,discussions_json,created_at,updated_at,target_kind,target_key,anchor_json)
      VALUES(?1,?2,?3,?4,?5,?6,?7,?7,?8,?9,?10) ON CONFLICT(id) DO UPDATE SET note=excluded.note,updated_at=excluded.updated_at,
      anchor_json=COALESCE(excluded.anchor_json,pdf_annotations.anchor_json)",
      params![annotation.id,document_id,annotation.source.id,encode(&annotation.anchors)?,annotation.note,encode(&annotation.discussions)?,now,target_kind,target_key,anchor]).map_err(|e|e.to_string())?;
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
/// Every mark on one target: a PDF, a library document or a text file.
#[tauri::command(async)]
pub fn learning_annotations_for(
    store: State<'_, SessionStore>,
    target: AnnotationTarget,
) -> Result<Vec<Annotation>, String> {
    target.check()?;
    annotations_for(&*store.lock_conn()?, &target).map_err(|e| e.to_string())
}
/// Marks on several targets at once, as a course's lessons need them.
#[tauri::command(async)]
pub fn learning_annotations_query(
    store: State<'_, SessionStore>,
    targets: Vec<AnnotationTarget>,
) -> Result<Vec<Annotation>, String> {
    if targets.len() > 512 {
        return Err("Too many annotation targets".into());
    }
    let conn = store.lock_conn()?;
    let mut found = Vec::new();
    for target in &targets {
        target.check()?;
        found.extend(annotations_for(&conn, target).map_err(|e| e.to_string())?);
    }
    Ok(found)
}
#[tauri::command(async)]
pub fn learning_annotation_get(
    store: State<'_, SessionStore>,
    id: String,
) -> Result<Option<Annotation>, String> {
    key(&id, 128)?;
    annotation_by_id(&*store.lock_conn()?, &id).map_err(|e| e.to_string())
}
#[tauri::command(async)]
pub fn learning_annotation_upsert(
    store: State<'_, SessionStore>,
    annotation: Annotation,
) -> Result<Annotation, String> {
    let conn = store.lock_conn()?;
    put_annotation(&conn, &annotation)?;
    annotation_by_id(&conn, &annotation.id)
        .map_err(|e| e.to_string())?
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
                    anchor: None,
                    annotation_id: Some("annotation".into()),
                },
            },
            target: None,
            anchor: None,
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
    fn text_anchor(exact: &str) -> TextAnchor {
        TextAnchor {
            exact: exact.into(),
            prefix: String::new(),
            suffix: String::new(),
            start: 0,
            end: exact.len() as u64,
            headings: Some(vec!["Pod phase".into()]),
            lines: None,
        }
    }
    #[test]
    fn a_pdf_table_from_an_older_build_is_widened_without_losing_rows() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE learning_sources (id TEXT PRIMARY KEY, source_json TEXT NOT NULL, created_at INTEGER NOT NULL);
             CREATE TABLE reading_documents (id TEXT PRIMARY KEY, path TEXT NOT NULL, title TEXT NOT NULL, fingerprint TEXT NOT NULL,
               created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(path,fingerprint));
             CREATE TABLE pdf_annotations (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, source_id TEXT NOT NULL,
               anchors_json TEXT NOT NULL, note TEXT NOT NULL, discussions_json TEXT NOT NULL,
               created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
             INSERT INTO reading_documents VALUES('doc','/b.pdf','B','f',1,1);
             INSERT INTO learning_sources VALUES('s','{\"id\":\"s\",\"title\":\"B\",\"quote\":\"q\",\"kind\":\"pdf\",\"documentId\":\"doc\",\"path\":\"/b.pdf\",\"anchors\":[{\"page\":1,\"rects\":[{\"x\":0.1,\"y\":0.1,\"width\":0.2,\"height\":0.1}]}],\"annotationId\":\"a\"}',1);
             INSERT INTO pdf_annotations VALUES('a','doc','s','[{\"page\":1,\"rects\":[{\"x\":0.1,\"y\":0.1,\"width\":0.2,\"height\":0.1}]}]','mine','[]',1,1);",
        )
        .unwrap();
        ensure_table(&conn).unwrap();
        ensure_table(&conn).unwrap();
        let old = annotations(&conn, "doc").unwrap();
        assert_eq!(old.len(), 1);
        assert_eq!(old[0].note, "mine");
        let target = AnnotationTarget::Pdf {
            document_id: "doc".into(),
        };
        assert_eq!(old[0].target, Some(target.clone()));
        assert_eq!(annotations_for(&conn, &target).unwrap().len(), 1);
    }
    #[test]
    fn documents_and_files_take_text_highlights_that_pdf_lists_never_show() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        conn.execute("INSERT INTO agent_documents(agent_id,id,title,body,created_at,updated_at) VALUES('agent','pods','Pods','A Pod phase.',1,1)", []).unwrap();
        let target = AnnotationTarget::Document {
            agent_id: "agent".into(),
            document_id: "pods".into(),
        };
        let mut annotation = Annotation {
            id: "mark".into(),
            document_id: String::new(),
            target: Some(target.clone()),
            anchor: Some(text_anchor("Pod phase")),
            source: Source {
                id: "mark-source".into(),
                title: "Pods".into(),
                quote: "Pod phase".into(),
                location: SourceLocation::Document {
                    agent_id: "agent".into(),
                    document_id: "pods".into(),
                    url: None,
                    section: None,
                    anchor: Some(text_anchor("Pod phase")),
                    annotation_id: Some("mark".into()),
                },
            },
            anchors: vec![],
            note: "why".into(),
            discussions: vec![],
            created_at: 0,
            updated_at: 0,
        };
        put_annotation(&conn, &annotation).unwrap();
        let found = annotations_for(&conn, &target).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].anchor, Some(text_anchor("Pod phase")));
        assert!(annotations(&conn, "").unwrap().is_empty());
        // A missing library document, or a source that points elsewhere, is refused.
        annotation.target = Some(AnnotationTarget::Document {
            agent_id: "agent".into(),
            document_id: "gone".into(),
        });
        assert!(put_annotation(&conn, &annotation).is_err());
        annotation.id = "file-mark".into();
        annotation.target = Some(AnnotationTarget::File {
            path: "/src/main.rs".into(),
        });
        assert!(put_annotation(&conn, &annotation).is_err());
        annotation.source.location = SourceLocation::File {
            path: "/src/main.rs".into(),
            lines: Some([3, 4]),
            anchor: None,
            annotation_id: Some("file-mark".into()),
        };
        put_annotation(&conn, &annotation).unwrap();
        let file = AnnotationTarget::File {
            path: "/src/main.rs".into(),
        };
        assert_eq!(annotations_for(&conn, &file).unwrap().len(), 1);
        assert_eq!(
            annotation_by_id(&conn, "file-mark")
                .unwrap()
                .unwrap()
                .target,
            Some(file)
        );
        annotation.anchor = None;
        annotation.id = "no-anchor".into();
        assert!(put_annotation(&conn, &annotation).is_err());
    }
    #[test]
    fn marks_in_a_mentor_folder_follow_the_folder_and_older_marks_still_show() {
        use crate::mentor_store::testing::{register, temp_dir};
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp_dir("marks");
        register(&conn, "agent", &folder);
        std::fs::create_dir_all(folder.join("sources")).unwrap();
        std::fs::write(
            folder.join("sources/pods.md"),
            "---\ntitle: Pods\nsourceUrl: https://k.io\n---\nA Pod phase.\n",
        )
        .unwrap();
        let file = folder
            .join("repos/fc/src/main.rs")
            .to_string_lossy()
            .into_owned();
        let mark = |id: &str, target: AnnotationTarget, location: SourceLocation| Annotation {
            id: id.into(),
            document_id: String::new(),
            target: Some(target),
            anchor: Some(text_anchor("Pod phase")),
            source: Source {
                id: format!("{id}-source"),
                title: "T".into(),
                quote: "Pod phase".into(),
                location,
            },
            anchors: vec![],
            note: String::new(),
            discussions: vec![],
            created_at: 0,
            updated_at: 0,
        };
        // A document mark on a source kept as a file.
        put_annotation(
            &conn,
            &mark(
                "doc",
                AnnotationTarget::Document {
                    agent_id: "agent".into(),
                    document_id: "pods".into(),
                },
                SourceLocation::Document {
                    agent_id: "agent".into(),
                    document_id: "pods".into(),
                    url: None,
                    section: None,
                    anchor: None,
                    annotation_id: None,
                },
            ),
        )
        .unwrap();
        // A file mark inside the folder is stored relative to it.
        let target = AnnotationTarget::File { path: file.clone() };
        put_annotation(
            &conn,
            &mark(
                "new",
                target.clone(),
                SourceLocation::File {
                    path: file.clone(),
                    lines: None,
                    anchor: None,
                    annotation_id: None,
                },
            ),
        )
        .unwrap();
        let (kind, key): (String, String) = conn
            .query_row(
                "SELECT target_kind, target_key FROM pdf_annotations WHERE id='new'",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(
            (kind.as_str(), key.as_str()),
            ("mentorFile", "agent/repos/fc/src/main.rs")
        );
        // A 0.3 mark on the same file by absolute path.
        conn.execute("INSERT INTO pdf_annotations(id,document_id,source_id,anchors_json,note,discussions_json,created_at,updated_at,target_kind,target_key,anchor_json) VALUES('old','', 'new-source','[]','', '[]',0,0,'file',?1,NULL)", [&file]).unwrap();
        let found = annotations_for(&conn, &target).unwrap();
        assert_eq!(
            found.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(),
            vec!["old", "new"]
        );
        assert!(found.iter().all(|a| a.target == Some(target.clone())));
        std::fs::remove_dir_all(folder).unwrap();
    }
    #[test]
    fn older_annotation_json_without_a_target_still_parses() {
        let parsed: Annotation = serde_json::from_str(r#"{"id":"a","documentId":"doc","source":{"id":"s","title":"T","quote":"q","kind":"file","path":"/a","lines":null},"anchors":[],"note":"","discussions":[],"createdAt":0,"updatedAt":0}"#).unwrap();
        assert_eq!(parsed.target, None);
        assert_eq!(parsed.document_id, "doc");
    }
}
