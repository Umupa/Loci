//! One mentor = one folder (v0.4).
//!
//! A mentor's content (sources, guides, courses, notes, canvases, Soul and
//! memory) lives as files in `<mentors root>/<slug>/`. Rust owns those files:
//! it writes them atomically, indexes them in SQLite for fast listing and
//! search, and watches them so edits made outside the app (by the mentor's
//! CLI, or the user's editor) show up live. SQLite keeps what changes often
//! or is not portable: conversations, progress, annotations, view state.
//!
//! The commands the window has always called (`agent_documents_*`,
//! `course_*`, `notes_*`, `canvas_*`, `agent_*`) keep their names and payloads;
//! for a mentor whose content is in its folder they read and write files, and
//! for anything else (a mentor not migrated yet, a note with no mentor, a
//! project canvas) they read the old tables as before.

pub mod bundle;
pub mod commands;
pub mod format;
pub mod fsio;
pub mod index;
pub mod migrate;
pub mod paths;
pub mod pdf;
pub mod registry;
pub mod watch;

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rusqlite::Connection;

use index::{Change, Row};
use paths::{content_path, relative_inside, Kind};

/// The mentors root of this build, set at startup.
pub struct MentorsRoot(pub Mutex<PathBuf>);

impl MentorsRoot {
    pub fn path(&self) -> PathBuf {
        self.0.lock().map(|p| p.clone()).unwrap_or_default()
    }
}

/// A mentor whose content lives in files: where, and what to resolve against.
#[derive(Debug, Clone)]
pub struct MentorCtx {
    pub agent: String,
    pub folder: PathBuf,
    /// The user's own workdir, when it is not the folder.
    pub workdir: Option<PathBuf>,
}

impl MentorCtx {
    pub fn path(&self, kind: Kind, id: &str) -> PathBuf {
        content_path(&self.folder, kind, id)
    }

    /// A lesson's relative `file:`: in the mentor's folder, else in its workdir.
    pub fn resolve_lesson_file(&self, relative: &str) -> Result<String, String> {
        let inside = relative_inside(&self.folder, relative)?;
        if !inside.exists() {
            if let Some(workdir) = &self.workdir {
                let there = relative_inside(workdir, relative)?;
                if there.exists() {
                    return Ok(there.to_string_lossy().into_owned());
                }
            }
        }
        Ok(inside.to_string_lossy().into_owned())
    }

    /// An absolute path inside the folder, as the folder-relative path a
    /// course file keeps; anything else stays as it is.
    pub fn relativize(&self, path: &str) -> String {
        Path::new(path)
            .strip_prefix(&self.folder)
            .ok()
            .and_then(|rel| rel.to_str())
            .filter(|rel| !rel.is_empty())
            .map_or_else(|| path.to_string(), str::to_string)
    }
}

/// The context of an agent whose content is in its folder, if it is one.
pub fn ctx_for(conn: &Connection, agent: &str) -> Result<Option<MentorCtx>, String> {
    let Some(folder) = registry::active_folder(conn, agent).map_err(|e| e.to_string())? else {
        return Ok(None);
    };
    let workdir = registry::read_identity(&folder)
        .ok()
        .and_then(|identity| registry::custom_workdir(&folder, &identity));
    Ok(Some(MentorCtx {
        agent: agent.to_string(),
        folder,
        workdir,
    }))
}

/// Whether a 0.3 row of this agent is still read from its table: always for
/// rows with no mentor or a mentor not migrated, and for rows changed after
/// the mentor's migration (they come into the folder on the next start).
pub fn legacy_visible(
    conn: &Connection,
    agent: Option<&str>,
    updated_at: i64,
) -> Result<bool, String> {
    let Some(agent) = agent else { return Ok(true) };
    Ok(
        match registry::get(conn, agent).map_err(|e| e.to_string())? {
            Some(record) => record.migrated_at.is_none_or(|at| updated_at > at),
            None => true,
        },
    )
}

/// Where a row's file is (it may be `.yml`, not the `.yaml` the app writes).
pub fn row_path(ctx: &MentorCtx, row: &Row) -> PathBuf {
    ctx.folder.join(&row.rel_path)
}

/// Re-reads one file when it changed on disk and returns its row, so a read
/// never shows text older than the file even before the watcher reports it.
pub fn current(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
) -> Result<Option<Row>, String> {
    let path = index::get(conn, &ctx.agent, kind, id)
        .map_err(|e| e.to_string())?
        .map_or_else(|| ctx.path(kind, id), |row| row_path(ctx, &row));
    index::index_file(conn, ctx, kind, id, &path, false)?;
    index::get(conn, &ctx.agent, kind, id).map_err(|e| e.to_string())
}

