//! Exporting a mentor is zipping its folder; importing is unzipping it into
//! the mentors root.
//!
//! The zip holds the folder's files (without `repos/` and `lab/` unless
//! asked), a `manifest.json` with each file's SHA-256 and the repositories
//! to clone again, and `.loci-state/`: reading progress, highlights and
//! notes on its documents and files, and view state. Conversations stay
//! behind. An import checks every path and hash, never follows or writes a
//! link, refuses oversized archives, and gives the mentor a new id when this
//! install already has one with its id.

use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};

use rusqlite::{params, Connection};
use serde::Serialize;
use serde_json::{json, Map, Value};

use super::fsio::sha256;
use super::index;
use super::paths::{self, MENTOR_FILE, REMOVED_MENTOR_FILE};
use super::registry::{self, MentorRecord};
use super::{ctx_for, MentorCtx};
use crate::session_store::now_millis;

pub const FORMAT: &str = "loci-mentor";
pub const FORMAT_VERSION: u64 = 1;
const MANIFEST: &str = "manifest.json";
const STATE_DIR: &str = ".loci-state";
const FILE_MAX: u64 = 200 * 1024 * 1024;
const TOTAL_MAX: u64 = 2 * 1024 * 1024 * 1024;
const ENTRIES_MAX: usize = 200_000;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportSummary {
    pub path: String,
    pub files: usize,
    pub bytes: u64,
    pub repos: Vec<Value>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSummary {
    pub id: String,
    pub folder: String,
    pub renamed_id: bool,
    pub files: usize,
    pub progress: usize,
    pub annotations: usize,
}

fn skip(rel: &Path, with_repos: bool) -> bool {
    let first = rel
        .components()
        .next()
        .and_then(|c| c.as_os_str().to_str())
        .unwrap_or("");
    let name = rel.file_name().and_then(|n| n.to_str()).unwrap_or("");
    (!with_repos && (first == "repos" || first == "lab"))
        || name == ".DS_Store"
        || name == REMOVED_MENTOR_FILE
        || first == STATE_DIR
        || name.ends_with(".tmp")
        || rel.components().any(|c| c.as_os_str() == ".git") && !with_repos
}

fn walk(dir: &Path, base: &Path, with_repos: bool, out: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        let Ok(rel) = path.strip_prefix(base) else {
            continue;
        };
        if skip(rel, with_repos) || kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            walk(&path, base, with_repos, out)?;
        } else if kind.is_file() {
            out.push(rel.to_path_buf());
        }
    }
    Ok(())
}

/// Each repository under `repos/` (one or two levels deep), with where it
/// came from and the commit it is at, so it can be cloned again.
fn repos(folder: &Path) -> Vec<Value> {
    let mut found = Vec::new();
    let mut look = |dir: &Path| {
        let git = dir.join(".git");
        if !git.exists() {
            return false;
        }
        let config = std::fs::read_to_string(git.join("config")).unwrap_or_default();
        let remote = config
            .lines()
            .map(str::trim)
            .find_map(|l| l.strip_prefix("url = ").or_else(|| l.strip_prefix("url=")))
            .map(str::to_string);
        let head = std::fs::read_to_string(git.join("HEAD"))
            .ok()
            .map(|h| h.trim().to_string())
            .and_then(|head| match head.strip_prefix("ref: ") {
                Some(name) => std::fs::read_to_string(git.join(name))
                    .ok()
                    .map(|sha| sha.trim().to_string())
                    .or_else(|| {
                        std::fs::read_to_string(git.join("packed-refs"))
                            .ok()
                            .and_then(|packed| {
                                packed.lines().find_map(|l| {
                                    l.strip_suffix(name).map(|sha| sha.trim().to_string())
                                })
                            })
                    }),
                None => Some(head),
            });
        let rel = dir
            .strip_prefix(folder)
            .unwrap_or(dir)
            .to_string_lossy()
            .into_owned();
        found.push(json!({ "path": rel, "remote": remote, "head": head }));
        true
    };
    if let Ok(entries) = std::fs::read_dir(folder.join("repos")) {
        for entry in entries.flatten().filter(|e| e.path().is_dir()) {
            if !look(&entry.path()) {
                if let Ok(inner) = std::fs::read_dir(entry.path()) {
                    for repo in inner.flatten().filter(|e| e.path().is_dir()) {
                        look(&repo.path());
                    }
                }
            }
        }
    }
    found
}

