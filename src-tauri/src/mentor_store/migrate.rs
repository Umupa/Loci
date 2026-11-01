//! Moving 0.3 data into mentors' folders.
//!
//! - Non-destructive: old rows, old `agents/<id>/` files, localStorage keys
//!   and the user's own workdirs are never changed. Folders only gain files.
//! - Idempotent and resumable: a file that already holds the same text is
//!   done; a mentor is marked migrated only after all of its files are
//!   written, and a crash part-way simply runs again.
//! - Conflicts are kept, not resolved: when a file already exists with other
//!   text, the 0.3 version is written beside it as `<id>.from-0.3.<ext>`.
//! - A dry run reports what would happen and writes nothing.
//! - Before the first real run, `loci.db` (VACUUM INTO), `agents/` and the
//!   roster are copied to `<app data>/backups/v0.4-migration-<time>/`.
//!
//! The same pass runs at every start, cheaply: a mentor added by an older
//! Loci after a downgrade is migrated then, and 0.3 rows edited after a
//! mentor's migration come back as files (or `.from-0.3` copies).

use std::path::{Path, PathBuf};

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

use super::format::{self, CanvasMeta, DocMeta, NoteMeta};
use super::fsio::{sha256, write_atomic};
use super::index;
use super::paths::{self, Kind, MENTOR_FILE, SHARED_REPOS};
use super::registry::{self, MentorRecord};
use super::MentorCtx;
use crate::session_store::now_millis;

/// Recorded in `schema_migrations` once every mentor of the 0.3 roster is in
/// its folder.
pub const MARKER_VERSION: i64 = 40;
const BACKUP_PREFIX: &str = "v0.4-migration-";

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrateInput {
    /// The window's `loci:agent-roster`, as it is.
    #[serde(default)]
    pub roster: Vec<Value>,
    /// The window's `loci:agent-overviews.v1`: view state per mentor.
    #[serde(default)]
    pub overviews: Option<Value>,
    #[serde(default)]
    pub dry_run: bool,
    /// Run one mentor again (its files that exist are kept).
    #[serde(default)]
    pub redo: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MentorReport {
    pub id: String,
    pub name: String,
    pub folder: String,
    /// The user's own workdir, left where it is.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workdir: Option<String>,
    pub new_folder: bool,
    pub files: Map<String, Value>,
    pub progress: usize,
    /// `.from-0.3` copies written beside files that already said otherwise.
    pub conflicts: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub dry_run: bool,
    /// Whether every mentor of the roster is now in its folder.
    pub done: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup: Option<String>,
    pub mentors: Vec<MentorReport>,
    /// `<app data>/agents/<id>` folders of agents no longer on the roster: left alone.
    pub orphan_agent_files: Vec<String>,
    /// Folders in the mentors root that are no mentor's: left alone.
    pub other_folders: Vec<String>,
    /// Tables of removed features: left alone for a later release.
    pub dead_tables: Vec<String>,
    /// 0.3 rows edited after their mentor moved to files, brought back.
    pub caught_up: usize,
}

pub struct MigrateEnv {
    pub root: PathBuf,
    pub app_data: PathBuf,
}

pub fn marker_set(conn: &Connection) -> rusqlite::Result<bool> {
    conn.query_row(
        "SELECT COUNT(*) FROM schema_migrations WHERE version = ?1",
        [MARKER_VERSION],
        |row| row.get::<_, i64>(0),
    )
    .map(|n| n > 0)
}

fn text(entry: &Map<String, Value>, key: &str) -> Option<String> {
    entry
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_string)
}

fn table_exists(conn: &Connection, name: &str) -> rusqlite::Result<bool> {
    conn.query_row(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
        [name],
        |row| row.get::<_, i64>(0),
    )
    .map(|n| n > 0)
}

/// What one write did, so a re-run can tell done from conflicting.
enum Outcome {
    Written,
    Unchanged,
    Conflict(PathBuf),
}

/// Writes `text` unless the file is there already: same text is done, other
/// text keeps the file and puts this one beside it as `.from-0.3`.
fn place(path: &Path, text: &str, mtime_ms: Option<i64>, dry: bool) -> Result<Outcome, String> {
    match std::fs::read(path) {
        Ok(current) if sha256(&current) == sha256(text.as_bytes()) => Ok(Outcome::Unchanged),
        Ok(_) => {
            let conflict = conflict_path(path);
            if !dry {
                let same =
                    std::fs::read(&conflict).is_ok_and(|c| sha256(&c) == sha256(text.as_bytes()));
                if !same {
                    write_atomic(&conflict, text.as_bytes())?;
                    set_mtime(&conflict, mtime_ms);
                }
            }
            Ok(Outcome::Conflict(conflict))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            if !dry {
                write_atomic(path, text.as_bytes())?;
                set_mtime(path, mtime_ms);
            }
            Ok(Outcome::Written)
        }
        Err(e) => Err(format!("{}: {e}", path.display())),
    }
}

fn conflict_path(path: &Path) -> PathBuf {
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("file");
    let (stem, ext) = name.rsplit_once('.').unwrap_or((name, "txt"));
    path.with_file_name(format!("{stem}.from-0.3.{ext}"))
}

/// Keeps the 0.3 "last changed" time, so the library keeps its order.
fn set_mtime(path: &Path, mtime_ms: Option<i64>) {
    let Some(ms) = mtime_ms.filter(|ms| *ms > 0) else {
        return;
    };
    let time = std::time::UNIX_EPOCH + std::time::Duration::from_millis(ms as u64);
    if let Ok(file) = std::fs::File::options().write(true).open(path) {
        let _ = file.set_modified(time);
    }
}

