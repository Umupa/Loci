//! The index of mentors' folders in SQLite: what each content file is
//! called and holds, so listing never touches the disk and search is one
//! query. Files are the truth; every row can be rebuilt from them.
//!
//! A row that stops parsing keeps its last good title and text and gains an
//! `error`, so a half-saved edit never makes a document vanish.

use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use serde_json::{json, Value};

use super::format;
use super::fsio::{sha256, stamp};
use super::paths::{self, classify, Kind, KINDS};
use super::pdf;
use super::MentorCtx;
use crate::session_store::now_millis;

/// Sources, guides and notes: what one document may weigh.
pub const TEXT_MAX: u64 = 1024 * 1024;
/// Courses and canvases, as the tables allowed.
pub const DATA_MAX: u64 = 50_000_000;

pub fn ensure_tables(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS mentors (
           id TEXT PRIMARY KEY,
           folder TEXT NOT NULL,
           session_id TEXT,
           position INTEGER NOT NULL DEFAULT 0,
           local_json TEXT NOT NULL DEFAULT '{}',
           migrated_at INTEGER,
           added_at INTEGER NOT NULL
         );
         CREATE TABLE IF NOT EXISTS mentor_content (
           seq INTEGER PRIMARY KEY,
           agent_id TEXT NOT NULL,
           kind TEXT NOT NULL,
           id TEXT NOT NULL,
           rel_path TEXT NOT NULL,
           title TEXT NOT NULL,
           subject TEXT,
           meta_json TEXT NOT NULL DEFAULT '{}',
           body TEXT,
           hash TEXT NOT NULL,
           size INTEGER NOT NULL,
           mtime_ns INTEGER NOT NULL,
           error TEXT,
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL,
           indexed_at INTEGER NOT NULL,
           UNIQUE (agent_id, kind, id),
           UNIQUE (agent_id, rel_path)
         );
         CREATE INDEX IF NOT EXISTS mentor_content_list
           ON mentor_content (agent_id, kind, updated_at DESC);
         CREATE INDEX IF NOT EXISTS mentor_content_kind_id
           ON mentor_content (kind, id);
         CREATE VIRTUAL TABLE IF NOT EXISTS mentor_content_fts USING fts5(
           title, body, content='mentor_content', content_rowid='seq', tokenize='trigram'
         );
         CREATE TRIGGER IF NOT EXISTS mentor_content_ai AFTER INSERT ON mentor_content BEGIN
           INSERT INTO mentor_content_fts(rowid, title, body)
           VALUES (new.seq, new.title, CASE WHEN new.kind IN ('source','guide','note') THEN coalesce(new.body,'') ELSE '' END);
         END;
         CREATE TRIGGER IF NOT EXISTS mentor_content_ad AFTER DELETE ON mentor_content BEGIN
           INSERT INTO mentor_content_fts(mentor_content_fts, rowid, title, body)
           VALUES ('delete', old.seq, old.title, CASE WHEN old.kind IN ('source','guide','note') THEN coalesce(old.body,'') ELSE '' END);
         END;
         CREATE TRIGGER IF NOT EXISTS mentor_content_au AFTER UPDATE ON mentor_content BEGIN
           INSERT INTO mentor_content_fts(mentor_content_fts, rowid, title, body)
           VALUES ('delete', old.seq, old.title, CASE WHEN old.kind IN ('source','guide','note') THEN coalesce(old.body,'') ELSE '' END);
           INSERT INTO mentor_content_fts(rowid, title, body)
           VALUES (new.seq, new.title, CASE WHEN new.kind IN ('source','guide','note') THEN coalesce(new.body,'') ELSE '' END);
         END;
         -- No foreign key to a course: an editor's save or a git checkout may
         -- take the file away for a moment, and progress must outlive that.
         CREATE TABLE IF NOT EXISTS lesson_progress (
           agent_id TEXT NOT NULL,
           course_id TEXT NOT NULL,
           item_id TEXT NOT NULL,
           status TEXT NOT NULL CHECK (status IN ('untouched', 'learning', 'mastered')),
           updated_at INTEGER NOT NULL,
           PRIMARY KEY (agent_id, course_id, item_id)
         );
         CREATE TABLE IF NOT EXISTS mentor_state (
           agent_id TEXT NOT NULL,
           key TEXT NOT NULL,
           json TEXT NOT NULL,
           updated_at INTEGER NOT NULL,
           PRIMARY KEY (agent_id, key)
         );",
    )
}

