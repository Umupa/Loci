use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};

use crate::fs::expand_home;
use crate::mentor_store::{self, format, index, paths::Kind, MentorCtx};
use crate::session_store::{now_millis, validate_id, SessionStore};

const TITLE_MAX: usize = 200;
const BODY_MAX: usize = 1_000_000;
const TAG_MAX: usize = 48;
const TAGS_MAX: usize = 20;
const IMAGE_MAX_BYTES: u64 = 20 * 1024 * 1024;
const IMAGE_EXTENSIONS: [&str; 6] = ["png", "jpg", "jpeg", "gif", "webp", "svg"];
const NOTE_ASSET_DIR: &str = "note-assets";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: String,
    pub slug: String,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_cwd: Option<String>,
    /// Stable agent ownership, independent of conversation resets.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
    /// Only notes created with a blank title may replace their generated slug once.
    pub slug_pending: bool,
    pub created_at: i64,
    pub updated_at: i64,
    /// The hash of the note's file, for a note kept in a mentor's folder.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hash: Option<String>,
    /// Set when the file had changed on disk since it was read: the disk
    /// version was kept beside it as this file before the save went through.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub conflict_copy: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteUpsert {
    pub id: String,
    pub title: String,
    pub body: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub source_session_id: Option<String>,
    #[serde(default)]
    pub source_cwd: Option<String>,
    #[serde(default)]
    pub agent_id: Option<String>,
    /// Finalize a pending slug on title blur or editor close, not a debounced save.
    #[serde(default)]
    pub finalize_slug: bool,
    /// The file hash the editor last saw, for a note kept in a mentor's folder.
    #[serde(default)]
    pub expected_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteImageAsset {
    pub name: String,
    pub markdown_path: String,
}