fn record(report: &mut MentorReport, kind: &str, outcome: Outcome) {
    let counts = report
        .files
        .entry(kind.to_string())
        .or_insert_with(|| json!({"written": 0, "unchanged": 0, "conflicts": 0}));
    let key = match &outcome {
        Outcome::Written => "written",
        Outcome::Unchanged => "unchanged",
        Outcome::Conflict(_) => "conflicts",
    };
    counts[key] = json!(counts[key].as_u64().unwrap_or(0) + 1);
    if let Outcome::Conflict(path) = outcome {
        report.conflicts.push(path.to_string_lossy().into_owned());
    }
}

/// The first `<root>/<slug>[-n]` that does not exist (for a dry run).
fn free_folder(root: &Path, slug: &str) -> PathBuf {
    (1..100)
        .map(|n| {
            if n == 1 {
                root.join(slug)
            } else {
                root.join(format!("{slug}-{n}"))
            }
        })
        .find(|dir| !dir.exists())
        .unwrap_or_else(|| root.join(slug))
}

/// Which folder a 0.3 mentor's content goes to. A default workdir
/// (`<root>/<slug>`) is used as it is; a workdir elsewhere is the user's and
/// stays where it is, with a new content folder in the root beside the others.
fn choose_folder(
    root: &Path,
    id: &str,
    entry: &Map<String, Value>,
    dry: bool,
) -> Result<(PathBuf, Option<PathBuf>, bool), String> {
    let workdir = text(entry, "workdir").map(|w| crate::fs::expand_home(&w));
    if let Some(dir) = &workdir {
        let under_root = dir.parent() == Some(root)
            && dir.file_name().and_then(|n| n.to_str()) != Some(SHARED_REPOS);
        let owner = registry::read_identity(dir).ok().and_then(|identity| {
            identity
                .get("id")
                .and_then(Value::as_str)
                .map(str::to_string)
        });
        if under_root && owner.as_deref().is_none_or(|owner| owner == id) {
            return Ok((dir.clone(), None, !dir.exists()));
        }
    }
    let slug = paths::mentor_slug(
        text(entry, "name").as_deref(),
        text(entry, "role").as_deref(),
        id,
    );
    let folder = if dry {
        free_folder(root, &slug)
    } else {
        paths::create_folder(root, &slug)?
    };
    Ok((folder, workdir, true))
}

/// `mentor.json` for a 0.3 roster entry, with the defaults of its conversation.
fn identity_for(
    conn: &Connection,
    id: &str,
    entry: &Map<String, Value>,
    workdir: Option<&Path>,
) -> Map<String, Value> {
    let mut identity = Map::new();
    identity.insert("schemaVersion".into(), json!(format::SCHEMA_VERSION));
    identity.insert("id".into(), json!(id));
    for key in ["name", "role", "avatar", "color"] {
        if let Some(value) = text(entry, key) {
            identity.insert(key.into(), json!(value));
        }
    }
    if let Some(workdir) = workdir {
        identity.insert("workdir".into(), json!(workdir.to_string_lossy()));
    }
    let folders: Vec<Value> = entry
        .get("projects")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|p| p.as_str().is_some_and(|p| !p.is_empty()))
        .cloned()
        .collect();
    if !folders.is_empty() {
        identity.insert("folders".into(), Value::Array(folders));
    }
    if let Some(session) = text(entry, "sessionId") {
        if let Ok(Some(defaults)) = session_defaults(conn, &session) {
            identity.insert("defaults".into(), defaults);
        }
    }
    identity.insert(
        "createdAt".into(),
        json!(super::fsio::iso_from_millis(now_millis())),
    );
    identity
}

fn session_defaults(conn: &Connection, session: &str) -> rusqlite::Result<Option<Value>> {
    conn.query_row(
        "SELECT harness, model, runtime_mode, model_settings FROM sessions WHERE id = ?1",
        [session],
        |row| {
            let settings: String = row.get(3)?;
            let settings: Value = serde_json::from_str(&settings).unwrap_or(Value::Null);
            let mut defaults = json!({
                "provider": row.get::<_, String>(0)?,
                "model": row.get::<_, String>(1)?,
                "mode": row.get::<_, String>(2)?,
            });
            if let Some(effort) = settings.get("effort").filter(|e| e.is_string()) {
                defaults["effort"] = effort.clone();
            }
            // Every setting, so a catalog that has not loaded yet still seeds
            // the conversation the 0.3 session ran with.
            if let Some(settings) = settings.as_object() {
                let settings: Map<String, Value> = settings
                    .iter()
                    .filter(|(_, value)| value.as_str().is_some_and(|v| !v.is_empty()))
                    .map(|(key, value)| (key.clone(), value.clone()))
                    .collect();
                if !settings.is_empty() {
                    defaults["modelSettings"] = Value::Object(settings);
                }
            }
            Ok(defaults)
        },
    )
    .optional()
}

fn local_flags(entry: &Map<String, Value>) -> Map<String, Value> {
    let mut local = Map::new();
    for key in [
        "accessMigrated",
        "showStartedSessionsInSidebar",
        "useSidebarFolders",
    ] {
        if let Some(flag) = entry.get(key).filter(|v| v.is_boolean()) {
            local.insert(key.into(), flag.clone());
        }
    }
    local
}

/// Copies `<app data>/agents/<id>/` (Soul, memory and its archive) into the
/// folder; `habits.json` stays in app data.
fn copy_agent_files(
    from: &Path,
    folder: &Path,
    report: &mut MentorReport,
    dry: bool,
) -> Result<(), String> {
    fn walk(dir: &Path, base: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            if kind.is_dir() {
                walk(&path, base, out);
            } else if kind.is_file() {
                if let Ok(rel) = path.strip_prefix(base) {
                    out.push(rel.to_path_buf());
                }
            }
        }
    }
    let mut files = Vec::new();
    walk(from, from, &mut files);
    files.sort();
    for rel in files {
        if rel == Path::new("habits.json") {
            continue;
        }
        let text = match std::fs::read_to_string(from.join(&rel)) {
            Ok(text) => text,
            Err(e) => return Err(format!("{}: {e}", from.join(&rel).display())),
        };
        let outcome = place(&folder.join(&rel), &text, None, dry)?;
        let label = if rel.starts_with("memory") || rel == Path::new("MEMORY.md") {
            "memory"
        } else {
            "soul"
        };
        record(report, label, outcome);
    }
    Ok(())
}

