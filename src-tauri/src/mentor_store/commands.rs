//! The Tauri commands of mentors' folders: the roster, the migration, the
//! index and search. The window keeps a copy of the roster in localStorage
//! (so its synchronous reads keep working, and so an older Loci still finds
//! it after a downgrade); the registry and `mentor.json` are the truth.

use std::path::{Path, PathBuf};

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use tauri::{AppHandle, Emitter, Manager, State};

use super::index::{self, Row};
use super::migrate::{self, MigrateEnv, MigrateInput, Report};
use super::paths::{self, Kind, MENTOR_FILE, REMOVED_MENTOR_FILE, SHARED_REPOS};
use super::registry::{self, MentorRecord};
use super::{ctx_for, MentorCtx, MentorsRoot};
use crate::session_store::{now_millis, SessionStore};

pub const MENTORS_CHANGED: &str = "loci:mentors-changed";
pub const CONTENT_CHANGED: &str = "loci:mentor-content-changed";

const LOCAL_FLAGS: [&str; 3] = [
    "accessMigrated",
    "showStartedSessionsInSidebar",
    "useSidebarFolders",
];

/// Sets the mentors root for this build. Debug builds and QA bundles take
/// `LOCI_MENTORS_ROOT`; the installed app always uses `~/Loci`.
pub fn init(app: &AppHandle) -> Result<(), String> {
    let home = crate::dirs_home().ok_or("No home folder")?;
    let root = paths::mentors_root_for(
        &app.config().identifier,
        Path::new(&home),
        std::env::var("LOCI_MENTORS_ROOT").ok().as_deref(),
    );
    app.manage(MentorsRoot(std::sync::Mutex::new(root)));
    Ok(())
}

fn text(entry: &Map<String, Value>, key: &str) -> Option<String> {
    entry
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_string)
}

/// A roster entry as the window's `Agent` type has it.
fn agent_json(record: &MentorRecord, identity: &Map<String, Value>) -> Value {
    let mut agent = Map::new();
    agent.insert("id".into(), json!(record.id));
    if let Some(session) = &record.session_id {
        agent.insert("sessionId".into(), json!(session));
    }
    for key in ["name", "role", "avatar", "color"] {
        if let Some(value) = text(identity, key) {
            agent.insert(key.into(), json!(value));
        }
    }
    let workdir =
        registry::custom_workdir(&record.folder, identity).unwrap_or_else(|| record.folder.clone());
    agent.insert("workdir".into(), json!(workdir.to_string_lossy()));
    agent.insert(
        "projects".into(),
        identity
            .get("folders")
            .cloned()
            .unwrap_or_else(|| json!([])),
    );
    if let Some(defaults) = identity.get("defaults") {
        agent.insert("defaults".into(), defaults.clone());
    }
    for key in LOCAL_FLAGS {
        if let Some(flag) = record.local.get(key) {
            agent.insert(key.into(), flag.clone());
        }
    }
    agent.insert("folder".into(), json!(record.folder.to_string_lossy()));
    Value::Object(agent)
}

/// `defaults` from a roster entry, as `mentor.json` keeps them: the provider,
/// model, permission mode and (when the model has one) the effort. An entry
/// from an older window that does not carry them leaves the file's as they are.
fn roster_defaults(entry: &Map<String, Value>) -> Option<Value> {
    let defaults = entry.get("defaults")?.as_object()?;
    let mut clean = Map::new();
    for key in ["provider", "model", "mode", "effort"] {
        if let Some(value) = defaults
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            clean.insert(key.into(), json!(value));
        }
    }
    if let Some(settings) = defaults.get("modelSettings").and_then(Value::as_object) {
        let settings: Map<String, Value> = settings
            .iter()
            .filter(|(_, value)| value.as_str().is_some_and(|v| !v.is_empty()))
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect();
        if !settings.is_empty() {
            clean.insert("modelSettings".into(), Value::Object(settings));
        }
    }
    let complete = ["provider", "model", "mode"]
        .iter()
        .all(|key| clean.contains_key(*key));
    complete.then_some(Value::Object(clean))
}