pub fn ensure_notes_table(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS notes (
           id TEXT PRIMARY KEY,
           slug TEXT NOT NULL UNIQUE,
           title TEXT NOT NULL,
           body TEXT NOT NULL DEFAULT '',
           tags_json TEXT NOT NULL DEFAULT '[]',
           source_session_id TEXT,
           source_cwd TEXT,
           slug_pending INTEGER NOT NULL DEFAULT 0,
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS notes_updated_idx
           ON notes (updated_at DESC, id);",
    )?;
    let tags_present: i64 = conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('notes') WHERE name = 'tags_json'",
        [],
        |row| row.get(0),
    )?;
    if tags_present == 0 {
        conn.execute(
            "ALTER TABLE notes ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
            [],
        )?;
    }
    let pending_present: i64 = conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('notes') WHERE name = 'slug_pending'",
        [],
        |row| row.get(0),
    )?;
    if pending_present == 0 {
        // Existing slugs may already be referenced, including "untitled".
        conn.execute(
            "ALTER TABLE notes ADD COLUMN slug_pending INTEGER NOT NULL DEFAULT 0",
            [],
        )?;
    }
    let agent_present: i64 = conn.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('notes') WHERE name = 'agent_id'",
        [],
        |row| row.get(0),
    )?;
    if agent_present == 0 {
        conn.execute("ALTER TABLE notes ADD COLUMN agent_id TEXT", [])?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Notes a mentor keeps in its folder: notes/<id>.md. Notes with no mentor,
// and notes of mentors not migrated yet, stay in the notes table.

fn note_from_row(row: index::Row) -> Note {
    let meta = &row.meta;
    let text = |key: &str| meta.get(key).and_then(|v| v.as_str()).map(str::to_string);
    Note {
        slug: text("slug").unwrap_or_else(|| row.id.clone()),
        tags: meta
            .get("tags")
            .and_then(|v| v.as_array())
            .map(|tags| {
                tags.iter()
                    .filter_map(|t| t.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default(),
        source_session_id: text("sourceSession"),
        source_cwd: text("sourceCwd"),
        slug_pending: meta
            .get("slugPending")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        agent_id: Some(row.agent_id.clone()),
        title: row.title,
        body: row.body.unwrap_or_default(),
        id: row.id,
        created_at: row.created_at,
        updated_at: row.updated_at,
        hash: Some(row.hash),
        conflict_copy: None,
    }
}

/// A file note by id, read fresh, with its mentor's context.
fn file_note(conn: &Connection, id: &str) -> Result<Option<(MentorCtx, Note)>, String> {
    let Some(row) = index::find(conn, Kind::Note, id).map_err(|e| e.to_string())? else {
        return Ok(None);
    };
    let Some(ctx) = mentor_store::ctx_for(conn, &row.agent_id)? else {
        return Ok(None);
    };
    Ok(mentor_store::current(conn, &ctx, Kind::Note, id)?.map(|row| (ctx, note_from_row(row))))
}

fn file_notes(conn: &Connection, ctx: &MentorCtx) -> Result<Vec<Note>, String> {
    let mut out = Vec::new();
    for row in index::list(conn, &ctx.agent, &[Kind::Note]).map_err(|e| e.to_string())? {
        if let Some(full) =
            index::get(conn, &ctx.agent, Kind::Note, &row.id).map_err(|e| e.to_string())?
        {
            out.push(note_from_row(full));
        }
    }
    Ok(out)
}

fn render(note: &Note) -> Result<String, String> {
    format::render_note(
        None,
        &format::NoteMeta {
            title: Some(note.title.clone()),
            slug: Some(note.slug.clone()),
            slug_pending: note.slug_pending,
            tags: note.tags.clone(),
            created_at: Some(note.created_at),
            updated_at: Some(note.updated_at),
            source_session: note.source_session_id.clone(),
            source_cwd: note.source_cwd.clone(),
        },
        &note.body,
    )
}

/// Writes the note's file. When it changed on disk since the editor read it,
/// the disk version is kept as `notes/<id>.conflict-<time>.md` first.
fn write_file_note(
    conn: &Connection,
    ctx: &MentorCtx,
    note: &Note,
    expected: Option<&str>,
) -> Result<Note, String> {
    let path = ctx.path(Kind::Note, &note.id);
    let mut conflict_copy = None;
    if let Some(expected) = expected {
        if let Ok(current) = std::fs::read(&path) {
            if mentor_store::fsio::sha256(&current) != expected {
                let copy = path.with_file_name(format!(
                    "{}.conflict-{}.md",
                    note.id,
                    mentor_store::stamp_now()
                ));
                mentor_store::fsio::write_atomic(&copy, &current)?;
                conflict_copy = Some(copy.to_string_lossy().into_owned());
            }
        }
    }
    let row = mentor_store::write_content(conn, ctx, Kind::Note, &note.id, &render(note)?)?;
    let mut saved = note_from_row(row);
    saved.conflict_copy = conflict_copy;
    Ok(saved)
}

fn file_upsert_note(
    conn: &Connection,
    ctx: &MentorCtx,
    existing: Option<Note>,
    note: &NoteUpsert,
) -> Result<Note, String> {
    let title = normalize_title(&note.title);
    let body = note.body.replace("\r\n", "\n").replace('\r', "\n");
    let tags = normalize_tags(&note.tags);
    let trimmed = |value: &Option<String>| {
        value
            .as_deref()
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(str::to_string)
    };
    let now = now_millis();
    let next = match existing {
        Some(existing) => {
            let unchanged =
                title == existing.title && body == existing.body && tags == existing.tags;
            let (slug, slug_pending) =
                if note.finalize_slug && existing.slug_pending && !is_placeholder_title(&title) {
                    (unique_slug(conn, &title).map_err(|e| e.to_string())?, false)
                } else {
                    (existing.slug.clone(), existing.slug_pending)
                };
            let source_cwd = trimmed(&note.source_cwd).or(existing.source_cwd.clone());
            if unchanged && slug == existing.slug && source_cwd == existing.source_cwd {
                return Ok(existing);
            }
            Note {
                updated_at: if unchanged { existing.updated_at } else { now },
                title,
                body,
                tags,
                slug,
                slug_pending,
                source_cwd,
                ..existing
            }
        }
        None => Note {
            id: note.id.clone(),
            slug_pending: note.title.trim().is_empty(),
            slug: unique_slug(conn, &title).map_err(|e| e.to_string())?,
            title,
            body,
            tags,
            source_session_id: trimmed(&note.source_session_id),
            source_cwd: trimmed(&note.source_cwd),
            agent_id: Some(ctx.agent.clone()),
            created_at: now,
            updated_at: now,
            hash: None,
            conflict_copy: None,
        },
    };
    write_file_note(conn, ctx, &next, note.expected_hash.as_deref())
}

/// 0.3 rows a mentor's migration turned into files are not shown again; a
/// row written after that (an older Loci after a downgrade) still is, until
/// the next start brings it into the folder.
fn legacy_visible(conn: &Connection, note: &Note) -> Result<bool, String> {
    mentor_store::legacy_visible(conn, note.agent_id.as_deref(), note.updated_at)
}

#[tauri::command(async)]
pub fn notes_list(
    store: State<'_, SessionStore>,
    agent_id: Option<String>,
) -> Result<Vec<Note>, String> {
    if let Some(id) = agent_id.as_deref() {
        validate_id(id, "agent")?;
    }
    let conn = store.lock_conn()?;
    if let Some(agent) = agent_id.as_deref() {
        if let Some(ctx) = mentor_store::ctx_for(&conn, agent)? {
            return file_notes(&conn, &ctx);
        }
        return list_notes(&conn, Some(agent)).map_err(|e| e.to_string());
    }
    let mut notes = Vec::new();
    for note in list_notes(&conn, None).map_err(|e| e.to_string())? {
        if legacy_visible(&conn, &note)? {
            notes.push(note);
        }
    }
    for row in index::all(&conn, Kind::Note).map_err(|e| e.to_string())? {
        notes.push(note_from_row(row));
    }
    notes.sort_by(|a, b| b.updated_at.cmp(&a.updated_at).then(a.id.cmp(&b.id)));
    Ok(notes)
}

#[tauri::command(async)]
pub fn notes_get(store: State<'_, SessionStore>, id: String) -> Result<Option<Note>, String> {
    validate_id(&id, "note")?;
    let conn = store.lock_conn()?;
    if let Some((_, note)) = file_note(&conn, &id)? {
        return Ok(Some(note));
    }
    match get_note(&conn, &id).map_err(|e| e.to_string())? {
        Some(note) if legacy_visible(&conn, &note)? => Ok(Some(note)),
        _ => Ok(None),
    }
}

#[tauri::command(async)]
pub fn notes_upsert(store: State<'_, SessionStore>, note: NoteUpsert) -> Result<Note, String> {
    validate_id(&note.id, "note")?;
    if let Some(session_id) = note.source_session_id.as_deref() {
        if !session_id.is_empty() {
            validate_id(session_id, "session")?;
        }
    }
    if let Some(id) = note.agent_id.as_deref() {
        validate_id(id, "agent")?;
    }
    if note.body.len() > BODY_MAX {
        return Err("Note is too large".into());
    }
    let conn = store.lock_conn()?;
    if let Some((ctx, existing)) = file_note(&conn, &note.id)? {
        return file_upsert_note(&conn, &ctx, Some(existing), &note);
    }
    let legacy = get_note(&conn, &note.id).map_err(|e| e.to_string())?;
    let owner = legacy
        .as_ref()
        .map_or(note.agent_id.clone(), |existing| existing.agent_id.clone());
    if let Some(agent) = owner.as_deref() {
        if let Some(ctx) = mentor_store::ctx_for(&conn, agent)? {
            // A new note of a mentor with a folder, or its 0.3 row edited
            // again after the file was removed: either way it is a file now.
            return file_upsert_note(&conn, &ctx, None, &note);
        }
    }
    upsert_note(&conn, &note).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn notes_finalize_slug(
    store: State<'_, SessionStore>,
    id: String,
    title: String,
) -> Result<Option<Note>, String> {
    validate_id(&id, "note")?;
    let conn = store.lock_conn()?;
    if let Some((ctx, mut note)) = file_note(&conn, &id)? {
        if note.slug_pending
            && note.title == normalize_title(&title)
            && !is_placeholder_title(&note.title)
        {
            note.slug = unique_slug(&conn, &note.title).map_err(|e| e.to_string())?;
            note.slug_pending = false;
            return write_file_note(&conn, &ctx, &note, None).map(Some);
        }
        return Ok(Some(note));
    }
    finalize_note_slug(&conn, &id, &title).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn notes_delete(
    app: AppHandle,
    store: State<'_, SessionStore>,
    id: String,
) -> Result<(), String> {
    validate_id(&id, "note")?;
    let conn = store.lock_conn()?;
    if let Some((ctx, _)) = file_note(&conn, &id)? {
        mentor_store::remove_content(&conn, &ctx, Kind::Note, &id)?;
        return Ok(());
    }
    delete_note(&conn, &id).map_err(|e| e.to_string())?;
    drop(conn);
    // The note deletion is authoritative. A cleanup failure should not leave a
    // successfully deleted note visible in the UI.
    let _ = remove_note_assets(&app, &id);
    Ok(())
}

#[tauri::command]
pub async fn notes_save_image(
    app: AppHandle,
    note_id: String,
    source_path: String,
) -> Result<NoteImageAsset, String> {
    tauri::async_runtime::spawn_blocking(move || save_note_image_sync(&app, &note_id, &source_path))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command(async)]
pub fn notes_image_path(app: AppHandle, asset: String) -> Result<String, String> {
    let relative = validate_note_asset_path(&asset)?;
    let path = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join(relative);
    if !path.is_file() {
        return Err("Note image was not found".into());
    }
    Ok(path.to_string_lossy().into_owned())
}

fn note_assets_dir(app: &AppHandle, note_id: &str) -> Result<PathBuf, String> {
    validate_id(note_id, "note")?;
    Ok(app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join(NOTE_ASSET_DIR)
        .join(note_id))
}

fn save_note_image_sync(
    app: &AppHandle,
    note_id: &str,
    source_path: &str,
) -> Result<NoteImageAsset, String> {
    let source = expand_home(source_path);
    let meta = std::fs::metadata(&source).map_err(|e| format!("{}: {e}", source.display()))?;
    if !meta.is_file() {
        return Err("Not a file".into());
    }
    if meta.len() > IMAGE_MAX_BYTES {
        return Err(format!(
            "Image is too large (maximum {} MB).",
            IMAGE_MAX_BYTES / 1024 / 1024
        ));
    }

    let (display_name, safe_name) = note_image_names(&source)?;
    let dir = note_assets_dir(app, note_id)?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let stored_name = format!("{stamp}-{safe_name}");
    let destination = dir.join(&stored_name);
    std::fs::copy(&source, &destination).map_err(|e| format!("{}: {e}", destination.display()))?;

    Ok(NoteImageAsset {
        name: display_name,
        markdown_path: format!("/{NOTE_ASSET_DIR}/{note_id}/{stored_name}"),
    })
}

fn note_image_names(source: &Path) -> Result<(String, String), String> {
    let extension = source
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !IMAGE_EXTENSIONS.contains(&extension.as_str()) {
        return Err("Image must be a PNG, JPG, GIF, WebP, or SVG file.".into());
    }
    let display_name = source
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("image")
        .to_string();
    let stem = source
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("image");
    let mut safe_stem: String = stem
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '-'
            }
        })
        .take(80)
        .collect();
    safe_stem = safe_stem.trim_matches('-').to_string();
    if safe_stem.is_empty() {
        safe_stem = "image".into();
    }
    Ok((display_name, format!("{safe_stem}.{extension}")))
}

fn validate_note_asset_path(asset: &str) -> Result<PathBuf, String> {
    let relative = asset
        .strip_prefix('/')
        .ok_or_else(|| "Invalid note image path".to_string())?;
    let path = Path::new(relative);
    let parts = path
        .components()
        .map(|part| match part {
            Component::Normal(value) => value.to_str().map(str::to_string),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()
        .ok_or_else(|| "Invalid note image path".to_string())?;
    if parts.len() != 3 || parts[0] != NOTE_ASSET_DIR {
        return Err("Invalid note image path".into());
    }
    validate_id(&parts[1], "note")?;
    if parts[2].is_empty()
        || !parts[2]
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
    {
        return Err("Invalid note image path".into());
    }
    Ok(path.to_path_buf())
}

fn remove_note_assets(app: &AppHandle, note_id: &str) -> Result<(), String> {
    let dir = note_assets_dir(app, note_id)?;
    match std::fs::remove_dir_all(dir) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

fn list_notes(conn: &Connection, agent_id: Option<&str>) -> rusqlite::Result<Vec<Note>> {
    let mut stmt = conn.prepare(
        "SELECT id, slug, title, body, source_session_id, source_cwd, tags_json,
                created_at, updated_at, slug_pending, agent_id
         FROM notes
         WHERE (?1 IS NULL OR agent_id = ?1)
         ORDER BY updated_at DESC, id ASC",
    )?;
    let rows = stmt.query_map(params![agent_id], read_note)?;
    rows.collect()
}

fn get_note(conn: &Connection, id: &str) -> rusqlite::Result<Option<Note>> {
    conn.query_row(
        "SELECT id, slug, title, body, source_session_id, source_cwd, tags_json,
                created_at, updated_at, slug_pending, agent_id
         FROM notes
         WHERE id = ?1",
        params![id],
        read_note,
    )
    .optional()
}

fn upsert_note(conn: &Connection, note: &NoteUpsert) -> rusqlite::Result<Note> {
    let title = normalize_title(&note.title);
    let body = note.body.replace("\r\n", "\n").replace('\r', "\n");
    let tags = normalize_tags(&note.tags);
    let tags_json = serde_json::to_string(&tags)
        .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;
    let source_session_id = note
        .source_session_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let source_cwd = note
        .source_cwd
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let now = now_millis();

    if let Some(existing) = get_note(conn, &note.id)? {
        let project_cwd = source_cwd.map(str::to_string).or(existing.source_cwd);
        let agent_id = existing.agent_id.or_else(|| note.agent_id.clone());
        // Project changes keep the note in its current position in the list.
        let updated_at =
            if title == existing.title && body == existing.body && tags == existing.tags {
                existing.updated_at
            } else {
                now
            };
        // Once established, a slug stays stable so @note/ references keep working.
        let (slug, slug_pending) =
            if note.finalize_slug && existing.slug_pending && !is_placeholder_title(&title) {
                (unique_slug(conn, &title)?, false)
            } else {
                (existing.slug, existing.slug_pending)
            };
        conn.execute(
            "UPDATE notes
             SET title = ?1, body = ?2, tags_json = ?3, updated_at = ?4,
                 source_cwd = ?6, slug = ?7, slug_pending = ?8, agent_id = ?9
             WHERE id = ?5",
            params![
                title,
                body,
                tags_json,
                updated_at,
                note.id,
                project_cwd,
                slug,
                slug_pending,
                agent_id
            ],
        )?;
        Ok(Note {
            id: note.id.clone(),
            slug,
            title,
            body,
            tags,
            source_session_id: existing.source_session_id,
            source_cwd: project_cwd,
            agent_id,
            slug_pending,
            created_at: existing.created_at,
            updated_at,
            hash: None,
            conflict_copy: None,
        })
    } else {
        // Explicit titles such as "Untitled" own their slug; only blank input is pending.
        let slug_pending = note.title.trim().is_empty();
        let slug = unique_slug(conn, &title)?;
        conn.execute(
            "INSERT INTO notes (
               id, slug, title, body, source_session_id, source_cwd, tags_json,
               created_at, updated_at, slug_pending, agent_id
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                note.id,
                slug,
                title,
                body,
                source_session_id,
                source_cwd,
                tags_json,
                now,
                now,
                slug_pending,
                note.agent_id
            ],
        )?;
        Ok(Note {
            id: note.id.clone(),
            slug,
            title,
            body,
            tags,
            source_session_id: source_session_id.map(str::to_string),
            source_cwd: source_cwd.map(str::to_string),
            agent_id: note.agent_id.clone(),
            slug_pending,
            created_at: now,
            updated_at: now,
            hash: None,
            conflict_copy: None,
        })
    }
}

// A finalization without local edits must not overwrite another window's
// saved contents or recreate a note that was deleted while this editor was open.
fn finalize_note_slug(conn: &Connection, id: &str, title: &str) -> rusqlite::Result<Option<Note>> {
    let Some(mut note) = get_note(conn, id)? else {
        return Ok(None);
    };
    if note.slug_pending
        && note.title == normalize_title(title)
        && !is_placeholder_title(&note.title)
    {
        note.slug = unique_slug(conn, &note.title)?;
        conn.execute(
            "UPDATE notes SET slug = ?1, slug_pending = 0 WHERE id = ?2",
            params![note.slug, id],
        )?;
        note.slug_pending = false;
    }
    Ok(Some(note))
}

fn delete_note(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM notes WHERE id = ?1", params![id])?;
    Ok(())
}

fn read_note(row: &rusqlite::Row<'_>) -> rusqlite::Result<Note> {
    let tags_json: String = row.get(6)?;
    let tags = serde_json::from_str::<Vec<String>>(&tags_json).unwrap_or_default();
    Ok(Note {
        id: row.get(0)?,
        slug: row.get(1)?,
        title: row.get(2)?,
        body: row.get(3)?,
        tags,
        source_session_id: row.get(4)?,
        source_cwd: row.get(5)?,
        created_at: row.get(7)?,
        updated_at: row.get(8)?,
        slug_pending: row.get(9)?,
        agent_id: row.get(10)?,
        hash: None,
        conflict_copy: None,
    })
}

fn normalize_tags(tags: &[String]) -> Vec<String> {
    let mut normalized = Vec::new();
    for input in tags {
        let tag = input
            .trim()
            .trim_start_matches('#')
            .split_whitespace()
            .collect::<Vec<_>>()
            .join("-")
            .to_lowercase();
        let tag: String = tag.chars().take(TAG_MAX).collect();
        let tag = tag.trim_end_matches('-').to_string();
        if tag.is_empty() || normalized.contains(&tag) {
            continue;
        }
        normalized.push(tag);
        if normalized.len() == TAGS_MAX {
            break;
        }
    }
    normalized
}

fn normalize_title(title: &str) -> String {
    let trimmed = title.trim();
    let sliced: String = trimmed.chars().take(TITLE_MAX).collect();
    let sliced = sliced.trim().to_string();
    if sliced.is_empty() {
        "Untitled".into()
    } else {
        sliced
    }
}

/// ASCII slug words before truncation, also used to detect placeholder titles.
fn slug_words(title: &str) -> String {
    let mut out = String::new();
    let mut dash = false;
    for ch in title.chars() {
        let c = ch.to_ascii_lowercase();
        if c.is_ascii_alphanumeric() {
            out.push(c);
            dash = false;
        } else if !out.is_empty() && !dash {
            out.push('-');
            dash = true;
        }
    }
    out.trim_end_matches('-').to_string()
}

fn slugify(title: &str) -> String {
    let words = slug_words(title);
    let slug = words[..words.len().min(48)].trim_end_matches('-');
    if slug.is_empty() {
        "note".into()
    } else {
        slug.into()
    }
}

// Inspect the full title so meaningful text beyond the slug cutoff still counts.
fn is_placeholder_title(title: &str) -> bool {
    let words = slug_words(title);
    match words.strip_prefix("untitled") {
        Some("") => true,
        Some(rest) => rest
            .strip_prefix('-')
            .is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())),
        None => false,
    }
}

fn unique_slug(conn: &Connection, title: &str) -> rusqlite::Result<String> {
    let base = slugify(title);
    for index in 0..1000 {
        let candidate = if index == 0 {
            base.clone()
        } else {
            format!("{base}-{}", index + 1)
        };
        let taken: i64 = conn.query_row(
            "SELECT (SELECT COUNT(*) FROM notes WHERE slug = ?1)
                  + (SELECT COUNT(*) FROM mentor_content WHERE kind = 'note' AND json_extract(meta_json, '$.slug') = ?1)",
            params![candidate],
            |row| row.get(0),
        )?;
        if taken == 0 {
            return Ok(candidate);
        }
    }
    Ok(format!("{base}-{}", now_millis()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session_store::SessionStore;

    fn upsert(store: &SessionStore, id: &str, title: &str, body: &str) -> Note {
        let conn = store.lock_conn().unwrap();
        upsert_note(
            &conn,
            &NoteUpsert {
                id: id.into(),
                title: title.into(),
                body: body.into(),
                tags: Vec::new(),
                source_session_id: None,
                agent_id: None,
                source_cwd: None,
                finalize_slug: true,
                expected_hash: None,
            },
        )
        .unwrap()
    }

    #[test]
    fn migrate_creates_notes_table() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let table: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(table, 1);
        let version: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM schema_migrations WHERE version = 1",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(version, 1);
    }

    #[test]
    fn agent_ownership_survives_edits_and_lists_without_the_original_session() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let mut input = NoteUpsert {
            id: "agent-note".into(),
            title: "Reading notes".into(),
            body: "First thought".into(),
            tags: vec![],
            source_session_id: Some("old-chat".into()),
            source_cwd: None,
            agent_id: Some("agent-a".into()),
            finalize_slug: false,
            expected_hash: None,
        };
        upsert_note(&conn, &input).unwrap();
        // Global Notes edits omit the association and must preserve it.
        input.agent_id = None;
        input.source_session_id = None;
        input.body = "Revised from Notes".into();
        let edited = upsert_note(&conn, &input).unwrap();
        assert_eq!(edited.agent_id.as_deref(), Some("agent-a"));
        assert_eq!(list_notes(&conn, Some("agent-a")).unwrap().len(), 1);
        assert!(list_notes(&conn, Some("agent-b")).unwrap().is_empty());
        assert_eq!(list_notes(&conn, None).unwrap().len(), 1);
        // Editing from another context cannot silently transfer ownership.
        input.agent_id = Some("agent-b".into());
        assert_eq!(
            upsert_note(&conn, &input).unwrap().agent_id.as_deref(),
            Some("agent-a")
        );
    }

    #[test]
    fn ensure_table_adds_tags_to_an_existing_notes_database() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE notes (
               id TEXT PRIMARY KEY,
               slug TEXT NOT NULL UNIQUE,
               title TEXT NOT NULL,
               body TEXT NOT NULL DEFAULT '',
               source_session_id TEXT,
               source_cwd TEXT,
               created_at INTEGER NOT NULL,
               updated_at INTEGER NOT NULL
             );
             INSERT INTO notes (id, slug, title, body, source_cwd, created_at, updated_at)
               VALUES ('old', 'untitled', 'Untitled', 'kept', '/repo', 1, 2);",
        )
        .unwrap();

        ensure_notes_table(&conn).unwrap();
        ensure_notes_table(&conn).unwrap();

        let tags_column: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM pragma_table_info('notes') WHERE name = 'tags_json'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(tags_column, 1);
        let note = get_note(&conn, "old").unwrap().unwrap();
        assert_eq!(note.slug, "untitled");
        assert_eq!(note.title, "Untitled");
        assert_eq!(note.body, "kept");
        assert_eq!(note.source_cwd.as_deref(), Some("/repo"));
        assert!(note.tags.is_empty());
        assert!(!note.slug_pending);
        assert_eq!((note.created_at, note.updated_at), (1, 2));
    }

    #[test]
    fn existing_notes_with_unused_columns_remain_readable_and_editable() {
        let store = SessionStore::open_in_memory().unwrap();
        let original = upsert(&store, "existing", "Saved note", "Keep this text.");
        {
            let conn = store.lock_conn().unwrap();
            conn.execute_batch(
                "ALTER TABLE notes ADD COLUMN retired_flag INTEGER NOT NULL DEFAULT 0;
                 ALTER TABLE notes ADD COLUMN retired_metadata TEXT;
                 UPDATE notes SET retired_flag = 1, retired_metadata = 'keep';",
            )
            .unwrap();
            ensure_notes_table(&conn).unwrap();
            assert_eq!(
                get_note(&conn, "existing").unwrap().unwrap().body,
                original.body
            );
        }

        let edited = upsert(&store, "existing", "Saved note", "Updated text.");
        upsert(&store, "new", "New note", "Another note.");
        let conn = store.lock_conn().unwrap();
        assert_eq!(edited.slug, original.slug);
        assert_eq!(edited.created_at, original.created_at);
        assert_eq!(
            get_note(&conn, "existing").unwrap().unwrap().body,
            "Updated text."
        );
        assert_eq!(list_notes(&conn, None).unwrap().len(), 2);
        let retained: (i64, String) = conn
            .query_row(
                "SELECT retired_flag, retired_metadata FROM notes WHERE id = 'existing'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(retained, (1, "keep".into()));
    }

    #[test]
    fn insert_update_and_list_newest_first() {
        let store = SessionStore::open_in_memory().unwrap();
        let first = upsert(&store, "n1", "Alpha", "one");
        std::thread::sleep(std::time::Duration::from_millis(5));
        let second = upsert(&store, "n2", "Beta", "two");
        assert_eq!(first.slug, "alpha");
        assert_eq!(second.slug, "beta");

        let conn = store.lock_conn().unwrap();
        let listed = list_notes(&conn, None).unwrap();
        assert_eq!(
            listed
                .iter()
                .map(|note| note.id.as_str())
                .collect::<Vec<_>>(),
            vec!["n2", "n1"]
        );

        std::thread::sleep(std::time::Duration::from_millis(5));
        let updated = upsert_note(
            &conn,
            &NoteUpsert {
                id: "n1".into(),
                title: "Alpha renamed".into(),
                body: "changed".into(),
                tags: vec!["Ideas".into(), "project docs".into(), "ideas".into()],
                source_session_id: Some("sess-1".into()),
                agent_id: None,
                source_cwd: Some("/tmp/a".into()),
                finalize_slug: false,
                expected_hash: None,
            },
        )
        .unwrap();
        assert_eq!(updated.slug, "alpha");
        assert_eq!(updated.title, "Alpha renamed");
        assert_eq!(updated.body, "changed");
        assert_eq!(updated.tags, vec!["ideas", "project-docs"]);
        assert_eq!(updated.created_at, first.created_at);
        assert!(updated.updated_at > first.updated_at);
        // Keep the source session when changing the note's project.
        assert_eq!(updated.source_session_id, None);
        assert_eq!(updated.source_cwd.as_deref(), Some("/tmp/a"));
        assert_eq!(
            get_note(&conn, "n1")
                .unwrap()
                .unwrap()
                .source_cwd
                .as_deref(),
            Some("/tmp/a")
        );

        drop(conn);
        let edited = upsert(&store, "n1", "Alpha renamed", "another edit");
        assert_eq!(edited.source_cwd.as_deref(), Some("/tmp/a"));
    }

    #[test]
    fn changing_only_project_preserves_note_order() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let mut input = NoteUpsert {
            id: "older".into(),
            title: "Plan".into(),
            body: "Keep this text.".into(),
            tags: vec!["ideas".into()],
            source_session_id: Some("original-session".into()),
            agent_id: None,
            source_cwd: Some("/work/Edefyn".into()),
            finalize_slug: false,
            expected_hash: None,
        };
        let original = upsert_note(&conn, &input).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        upsert_note(
            &conn,
            &NoteUpsert {
                id: "newer".into(),
                title: "Newer note".into(),
                body: "Another note.".into(),
                tags: vec![],
                source_session_id: None,
                agent_id: None,
                source_cwd: None,
                finalize_slug: true,
                expected_hash: None,
            },
        )
        .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));

        input.source_cwd = Some("/work/portognjeeen".into());
        let moved = upsert_note(&conn, &input).unwrap();
        assert_eq!(moved.updated_at, original.updated_at);
        assert_eq!(moved.source_cwd.as_deref(), Some("/work/portognjeeen"));
        assert_eq!(moved.source_session_id, original.source_session_id);
        assert_eq!(moved.slug, original.slug);
        assert_eq!(moved.created_at, original.created_at);

        let listed = list_notes(&conn, None).unwrap();
        assert_eq!(listed[0].id, "newer");
        assert_eq!(listed[1].id, "older");
        assert_eq!(listed[1].updated_at, original.updated_at);
        assert_eq!(listed[1].source_cwd, moved.source_cwd);

        input.title = "Updated plan".into();
        input.source_cwd = Some("/work/Edefyn".into());
        let edited = upsert_note(&conn, &input).unwrap();
        assert!(edited.updated_at > original.updated_at);
        assert_eq!(list_notes(&conn, None).unwrap()[0].id, "older");
    }

    #[test]
    fn slug_collisions_get_a_numeric_suffix() {
        let store = SessionStore::open_in_memory().unwrap();
        let first = upsert(&store, "n1", "Auth approach", "a");
        let second = upsert(&store, "n2", "Auth approach", "b");
        assert_eq!(first.slug, "auth-approach");
        assert_eq!(second.slug, "auth-approach-2");
    }

    fn save(store: &SessionStore, id: &str, title: &str, finalize_slug: bool) -> Note {
        let conn = store.lock_conn().unwrap();
        upsert_note(
            &conn,
            &NoteUpsert {
                id: id.into(),
                title: title.into(),
                body: String::new(),
                tags: Vec::new(),
                source_session_id: None,
                agent_id: None,
                source_cwd: None,
                finalize_slug,
                expected_hash: None,
            },
        )
        .unwrap()
    }

    #[test]
    fn only_a_blank_title_creates_a_pending_slug() {
        let store = SessionStore::open_in_memory().unwrap();
        let blank = save(&store, "blank", "  ", false);
        assert_eq!(
            (blank.title.as_str(), blank.slug.as_str()),
            ("Untitled", "untitled")
        );
        assert!(blank.slug_pending);
        for (id, title, slug) in [
            ("typed", "Untitled", "untitled-2"),
            ("numbered", "Untitled 2", "untitled-2-2"),
            ("named", "Plan", "plan"),
        ] {
            let created = save(&store, id, title, false);
            assert_eq!(created.slug, slug);
            assert!(!created.slug_pending);
            let finalized = save(&store, id, "Release notes", true);
            assert_eq!(finalized.slug, slug);
            assert!(!finalized.slug_pending);
        }
    }

    #[test]
    fn pending_slug_survives_debounced_saves_and_finalizes_once() {
        let store = SessionStore::open_in_memory().unwrap();
        save(&store, "n1", "", false);
        save(&store, "n1", "This i", false);
        let typed = save(&store, "n1", "This is my first note", false);
        assert_eq!(typed.slug, "untitled");
        let reopened = get_note(&store.lock_conn().unwrap(), "n1")
            .unwrap()
            .unwrap();
        assert_eq!(reopened.title, "This is my first note");
        assert!(reopened.slug_pending);

        let finalized = save(&store, "n1", "This is my first note", true);
        assert_eq!(finalized.slug, "this-is-my-first-note");
        assert!(!finalized.slug_pending);

        // Renaming or clearing an established note never makes it pending.
        for title in ["Renamed", "", "Another name"] {
            let renamed = save(&store, "n1", title, true);
            assert_eq!(renamed.slug, "this-is-my-first-note");
            assert!(!renamed.slug_pending);
        }
    }

    #[test]
    fn pending_slug_waits_for_a_real_title() {
        let store = SessionStore::open_in_memory().unwrap();
        save(&store, "n1", "", false);
        for title in ["Untitled", "   ", "Untitled 2"] {
            let saved = save(&store, "n1", title, true);
            assert_eq!(saved.slug, "untitled");
            assert!(saved.slug_pending);
        }
        assert_eq!(
            save(&store, "n1", "Auth approach", true).slug,
            "auth-approach"
        );
    }

    #[test]
    fn finalizing_a_pending_slug_avoids_collisions() {
        let store = SessionStore::open_in_memory().unwrap();
        save(&store, "n1", "Plan", false);
        save(&store, "n2", "", false);
        let second_blank = save(&store, "n3", "", false);
        assert_eq!(second_blank.slug, "untitled-2");
        assert_eq!(save(&store, "n2", "Plan", true).slug, "plan-2");
        assert_eq!(save(&store, "n3", "Plan", true).slug, "plan-3");
    }

    #[test]
    fn notes_from_before_slug_pending_keep_their_slugs() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE notes (
               id TEXT PRIMARY KEY,
               slug TEXT NOT NULL UNIQUE,
               title TEXT NOT NULL,
               body TEXT NOT NULL DEFAULT '',
               tags_json TEXT NOT NULL DEFAULT '[]',
               source_session_id TEXT,
               source_cwd TEXT,
               created_at INTEGER NOT NULL,
               updated_at INTEGER NOT NULL
             );
             INSERT INTO notes (id, slug, title, created_at, updated_at)
               VALUES ('blank', 'untitled', 'Untitled', 0, 0),
                      ('named-later', 'untitled-2', 'Auth approach', 0, 0),
                      ('numbered', 'untitled-3', 'Untitled 3', 0, 0),
                      ('titled', 'plan', 'Plan', 0, 0),
                      ('cleared', 'roadmap', 'Untitled', 0, 0);",
        )
        .unwrap();

        ensure_notes_table(&conn).unwrap();
        ensure_notes_table(&conn).unwrap();

        let rows = [
            ("blank", "untitled"),
            ("named-later", "untitled-2"),
            ("numbered", "untitled-3"),
            ("titled", "plan"),
            ("cleared", "roadmap"),
        ];
        for (id, slug) in rows {
            let note = get_note(&conn, id).unwrap().unwrap();
            assert_eq!(note.slug, slug);
            assert!(!note.slug_pending);
            for finalize_slug in [false, true] {
                let saved = upsert_note(
                    &conn,
                    &NoteUpsert {
                        id: id.into(),
                        title: "Release notes".into(),
                        body: "edited".into(),
                        tags: Vec::new(),
                        source_session_id: None,
                        agent_id: None,
                        source_cwd: None,
                        finalize_slug,
                        expected_hash: None,
                    },
                )
                .unwrap();
                assert_eq!(saved.slug, slug);
                assert!(!saved.slug_pending);
            }
            let resolved: String = conn
                .query_row(
                    "SELECT id FROM notes WHERE slug = ?1",
                    params![slug],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(resolved, id);
        }
    }

    #[test]
    fn placeholder_title_detection() {
        assert!(is_placeholder_title("Untitled"));
        assert!(is_placeholder_title("untitled 2"));
        assert!(is_placeholder_title("Untitled-137"));
        assert!(!is_placeholder_title("Untitled draft"));
        assert!(!is_placeholder_title("Untitled2"));
        assert!(!is_placeholder_title("My untitled"));
        // The slug cuts off at 48 chars; the meaningful suffix still counts.
        let long = format!("Untitled {} draft", "1".repeat(40));
        assert!(slugify(&long).len() <= 48);
        assert!(!is_placeholder_title(&long));
        assert!(is_placeholder_title(&format!(
            "Untitled {}",
            "1".repeat(60)
        )));
    }

    #[test]
    fn real_title_past_the_slug_cutoff_finalizes() {
        let store = SessionStore::open_in_memory().unwrap();
        save(&store, "n1", "", false);
        let title = format!("Untitled {} draft", "1".repeat(40));
        let finalized = save(&store, "n1", &title, true);
        assert!(!finalized.slug_pending);
        assert_eq!(finalized.slug, slugify(&title));
    }

    #[test]
    fn slug_only_finalization_preserves_other_windows_edits() {
        let store = SessionStore::open_in_memory().unwrap();
        save(&store, "n1", "", false);
        save(&store, "n1", "Plan", false);
        let conn = store.lock_conn().unwrap();
        conn.execute(
            "UPDATE notes SET body = 'new body', tags_json = '[\"new\"]', source_cwd = '/new', updated_at = 42 WHERE id = 'n1'",
            [],
        ).unwrap();
        let saved = finalize_note_slug(&conn, "n1", "Plan").unwrap().unwrap();
        assert_eq!(saved.slug, "plan");
        assert!(!saved.slug_pending);
        assert_eq!(saved.body, "new body");
        assert_eq!(saved.tags, vec!["new"]);
        assert_eq!(saved.source_cwd.as_deref(), Some("/new"));
        assert_eq!(saved.updated_at, 42);
        let repeated = finalize_note_slug(&conn, "n1", "Plan").unwrap().unwrap();
        assert_eq!(repeated.slug, "plan");
    }

    #[test]
    fn slug_only_finalization_does_not_finalize_a_newer_title_or_recreate_a_deleted_note() {
        let store = SessionStore::open_in_memory().unwrap();
        save(&store, "n1", "", false);
        save(&store, "n1", "New partial title", false);
        let conn = store.lock_conn().unwrap();
        let saved = finalize_note_slug(&conn, "n1", "Older title")
            .unwrap()
            .unwrap();
        assert_eq!(saved.title, "New partial title");
        assert_eq!(saved.slug, "untitled");
        assert!(saved.slug_pending);
        delete_note(&conn, "n1").unwrap();
        assert!(finalize_note_slug(&conn, "n1", "Older title")
            .unwrap()
            .is_none());
        assert!(get_note(&conn, "n1").unwrap().is_none());
    }

    #[test]
    fn empty_title_becomes_untitled() {
        let store = SessionStore::open_in_memory().unwrap();
        let note = upsert(&store, "n1", "   ", "");
        assert_eq!(note.title, "Untitled");
        assert_eq!(note.slug, "untitled");
    }

    #[test]
    fn note_image_names_are_safe_and_keep_supported_extensions() {
        assert_eq!(
            note_image_names(Path::new("/tmp/Architecture draft [2].PNG")).unwrap(),
            (
                "Architecture draft [2].PNG".into(),
                "Architecture-draft--2.png".into()
            )
        );
        assert!(note_image_names(Path::new("/tmp/archive.zip")).is_err());
    }

    #[test]
    fn note_asset_paths_cannot_escape_app_data() {
        assert_eq!(
            validate_note_asset_path("/note-assets/note-1/123-image.png").unwrap(),
            PathBuf::from("note-assets/note-1/123-image.png")
        );
        assert!(validate_note_asset_path("/note-assets/note-1/../secret.png").is_err());
        assert!(validate_note_asset_path("/other/note-1/image.png").is_err());
    }

    #[test]
    fn delete_removes_the_row() {
        let store = SessionStore::open_in_memory().unwrap();
        upsert(&store, "n1", "Gone", "bye");
        let conn = store.lock_conn().unwrap();
        delete_note(&conn, "n1").unwrap();
        assert!(get_note(&conn, "n1").unwrap().is_none());
        assert!(list_notes(&conn, None).unwrap().is_empty());
    }

    #[test]
    fn slugify_strips_punctuation() {
        assert_eq!(slugify("Hello, World!"), "hello-world");
        assert_eq!(slugify("***"), "note");
        assert_eq!(slugify("Ä"), "note");
    }

    #[test]
    fn a_mentors_notes_are_files_and_a_stale_editor_never_loses_the_disk_version() {
        use crate::mentor_store::testing::{register, temp_dir};
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp_dir("notes");
        register(&conn, "agent", &folder);
        let ctx = mentor_store::ctx_for(&conn, "agent").unwrap().unwrap();
        // A 0.3 note with the slug "kvm" keeps that slug taken.
        conn.execute("INSERT INTO notes (id, slug, title, created_at, updated_at) VALUES ('old', 'kvm', 'KVM', 1, 1)", []).unwrap();
        let input = |title: &str, body: &str, expected: Option<String>| NoteUpsert {
            id: "n1".into(),
            title: title.into(),
            body: body.into(),
            tags: vec!["Virt".into()],
            source_session_id: None,
            source_cwd: None,
            agent_id: Some("agent".into()),
            finalize_slug: true,
            expected_hash: expected,
        };
        let first = file_upsert_note(&conn, &ctx, None, &input("KVM", "one", None)).unwrap();
        assert_eq!(first.slug, "kvm-2");
        assert_eq!(first.tags, vec!["virt"]);
        let text = std::fs::read_to_string(folder.join("notes/n1.md")).unwrap();
        assert!(text.contains("slug: kvm-2") && text.ends_with("---\none"));
        let (_, found) = file_note(&conn, "n1").unwrap().unwrap();
        assert_eq!(found.hash, first.hash);

        // Edited on disk while the editor was open: the editor's save goes
        // through and the disk version is kept beside it.
        std::fs::write(
            folder.join("notes/n1.md"),
            "---\ntitle: KVM\nslug: kvm-2\n---\nedited in vim",
        )
        .unwrap();
        let (_, current) = file_note(&conn, "n1").unwrap().unwrap();
        let saved = file_upsert_note(
            &conn,
            &ctx,
            Some(current),
            &input("KVM", "from the editor", first.hash.clone()),
        )
        .unwrap();
        let copy = saved.conflict_copy.expect("a conflict copy");
        assert!(std::fs::read_to_string(&copy)
            .unwrap()
            .contains("edited in vim"));
        assert!(std::fs::read_to_string(folder.join("notes/n1.md"))
            .unwrap()
            .ends_with("from the editor"));
        // The copy is not a note of its own.
        assert_eq!(file_notes(&conn, &ctx).unwrap().len(), 1);
        std::fs::remove_dir_all(folder).unwrap();
    }
}