struct Since(Option<i64>);

impl Since {
    fn clause(&self) -> &'static str {
        if self.0.is_some() {
            " AND updated_at > ?2"
        } else {
            " AND ?2 IS NULL"
        }
    }
}

/// Writes the mentor's 0.3 rows as files. With `since`, only rows changed
/// after that time (the catch-up after a downgrade).
fn write_rows(
    conn: &Connection,
    ctx: &MentorCtx,
    since: Since,
    report: &mut MentorReport,
    dry: bool,
) -> Result<usize, String> {
    let agent = ctx.agent.as_str();
    let mut touched = 0;
    // Sources and guides.
    {
        let mut statement = conn
            .prepare(&format!(
                "SELECT id, title, subject, body, source_url, source_version, fetched_at, created_at, updated_at
                 FROM agent_documents WHERE agent_id = ?1{}",
                since.clause()
            ))
            .map_err(|e| e.to_string())?;
        let rows = statement
            .query_map(params![agent, since.0], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    DocMeta {
                        title: row.get(1)?,
                        subject: row.get(2)?,
                        source_url: row.get(4)?,
                        version: row.get(5)?,
                        fetched_at: row.get(6)?,
                        created_at: row.get(7)?,
                    },
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(8)?,
                ))
            })
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (id, meta, body, updated) = row.map_err(|e| e.to_string())?;
            if !paths::valid_content_id(&id) {
                continue;
            }
            let kind = if meta.source_url.is_some() {
                Kind::Source
            } else {
                Kind::Guide
            };
            let text = format::render_doc(None, &meta, &body)?;
            let outcome = place(&ctx.path(kind, &id), &text, Some(updated), dry)?;
            record(report, kind.dir(), outcome);
            touched += 1;
        }
    }
    // Courses, and their progress.
    {
        let mut statement = conn
            .prepare(&format!(
                "SELECT id, engine, title, data_json, updated_at FROM courses WHERE agent_id = ?1{}",
                since.clause()
            ))
            .map_err(|e| e.to_string())?;
        let rows = statement
            .query_map(params![agent, since.0], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            })
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (id, engine, title, data, updated) = row.map_err(|e| e.to_string())?;
            if !paths::valid_content_id(&id) {
                continue;
            }
            let relativize = |path: &str| ctx.relativize(path);
            let text = format::render_course(&title, &engine, &data, &relativize)?;
            let outcome = place(&ctx.path(Kind::Course, &id), &text, Some(updated), dry)?;
            record(report, "courses", outcome);
            touched += 1;
        }
    }
    if since.0.is_none() && !dry {
        report.progress = conn
            .execute(
                "INSERT OR IGNORE INTO lesson_progress (agent_id, course_id, item_id, status, updated_at)
                 SELECT agent_id, course_id, item_id, status, ?2 FROM course_progress WHERE agent_id = ?1",
                params![agent, now_millis()],
            )
            .map_err(|e| e.to_string())?;
    } else if since.0.is_none() {
        report.progress = conn
            .query_row(
                "SELECT COUNT(*) FROM course_progress WHERE agent_id = ?1",
                [agent],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|e| e.to_string())? as usize;
    }
    // Notes the mentor owns.
    {
        let mut statement = conn
            .prepare(&format!(
                "SELECT id, slug, title, body, tags_json, source_session_id, source_cwd, slug_pending,
                        created_at, updated_at
                 FROM notes WHERE agent_id = ?1{}",
                since.clause()
            ))
            .map_err(|e| e.to_string())?;
        let rows = statement
            .query_map(params![agent, since.0], |row| {
                let tags: String = row.get(4)?;
                Ok((
                    row.get::<_, String>(0)?,
                    NoteMeta {
                        slug: row.get(1)?,
                        title: row.get(2)?,
                        tags: serde_json::from_str(&tags).unwrap_or_default(),
                        source_session: row.get(5)?,
                        source_cwd: row.get(6)?,
                        slug_pending: row.get(7)?,
                        created_at: row.get(8)?,
                        updated_at: row.get(9)?,
                    },
                    row.get::<_, String>(3)?,
                ))
            })
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (id, meta, body) = row.map_err(|e| e.to_string())?;
            if !paths::valid_content_id(&id) {
                continue;
            }
            let updated = meta.updated_at;
            let text = format::render_note(None, &meta, &body)?;
            let outcome = place(&ctx.path(Kind::Note, &id), &text, updated, dry)?;
            record(report, "notes", outcome);
            touched += 1;
        }
    }
    // Canvases drawn into the mentor's library.
    {
        let mut statement = conn
            .prepare(&format!(
                "SELECT id, title, data_json, tags_json, created_at, updated_at
                 FROM canvases WHERE cwd = 'loci-agent://' || ?1{}",
                since.clause()
            ))
            .map_err(|e| e.to_string())?;
        let rows = statement
            .query_map(params![agent, since.0], |row| {
                let tags: String = row.get(3)?;
                Ok((
                    row.get::<_, String>(0)?,
                    CanvasMeta {
                        title: row.get(1)?,
                        tags: serde_json::from_str(&tags).unwrap_or_default(),
                        created_at: row.get(4)?,
                        updated_at: row.get(5)?,
                    },
                    row.get::<_, String>(2)?,
                ))
            })
            .map_err(|e| e.to_string())?;
        for row in rows {
            let (id, meta, data) = row.map_err(|e| e.to_string())?;
            if !paths::valid_content_id(&id) {
                continue;
            }
            let updated = meta.updated_at;
            let text = format::render_canvas(&meta, &data)?;
            let outcome = place(&ctx.path(Kind::Canvas, &id), &text, updated, dry)?;
            record(report, "canvases", outcome);
            touched += 1;
        }
    }
    Ok(touched)
}