fn rows(conn: &Connection, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Value>, String> {
    let mut statement = conn.prepare(sql).map_err(|e| e.to_string())?;
    let names: Vec<String> = statement
        .column_names()
        .iter()
        .map(|s| s.to_string())
        .collect();
    let rows = statement
        .query_map(args, |row| {
            let mut object = Map::new();
            for (i, name) in names.iter().enumerate() {
                let value = match row.get_ref(i)? {
                    rusqlite::types::ValueRef::Null => Value::Null,
                    rusqlite::types::ValueRef::Integer(n) => json!(n),
                    rusqlite::types::ValueRef::Real(f) => json!(f),
                    rusqlite::types::ValueRef::Text(t) => json!(String::from_utf8_lossy(t)),
                    rusqlite::types::ValueRef::Blob(_) => Value::Null,
                };
                object.insert(name.clone(), value);
            }
            Ok(Value::Object(object))
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<_, _>>().map_err(|e| e.to_string())
}

/// What lives in SQLite but belongs with the folder, keyed without the
/// agent id so an import can give it another.
fn state(conn: &Connection, agent: &str) -> Result<Value, String> {
    let prefix = format!("{agent}/");
    let annotations = rows(
        conn,
        "SELECT a.id, a.target_kind, substr(a.target_key, length(?1) + 1) AS target_key,
                a.anchors_json, a.note, a.discussions_json, a.created_at, a.updated_at,
                a.anchor_json, s.source_json
         FROM pdf_annotations a LEFT JOIN learning_sources s ON s.id = a.source_id
         WHERE a.target_kind IN ('document', 'mentorFile') AND substr(a.target_key, 1, length(?1)) = ?1",
        [&prefix],
    )?;
    Ok(json!({
        "progress": rows(conn, "SELECT course_id, item_id, status FROM lesson_progress WHERE agent_id = ?1", [agent])?,
        "annotations": annotations,
        "view": rows(conn, "SELECT key, json FROM mentor_state WHERE agent_id = ?1", [agent])?,
    }))
}

pub fn export(
    conn: &Connection,
    agent: &str,
    out: &Path,
    with_repos: bool,
    app_version: &str,
) -> Result<ExportSummary, String> {
    let ctx = ctx_for(conn, agent)?.ok_or("This mentor's content is not in a folder yet")?;
    index::reconcile(conn, &ctx)?;
    let mut files = Vec::new();
    walk(&ctx.folder, &ctx.folder, with_repos, &mut files)?;
    files.sort();
    let identity = registry::read_identity(&ctx.folder)?;
    let temp = out.with_extension("zip.loci-tmp");
    let file = std::fs::File::create(&temp).map_err(|e| format!("{}: {e}", temp.display()))?;
    let mut zip = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .large_file(true);
    let mut listed = Vec::new();
    let mut bytes = 0u64;
    let result = (|| {
        for rel in &files {
            let data = std::fs::read(ctx.folder.join(rel)).map_err(|e| e.to_string())?;
            let name = rel.to_string_lossy().replace('\\', "/");
            zip.start_file(&name, options).map_err(|e| e.to_string())?;
            zip.write_all(&data).map_err(|e| e.to_string())?;
            bytes += data.len() as u64;
            listed.push(json!({ "path": name, "sha256": sha256(&data), "size": data.len() }));
        }
        let state = serde_json::to_vec_pretty(&state(conn, agent)?).map_err(|e| e.to_string())?;
        zip.start_file(format!("{STATE_DIR}/state.json"), options)
            .map_err(|e| e.to_string())?;
        zip.write_all(&state).map_err(|e| e.to_string())?;
        let repos = repos(&ctx.folder);
        let manifest = json!({
            "format": FORMAT,
            "formatVersion": FORMAT_VERSION,
            "schemaVersion": super::format::SCHEMA_VERSION,
            "exportedAt": super::fsio::iso_from_millis(now_millis()),
            "appVersion": app_version,
            "mentor": { "id": agent, "name": identity.get("name") },
            "withRepos": with_repos,
            "files": listed,
            "state": { "path": format!("{STATE_DIR}/state.json"), "sha256": sha256(&state) },
            "repos": repos,
        });
        zip.start_file(MANIFEST, options)
            .map_err(|e| e.to_string())?;
        zip.write_all(&serde_json::to_vec_pretty(&manifest).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        zip.finish().map_err(|e| e.to_string())?;
        Ok::<_, String>(repos)
    })();
    match result {
        Ok(repos) => {
            std::fs::rename(&temp, out).map_err(|e| format!("{}: {e}", out.display()))?;
            Ok(ExportSummary {
                path: out.to_string_lossy().into_owned(),
                files: files.len(),
                bytes,
                repos,
            })
        }
        Err(error) => {
            let _ = std::fs::remove_file(&temp);
            Err(error)
        }
    }
}

/// A zip entry's path, if it is a plain relative path that stays inside.
fn safe_name(name: &str) -> Option<PathBuf> {
    let path = Path::new(name);
    if name.is_empty() || name.contains('\\') || name.contains('\0') {
        return None;
    }
    path.components()
        .all(|c| matches!(c, Component::Normal(_)))
        .then(|| path.to_path_buf())
}

fn read_archive(path: &Path, into: &Path) -> Result<(Value, Option<Value>, usize), String> {
    let file = std::fs::File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| format!("Not a mentor archive: {e}"))?;
    if zip.len() > ENTRIES_MAX {
        return Err("The archive has too many files".into());
    }
    let mut manifest: Option<Value> = None;
    let mut state: Option<Vec<u8>> = None;
    let mut written = Vec::new();
    let mut total = 0u64;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i).map_err(|e| e.to_string())?;
        if entry.is_dir() {
            continue;
        }
        let name = entry.name().map_err(|e| e.to_string())?.to_string();
        if entry.is_symlink() {
            return Err(format!("The archive holds a link: {name}"));
        }
        let rel = safe_name(&name).ok_or_else(|| format!("Unsafe path in the archive: {name}"))?;
        if entry.size() > FILE_MAX {
            return Err(format!("{name} is too large"));
        }
        let mut data = Vec::new();
        entry
            .by_ref()
            .take(FILE_MAX + 1)
            .read_to_end(&mut data)
            .map_err(|e| e.to_string())?;
        if data.len() as u64 > FILE_MAX {
            return Err(format!("{name} is too large"));
        }
        total += data.len() as u64;
        if total > TOTAL_MAX {
            return Err("The archive is too large".into());
        }
        if name == MANIFEST {
            manifest =
                Some(serde_json::from_slice(&data).map_err(|e| format!("manifest.json: {e}"))?);
            continue;
        }
        if name == format!("{STATE_DIR}/state.json") {
            state = Some(data);
            continue;
        }
        let target = into.join(&rel);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(&target, &data).map_err(|e| format!("{}: {e}", target.display()))?;
        written.push((name, sha256(&data)));
    }
    let manifest = manifest.ok_or("The archive has no manifest.json")?;
    if manifest["format"] != FORMAT {
        return Err("Not a Loci mentor archive".into());
    }
    if manifest["formatVersion"]
        .as_u64()
        .is_none_or(|v| v > FORMAT_VERSION)
    {
        return Err("This archive was made by a newer Loci; update Loci to import it".into());
    }
    let expected: std::collections::HashMap<&str, &str> = manifest["files"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|f| Some((f["path"].as_str()?, f["sha256"].as_str()?)))
        .collect();
    if expected.len() != written.len() {
        return Err("The archive's files do not match its manifest".into());
    }
    for (name, hash) in &written {
        if expected.get(name.as_str()) != Some(&hash.as_str()) {
            return Err(format!("{name} does not match its manifest"));
        }
    }
    let state = match state {
        Some(data) => {
            if manifest["state"]["sha256"].as_str() != Some(sha256(&data).as_str()) {
                return Err("The archive's state does not match its manifest".into());
            }
            Some(serde_json::from_slice(&data).map_err(|e| e.to_string())?)
        }
        None => None,
    };
    Ok((manifest, state, written.len()))
}

/// Puts the exported state back under the mentor's (maybe new) id.
fn restore_state(
    conn: &Connection,
    old: &str,
    agent: &str,
    state: &Value,
) -> Result<(usize, usize), String> {
    let renamed = old != agent;
    let mut progress = 0;
    for row in state["progress"].as_array().into_iter().flatten() {
        progress += conn
            .execute(
                "INSERT OR IGNORE INTO lesson_progress (agent_id, course_id, item_id, status, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![agent, row["course_id"].as_str(), row["item_id"].as_str(), row["status"].as_str(), now_millis()],
            )
            .map_err(|e| e.to_string())?;
    }
    for row in state["view"].as_array().into_iter().flatten() {
        conn.execute(
            "INSERT OR IGNORE INTO mentor_state (agent_id, key, json, updated_at) VALUES (?1, ?2, ?3, ?4)",
            params![agent, row["key"].as_str(), row["json"].as_str(), now_millis()],
        )
        .map_err(|e| e.to_string())?;
    }
    let mut annotations = 0;
    for row in state["annotations"].as_array().into_iter().flatten() {
        let Some(id) = row["id"].as_str() else {
            continue;
        };
        let id = if renamed {
            format!("{id}-{}", &agent[..agent.len().min(8)])
        } else {
            id.to_string()
        };
        let source_json = row["source_json"].as_str().map(|s| {
            if renamed {
                s.replace(old, agent)
            } else {
                s.to_string()
            }
        });
        let Some(source_json) = source_json else {
            continue;
        };
        let Ok(source) = serde_json::from_str::<Value>(&source_json) else {
            continue;
        };
        let Some(source_id) = source["id"].as_str() else {
            continue;
        };
        conn.execute(
            "INSERT OR IGNORE INTO learning_sources (id, source_json, created_at) VALUES (?1, ?2, ?3)",
            params![source_id, source_json, now_millis()],
        )
        .map_err(|e| e.to_string())?;
        annotations += conn
            .execute(
                "INSERT OR IGNORE INTO pdf_annotations (id, document_id, source_id, anchors_json, note, discussions_json, created_at, updated_at, target_kind, target_key, anchor_json)
                 VALUES (?1, '', ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                params![
                    id,
                    source_id,
                    row["anchors_json"].as_str().unwrap_or("[]"),
                    row["note"].as_str().unwrap_or(""),
                    // Discussions name conversations of the other install.
                    "[]",
                    row["created_at"].as_i64().unwrap_or(0),
                    row["updated_at"].as_i64().unwrap_or(0),
                    row["target_kind"].as_str(),
                    format!("{agent}/{}", row["target_key"].as_str().unwrap_or("")),
                    row["anchor_json"].as_str(),
                ],
            )
            .map_err(|e| e.to_string())?;
    }
    Ok((progress, annotations))
}

fn register(conn: &Connection, id: &str, folder: &Path) -> Result<MentorCtx, String> {
    let position = registry::list(conn)
        .map_err(|e| e.to_string())?
        .iter()
        .map(|r| r.position)
        .max()
        .unwrap_or(-1)
        + 1;
    registry::upsert(
        conn,
        &MentorRecord {
            id: id.into(),
            folder: folder.to_path_buf(),
            session_id: None,
            position,
            local: Map::new(),
            migrated_at: Some(now_millis()),
            added_at: now_millis(),
        },
    )
    .map_err(|e| e.to_string())?;
    let ctx = ctx_for(conn, id)?.ok_or("The imported mentor is missing")?;
    index::reconcile(conn, &ctx)?;
    Ok(ctx)
}

/// Imports a zip made by `export` into a new folder in the root.
pub fn import_zip(conn: &Connection, root: &Path, archive: &Path) -> Result<ImportSummary, String> {
    std::fs::create_dir_all(root).map_err(|e| format!("{}: {e}", root.display()))?;
    let staging = root.join(format!(".import-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&staging).map_err(|e| e.to_string())?;
    let result = (|| {
        let (_, state, files) = read_archive(archive, &staging)?;
        let mut identity = registry::read_identity(&staging)?;
        let old = identity["id"].as_str().unwrap_or_default().to_string();
        let taken = registry::get(conn, &old)
            .map_err(|e| e.to_string())?
            .is_some();
        let id = if taken {
            uuid::Uuid::new_v4().to_string()
        } else {
            old.clone()
        };
        if taken {
            identity.insert("id".into(), json!(id));
            registry::write_identity(&staging, &identity)?;
        }
        // A workdir of the other machine's does not exist here.
        if registry::custom_workdir(&staging, &identity).is_some_and(|w| !w.is_dir()) {
            identity.remove("workdir");
            registry::write_identity(&staging, &identity)?;
        }
        let slug = paths::mentor_slug(
            identity.get("name").and_then(Value::as_str),
            identity.get("role").and_then(Value::as_str),
            &id,
        );
        let folder = paths::create_folder(root, &slug)?;
        std::fs::remove_dir(&folder).map_err(|e| e.to_string())?;
        std::fs::rename(&staging, &folder).map_err(|e| format!("{}: {e}", folder.display()))?;
        register(conn, &id, &folder)?;
        let (progress, annotations) = match &state {
            Some(state) => restore_state(conn, &old, &id, state)?,
            None => (0, 0),
        };
        Ok(ImportSummary {
            id,
            folder: folder.to_string_lossy().into_owned(),
            renamed_id: taken,
            files,
            progress,
            annotations,
        })
    })();
    if staging.exists() {
        let _ = std::fs::remove_dir_all(&staging);
    }
    result
}

/// Brings back a mentor folder as it is, where it is: one kept after a
/// reset or removal, or copied from elsewhere. Nothing is moved.
pub fn import_folder(conn: &Connection, folder: &Path) -> Result<ImportSummary, String> {
    if !folder.is_absolute() || !folder.is_dir() {
        return Err(format!("Not a folder: {}", folder.display()));
    }
    let file = folder.join(MENTOR_FILE);
    let removed = folder.join(REMOVED_MENTOR_FILE);
    if !file.is_file() && removed.is_file() {
        std::fs::rename(&removed, &file).map_err(|e| e.to_string())?;
    }
    let identity = registry::read_identity(folder)?;
    let id = identity["id"].as_str().unwrap_or_default().to_string();
    if let Some(record) = registry::get(conn, &id).map_err(|e| e.to_string())? {
        if record.folder != folder {
            return Err(format!(
                "A mentor with this id is already at {}",
                record.folder.display()
            ));
        }
    }
    let ctx = register(conn, &id, folder)?;
    let files = index::list(conn, &ctx.agent, &paths::KINDS)
        .map_err(|e| e.to_string())?
        .len();
    Ok(ImportSummary {
        id,
        folder: folder.to_string_lossy().into_owned(),
        renamed_id: false,
        files,
        progress: 0,
        annotations: 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mentor_store::testing::{register as register_test, temp_dir};
    use crate::session_store::SessionStore;

    fn mentor(conn: &Connection, root: &Path) -> PathBuf {
        let folder = root.join("lens");
        register_test(conn, "m-1", &folder);
        let mut identity = registry::read_identity(&folder).unwrap();
        identity.insert("name".into(), json!("Repo Lens"));
        registry::write_identity(&folder, &identity).unwrap();
        for (rel, text) in [
            ("SOUL.md", "soul"),
            ("sources/virtio.md", "---\ntitle: V\nsourceUrl: https://v.org\n---\nrings"),
            ("courses/c.yaml", "title: C\nchapters:\n  - title: x\n    lessons:\n      - id: a\n        title: A\n        document: virtio\n"),
            ("repos/fc/.git/HEAD", "ref: refs/heads/main\n"),
            ("repos/fc/.git/refs/heads/main", "0123abcd\n"),
            ("repos/fc/.git/config", "[remote \"origin\"]\n\turl = https://github.com/f/c\n"),
            ("repos/fc/src/main.rs", "fn main() {}"),
        ] {
            let path = folder.join(rel);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
        }
        let ctx = ctx_for(conn, "m-1").unwrap().unwrap();
        index::reconcile(conn, &ctx).unwrap();
        conn.execute(
            "INSERT INTO lesson_progress VALUES ('m-1','c','a','mastered',1)",
            [],
        )
        .unwrap();
        conn.execute("INSERT INTO learning_sources VALUES ('s1', '{\"id\":\"s1\",\"title\":\"V\",\"quote\":\"rings\",\"kind\":\"document\",\"agentId\":\"m-1\",\"documentId\":\"virtio\"}', 1)", []).unwrap();
        conn.execute("INSERT INTO pdf_annotations(id,document_id,source_id,anchors_json,note,discussions_json,created_at,updated_at,target_kind,target_key,anchor_json) VALUES ('a1','','s1','[]','why','[{\"sessionId\":\"x\"}]',1,1,'document','m-1/virtio','{}')", []).unwrap();
        folder
    }

    #[test]
    fn export_and_import_carry_a_pdf_and_its_sidecar() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("bundle-pdf");
        let folder = root.join("paper-reader");
        register_test(&conn, "m-pdf", &folder);
        std::fs::create_dir_all(folder.join("sources")).unwrap();
        std::fs::write(
            folder.join("sources/firecracker.pdf"),
            crate::mentor_store::pdf::sample_pdf(&["Sandbox page one"]),
        )
        .unwrap();
        std::fs::write(
            folder.join("sources/firecracker.pdf.yaml"),
            "title: Firecracker\nsourceUrl: https://www.usenix.org/system/files/nsdi20-paper-agache.pdf\npages: 1\n",
        )
        .unwrap();
        let out = root.join("paper-reader.zip");
        let summary = export(&conn, "m-pdf", &out, false, "0.4.0").unwrap();
        assert!(summary.files >= 3);

        let other = SessionStore::open_in_memory().unwrap();
        let other_conn = other.lock_conn().unwrap();
        let other_root = temp_dir("bundle-pdf-other");
        let imported = import_zip(&other_conn, &other_root, &out).unwrap();
        let imported_pdf = Path::new(&imported.folder).join("sources/firecracker.pdf");
        assert!(imported_pdf.is_file());
        assert!(Path::new(&imported.folder)
            .join("sources/firecracker.pdf.yaml")
            .is_file());
        let row = index::get(&other_conn, "m-pdf", paths::Kind::Source, "firecracker")
            .unwrap()
            .unwrap();
        assert_eq!(row.meta["pdf"], json!(true));
        assert_eq!(row.meta["pages"], json!(1));
        assert!(row.body.unwrap().contains("Sandbox page one"));
        for dir in [root, other_root] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn a_mentor_round_trips_through_a_zip_with_its_progress_and_marks() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("bundle");
        mentor(&conn, &root);
        let out = root.join("lens.zip");
        let summary = export(&conn, "m-1", &out, false, "0.4.0").unwrap();
        assert_eq!(summary.files, 4); // mentor.json, SOUL.md, the source and the course
        assert_eq!(summary.repos[0]["remote"], "https://github.com/f/c");
        assert_eq!(summary.repos[0]["head"], "0123abcd");

        // Into another install: same id, a folder of its own, state restored.
        let other = SessionStore::open_in_memory().unwrap();
        let other_conn = other.lock_conn().unwrap();
        let other_root = temp_dir("bundle-other");
        let imported = import_zip(&other_conn, &other_root, &out).unwrap();
        assert_eq!(imported.id, "m-1");
        assert_eq!(
            imported.folder,
            other_root.join("repo-lens").to_string_lossy()
        );
        assert_eq!((imported.progress, imported.annotations), (1, 1));
        assert!(!other_root.join("repo-lens/repos").exists());
        assert_eq!(
            index::list(&other_conn, "m-1", &paths::KINDS)
                .unwrap()
                .len(),
            2
        );
        let discussions: String = other_conn
            .query_row("SELECT discussions_json FROM pdf_annotations", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(discussions, "[]");

        // Into the same install: a new id, its marks under the new id.
        let again = import_zip(&conn, &root, &out).unwrap();
        assert!(again.renamed_id);
        assert_ne!(again.id, "m-1");
        let key: String = conn
            .query_row(
                "SELECT target_key FROM pdf_annotations WHERE id <> 'a1'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(key, format!("{}/virtio", again.id));
        assert_eq!(
            registry::read_identity(Path::new(&again.folder)).unwrap()["id"],
            again.id.as_str()
        );
        for dir in [root, other_root] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn note_pictures_beside_a_note_travel_in_the_zip() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("bundle-images");
        let folder = root.join("lens");
        register_test(&conn, "m-1", &folder);
        let mut identity = registry::read_identity(&folder).unwrap();
        identity.insert("name".into(), json!("Repo Lens"));
        identity.insert(
            "defaults".into(),
            json!({"provider": "grok", "model": "grok:deepseek-flash", "mode": "full-access"}),
        );
        registry::write_identity(&folder, &identity).unwrap();
        let notes = folder.join("notes");
        std::fs::create_dir_all(notes.join("assets/n1")).unwrap();
        std::fs::write(
            notes.join("n1.md"),
            "---\ntitle: Sketch\nslug: sketch\n---\n![pic](assets/n1/1-pic.png)\n",
        )
        .unwrap();
        std::fs::write(notes.join("assets/n1/1-pic.png"), b"png bytes").unwrap();
        let ctx = ctx_for(&conn, "m-1").unwrap().unwrap();
        index::reconcile(&conn, &ctx).unwrap();
        let out = root.join("lens.zip");
        export(&conn, "m-1", &out, false, "0.4.0").unwrap();

        let other = SessionStore::open_in_memory().unwrap();
        let other_conn = other.lock_conn().unwrap();
        let other_root = temp_dir("bundle-images-other");
        let imported = import_zip(&other_conn, &other_root, &out).unwrap();
        let imported_folder = PathBuf::from(&imported.folder);
        assert_eq!(
            std::fs::read(imported_folder.join("notes/assets/n1/1-pic.png")).unwrap(),
            b"png bytes"
        );
        assert!(std::fs::read_to_string(imported_folder.join("notes/n1.md"))
            .unwrap()
            .contains("](assets/n1/1-pic.png)"));
        // The mentor's stored defaults came with it, so its first chat keeps them.
        assert_eq!(
            registry::read_identity(&imported_folder).unwrap()["defaults"]["model"],
            "grok:deepseek-flash"
        );
        for dir in [root, other_root] {
            std::fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn a_tampered_or_unsafe_archive_is_refused_and_leaves_nothing() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("bundle-bad");
        let write_zip = |name: &str, entries: &[(&str, &[u8])]| {
            let path = root.join(name);
            let mut zip = zip::ZipWriter::new(std::fs::File::create(&path).unwrap());
            for (entry, data) in entries {
                zip.start_file(*entry, zip::write::SimpleFileOptions::default())
                    .unwrap();
                zip.write_all(data).unwrap();
            }
            zip.finish().unwrap();
            path
        };
        let manifest = |files: Value| {
            serde_json::to_vec(&json!({"format": FORMAT, "formatVersion": 1, "files": files}))
                .unwrap()
        };
        let slip = write_zip(
            "slip.zip",
            &[
                ("../evil.md", b"x"),
                ("manifest.json", &manifest(json!([]))),
            ],
        );
        assert!(import_zip(&conn, &root, &slip)
            .unwrap_err()
            .contains("Unsafe path"));
        assert!(!root.parent().unwrap().join("evil.md").exists());
        let tampered = write_zip(
            "tampered.zip",
            &[
                ("mentor.json", br#"{"schemaVersion":1,"id":"x-1"}"#),
                (
                    "manifest.json",
                    &manifest(json!([{"path":"mentor.json","sha256":"00"}])),
                ),
            ],
        );
        assert!(import_zip(&conn, &root, &tampered)
            .unwrap_err()
            .contains("does not match"));
        let foreign = write_zip(
            "foreign.zip",
            &[("manifest.json", br#"{"format":"other"}"#)],
        );
        assert!(import_zip(&conn, &root, &foreign).is_err());
        let names: Vec<_> = std::fs::read_dir(&root)
            .unwrap()
            .flatten()
            .map(|e| e.file_name())
            .collect();
        assert_eq!(names.len(), 3, "only the zips remain: {names:?}");
        assert!(registry::list(&conn).unwrap().is_empty());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_removed_mentor_folder_comes_back_in_place() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("bundle-folder");
        let folder = mentor(&conn, &root);
        crate::mentor_store::commands::remove(&conn, "m-1").unwrap();
        assert!(folder.join(REMOVED_MENTOR_FILE).is_file());
        let back = import_folder(&conn, &folder).unwrap();
        assert_eq!(back.id, "m-1");
        assert!(folder.join(MENTOR_FILE).is_file());
        assert_eq!(back.files, 2);
        std::fs::remove_dir_all(root).unwrap();
    }
}