/// Writes a content file and indexes it before returning, so the watcher's
/// echo of this write finds nothing new and reports nothing.
pub fn write_content(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
    text: &str,
) -> Result<Row, String> {
    let path = index::get(conn, &ctx.agent, kind, id)
        .map_err(|e| e.to_string())?
        .map_or_else(|| ctx.path(kind, id), |row| row_path(ctx, &row));
    fsio::write_atomic(&path, text.as_bytes())?;
    index::index_file(conn, ctx, kind, id, &path, true)?;
    let row = index::get(conn, &ctx.agent, kind, id)
        .map_err(|e| e.to_string())?
        .ok_or("The saved file is missing from the index")?;
    if let Some(error) = row
        .error
        .as_ref()
        .filter(|_| row.hash != fsio::sha256(text.as_bytes()))
    {
        return Err(error.clone());
    }
    Ok(row)
}

/// Takes a PDF in as `sources/<id>.pdf` with its sidecar, and indexes the
/// pair. The PDF's text is read here, so the write reports what the index has.
pub fn write_pdf_source(
    conn: &Connection,
    ctx: &MentorCtx,
    id: &str,
    bytes: &[u8],
    meta: &pdf::PdfMeta,
) -> Result<Row, String> {
    let pdf_path = paths::pdf_source_path(&ctx.folder, id);
    let sidecar = paths::existing_pdf_sidecar(&ctx.folder, id)
        .unwrap_or_else(|| paths::pdf_sidecar_path(&ctx.folder, id));
    fsio::write_atomic(&pdf_path, bytes)?;
    let existing = std::fs::read_to_string(&sidecar)
        .ok()
        .and_then(|text| pdf::parse_sidecar(&text).ok().map(|(_, map)| map));
    let mut meta = meta.clone();
    if meta.pages.is_none() {
        meta.pages = pdf::page_count(&pdf_path).ok().filter(|pages| *pages > 0);
    }
    let text = pdf::render_sidecar(existing, &meta)?;
    fsio::write_atomic(&sidecar, text.as_bytes())?;
    index::index_file(conn, ctx, Kind::Source, id, &sidecar, true)?;
    index::get(conn, &ctx.agent, Kind::Source, id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "The saved source is missing from the index".to_string())
}

/// Removes a PDF source's two files. The index forgets the row with the sidecar.
pub fn remove_pdf_source(conn: &Connection, ctx: &MentorCtx, id: &str) -> Result<bool, String> {
    let sidecar = index::get(conn, &ctx.agent, Kind::Source, id)
        .map_err(|e| e.to_string())?
        .map(|row| row_path(ctx, &row))
        .unwrap_or_else(|| paths::pdf_sidecar_path(&ctx.folder, id));
    let mut existed = false;
    for path in [
        sidecar.clone(),
        pdf::pdf_beside_sidecar(&sidecar)
            .unwrap_or_else(|| paths::pdf_source_path(&ctx.folder, id)),
    ] {
        match std::fs::remove_file(&path) {
            Ok(()) => existed = true,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("{}: {e}", path.display())),
        }
    }
    index::index_file(conn, ctx, Kind::Source, id, &sidecar, true)?;
    Ok(existed)
}

/// Removes a content file the user or the mentor asked to delete.
pub fn remove_content(
    conn: &Connection,
    ctx: &MentorCtx,
    kind: Kind,
    id: &str,
) -> Result<bool, String> {
    let path = index::get(conn, &ctx.agent, kind, id)
        .map_err(|e| e.to_string())?
        .map_or_else(|| ctx.path(kind, id), |row| row_path(ctx, &row));
    let existed = match std::fs::remove_file(&path) {
        Ok(()) => true,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => false,
        Err(e) => return Err(format!("{}: {e}", path.display())),
    };
    let change = index::index_file(conn, ctx, kind, id, &path, true)?;
    Ok(existed || change == Change::Removed)
}

/// The current time as a file name part: `20261101-091200`.
pub fn stamp_now() -> String {
    let iso = fsio::iso_from_millis(crate::session_store::now_millis());
    format!(
        "{}{}{}-{}{}{}",
        &iso[0..4],
        &iso[5..7],
        &iso[8..10],
        &iso[11..13],
        &iso[14..16],
        &iso[17..19]
    )
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use crate::session_store::now_millis;

    pub fn temp_dir(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("loci-{label}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Registers `agent` as a mentor whose content is in `folder`.
    pub fn register(conn: &Connection, agent: &str, folder: &Path) {
        std::fs::create_dir_all(folder).unwrap();
        let mut identity = serde_json::Map::new();
        identity.insert("schemaVersion".into(), 1.into());
        identity.insert("id".into(), agent.into());
        registry::write_identity(folder, &identity).unwrap();
        registry::upsert(
            conn,
            &registry::MentorRecord {
                id: agent.into(),
                folder: folder.to_path_buf(),
                session_id: None,
                position: 0,
                local: serde_json::Map::new(),
                migrated_at: Some(now_millis()),
                added_at: now_millis(),
            },
        )
        .unwrap();
    }
}