fn backup(conn: &Connection, env: &MigrateEnv, input: &MigrateInput) -> Result<PathBuf, String> {
    let backups = env.app_data.join("backups");
    if let Ok(entries) = std::fs::read_dir(&backups) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            if name.to_string_lossy().starts_with(BACKUP_PREFIX)
                && entry.path().join("loci.db").is_file()
            {
                return Ok(entry.path());
            }
        }
    }
    let dir = backups.join(format!("{BACKUP_PREFIX}{}", super::stamp_now()));
    std::fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let agents = env.app_data.join("agents");
    if agents.is_dir() {
        copy_tree(&agents, &dir.join("agents"))?;
    }
    write_atomic(
        &dir.join("roster.json"),
        serde_json::to_string_pretty(&input.roster)
            .map_err(|e| e.to_string())?
            .as_bytes(),
    )?;
    if let Some(overviews) = &input.overviews {
        write_atomic(
            &dir.join("overviews.json"),
            overviews.to_string().as_bytes(),
        )?;
    }
    // Last, so a backup folder with loci.db in it is a complete one.
    let target = dir.join("loci.db");
    conn.execute("VACUUM INTO ?1", [target.to_string_lossy()])
        .map_err(|e| format!("Could not back up the database: {e}"))?;
    Ok(dir)
}

pub fn copy_tree(from: &Path, to: &Path) -> Result<(), String> {
    std::fs::create_dir_all(to).map_err(|e| format!("{}: {e}", to.display()))?;
    for entry in std::fs::read_dir(from).map_err(|e| format!("{}: {e}", from.display()))? {
        let entry = entry.map_err(|e| e.to_string())?;
        let kind = entry.file_type().map_err(|e| e.to_string())?;
        let target = to.join(entry.file_name());
        if kind.is_dir() {
            copy_tree(&entry.path(), &target)?;
        } else if kind.is_file() {
            std::fs::copy(entry.path(), &target)
                .map_err(|e| format!("{}: {e}", entry.path().display()))?;
        }
    }
    Ok(())
}

fn migrate_one(
    conn: &Connection,
    env: &MigrateEnv,
    id: &str,
    entry: &Map<String, Value>,
    position: i64,
    overviews: Option<&Value>,
    dry: bool,
) -> Result<MentorReport, String> {
    let mut report = MentorReport {
        id: id.to_string(),
        name: text(entry, "name").unwrap_or_default(),
        ..Default::default()
    };
    let existing = registry::get(conn, id).map_err(|e| e.to_string())?;
    let (folder, workdir, new_folder) = match &existing {
        Some(record) => {
            let identity = registry::read_identity(&record.folder).ok();
            let workdir = identity
                .as_ref()
                .and_then(|i| registry::custom_workdir(&record.folder, i));
            (record.folder.clone(), workdir, false)
        }
        None => choose_folder(&env.root, id, entry, dry)?,
    };
    report.folder = folder.to_string_lossy().into_owned();
    report.workdir = workdir.as_ref().map(|w| w.to_string_lossy().into_owned());
    report.new_folder = new_folder;
    let ctx = MentorCtx {
        agent: id.to_string(),
        folder: folder.clone(),
        workdir: workdir.clone(),
    };
    if !dry {
        std::fs::create_dir_all(&folder).map_err(|e| format!("{}: {e}", folder.display()))?;
        if !folder.join(MENTOR_FILE).exists() {
            let identity = identity_for(conn, id, entry, workdir.as_deref());
            registry::write_identity(&folder, &identity)?;
        }
        registry::upsert(
            conn,
            &MentorRecord {
                id: id.to_string(),
                folder: folder.clone(),
                session_id: text(entry, "sessionId"),
                position,
                local: local_flags(entry),
                migrated_at: None,
                added_at: existing.as_ref().map_or_else(now_millis, |r| r.added_at),
            },
        )
        .map_err(|e| e.to_string())?;
    }
    copy_agent_files(
        &env.app_data.join("agents").join(id),
        &folder,
        &mut report,
        dry,
    )?;
    write_rows(conn, &ctx, Since(None), &mut report, dry)?;
    if !dry {
        if let Some(view) = overviews.and_then(|o| o.get(id)) {
            conn.execute(
                "INSERT OR IGNORE INTO mentor_state (agent_id, key, json, updated_at) VALUES (?1, 'view', ?2, ?3)",
                params![id, view.to_string(), now_millis()],
            )
            .map_err(|e| e.to_string())?;
        }
        conn.execute(
            "UPDATE mentors SET migrated_at = ?2 WHERE id = ?1",
            params![id, now_millis()],
        )
        .map_err(|e| e.to_string())?;
        index::reconcile(conn, &ctx)?;
    }
    Ok(report)
}