/// One indexed file.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Row {
    pub agent_id: String,
    pub kind: String,
    pub id: String,
    pub rel_path: String,
    pub title: String,
    pub subject: Option<String>,
    pub meta: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    pub hash: String,
    pub error: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Change {
    Unchanged,
    Changed,
    Removed,
}

struct Parsed {
    title: Option<String>,
    subject: Option<String>,
    meta: Value,
    body: Option<String>,
    created_at: Option<i64>,
    updated_at: Option<i64>,
    /// Read, but something about it needs the author's attention.
    warning: Option<String>,
}

fn ascii_id(id: &str) -> bool {
    id.bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// A PDF source's row: its sidecar's front matter, the PDF's text, and its
/// page count. The PDF is read here so search and `documents.read` have the
/// words without opening the file again.
fn parse_pdf_source(id: &str, sidecar: &str, pdf_path: &Path) -> Result<Parsed, String> {
    let (meta, _) = pdf::parse_sidecar(sidecar)?;
    let mut warning = if meta.source_url.is_none() {
        Some("A source needs sourceUrl in its sidecar".to_string())
    } else {
        None
    };
    let read = if pdf_path.is_file() {
        match pdf::read_pdf(pdf_path) {
            Ok(read) => Some(read),
            Err(error) => {
                warning = Some(error);
                None
            }
        }
    } else {
        warning = Some(format!(
            "{} is missing; restore it beside the sidecar",
            pdf_path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("The PDF")
        ));
        None
    };
    let title = meta
        .title
        .clone()
        .or_else(|| {
            read.as_ref()
                .and_then(|read| pdf::title_from_text(&read.text))
        })
        .or_else(|| Some(id.to_string()));
    let pages = read.as_ref().map(|read| read.pages).or(meta.pages);
    if let Some(read) = &read {
        if warning.is_none() {
            warning = read.warning.clone();
        }
    }
    Ok(Parsed {
        title,
        subject: meta.subject.clone(),
        meta: json!({
            "sourceUrl": meta.source_url,
            "version": meta.version,
            "fetchedAt": meta.fetched_at,
            "pdf": true,
            "pages": pages,
        }),
        body: read.map(|read| read.text),
        created_at: meta.fetched_at,
        updated_at: None,
        warning,
    })
}

fn parse(kind: Kind, id: &str, text: &str, ctx: &MentorCtx) -> Result<Parsed, String> {
    if matches!(kind, Kind::Course | Kind::Note | Kind::Canvas) && !ascii_id(id) {
        return Err(format!(
            "Rename it: {} ids use only ASCII letters, digits, - and _",
            kind.as_str()
        ));
    }
    match kind {
        Kind::Source | Kind::Guide => {
            let (meta, _, body) = format::parse_doc(text)?;
            let warning = match (kind, &meta.source_url) {
                (Kind::Source, None) => Some("A source needs sourceUrl in its front-matter".into()),
                (Kind::Guide, Some(_)) => {
                    Some("Guides have no sourceUrl; move this file to sources/".into())
                }
                _ => None,
            };
            Ok(Parsed {
                title: meta.title.clone().or_else(|| format::first_heading(&body)),
                subject: meta.subject.clone(),
                meta: json!({
                    "sourceUrl": meta.source_url,
                    "version": meta.version,
                    "fetchedAt": meta.fetched_at,
                }),
                body: Some(body),
                created_at: meta.created_at,
                updated_at: None,
                warning,
            })
        }
        Kind::Note => {
            let (meta, _, body) = format::parse_note(text)?;
            Ok(Parsed {
                title: meta.title.clone().or_else(|| format::first_heading(&body)),
                subject: None,
                meta: json!({
                    "slug": meta.slug,
                    "slugPending": meta.slug_pending,
                    "tags": meta.tags,
                    "sourceSession": meta.source_session,
                    "sourceCwd": meta.source_cwd,
                }),
                body: Some(body),
                created_at: meta.created_at,
                updated_at: meta.updated_at,
                warning: None,
            })
        }
        // The learning path shares the courses folder under a reserved id.
        Kind::Course if id == crate::course_path::PATH_ID => {
            let path = crate::course_path::parse(text)?;
            Ok(Parsed {
                title: path
                    .get("title")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                    .or_else(|| Some("Learning path".into())),
                subject: None,
                meta: json!({ "path": true }),
                body: Some(path.to_string()),
                created_at: None,
                updated_at: None,
                warning: None,
            })
        }
        Kind::Course => {
            let resolve = |path: &str| ctx.resolve_lesson_file(path);
            let course = format::parse_course(text, &resolve)?;
            let (data_json, _) = crate::course::validate_data(&course.engine, &course.data_json)?;
            Ok(Parsed {
                title: Some(course.title),
                subject: None,
                meta: json!({ "engine": course.engine }),
                body: Some(data_json),
                created_at: None,
                updated_at: None,
                warning: None,
            })
        }
        Kind::Canvas => {
            let (meta, data) = format::parse_canvas(text)?;
            Ok(Parsed {
                title: meta.title.clone(),
                subject: None,
                meta: json!({ "tags": meta.tags }),
                body: Some(data),
                created_at: meta.created_at,
                updated_at: meta.updated_at,
                warning: None,
            })
        }
    }
}

fn row_stamp(
    conn: &Connection,
    agent: &str,
    rel: &str,
) -> rusqlite::Result<Option<(i64, i64, String)>> {
    conn.query_row(
        "SELECT size, mtime_ns, hash FROM mentor_content WHERE agent_id = ?1 AND rel_path = ?2",
        params![agent, rel],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )
    .optional()
}

fn rel_path(kind: Kind, path: &Path) -> String {
    format!(
        "{}/{}",
        kind.dir(),
        path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
    )
}

#[allow(clippy::too_many_arguments)]
fn write_row(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
    rel: &str,
    hash: &str,
    size: i64,
    mtime: i64,
    now: i64,
    mtime_ms: i64,
    parsed: Parsed,
) -> Result<(), String> {
    let created = parsed.created_at.unwrap_or(mtime_ms);
    // An edit that did not bump updatedAt still counts as a change.
    let updated = parsed.updated_at.map_or(mtime_ms, |at| at.max(mtime_ms));
    conn.execute(
        "INSERT INTO mentor_content
           (agent_id, kind, id, rel_path, title, subject, meta_json, body, hash, size,
            mtime_ns, error, created_at, updated_at, indexed_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
         ON CONFLICT(agent_id, kind, id) DO UPDATE SET
           rel_path = excluded.rel_path, title = excluded.title, subject = excluded.subject,
           meta_json = excluded.meta_json, body = excluded.body, hash = excluded.hash,
           size = excluded.size, mtime_ns = excluded.mtime_ns, error = excluded.error,
           created_at = excluded.created_at, updated_at = excluded.updated_at,
           indexed_at = excluded.indexed_at",
        params![
            ctx.agent,
            kind.as_str(),
            id,
            rel,
            parsed.title.unwrap_or_else(|| id.to_string()),
            parsed.subject,
            parsed.meta.to_string(),
            parsed.body,
            hash,
            size,
            mtime,
            parsed.warning,
            created,
            updated,
            now
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// Keeps the last good parse; only says what is wrong now. A file never read
/// before is still listed, under its id and whatever could be read of it.
#[allow(clippy::too_many_arguments)]
fn write_error(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
    rel: &str,
    hash: &str,
    size: i64,
    mtime: i64,
    now: i64,
    mtime_ms: i64,
    error: String,
) -> Result<(), String> {
    let updated = conn
        .execute(
            "UPDATE mentor_content SET hash = ?3, size = ?4, mtime_ns = ?5, error = ?6, indexed_at = ?7
             WHERE agent_id = ?1 AND rel_path = ?2",
            params![ctx.agent, rel, hash, size, mtime, error, now],
        )
        .map_err(|e| e.to_string())?;
    if updated > 0 {
        return Ok(());
    }
    conn.execute(
        "INSERT INTO mentor_content
           (agent_id, kind, id, rel_path, title, meta_json, hash, size, mtime_ns, error,
            created_at, updated_at, indexed_at)
         VALUES (?1, ?2, ?3, ?4, ?3, '{}', ?5, ?6, ?7, ?8, ?9, ?9, ?10)",
        params![
            ctx.agent,
            kind.as_str(),
            id,
            rel,
            hash,
            size,
            mtime,
            error,
            mtime_ms,
            now
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// A PDF source is indexed from its sidecar and the PDF beside it: either
/// file changing re-reads the pair.
fn index_pdf_file(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
    sidecar: &Path,
    rel: &str,
    force: bool,
) -> Result<Change, String> {
    let sidecar_meta = match std::fs::metadata(sidecar) {
        Ok(meta) if meta.is_file() => meta,
        Ok(_) => return Ok(Change::Unchanged),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return forget_path(conn, &ctx.agent, rel);
        }
        Err(e) => return Err(format!("{}: {e}", sidecar.display())),
    };
    // The canonical name is `<id>.pdf`; a hand-named pair may differ in case.
    let pdf_path = pdf::pdf_beside_sidecar(sidecar).unwrap_or_else(|| sidecar.with_extension(""));
    let pdf_meta = std::fs::metadata(&pdf_path)
        .ok()
        .filter(std::fs::Metadata::is_file);
    let (side_size, side_mtime) = stamp(&sidecar_meta);
    let (pdf_size, pdf_mtime) = pdf_meta.as_ref().map(stamp).unwrap_or((0, i64::MIN));
    let size = side_size.saturating_add(pdf_size);
    let mtime = side_mtime.max(pdf_mtime);
    let previous = row_stamp(conn, &ctx.agent, rel).map_err(|e| e.to_string())?;
    if !force
        && previous
            .as_ref()
            .is_some_and(|(s, m, _)| *s == size && *m == mtime)
    {
        return Ok(Change::Unchanged);
    }
    let now = now_millis();
    let mtime_ms = mtime / 1_000_000;
    let bytes = match std::fs::read(sidecar) {
        Ok(bytes) => bytes,
        Err(e) => {
            write_error(
                conn,
                ctx,
                kind,
                id,
                rel,
                "",
                size,
                mtime,
                now,
                mtime_ms,
                e.to_string(),
            )?;
            return Ok(Change::Changed);
        }
    };
    // The PDF's bytes are not hashed twice: its size and time already moved.
    let mut key = bytes.clone();
    key.extend_from_slice(&pdf_size.to_le_bytes());
    key.extend_from_slice(&pdf_mtime.to_le_bytes());
    let hash = sha256(&key);
    if previous.as_ref().is_some_and(|(_, _, h)| *h == hash) {
        conn.execute(
            "UPDATE mentor_content SET size = ?3, mtime_ns = ?4 WHERE agent_id = ?1 AND rel_path = ?2",
            params![ctx.agent, rel, size, mtime],
        )
        .map_err(|e| e.to_string())?;
        return Ok(Change::Unchanged);
    }
    let text = match String::from_utf8(bytes) {
        Ok(text) => text,
        Err(_) => {
            write_error(
                conn,
                ctx,
                kind,
                id,
                rel,
                &hash,
                size,
                mtime,
                now,
                mtime_ms,
                "Not UTF-8 text".into(),
            )?;
            return Ok(Change::Changed);
        }
    };
    match parse_pdf_source(id, &text, &pdf_path) {
        Ok(parsed) => {
            write_row(
                conn, ctx, kind, id, rel, &hash, size, mtime, now, mtime_ms, parsed,
            )?;
        }
        Err(error) => write_error(
            conn, ctx, kind, id, rel, &hash, size, mtime, now, mtime_ms, error,
        )?,
    }
    Ok(Change::Changed)
}

/// Indexes one file (or forgets it when it is gone). `force` re-reads it
/// even when its size and time look unchanged.
pub fn index_file(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
    path: &Path,
    force: bool,
) -> Result<Change, String> {
    let rel = rel_path(kind, path);
    if paths::is_pdf_sidecar(path) {
        return index_pdf_file(conn, ctx, kind, id, path, &rel, force);
    }
    let meta = match std::fs::metadata(path) {
        Ok(meta) if meta.is_file() => meta,
        Ok(_) => return Ok(Change::Unchanged),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return forget_path(conn, &ctx.agent, &rel);
        }
        Err(e) => return Err(format!("{}: {e}", path.display())),
    };
    let (size, mtime) = stamp(&meta);
    let previous = row_stamp(conn, &ctx.agent, &rel).map_err(|e| e.to_string())?;
    if !force
        && previous
            .as_ref()
            .is_some_and(|(s, m, _)| *s == size && *m == mtime)
    {
        return Ok(Change::Unchanged);
    }
    let limit = if kind.searchable() {
        TEXT_MAX
    } else {
        DATA_MAX
    };
    let now = now_millis();
    let mtime_ms = mtime / 1_000_000;
    if size as u64 > limit {
        write_error(
            conn,
            ctx,
            kind,
            id,
            &rel,
            "",
            size,
            mtime,
            now,
            mtime_ms,
            format!("Too large ({} KB); split it", size / 1024),
        )?;
        return Ok(Change::Changed);
    }
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) => {
            write_error(
                conn,
                ctx,
                kind,
                id,
                &rel,
                "",
                size,
                mtime,
                now,
                mtime_ms,
                e.to_string(),
            )?;
            return Ok(Change::Changed);
        }
    };
    let hash = sha256(&bytes);
    if previous.as_ref().is_some_and(|(_, _, h)| *h == hash) {
        conn.execute(
            "UPDATE mentor_content SET size = ?3, mtime_ns = ?4 WHERE agent_id = ?1 AND rel_path = ?2",
            params![ctx.agent, rel, size, mtime],
        )
        .map_err(|e| e.to_string())?;
        return Ok(Change::Unchanged);
    }
    let text = match String::from_utf8(bytes) {
        Ok(text) => text,
        Err(_) => {
            write_error(
                conn,
                ctx,
                kind,
                id,
                &rel,
                &hash,
                size,
                mtime,
                now,
                mtime_ms,
                "Not UTF-8 text".into(),
            )?;
            return Ok(Change::Changed);
        }
    };
    match parse(kind, id, &text, ctx) {
        Ok(parsed) => {
            write_row(
                conn, ctx, kind, id, &rel, &hash, size, mtime, now, mtime_ms, parsed,
            )?;
        }
        Err(error) => write_error(
            conn, ctx, kind, id, &rel, &hash, size, mtime, now, mtime_ms, error,
        )?,
    }
    Ok(Change::Changed)
}

fn forget_path(conn: &Connection, agent: &str, rel: &str) -> Result<Change, String> {
    let removed = conn
        .execute(
            "DELETE FROM mentor_content WHERE agent_id = ?1 AND rel_path = ?2",
            params![agent, rel],
        )
        .map_err(|e| e.to_string())?;
    Ok(if removed > 0 {
        Change::Removed
    } else {
        Change::Unchanged
    })
}

/// Forgets every row of a mentor (its folder is gone or it was removed).
pub fn forget_mentor(conn: &Connection, agent: &str) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM mentor_content WHERE agent_id = ?1", [agent])?;
    Ok(())
}

/// Brings a mentor's rows in line with its folder: new and changed files are
/// read, rows of files that are gone are dropped. Only the five content
/// folders are looked at, never `repos/` or `lab/`.
pub fn reconcile(
    conn: &Connection,
    ctx: &MentorCtx,
) -> Result<Vec<(Kind, String, Change)>, String> {
    let mut seen = std::collections::HashSet::new();
    let mut changes = Vec::new();
    for kind in KINDS {
        let dir = ctx.folder.join(kind.dir());
        let entries = match std::fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(format!("{}: {e}", dir.display())),
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some((found, id)) = classify(&ctx.folder, &path) else {
                continue;
            };
            if found != kind {
                continue;
            }
            seen.insert(rel_path(kind, &path));
            let change = index_file(conn, ctx, kind, &id, &path, false)?;
            if change != Change::Unchanged {
                changes.push((kind, id, change));
            }
        }
    }
    let rows: Vec<(String, String, String)> = {
        let mut statement = conn
            .prepare("SELECT rel_path, kind, id FROM mentor_content WHERE agent_id = ?1")
            .map_err(|e| e.to_string())?;
        let rows = statement
            .query_map([&ctx.agent], |row| {
                Ok((row.get(0)?, row.get(1)?, row.get(2)?))
            })
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<_, _>>().map_err(|e| e.to_string())?
    };
    for (rel, kind, id) in rows {
        if !seen.contains(&rel) {
            forget_path(conn, &ctx.agent, &rel)?;
            if let Some(kind) = Kind::parse(&kind) {
                changes.push((kind, id, Change::Removed));
            }
        }
    }
    Ok(changes)
}

const ROW_COLUMNS: &str =
    "agent_id, kind, id, rel_path, title, subject, meta_json, hash, error, created_at, updated_at";

fn read_row(row: &rusqlite::Row<'_>, with_body: bool) -> rusqlite::Result<Row> {
    let meta: String = row.get(6)?;
    Ok(Row {
        agent_id: row.get(0)?,
        kind: row.get(1)?,
        id: row.get(2)?,
        rel_path: row.get(3)?,
        title: row.get(4)?,
        subject: row.get(5)?,
        meta: serde_json::from_str(&meta).unwrap_or(Value::Null),
        hash: row.get(7)?,
        error: row.get(8)?,
        created_at: row.get(9)?,
        updated_at: row.get(10)?,
        body: if with_body { row.get(11)? } else { None },
    })
}

/// A mentor's rows of these kinds, newest first, without their text.
pub fn list(conn: &Connection, agent: &str, kinds: &[Kind]) -> rusqlite::Result<Vec<Row>> {
    let mut out = Vec::new();
    let mut statement = conn.prepare(&format!(
        "SELECT {ROW_COLUMNS} FROM mentor_content WHERE agent_id = ?1 AND kind = ?2
         ORDER BY updated_at DESC, id"
    ))?;
    for kind in kinds {
        let rows =
            statement.query_map(params![agent, kind.as_str()], |row| read_row(row, false))?;
        for row in rows {
            out.push(row?);
        }
    }
    out.sort_by(|a, b| b.updated_at.cmp(&a.updated_at).then(a.id.cmp(&b.id)));
    Ok(out)
}

pub fn get(conn: &Connection, agent: &str, kind: Kind, id: &str) -> rusqlite::Result<Option<Row>> {
    conn.query_row(
        &format!(
            "SELECT {ROW_COLUMNS}, body FROM mentor_content WHERE agent_id = ?1 AND kind = ?2 AND id = ?3"
        ),
        params![agent, kind.as_str(), id],
        |row| read_row(row, true),
    )
    .optional()
}

/// A note or canvas by id alone, whichever mentor keeps it.
pub fn find(conn: &Connection, kind: Kind, id: &str) -> rusqlite::Result<Option<Row>> {
    conn.query_row(
        &format!(
            "SELECT {ROW_COLUMNS}, body FROM mentor_content c WHERE kind = ?1 AND id = ?2
               AND EXISTS (SELECT 1 FROM mentors m WHERE m.id = c.agent_id AND m.migrated_at IS NOT NULL)"
        ),
        params![kind.as_str(), id],
        |row| read_row(row, true),
    )
    .optional()
}

/// Every row of a kind, for the lists that span mentors.
pub fn all(conn: &Connection, kind: Kind) -> rusqlite::Result<Vec<Row>> {
    let mut statement = conn.prepare(&format!(
        "SELECT {ROW_COLUMNS}, body FROM mentor_content c WHERE kind = ?1
           AND EXISTS (SELECT 1 FROM mentors m WHERE m.id = c.agent_id AND m.migrated_at IS NOT NULL)
         ORDER BY updated_at DESC, id"
    ))?;
    let rows = statement.query_map([kind.as_str()], |row| read_row(row, true))?;
    rows.collect()
}

/// Files the index could not read, or read with a warning.
pub fn problems(conn: &Connection, agent: &str) -> rusqlite::Result<Vec<Row>> {
    let mut statement = conn.prepare(&format!(
        "SELECT {ROW_COLUMNS} FROM mentor_content WHERE agent_id = ?1 AND error IS NOT NULL ORDER BY rel_path"
    ))?;
    let rows = statement.query_map([agent], |row| read_row(row, false))?;
    rows.collect()
}

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Hit {
    pub agent_id: String,
    pub kind: String,
    pub id: String,
    pub title: String,
    pub snippet: String,
}

/// Full-text search over titles and the text of sources, guides and notes.
/// Any script works (trigram index); a query under three characters falls
/// back to matching titles and text by substring.
pub fn search(
    conn: &Connection,
    agent: Option<&str>,
    query: &str,
    limit: usize,
) -> rusqlite::Result<Vec<Hit>> {
    let query = query.trim();
    if query.is_empty() {
        return Ok(Vec::new());
    }
    let limit = limit.clamp(1, 200) as i64;
    let read = |row: &rusqlite::Row<'_>| {
        Ok(Hit {
            agent_id: row.get(0)?,
            kind: row.get(1)?,
            id: row.get(2)?,
            title: row.get(3)?,
            snippet: row.get::<_, Option<String>>(4)?.unwrap_or_default(),
        })
    };
    if query.chars().count() < 3 {
        let like = format!("%{}%", query.replace(['%', '_'], ""));
        let mut statement = conn.prepare(
            "SELECT agent_id, kind, id, title, substr(coalesce(body, ''), 1, 160) FROM mentor_content
             WHERE (?1 IS NULL OR agent_id = ?1) AND (title LIKE ?2 OR (kind IN ('source','guide','note') AND body LIKE ?2))
             ORDER BY updated_at DESC LIMIT ?3",
        )?;
        let rows = statement.query_map(params![agent, like, limit], read)?;
        return rows.collect();
    }
    let phrase = format!("\"{}\"", query.replace('"', "\"\""));
    let mut statement = conn.prepare(
        "SELECT c.agent_id, c.kind, c.id, c.title,
                snippet(mentor_content_fts, 1, '[', ']', '…', 12)
         FROM mentor_content_fts f JOIN mentor_content c ON c.seq = f.rowid
         WHERE mentor_content_fts MATCH ?1 AND (?2 IS NULL OR c.agent_id = ?2)
         ORDER BY rank LIMIT ?3",
    )?;
    let rows = statement.query_map(params![phrase, agent, limit], read)?;
    rows.collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session_store::SessionStore;
    use std::path::PathBuf;

    fn temp() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("loci-index-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn ctx(folder: &Path) -> MentorCtx {
        MentorCtx {
            agent: "a1".into(),
            folder: folder.to_path_buf(),
            workdir: None,
        }
    }

    fn write(folder: &Path, rel: &str, text: &str) {
        let path = folder.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    #[test]
    fn reconcile_reads_new_changed_and_removed_files_and_keeps_the_last_good_parse() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp();
        let ctx = ctx(&folder);
        write(
            &folder,
            "sources/virtio.md",
            "---\ntitle: Virtio\nsourceUrl: https://x.org/v\n---\nqueues and rings\n",
        );
        write(&folder, "guides/g.md", "# A guide\ntext");
        write(&folder, "courses/c.yaml", "title: C\nchapters:\n  - title: One\n    lessons:\n      - id: l1\n        title: L\n        document: virtio\n");
        write(
            &folder,
            "notes/n1.md",
            "---\ntitle: N\ntags: [a]\n---\nnote",
        );
        write(
            &folder,
            "canvases/k.excalidraw",
            r#"{"elements":[],"loci":{"title":"K"}}"#,
        );
        write(&folder, "repos/x/README.md", "ignored");
        write(&folder, "sources/.virtio.md.swp", "ignored");
        let changes = reconcile(&conn, &ctx).unwrap();
        assert_eq!(changes.len(), 5);
        let docs = list(&conn, "a1", &[Kind::Source, Kind::Guide]).unwrap();
        assert_eq!(docs.len(), 2);
        let guide = get(&conn, "a1", Kind::Guide, "g").unwrap().unwrap();
        assert_eq!(guide.title, "A guide");
        assert!(reconcile(&conn, &ctx).unwrap().is_empty());

        // A broken edit keeps the last good title and text.
        write(&folder, "sources/virtio.md", "---\ntitle: [broken\n---\n");
        index_file(
            &conn,
            &ctx,
            Kind::Source,
            "virtio",
            &folder.join("sources/virtio.md"),
            true,
        )
        .unwrap();
        let source = get(&conn, "a1", Kind::Source, "virtio").unwrap().unwrap();
        assert_eq!(source.title, "Virtio");
        assert_eq!(source.body.as_deref(), Some("queues and rings\n"));
        assert!(source.error.unwrap().contains("YAML"));
        assert_eq!(problems(&conn, "a1").unwrap().len(), 1);

        std::fs::remove_file(folder.join("guides/g.md")).unwrap();
        let changes = reconcile(&conn, &ctx).unwrap();
        assert!(changes.contains(&(Kind::Guide, "g".into(), Change::Removed)));
        assert!(get(&conn, "a1", Kind::Guide, "g").unwrap().is_none());
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn a_pdf_source_is_listed_searched_and_keeps_its_pair_in_step() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp();
        let ctx = ctx(&folder);
        write(
            &folder,
            "sources/firecracker.pdf.yaml",
            "title: 'Firecracker: Lightweight Virtualization'\nsourceUrl: https://www.usenix.org/system/files/nsdi20-paper-agache.pdf\nversion: NSDI '20\nsubject: Virtualization\npages: 2\n",
        );
        std::fs::write(
            folder.join("sources/firecracker.pdf"),
            super::pdf::sample_pdf(&["Sandbox page one", "Sandbox page two"]),
        )
        .unwrap();
        reconcile(&conn, &ctx).unwrap();
        let row = get(&conn, "a1", Kind::Source, "firecracker")
            .unwrap()
            .unwrap();
        assert_eq!(row.title, "Firecracker: Lightweight Virtualization");
        assert_eq!(row.subject.as_deref(), Some("Virtualization"));
        assert_eq!(row.meta["pdf"], json!(true));
        assert_eq!(row.meta["pages"], json!(2));
        assert_eq!(row.meta["version"], json!("NSDI '20"));
        assert_eq!(row.rel_path, "sources/firecracker.pdf.yaml");
        let body = row.body.unwrap();
        assert!(body.contains("Sandbox page one"));
        assert!(body.contains("Sandbox page two"));
        assert_eq!(
            search(&conn, Some("a1"), "sandbox page two", 10).unwrap()[0].id,
            "firecracker"
        );

        // The PDF alone changing is noticed, and its page count follows.
        std::fs::write(
            folder.join("sources/firecracker.pdf"),
            super::pdf::sample_pdf(&["Sandbox page one"]),
        )
        .unwrap();
        let changes = reconcile(&conn, &ctx).unwrap();
        assert!(changes.contains(&(Kind::Source, "firecracker".into(), Change::Changed)));
        let row = get(&conn, "a1", Kind::Source, "firecracker")
            .unwrap()
            .unwrap();
        assert_eq!(row.meta["pages"], json!(1));
        assert!(!row.body.unwrap().contains("Sandbox page two"));

        // A missing PDF leaves the source listed, with what is wrong.
        std::fs::remove_file(folder.join("sources/firecracker.pdf")).unwrap();
        reconcile(&conn, &ctx).unwrap();
        let row = get(&conn, "a1", Kind::Source, "firecracker")
            .unwrap()
            .unwrap();
        assert!(row.error.unwrap().contains("firecracker.pdf is missing"));
        assert_eq!(row.title, "Firecracker: Lightweight Virtualization");
        assert_eq!(problems(&conn, "a1").unwrap().len(), 1);

        // The sidecar going away forgets the source; the PDF is left for check.
        std::fs::remove_file(folder.join("sources/firecracker.pdf.yaml")).unwrap();
        reconcile(&conn, &ctx).unwrap();
        assert!(get(&conn, "a1", Kind::Source, "firecracker")
            .unwrap()
            .is_none());
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn search_finds_words_in_any_script() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp();
        let ctx = ctx(&folder);
        write(&folder, "sources/kvm.md", "---\ntitle: KVM API\nsourceUrl: https://k.org\n---\nThe ioctl KVM_CREATE_VM makes a virtual machine.\n");
        write(
            &folder,
            "notes/n.md",
            "---\ntitle: 笔记\n---\n虚拟机快照与恢复",
        );
        reconcile(&conn, &ctx).unwrap();
        let hits = search(&conn, Some("a1"), "create_vm", 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].id, "kvm");
        assert!(
            hits[0].snippet.contains("[KVM_CREATE_VM]") || hits[0].snippet.contains("CREATE_VM")
        );
        assert_eq!(search(&conn, Some("a1"), "快照与", 10).unwrap()[0].id, "n");
        assert_eq!(search(&conn, Some("a1"), "笔记", 10).unwrap()[0].id, "n");
        assert!(search(&conn, Some("other"), "create_vm", 10)
            .unwrap()
            .is_empty());
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn ids_some_kinds_cannot_take_are_flagged_not_dropped() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp();
        write(&folder, "notes/笔记.md", "x");
        reconcile(&conn, &ctx(&folder)).unwrap();
        let rows = problems(&conn, "a1").unwrap();
        assert_eq!(rows.len(), 1);
        assert!(rows[0].error.as_deref().unwrap().contains("Rename"));
        std::fs::remove_dir_all(folder).unwrap();
    }

    #[test]
    fn thousands_of_files_reconcile_quickly_when_nothing_changed() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp();
        let ctx = ctx(&folder);
        for i in 0..3000 {
            write(
                &folder,
                &format!("guides/g{i}.md"),
                &format!("# Guide {i}\nbody {i}"),
            );
        }
        reconcile(&conn, &ctx).unwrap();
        let started = std::time::Instant::now();
        assert!(reconcile(&conn, &ctx).unwrap().is_empty());
        // Generous: this runs beside other builds; a cold walk is ~50 ms.
        assert!(started.elapsed() < std::time::Duration::from_secs(10));
        let listed = std::time::Instant::now();
        assert_eq!(list(&conn, "a1", &[Kind::Guide]).unwrap().len(), 3000);
        assert!(listed.elapsed() < std::time::Duration::from_secs(5));
        std::fs::remove_dir_all(folder).unwrap();
    }
}