/// Folders in the root that hold a `mentor.json` this install does not know
/// yet (copied in, or kept after a reset) become mentors.
fn adopt(conn: &Connection, root: &Path) -> Result<bool, String> {
    if !migrate::marker_set(conn).map_err(|e| e.to_string())? {
        return Ok(false);
    }
    let Ok(entries) = std::fs::read_dir(root) else {
        return Ok(false);
    };
    let known = registry::list(conn).map_err(|e| e.to_string())?;
    let mut position = known.iter().map(|r| r.position).max().unwrap_or(-1);
    let mut adopted = false;
    let mut dirs: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.join(MENTOR_FILE).is_file())
        .filter(|p| p.file_name().and_then(|n| n.to_str()) != Some(SHARED_REPOS))
        .collect();
    dirs.sort();
    for folder in dirs {
        let Ok(identity) = registry::read_identity(&folder) else {
            continue;
        };
        let Some(id) = identity.get("id").and_then(Value::as_str) else {
            continue;
        };
        if known.iter().any(|r| r.id == id || r.folder == folder) {
            continue;
        }
        position += 1;
        let record = MentorRecord {
            id: id.to_string(),
            folder: folder.clone(),
            session_id: None,
            position,
            local: Map::new(),
            migrated_at: Some(now_millis()),
            added_at: now_millis(),
        };
        registry::upsert(conn, &record).map_err(|e| e.to_string())?;
        let workdir = registry::custom_workdir(&folder, &identity);
        index::reconcile(
            conn,
            &MentorCtx {
                agent: id.to_string(),
                folder,
                workdir,
            },
        )?;
        adopted = true;
    }
    Ok(adopted)
}

pub fn load(conn: &Connection, root: &Path) -> Result<Vec<Value>, String> {
    adopt(conn, root)?;
    let mut agents = Vec::new();
    for record in registry::list(conn).map_err(|e| e.to_string())? {
        if record.migrated_at.is_none() {
            continue;
        }
        // A folder that is gone (an unplugged disk) is left registered and
        // comes back with it.
        let Ok(identity) = registry::read_identity(&record.folder) else {
            continue;
        };
        agents.push(agent_json(&record, &identity));
    }
    Ok(agents)
}