/// The rows of migrated mentors that an older Loci changed afterwards.
fn catch_up(conn: &Connection, report: &mut Report) -> Result<(), String> {
    for record in registry::list(conn).map_err(|e| e.to_string())? {
        let Some(migrated_at) = record.migrated_at else {
            continue;
        };
        let ctx = MentorCtx {
            agent: record.id.clone(),
            folder: record.folder.clone(),
            workdir: None,
        };
        if !record.folder.join(MENTOR_FILE).exists() {
            continue;
        }
        let mut scratch = MentorReport::default();
        let touched = write_rows(conn, &ctx, Since(Some(migrated_at)), &mut scratch, false)?;
        if touched > 0 {
            report.caught_up += touched;
            index::reconcile(conn, &ctx)?;
            // Rows up to the newest one have been brought over.
            let newest: i64 = conn
                .query_row(
                    "SELECT max(coalesce((SELECT max(updated_at) FROM agent_documents WHERE agent_id = ?1), 0),
                                coalesce((SELECT max(updated_at) FROM courses WHERE agent_id = ?1), 0),
                                coalesce((SELECT max(updated_at) FROM notes WHERE agent_id = ?1), 0),
                                coalesce((SELECT max(updated_at) FROM canvases WHERE cwd = 'loci-agent://' || ?1), 0))",
                    [&record.id],
                    |row| row.get(0),
                )
                .map_err(|e| e.to_string())?;
            conn.execute(
                "UPDATE mentors SET migrated_at = ?2 WHERE id = ?1",
                params![record.id, now_millis().max(newest)],
            )
            .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Runs (or, with `dry_run`, describes) the migration of the roster given.
pub fn run(conn: &Connection, env: &MigrateEnv, input: &MigrateInput) -> Result<Report, String> {
    let dry = input.dry_run;
    let mut report = Report {
        dry_run: dry,
        ..Default::default()
    };
    let mut pending: Vec<(i64, String, Map<String, Value>)> = Vec::new();
    for (position, entry) in input.roster.iter().enumerate() {
        let Some(entry) = entry.as_object() else {
            continue;
        };
        let Some(id) = text(entry, "id")
            .filter(|id| id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'))
        else {
            continue;
        };
        let record = registry::get(conn, &id).map_err(|e| e.to_string())?;
        let done = record.as_ref().is_some_and(|r| r.migrated_at.is_some());
        if done && input.redo.as_deref() != Some(id.as_str()) {
            continue;
        }
        // A mentor removed in 0.4 may linger in an older window's storage.
        if record.is_none()
            && marker_set(conn).map_err(|e| e.to_string())?
            && removed_folder_exists(&env.root, &id)
        {
            continue;
        }
        pending.push((position as i64, id, entry.clone()));
    }
    if !pending.is_empty() && !dry {
        report.backup = Some(backup(conn, env, input)?.to_string_lossy().into_owned());
    }
    for (position, id, entry) in &pending {
        match migrate_one(
            conn,
            env,
            id,
            entry,
            *position,
            input.overviews.as_ref(),
            dry,
        ) {
            Ok(mentor) => report.mentors.push(mentor),
            Err(error) => report.mentors.push(MentorReport {
                id: id.clone(),
                name: text(entry, "name").unwrap_or_default(),
                error: Some(error),
                ..Default::default()
            }),
        }
    }
    if !dry {
        catch_up(conn, &mut report)?;
    }
    report.done = report.mentors.iter().all(|m| m.error.is_none());
    if report.done && !dry {
        conn.execute(
            "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?1, ?2)",
            params![MARKER_VERSION, now_millis()],
        )
        .map_err(|e| e.to_string())?;
    }
    describe_leftovers(conn, env, input, &mut report)?;
    Ok(report)
}

fn removed_folder_exists(root: &Path, id: &str) -> bool {
    let Ok(entries) = std::fs::read_dir(root) else {
        return false;
    };
    entries.flatten().any(|entry| {
        let removed = entry.path().join(paths::REMOVED_MENTOR_FILE);
        std::fs::read_to_string(removed)
            .ok()
            .and_then(|text| format::parse_mentor(&text).ok())
            .is_some_and(|identity| identity.get("id").and_then(Value::as_str) == Some(id))
    })
}

fn describe_leftovers(
    conn: &Connection,
    env: &MigrateEnv,
    input: &MigrateInput,
    report: &mut Report,
) -> Result<(), String> {
    let known: std::collections::HashSet<String> = input
        .roster
        .iter()
        .filter_map(|e| e.get("id").and_then(Value::as_str).map(str::to_string))
        .chain(
            registry::list(conn)
                .map_err(|e| e.to_string())?
                .into_iter()
                .map(|r| r.id),
        )
        .collect();
    if let Ok(entries) = std::fs::read_dir(env.app_data.join("agents")) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if entry.path().is_dir() && !known.contains(&name) {
                report
                    .orphan_agent_files
                    .push(entry.path().to_string_lossy().into_owned());
            }
        }
    }
    let folders: std::collections::HashSet<PathBuf> = registry::list(conn)
        .map_err(|e| e.to_string())?
        .into_iter()
        .map(|r| r.folder)
        .chain(report.mentors.iter().map(|m| PathBuf::from(&m.folder)))
        .collect();
    if let Ok(entries) = std::fs::read_dir(&env.root) {
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if path.is_dir()
                && !name.starts_with('.')
                && name != SHARED_REPOS
                && !folders.contains(&path)
            {
                report
                    .other_folders
                    .push(path.to_string_lossy().into_owned());
            }
        }
    }
    report.orphan_agent_files.sort();
    report.other_folders.sort();
    for table in [
        "feed_item_state",
        "session_reminders",
        "workspace_snapshot",
        "learning_widgets",
    ] {
        if table_exists(conn, table).map_err(|e| e.to_string())? {
            report.dead_tables.push(table.into());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mentor_store::testing::temp_dir;
    use crate::session_store::SessionStore;

    /// A 0.3 database with every kind of row, one mentor in a default workdir
    /// and one whose workdir is a folder of the user's.
    fn seed(conn: &Connection, root: &Path, custom: &Path) {
        conn.execute_batch(
            "INSERT INTO sessions (id,cwd,harness,model,runtime_mode,title,created_at,updated_at,model_settings)
               VALUES ('s1','/w','claude','opus','full-access','chat',1,1,'{\"effort\":\"high\"}');
             INSERT INTO agent_documents (agent_id,id,title,subject,body,source_url,source_version,fetched_at,created_at,updated_at)
               VALUES ('m1','virtio','Virtio','virt','# Virtio\n\nrings\n','https://v.org','1.2',1700000000000,1700000000000,1700000001000);
             INSERT INTO agent_documents (agent_id,id,title,body,created_at,updated_at)
               VALUES ('m1','引言','引言','中文导读',1700000000000,1700000002000);
             INSERT INTO agent_documents (agent_id,id,title,body,created_at,updated_at)
               VALUES ('m2','g','G','guide',1,1);
             INSERT INTO courses VALUES ('m1','c1','reading','Course',
               '{\"chapters\":[{\"title\":\"One\",\"lessons\":[{\"id\":\"l1\",\"title\":\"L1\",\"document\":\"virtio\"},{\"id\":\"l2\",\"title\":\"L2\",\"document\":\"引言\"}]}]}',1,5);
             INSERT INTO course_progress VALUES ('m1','c1','l1','mastered');
             INSERT INTO course_progress VALUES ('m1','c1','l2','learning');
             INSERT INTO notes (id,slug,title,body,tags_json,created_at,updated_at,agent_id)
               VALUES ('n1','kvm','KVM','note body','[\"kvm\"]',1,2,'m1');
             INSERT INTO notes (id,slug,title,body,created_at,updated_at)
               VALUES ('n2','loose','Loose','no mentor',1,2);
             INSERT INTO canvases (id,title,data_json,cwd,created_at,updated_at)
               VALUES ('k1','Map','{\"elements\":[],\"appState\":{},\"files\":{}}','loci-agent://m1',1,3);
             INSERT INTO canvases (id,title,cwd,created_at,updated_at) VALUES ('k2','Project','/repo',1,3);
             CREATE TABLE feed_item_state (id TEXT);",
        )
        .unwrap();
        std::fs::create_dir_all(root.join("ember/repos")).unwrap();
        std::fs::create_dir_all(root.join("repos/x")).unwrap();
        std::fs::create_dir_all(custom).unwrap();
        std::fs::write(custom.join("notes.txt"), "the user's").unwrap();
    }

    fn roster(root: &Path, custom: &Path) -> Vec<Value> {
        vec![
            json!({"id":"m1","sessionId":"s1","name":"Repo Lens","avatar":"nova","color":"red",
                   "workdir": root.join("repo-lens").to_string_lossy(),"projects":["/p"],"accessMigrated":true}),
            json!({"id":"m2","name":"沙箱导师","role":"Sandbox internals guide","avatar":"bolt","color":"blue",
                   "workdir": custom.to_string_lossy(),"projects":[]}),
        ]
    }

    fn agents_dir(app: &Path) {
        let dir = app.join("agents/m1");
        std::fs::create_dir_all(dir.join("memory/archive")).unwrap();
        std::fs::write(dir.join("SOUL.md"), "soul").unwrap();
        std::fs::write(dir.join("MEMORY.md"), "- fact").unwrap();
        std::fs::write(dir.join("memory/kvm.md"), "topic").unwrap();
        std::fs::write(dir.join("memory/archive/2026.md"), "old").unwrap();
        std::fs::write(dir.join("habits.json"), "[]").unwrap();
        std::fs::create_dir_all(app.join("agents/orphan")).unwrap();
    }

    fn snapshot(conn: &Connection) -> String {
        [
            "agent_documents",
            "courses",
            "course_progress",
            "notes",
            "canvases",
        ]
        .iter()
        .map(|t| {
            let mut statement = conn
                .prepare(&format!("SELECT * FROM {t} ORDER BY 1, 2"))
                .unwrap();
            let count = statement.column_count();
            let rows: Vec<String> = statement
                .query_map([], |row| {
                    Ok((0..count)
                        .map(|i| format!("{:?}", row.get_ref(i).unwrap()))
                        .collect::<Vec<_>>()
                        .join("|"))
                })
                .unwrap()
                .map(Result::unwrap)
                .collect();
            rows.join("\n")
        })
        .collect::<Vec<_>>()
        .join("\n--\n")
    }

    #[test]
    fn a_dry_run_reports_and_writes_nothing() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let (root, app, custom) = (temp_dir("root"), temp_dir("app"), temp_dir("custom"));
        seed(&conn, &root, &custom);
        agents_dir(&app);
        let env = MigrateEnv {
            root: root.clone(),
            app_data: app.clone(),
        };
        let input = MigrateInput {
            roster: roster(&root, &custom),
            dry_run: true,
            ..Default::default()
        };
        let report = run(&conn, &env, &input).unwrap();
        assert_eq!(report.mentors.len(), 2);
        assert_eq!(
            report.mentors[0].folder,
            root.join("repo-lens").to_string_lossy()
        );
        assert_eq!(
            report.mentors[1].folder,
            root.join("sandbox-internals-guide").to_string_lossy()
        );
        assert_eq!(report.mentors[0].files["guides"]["written"], 1);
        assert_eq!(report.mentors[0].progress, 2);
        assert!(!root.join("repo-lens").exists());
        assert!(!root.join("sandbox-internals-guide").exists());
        assert!(!app.join("backups").exists());
        assert!(!marker_set(&conn).unwrap());
        assert!(registry::list(&conn).unwrap().is_empty());
        for dir in [root, app, custom] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn migration_writes_every_kind_keeps_old_data_and_is_idempotent() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let (root, app, custom) = (temp_dir("root"), temp_dir("app"), temp_dir("custom"));
        seed(&conn, &root, &custom);
        agents_dir(&app);
        let before = snapshot(&conn);
        let env = MigrateEnv {
            root: root.clone(),
            app_data: app.clone(),
        };
        let input = MigrateInput {
            roster: roster(&root, &custom),
            overviews: Some(json!({"m1": {"segment": "courses"}})),
            ..Default::default()
        };
        let report = run(&conn, &env, &input).unwrap();
        assert!(report.done, "{report:?}");
        assert!(marker_set(&conn).unwrap());
        let backup = PathBuf::from(report.backup.clone().unwrap());
        assert!(backup.join("loci.db").is_file());
        assert!(backup.join("agents/m1/SOUL.md").is_file());
        assert!(backup.join("roster.json").is_file());

        let lens = root.join("repo-lens");
        let identity = registry::read_identity(&lens).unwrap();
        assert_eq!(identity["name"], "Repo Lens");
        assert!(identity.get("workdir").is_none());
        assert_eq!(identity["folders"], json!(["/p"]));
        assert_eq!(identity["defaults"]["provider"], "claude");
        assert_eq!(identity["defaults"]["effort"], "high");
        assert_eq!(identity["defaults"]["modelSettings"]["effort"], "high");
        assert_eq!(identity["defaults"]["mode"], "full-access");
        assert_eq!(
            std::fs::read_to_string(lens.join("SOUL.md")).unwrap(),
            "soul"
        );
        assert!(lens.join("memory/archive/2026.md").is_file());
        assert!(!lens.join("habits.json").exists());
        let source = std::fs::read_to_string(lens.join("sources/virtio.md")).unwrap();
        assert!(source.contains("sourceUrl: https://v.org"));
        assert!(source.ends_with("---\n# Virtio\n\nrings\n"));
        assert!(lens.join("guides/引言.md").is_file());
        assert!(lens.join("courses/c1.yaml").is_file());
        assert!(lens.join("notes/n1.md").is_file());
        assert!(lens.join("canvases/k1.excalidraw").is_file());
        assert!(!lens.join("notes/n2.md").exists());
        assert!(!lens.join("canvases/k2.excalidraw").exists());

        // The user's own workdir is untouched; content goes beside the others.
        let sandbox = root.join("sandbox-internals-guide");
        assert_eq!(
            registry::read_identity(&sandbox).unwrap()["workdir"],
            custom.to_string_lossy().as_ref()
        );
        assert_eq!(std::fs::read_dir(&custom).unwrap().count(), 1);
        assert!(sandbox.join("guides/g.md").is_file());

        // The index sees it, progress and view state came along.
        let rows = index::list(&conn, "m1", &[Kind::Source, Kind::Guide, Kind::Course]).unwrap();
        assert_eq!(rows.len(), 3);
        assert!(rows.iter().all(|r| r.error.is_none()), "{rows:?}");
        let progress: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM lesson_progress WHERE agent_id='m1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(progress, 2);
        let view: String = conn
            .query_row(
                "SELECT json FROM mentor_state WHERE agent_id='m1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert!(view.contains("courses"));
        // The library keeps its 0.3 order.
        let guide = index::get(&conn, "m1", Kind::Guide, "引言")
            .unwrap()
            .unwrap();
        assert_eq!(guide.updated_at, 1_700_000_002_000);

        assert_eq!(
            report.orphan_agent_files,
            vec![app.join("agents/orphan").to_string_lossy().into_owned()]
        );
        assert!(report
            .other_folders
            .contains(&root.join("ember").to_string_lossy().into_owned()));
        assert_eq!(
            report.dead_tables,
            vec![
                "feed_item_state".to_string(),
                "workspace_snapshot".to_string()
            ]
        );
        assert_eq!(snapshot(&conn), before, "0.3 rows are left as they were");

        // Again: nothing to do, nothing written.
        let again = run(&conn, &env, &input).unwrap();
        assert!(again.mentors.is_empty() && again.done);
        // Redo one mentor: every file is already there.
        let redo = run(
            &conn,
            &env,
            &MigrateInput {
                redo: Some("m1".into()),
                ..input.clone()
            },
        )
        .unwrap();
        assert_eq!(redo.mentors[0].files["guides"]["unchanged"], 1);
        assert!(redo.mentors[0].conflicts.is_empty());
        for dir in [root, app, custom] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn an_interrupted_migration_resumes_and_conflicts_are_kept_beside() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let (root, app, custom) = (temp_dir("root"), temp_dir("app"), temp_dir("custom"));
        seed(&conn, &root, &custom);
        agents_dir(&app);
        // A crash left part of the files, and the user edited one meanwhile.
        let lens = root.join("repo-lens");
        std::fs::create_dir_all(lens.join("guides")).unwrap();
        std::fs::write(lens.join("guides/引言.md"), "edited by the user").unwrap();
        let env = MigrateEnv {
            root: root.clone(),
            app_data: app.clone(),
        };
        let input = MigrateInput {
            roster: roster(&root, &custom),
            ..Default::default()
        };
        let report = run(&conn, &env, &input).unwrap();
        assert!(report.done);
        assert_eq!(
            std::fs::read_to_string(lens.join("guides/引言.md")).unwrap(),
            "edited by the user"
        );
        assert!(lens.join("guides/引言.from-0.3.md").is_file());
        assert_eq!(report.mentors[0].conflicts.len(), 1);
        // The conflict copy is not listed as a document of its own.
        assert_eq!(index::list(&conn, "m1", &[Kind::Guide]).unwrap().len(), 1);
        for dir in [root, app, custom] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn rows_an_older_loci_changed_after_migration_come_back() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let (root, app, custom) = (temp_dir("root"), temp_dir("app"), temp_dir("custom"));
        seed(&conn, &root, &custom);
        let env = MigrateEnv {
            root: root.clone(),
            app_data: app.clone(),
        };
        let input = MigrateInput {
            roster: roster(&root, &custom),
            ..Default::default()
        };
        run(&conn, &env, &input).unwrap();
        // Downgraded to 0.3: it edits one guide and adds another.
        let later = now_millis() + 10_000;
        conn.execute(
            "UPDATE agent_documents SET body = 'newer', updated_at = ?1 WHERE id = '引言'",
            [later],
        )
        .unwrap();
        conn.execute("INSERT INTO agent_documents (agent_id,id,title,body,created_at,updated_at) VALUES ('m1','fresh','Fresh','new',?1,?1)", [later]).unwrap();
        let report = run(&conn, &env, &input).unwrap();
        assert_eq!(report.caught_up, 2);
        let lens = root.join("repo-lens");
        assert!(lens.join("guides/fresh.md").is_file());
        assert!(
            std::fs::read_to_string(lens.join("guides/引言.from-0.3.md"))
                .unwrap()
                .contains("newer")
        );
        // And not again.
        assert_eq!(run(&conn, &env, &input).unwrap().caught_up, 0);
        for dir in [root, app, custom] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    /// Runs against a copy of a real 0.3 install. Set LOCI_TEST_03_DB (a copy
    /// of loci.db), LOCI_TEST_03_AGENTS (a copy of agents/) and
    /// LOCI_TEST_03_ROSTER (the roster JSON); never point these at live data.
    #[test]
    #[ignore]
    fn migrates_a_real_03_database() {
        let db = PathBuf::from(std::env::var("LOCI_TEST_03_DB").expect("LOCI_TEST_03_DB"));
        let agents =
            PathBuf::from(std::env::var("LOCI_TEST_03_AGENTS").expect("LOCI_TEST_03_AGENTS"));
        let roster: Vec<Value> = serde_json::from_str(
            &std::fs::read_to_string(
                std::env::var("LOCI_TEST_03_ROSTER").expect("LOCI_TEST_03_ROSTER"),
            )
            .unwrap(),
        )
        .unwrap();
        let work = temp_dir("real03");
        let app = work.join("app");
        std::fs::create_dir_all(&app).unwrap();
        std::fs::copy(&db, app.join("loci.db")).unwrap();
        copy_tree(&agents, &app.join("agents")).unwrap();
        let root = work.join("Loci");
        let store = SessionStore::open(app.join("loci.db")).unwrap();
        let conn = store.lock_conn().unwrap();
        let before = snapshot(&conn);
        let env = MigrateEnv {
            root: root.clone(),
            app_data: app.clone(),
        };
        let input = MigrateInput {
            roster: roster.clone(),
            ..Default::default()
        };

        let dry = run(
            &conn,
            &env,
            &MigrateInput {
                dry_run: true,
                ..input.clone()
            },
        )
        .unwrap();
        assert!(!root.exists() || std::fs::read_dir(&root).unwrap().count() == 0);
        let report = run(&conn, &env, &input).unwrap();
        println!("{}", serde_json::to_string_pretty(&json!({
            "dryRun": dry.mentors.iter().map(|m| json!({"id": m.id, "folder": m.folder, "files": m.files})).collect::<Vec<_>>(),
            "orphans": report.orphan_agent_files, "other": report.other_folders,
            "dead": report.dead_tables, "backup": report.backup,
            "mentors": report.mentors.iter().map(|m| json!({"id": m.id, "name": m.name, "folder": m.folder, "workdir": m.workdir, "files": m.files, "progress": m.progress, "conflicts": m.conflicts, "error": m.error})).collect::<Vec<_>>(),
        })).unwrap());
        assert!(report.done);
        assert_eq!(snapshot(&conn), before, "0.3 rows unchanged");
        for mentor in &report.mentors {
            let rows: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM agent_documents WHERE agent_id = ?1",
                    [&mentor.id],
                    |r| r.get(0),
                )
                .unwrap();
            let indexed = index::list(&conn, &mentor.id, &[Kind::Source, Kind::Guide]).unwrap();
            assert_eq!(
                indexed.len() as i64,
                rows,
                "every document of {} is a file",
                mentor.id
            );
            assert!(indexed.iter().all(|r| r.error.is_none()));
            // Each file reads back as its row.
            for row in &indexed {
                let (body, title): (String, String) = conn
                    .query_row(
                        "SELECT body, title FROM agent_documents WHERE agent_id = ?1 AND id = ?2",
                        params![mentor.id, row.id],
                        |r| Ok((r.get(0)?, r.get(1)?)),
                    )
                    .unwrap();
                let full = index::get(&conn, &mentor.id, Kind::parse(&row.kind).unwrap(), &row.id)
                    .unwrap()
                    .unwrap();
                assert_eq!(full.body.as_deref(), Some(body.as_str()));
                assert_eq!(full.title, title);
            }
            let courses: Vec<(String, String)> = {
                let mut s = conn
                    .prepare("SELECT id, data_json FROM courses WHERE agent_id = ?1")
                    .unwrap();
                s.query_map([&mentor.id], |r| Ok((r.get(0)?, r.get(1)?)))
                    .unwrap()
                    .map(Result::unwrap)
                    .collect()
            };
            for (id, data) in courses {
                let row = index::get(&conn, &mentor.id, Kind::Course, &id)
                    .unwrap()
                    .unwrap();
                assert!(row.error.is_none(), "{:?}", row.error);
                assert_eq!(
                    serde_json::from_str::<Value>(row.body.as_deref().unwrap()).unwrap(),
                    serde_json::from_str::<Value>(&data).unwrap()
                );
            }
            let old: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM course_progress WHERE agent_id = ?1",
                    [&mentor.id],
                    |r| r.get(0),
                )
                .unwrap();
            let new: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM lesson_progress WHERE agent_id = ?1",
                    [&mentor.id],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(old, new);
        }
        let again = run(&conn, &env, &input).unwrap();
        assert!(again.mentors.is_empty() && again.caught_up == 0);
        drop(conn);
        std::fs::remove_dir_all(work).unwrap();
    }
}