/// Brings `mentor.json` and the registry in line with the window's roster,
/// in its order. A new entry gets a folder of its own. Entries missing from
/// the roster are not removed here; only `mentors_remove` removes.
pub fn sync(conn: &Connection, root: &Path, roster: &[Value]) -> Result<bool, String> {
    let ready = migrate::marker_set(conn).map_err(|e| e.to_string())?;
    let mut changed = false;
    for (position, entry) in roster.iter().enumerate() {
        let Some(entry) = entry.as_object() else {
            continue;
        };
        let Some(id) = text(entry, "id")
            .filter(|id| id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'))
        else {
            continue;
        };
        let existing = registry::get(conn, &id).map_err(|e| e.to_string())?;
        let (mut record, mut identity) = match existing {
            Some(record) if record.migrated_at.is_some() => {
                let identity = registry::read_identity(&record.folder).unwrap_or_else(|_| {
                    let mut identity = Map::new();
                    identity.insert("schemaVersion".into(), json!(super::format::SCHEMA_VERSION));
                    identity.insert("id".into(), json!(id));
                    identity
                });
                (record, identity)
            }
            Some(_) => continue,
            None if !ready => continue,
            None => {
                let folder = paths::create_folder(root, &desired_slug(entry, &id))?;
                std::fs::create_dir_all(folder.join(SHARED_REPOS))
                    .map_err(|e| format!("{}: {e}", folder.display()))?;
                let mut identity = Map::new();
                identity.insert("schemaVersion".into(), json!(super::format::SCHEMA_VERSION));
                identity.insert("id".into(), json!(id));
                identity.insert(
                    "createdAt".into(),
                    json!(super::fsio::iso_from_millis(now_millis())),
                );
                changed = true;
                (
                    MentorRecord {
                        id: id.clone(),
                        folder,
                        session_id: None,
                        position: position as i64,
                        local: Map::new(),
                        migrated_at: Some(now_millis()),
                        added_at: now_millis(),
                    },
                    identity,
                )
            }
        };
        let before_identity = identity.clone();
        for key in ["name", "role", "avatar", "color"] {
            match text(entry, key) {
                Some(value) => {
                    identity.insert(key.into(), json!(value));
                }
                None => {
                    identity.remove(key);
                }
            }
        }
        match text(entry, "workdir").map(|w| crate::fs::expand_home(&w)) {
            Some(workdir) if workdir == record.folder => {
                identity.remove("workdir");
            }
            // Chosen folders exist (setting one creates it); a path that does
            // not is a stale copy of a folder that moved, not a choice.
            Some(workdir) if workdir.is_absolute() && workdir.is_dir() => {
                identity.insert("workdir".into(), json!(workdir.to_string_lossy()));
            }
            Some(_) => {}
            None => {
                identity.remove("workdir");
            }
        }
        match entry.get("projects").and_then(Value::as_array) {
            Some(projects) if !projects.is_empty() => {
                identity.insert("folders".into(), Value::Array(projects.clone()));
            }
            _ => {
                identity.remove("folders");
            }
        }
        // Who its next conversation starts as, so a reset, an import or a
        // released empty chat keeps the mentor's provider and permissions.
        if let Some(defaults) = roster_defaults(entry) {
            identity.insert("defaults".into(), defaults);
        }
        // A mentor named after it was made (the CLI names it in a second
        // step) moves to a folder of its name while nothing points at the old one.
        if let Some(folder) = rename_unused(conn, root, &record, entry, &id)? {
            record.folder = folder;
            changed = true;
        }
        if identity != before_identity && registry::write_identity(&record.folder, &identity)? {
            changed = true;
        }
        let before = record.clone();
        record.position = position as i64;
        record.session_id = text(entry, "sessionId");
        for key in LOCAL_FLAGS {
            match entry.get(key).filter(|v| v.is_boolean()) {
                Some(flag) => {
                    record.local.insert(key.into(), flag.clone());
                }
                None => {
                    record.local.remove(key);
                }
            }
        }
        if record != before || changed {
            registry::upsert(conn, &record).map_err(|e| e.to_string())?;
            changed = true;
        }
    }
    Ok(changed)
}

fn valid_slug(slug: &str) -> bool {
    !slug.is_empty()
        && slug.len() <= 40
        && slug != SHARED_REPOS
        && !slug.starts_with('-')
        && !slug.ends_with('-')
        && slug
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// The folder name the window asks for (its name, else its face's name, as
/// 0.3 named workdirs), else one made from its name or role here.
fn desired_slug(entry: &Map<String, Value>, id: &str) -> String {
    text(entry, "slug")
        .filter(|slug| valid_slug(slug))
        .unwrap_or_else(|| {
            paths::mentor_slug(
                text(entry, "name").as_deref(),
                text(entry, "role").as_deref(),
                id,
            )
        })
}

/// A new folder for a mentor whose name changed before anything used its
/// folder: no conversation, no content, nothing in `repos/`, no workdir of
/// the user's. Anything else keeps its path, as workdirs always have.
fn rename_unused(
    conn: &Connection,
    root: &Path,
    record: &MentorRecord,
    entry: &Map<String, Value>,
    id: &str,
) -> Result<Option<PathBuf>, String> {
    let slug = desired_slug(entry, id);
    let name = record
        .folder
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default();
    if name == slug
        || name.strip_prefix(&slug).is_some_and(|rest| {
            rest.starts_with('-') && rest[1..].bytes().all(|b| b.is_ascii_digit())
        })
        || record.session_id.is_some()
        || text(entry, "sessionId").is_some()
        || record.folder.parent() != Some(root)
        || text(entry, "workdir").is_some_and(|w| crate::fs::expand_home(&w) != record.folder)
        || !index::list(conn, id, &paths::KINDS)
            .map_err(|e| e.to_string())?
            .is_empty()
    {
        return Ok(None);
    }
    let repos = record.folder.join(SHARED_REPOS);
    if std::fs::read_dir(&repos).is_ok_and(|mut entries| entries.next().is_some()) {
        return Ok(None);
    }
    let target = paths::create_folder(root, &slug)?;
    std::fs::remove_dir(&target).map_err(|e| e.to_string())?;
    std::fs::rename(&record.folder, &target).map_err(|e| format!("{}: {e}", target.display()))?;
    Ok(Some(target))
}

/// Forgets a mentor. Its folder stays, with `mentor.json` renamed so it is
/// not adopted again; renaming it back (or `loci mentors import --folder`)
/// brings the mentor back.
pub fn remove(conn: &Connection, id: &str) -> Result<(), String> {
    let Some(record) = registry::get(conn, id).map_err(|e| e.to_string())? else {
        return Ok(());
    };
    let file = record.folder.join(MENTOR_FILE);
    if file.is_file() {
        std::fs::rename(&file, record.folder.join(REMOVED_MENTOR_FILE))
            .map_err(|e| format!("{}: {e}", file.display()))?;
    }
    registry::remove(conn, id).map_err(|e| e.to_string())?;
    index::forget_mentor(conn, id).map_err(|e| e.to_string())?;
    Ok(())
}

fn app_data(app: &AppHandle) -> Result<PathBuf, String> {
    app.path().app_data_dir().map_err(|e| e.to_string())
}

fn notify_mentors(app: &AppHandle) {
    let _ = app.emit(MENTORS_CHANGED, ());
}

#[tauri::command(async)]
pub fn mentors_load(
    store: State<'_, SessionStore>,
    root: State<'_, MentorsRoot>,
) -> Result<Vec<Value>, String> {
    let conn = store.lock_conn()?;
    load(&conn, &root.path())
}

/// Saves the window's roster; returns it as the registry now has it (a new
/// mentor comes back with its folder as its workdir).
#[tauri::command(async)]
pub fn mentors_sync(
    app: AppHandle,
    store: State<'_, SessionStore>,
    root: State<'_, MentorsRoot>,
    roster: Vec<Value>,
) -> Result<Vec<Value>, String> {
    let conn = store.lock_conn()?;
    let changed = sync(&conn, &root.path(), &roster)?;
    let agents = load(&conn, &root.path())?;
    drop(conn);
    if changed {
        notify_mentors(&app);
    }
    Ok(agents)
}

#[tauri::command(async)]
pub fn mentors_remove(
    app: AppHandle,
    store: State<'_, SessionStore>,
    id: String,
) -> Result<(), String> {
    crate::session_store::validate_id(&id, "agent")?;
    let conn = store.lock_conn()?;
    remove(&conn, &id)?;
    drop(conn);
    notify_mentors(&app);
    Ok(())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageStatus {
    /// Whether the 0.3 roster is in folders; until then the window's roster is the truth.
    pub ready: bool,
    pub root: String,
    pub mentors: Vec<Value>,
}

pub fn status(conn: &Connection, root: &Path) -> Result<StorageStatus, String> {
    let mut mentors = Vec::new();
    for record in registry::list(conn).map_err(|e| e.to_string())? {
        let counts: Vec<(String, i64, i64)> = {
            let mut statement = conn
                .prepare(
                    "SELECT kind, COUNT(*), SUM(error IS NOT NULL) FROM mentor_content WHERE agent_id = ?1 GROUP BY kind",
                )
                .map_err(|e| e.to_string())?;
            let rows = statement
                .query_map([&record.id], |row| {
                    Ok((row.get(0)?, row.get(1)?, row.get(2)?))
                })
                .map_err(|e| e.to_string())?;
            rows.collect::<Result<_, _>>().map_err(|e| e.to_string())?
        };
        let mut files = Map::new();
        let mut problems = 0;
        for (kind, count, errors) in counts {
            files.insert(kind, json!(count));
            problems += errors;
        }
        let identity = registry::read_identity(&record.folder).ok();
        mentors.push(json!({
            "id": record.id,
            "name": identity.as_ref().and_then(|i| text(i, "name")),
            "folder": record.folder.to_string_lossy(),
            "folderPresent": record.folder.join(MENTOR_FILE).is_file(),
            "migrated": record.migrated_at.is_some(),
            "files": files,
            "problems": problems,
        }));
    }
    Ok(StorageStatus {
        ready: migrate::marker_set(conn).map_err(|e| e.to_string())?,
        root: root.to_string_lossy().into_owned(),
        mentors,
    })
}

#[tauri::command(async)]
pub fn storage_status(
    store: State<'_, SessionStore>,
    root: State<'_, MentorsRoot>,
) -> Result<StorageStatus, String> {
    let conn = store.lock_conn()?;
    status(&conn, &root.path())
}

#[tauri::command(async)]
pub fn storage_migrate(
    app: AppHandle,
    store: State<'_, SessionStore>,
    root: State<'_, MentorsRoot>,
    input: MigrateInput,
) -> Result<Report, String> {
    let env = MigrateEnv {
        root: root.path(),
        app_data: app_data(&app)?,
    };
    let conn = store.lock_conn()?;
    let report = migrate::run(&conn, &env, &input)?;
    drop(conn);
    if !input.dry_run && (!report.mentors.is_empty() || report.caught_up > 0) {
        notify_mentors(&app);
    }
    Ok(report)
}

/// Re-reads mentors' folders (one, or all) and reports what changed.
pub fn reindex(conn: &Connection, agent: Option<&str>) -> Result<Value, String> {
    let mut out = Vec::new();
    for record in registry::list(conn).map_err(|e| e.to_string())? {
        if agent.is_some_and(|a| a != record.id) {
            continue;
        }
        let Some(ctx) = ctx_for(conn, &record.id)? else {
            continue;
        };
        let changes = index::reconcile(conn, &ctx)?;
        out.push(json!({ "id": record.id, "changed": changes.len() }));
    }
    Ok(Value::Array(out))
}

#[tauri::command(async)]
pub fn storage_reindex(
    app: AppHandle,
    store: State<'_, SessionStore>,
    agent: Option<String>,
) -> Result<Value, String> {
    let conn = store.lock_conn()?;
    let result = reindex(&conn, agent.as_deref())?;
    drop(conn);
    let _ = app.emit(CONTENT_CHANGED, json!({ "agentId": agent }));
    Ok(result)
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Problem {
    pub path: String,
    pub kind: String,
    pub id: String,
    pub error: String,
}

pub fn check(conn: &Connection, agent: &str) -> Result<Vec<Problem>, String> {
    let Some(ctx) = ctx_for(conn, agent)? else {
        return Err("This mentor's content is not in a folder yet".into());
    };
    index::reconcile(conn, &ctx)?;
    Ok(index::problems(conn, agent)
        .map_err(|e| e.to_string())?
        .into_iter()
        .map(|row: Row| Problem {
            path: ctx
                .folder
                .join(&row.rel_path)
                .to_string_lossy()
                .into_owned(),
            kind: row.kind,
            id: row.id,
            error: row.error.unwrap_or_default(),
        })
        .collect())
}

#[tauri::command(async)]
pub fn library_check(
    store: State<'_, SessionStore>,
    agent: String,
) -> Result<Vec<Problem>, String> {
    crate::session_store::validate_id(&agent, "agent")?;
    let conn = store.lock_conn()?;
    check(&conn, &agent)
}

#[tauri::command(async)]
pub fn library_search(
    store: State<'_, SessionStore>,
    agent: Option<String>,
    query: String,
    limit: Option<usize>,
) -> Result<Vec<index::Hit>, String> {
    if query.chars().count() > 200 {
        return Err("The query is too long".into());
    }
    let conn = store.lock_conn()?;
    index::search(&conn, agent.as_deref(), &query, limit.unwrap_or(20)).map_err(|e| e.to_string())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StateWrite {
    agent: String,
    key: String,
    /// `null` forgets it.
    value: Value,
}

/// Every mentor's state under `key`, as `{agentId: value}`.
#[tauri::command(async)]
pub fn mentor_state_all(store: State<'_, SessionStore>, key: String) -> Result<Value, String> {
    let conn = store.lock_conn()?;
    let mut statement = conn
        .prepare("SELECT agent_id, json FROM mentor_state WHERE key = ?1")
        .map_err(|e| e.to_string())?;
    let rows = statement
        .query_map([&key], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| e.to_string())?;
    let mut out = Map::new();
    for row in rows {
        let (agent, raw) = row.map_err(|e| e.to_string())?;
        out.insert(agent, serde_json::from_str(&raw).unwrap_or(Value::Null));
    }
    Ok(Value::Object(out))
}

#[tauri::command(async)]
pub fn mentor_state_set(
    store: State<'_, SessionStore>,
    writes: Vec<StateWrite>,
) -> Result<(), String> {
    let conn = store.lock_conn()?;
    for write in writes {
        if write.key.len() > 64 || write.agent.len() > 64 {
            return Err("Not a mentor state key".into());
        }
        if write.value.is_null() {
            conn.execute(
                "DELETE FROM mentor_state WHERE agent_id = ?1 AND key = ?2",
                params![write.agent, write.key],
            )
        } else {
            conn.execute(
                "INSERT INTO mentor_state (agent_id, key, json, updated_at) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(agent_id, key) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at",
                params![write.agent, write.key, write.value.to_string(), now_millis()],
            )
        }
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Zips a mentor's folder (without repos/ and lab/ unless asked) to `path`.
#[tauri::command(async)]
pub fn mentors_export(
    app: AppHandle,
    store: State<'_, SessionStore>,
    agent: String,
    path: String,
    with_repos: Option<bool>,
) -> Result<super::bundle::ExportSummary, String> {
    crate::session_store::validate_id(&agent, "agent")?;
    let out = crate::fs::expand_home(&path);
    if !out.is_absolute() {
        return Err("path must be an absolute path for the .zip".into());
    }
    let version = app.package_info().version.to_string();
    let conn = store.lock_conn()?;
    super::bundle::export(&conn, &agent, &out, with_repos.unwrap_or(false), &version)
}

/// Imports a mentor from an exported .zip (`path`) or adopts a mentor folder
/// where it is (`folder`).
#[tauri::command(async)]
pub fn mentors_import(
    app: AppHandle,
    store: State<'_, SessionStore>,
    root: State<'_, MentorsRoot>,
    path: Option<String>,
    folder: Option<String>,
) -> Result<super::bundle::ImportSummary, String> {
    let conn = store.lock_conn()?;
    let summary = match (path, folder) {
        (Some(path), None) => {
            super::bundle::import_zip(&conn, &root.path(), &crate::fs::expand_home(&path))?
        }
        (None, Some(folder)) => {
            super::bundle::import_folder(&conn, &crate::fs::expand_home(&folder))?
        }
        _ => return Err("Give the .zip to import or the folder to bring back, not both".into()),
    };
    drop(conn);
    notify_mentors(&app);
    Ok(summary)
}

/// The kinds a window refreshes on, by the event it already listens to.
pub fn kind_event(kind: Kind) -> &'static str {
    match kind {
        Kind::Source | Kind::Guide => "documents",
        Kind::Course => "courses",
        Kind::Note => "notes",
        Kind::Canvas => "canvases",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mentor_store::testing::temp_dir;

    fn ready(conn: &Connection) {
        conn.execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (?1, 1)",
            [migrate::MARKER_VERSION],
        )
        .unwrap();
    }

    #[test]
    fn a_new_mentor_gets_a_folder_and_the_roster_round_trips() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("roster");
        ready(&conn);
        let roster = vec![
            json!({"id":"m-1","name":"Repo Lens","avatar":"nova","color":"red","projects":["/p"],"accessMigrated":true}),
        ];
        assert!(sync(&conn, &root, &roster).unwrap());
        let agents = load(&conn, &root).unwrap();
        assert_eq!(agents.len(), 1);
        let folder = root.join("repo-lens");
        assert_eq!(agents[0]["workdir"], folder.to_string_lossy().as_ref());
        assert_eq!(agents[0]["projects"], json!(["/p"]));
        assert_eq!(agents[0]["accessMigrated"], true);
        assert!(folder.join("repos").is_dir());
        let identity = registry::read_identity(&folder).unwrap();
        assert_eq!(identity["name"], "Repo Lens");
        assert!(identity.get("workdir").is_none());

        // Renaming keeps the folder; a custom workdir is recorded; same roster is no change.
        let mut renamed = agents[0].clone();
        renamed["name"] = json!("Lens");
        let study = root.join("elsewhere/study");
        std::fs::create_dir_all(&study).unwrap();
        renamed["workdir"] = json!(study.to_string_lossy());
        renamed["sessionId"] = json!("s-9");
        assert!(sync(&conn, &root, &[renamed.clone()]).unwrap());
        assert!(!sync(&conn, &root, &[renamed]).unwrap());
        let agents = load(&conn, &root).unwrap();
        assert_eq!(agents[0]["name"], "Lens");
        assert_eq!(agents[0]["workdir"], study.to_string_lossy().as_ref());
        // A stale workdir that no longer exists is not taken as a choice.
        let mut stale = agents[0].clone();
        stale["workdir"] = json!("/nonexistent/old-folder");
        sync(&conn, &root, &[stale]).unwrap();
        assert_eq!(
            load(&conn, &root).unwrap()[0]["workdir"],
            study.to_string_lossy().as_ref()
        );
        assert_eq!(agents[0]["sessionId"], "s-9");
        assert_eq!(agents[0]["folder"], folder.to_string_lossy().as_ref());

        // Removing keeps the folder and does not adopt it again.
        remove(&conn, "m-1").unwrap();
        assert!(load(&conn, &root).unwrap().is_empty());
        assert!(folder.join(REMOVED_MENTOR_FILE).is_file());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_mentors_defaults_are_written_to_mentor_json_and_read_back() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("defaults");
        ready(&conn);
        let roster = vec![json!({
            "id": "m-1", "avatar": "ember", "name": "E2B Reader",
            "defaults": {"provider": "grok", "model": "grok:deepseek-flash", "mode": "full-access",
                         "effort": "high", "modelSettings": {"effort": "high"}}
        })];
        sync(&conn, &root, &roster).unwrap();
        let folder = root.join("e2b-reader");
        let identity = registry::read_identity(&folder).unwrap();
        assert_eq!(identity["defaults"]["provider"], "grok");
        assert_eq!(identity["defaults"]["model"], "grok:deepseek-flash");
        assert_eq!(identity["defaults"]["mode"], "full-access");
        assert_eq!(identity["defaults"]["effort"], "high");
        assert_eq!(identity["defaults"]["modelSettings"]["effort"], "high");
        // The window sees them, so a new chat can start from them.
        let agents = load(&conn, &root).unwrap();
        assert_eq!(agents[0]["defaults"], identity["defaults"]);
        // A later change of model is written, and an entry without defaults
        // (an older window) leaves the file's.
        let changed = vec![json!({
            "id": "m-1", "avatar": "ember", "name": "E2B Reader",
            "defaults": {"provider": "grok", "model": "grok:other", "mode": "supervised"}
        })];
        assert!(sync(&conn, &root, &changed).unwrap());
        let identity = registry::read_identity(&folder).unwrap();
        assert_eq!(identity["defaults"]["model"], "grok:other");
        assert_eq!(identity["defaults"]["mode"], "supervised");
        assert!(identity["defaults"].get("effort").is_none());
        sync(
            &conn,
            &root,
            &[json!({"id": "m-1", "avatar": "ember", "name": "E2B Reader"})],
        )
        .unwrap();
        assert_eq!(
            registry::read_identity(&folder).unwrap()["defaults"]["model"],
            "grok:other"
        );
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_mentor_named_after_it_was_made_moves_to_a_folder_of_its_name_until_it_is_used() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("rename");
        ready(&conn);
        sync(
            &conn,
            &root,
            &[json!({"id":"m-1","avatar":"ember","slug":"ember"})],
        )
        .unwrap();
        assert!(root.join("ember").is_dir());
        sync(
            &conn,
            &root,
            &[json!({"id":"m-1","avatar":"ember","name":"E2B Reader","slug":"e2b-reader"})],
        )
        .unwrap();
        assert!(!root.join("ember").exists());
        let agents = load(&conn, &root).unwrap();
        assert_eq!(
            agents[0]["folder"],
            root.join("e2b-reader").to_string_lossy().as_ref()
        );
        assert_eq!(
            agents[0]["workdir"],
            root.join("e2b-reader").to_string_lossy().as_ref()
        );
        // Once it has a conversation, it keeps its folder whatever it is called.
        sync(&conn, &root, &[json!({"id":"m-1","avatar":"ember","name":"E2B Reader","slug":"e2b-reader","sessionId":"s1"})]).unwrap();
        sync(
            &conn,
            &root,
            &[json!({"id":"m-1","avatar":"ember","name":"Other","slug":"other","sessionId":"s1"})],
        )
        .unwrap();
        assert!(root.join("e2b-reader").is_dir() && !root.join("other").exists());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn nothing_is_created_before_the_migration_has_run() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("roster");
        assert!(!sync(&conn, &root, &[json!({"id":"m-1","name":"A"})]).unwrap());
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 0);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_mentor_folder_copied_into_the_root_is_adopted() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("adopt");
        ready(&conn);
        let folder = root.join("copied");
        std::fs::create_dir_all(folder.join("guides")).unwrap();
        std::fs::write(
            folder.join(MENTOR_FILE),
            r#"{"schemaVersion":1,"id":"m-7","name":"Copied"}"#,
        )
        .unwrap();
        std::fs::write(folder.join("guides/g.md"), "# G").unwrap();
        std::fs::create_dir_all(root.join("ember/repos")).unwrap();
        let agents = load(&conn, &root).unwrap();
        assert_eq!(agents.len(), 1);
        assert_eq!(agents[0]["name"], "Copied");
        assert_eq!(index::list(&conn, "m-7", &[Kind::Guide]).unwrap().len(), 1);
        let status = status(&conn, &root).unwrap();
        assert!(status.ready);
        assert_eq!(status.mentors[0]["files"]["guide"], 1);
        std::fs::remove_dir_all(root).unwrap();
    }
}
