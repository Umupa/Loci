//! Watching mentors' folders, so a file the mentor's CLI or the user's editor
//! changes shows up in the app without a reload.
//!
//! Only the folders that hold content are watched, each on its own and not
//! recursively: the root (mentors added or removed), each mentor folder
//! (`mentor.json`, `SOUL.md`, `MEMORY.md`), its five content folders and
//! `memory/`. `repos/` and `lab/` are never watched, so a large checkout
//! costs nothing. Events are gathered for a moment, then each changed file
//! is indexed; the app's own writes were indexed when they were made, so
//! their echo finds the same hash and reports nothing.

use std::collections::{BTreeSet, HashSet};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, RecvTimeoutError};
use std::time::{Duration, Instant};

use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use rusqlite::Connection;
use serde_json::json;
use tauri::{AppHandle, Emitter, Manager};

use super::commands::{kind_event, CONTENT_CHANGED, MENTORS_CHANGED};
use super::index::{self, Change};
use super::paths::{classify, KINDS, MENTOR_FILE};
use super::{ctx_for, registry, MentorsRoot};
use crate::session_store::SessionStore;

const SETTLE: Duration = Duration::from_millis(200);
const RESCAN_FOLDERS: Duration = Duration::from_secs(5);

/// What one batch of file events comes to, for the window.
#[derive(Debug, Default, PartialEq)]
pub struct Outcome {
    pub roster: bool,
    /// `(agent, event kind, id)`: documents, courses, notes, canvases, files.
    pub content: BTreeSet<(String, String, String)>,
}

/// The folders to watch for the mentors this install knows.
pub fn watched_dirs(conn: &Connection, root: &Path) -> Vec<PathBuf> {
    let mut dirs = vec![root.to_path_buf()];
    for record in registry::list(conn).unwrap_or_default() {
        if record.migrated_at.is_none() || !record.folder.is_dir() {
            continue;
        }
        dirs.push(record.folder.clone());
        dirs.push(record.folder.join("memory"));
        for kind in KINDS {
            dirs.push(record.folder.join(kind.dir()));
        }
    }
    dirs
}

/// Indexes the files of one batch of events and says what the window
/// should refresh.
pub fn apply(conn: &Connection, root: &Path, paths: &HashSet<PathBuf>, rescan: bool) -> Outcome {
    let mut outcome = Outcome::default();
    // Events may name the real path (/private/var/... for /var/...).
    let records: Vec<_> = registry::list(conn)
        .unwrap_or_default()
        .into_iter()
        .flat_map(|record| {
            let real = record
                .folder
                .canonicalize()
                .ok()
                .filter(|real| *real != record.folder);
            let alias = real.map(|folder| registry::MentorRecord {
                folder,
                ..record.clone()
            });
            std::iter::once(record).chain(alias)
        })
        .collect();
    let real_root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    if rescan {
        let mut done = HashSet::new();
        for record in records
            .iter()
            .filter(|r| r.folder.join(MENTOR_FILE).is_file())
        {
            if !done.insert(record.id.clone()) {
                continue;
            }
            if let Ok(Some(ctx)) = ctx_for(conn, &record.id) {
                for (kind, id, _) in index::reconcile(conn, &ctx).unwrap_or_default() {
                    outcome
                        .content
                        .insert((record.id.clone(), kind_event(kind).into(), id));
                }
                outcome
                    .content
                    .insert((record.id.clone(), "files".into(), String::new()));
            }
        }
        outcome.roster = true;
        return outcome;
    }
    for path in paths {
        if path.parent() == Some(root) || path.parent() == Some(real_root.as_path()) {
            // A mentor folder appeared or went away.
            outcome.roster = true;
            continue;
        }
        let Some(record) = records
            .iter()
            .filter(|r| r.migrated_at.is_some())
            .find(|r| path.starts_with(&r.folder))
        else {
            continue;
        };
        let Ok(relative) = path.strip_prefix(&record.folder) else {
            continue;
        };
        let rel = relative.to_string_lossy();
        if rel == MENTOR_FILE {
            outcome.roster = true;
            continue;
        }
        if rel == "SOUL.md" || rel == "MEMORY.md" || rel.starts_with("memory/") {
            outcome
                .content
                .insert((record.id.clone(), "files".into(), String::new()));
            continue;
        }
        let Some((kind, id)) = classify(&record.folder, path) else {
            continue;
        };
        let Ok(Some(ctx)) = ctx_for(conn, &record.id) else {
            continue;
        };
        let file = if path.exists() {
            path.clone()
        } else {
            // Gone: forget the row under whichever extension it had.
            index::get(conn, &record.id, kind, &id)
                .ok()
                .flatten()
                .map_or(path.clone(), |row| record.folder.join(row.rel_path))
        };
        match index::index_file(conn, &ctx, kind, &id, &file, false) {
            Ok(Change::Unchanged) | Err(_) => {}
            Ok(_) => {
                outcome
                    .content
                    .insert((record.id.clone(), kind_event(kind).into(), id));
            }
        }
    }
    outcome
}

fn emit(app: &AppHandle, outcome: &Outcome) {
    if outcome.roster {
        let _ = app.emit(MENTORS_CHANGED, ());
    }
    for (agent, kind, id) in &outcome.content {
        let _ = app.emit(
            CONTENT_CHANGED,
            json!({ "agentId": agent, "kind": kind, "id": if id.is_empty() { None } else { Some(id) } }),
        );
    }
}

/// Starts watching on a thread of its own. Failing to watch is not fatal:
/// the app still reads files fresh when it opens them.
pub fn start(app: &AppHandle) {
    let app = app.clone();
    std::thread::Builder::new()
        .name("loci-mentor-watch".into())
        .spawn(move || {
            if let Err(error) = run(&app) {
                eprintln!("Mentor folders are not watched: {error}");
            }
        })
        .ok();
}

fn run(app: &AppHandle) -> Result<(), String> {
    let root = app.state::<MentorsRoot>().path();
    let (sender, events) = channel();
    let mut watcher: RecommendedWatcher =
        notify::recommended_watcher(sender).map_err(|e| e.to_string())?;
    let mut watching: HashSet<PathBuf> = HashSet::new();
    let mut last_scan = Instant::now() - RESCAN_FOLDERS;
    let mut pending: HashSet<PathBuf> = HashSet::new();
    let mut rescan = false;
    let mut first: Option<Instant> = None;
    loop {
        if last_scan.elapsed() >= RESCAN_FOLDERS {
            last_scan = Instant::now();
            let wanted: HashSet<PathBuf> = {
                let store = app.state::<SessionStore>();
                let Ok(conn) = store.lock_conn() else {
                    continue;
                };
                watched_dirs(&conn, &root).into_iter().collect()
            };
            let mut added = false;
            for dir in wanted.difference(&watching.clone()) {
                if dir.is_dir() && watcher.watch(dir, RecursiveMode::NonRecursive).is_ok() {
                    watching.insert(dir.clone());
                    added = true;
                }
            }
            // At start, and whenever a folder is newly watched, catch up on
            // whatever changed while nobody was watching.
            if added {
                rescan = true;
                first.get_or_insert_with(Instant::now);
            }
            for dir in watching.clone().difference(&wanted) {
                let _ = watcher.unwatch(dir);
                watching.remove(dir);
            }
            // A content folder made after its mentor was first watched.
            watching.retain(|dir| dir.is_dir());
        }
        match events.recv_timeout(Duration::from_millis(250)) {
            Ok(Ok(event)) => {
                if event.need_rescan() {
                    rescan = true;
                }
                pending.extend(event.paths);
                first.get_or_insert_with(Instant::now);
            }
            Ok(Err(_)) => {
                rescan = true;
                first.get_or_insert_with(Instant::now);
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return Ok(()),
        }
        if first.is_some_and(|at| at.elapsed() >= SETTLE) {
            let outcome = {
                let store = app.state::<SessionStore>();
                let Ok(conn) = store.lock_conn() else {
                    continue;
                };
                apply(&conn, &root, &pending, rescan)
            };
            pending.clear();
            rescan = false;
            first = None;
            if outcome.roster {
                // New folders are watched on the next pass.
                last_scan = Instant::now() - RESCAN_FOLDERS;
            }
            emit(app, &outcome);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mentor_store::testing::{register, temp_dir};

    #[test]
    fn a_batch_of_edits_is_indexed_and_the_apps_own_writes_report_nothing() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("watch");
        let folder = root.join("lens");
        register(&conn, "m1", &folder);
        let ctx = ctx_for(&conn, "m1").unwrap().unwrap();
        let dirs = watched_dirs(&conn, &root);
        assert!(dirs.contains(&folder.join("sources")));
        assert!(!dirs.iter().any(|d| d.ends_with("repos")));

        // The app writes a guide: its echo changes nothing.
        crate::mentor_store::write_content(
            &conn,
            &ctx,
            crate::mentor_store::paths::Kind::Guide,
            "g",
            "# G\n",
        )
        .unwrap();
        let echo = apply(
            &conn,
            &root,
            &HashSet::from([folder.join("guides/g.md")]),
            false,
        );
        assert_eq!(echo, Outcome::default());

        // The user edits it, adds a course, touches the Soul and repos/.
        std::fs::write(folder.join("guides/g.md"), "# G edited\n").unwrap();
        std::fs::create_dir_all(folder.join("courses")).unwrap();
        std::fs::write(folder.join("courses/c.yaml"), "title: C\nchapters:\n  - title: x\n    lessons:\n      - id: a\n        title: A\n        document: g\n").unwrap();
        std::fs::write(folder.join("SOUL.md"), "soul").unwrap();
        let paths = HashSet::from([
            folder.join("guides/g.md"),
            folder.join("courses/c.yaml"),
            folder.join("SOUL.md"),
            folder.join("repos/x/main.rs"),
            folder.join("guides/.g.md.swp"),
        ]);
        let outcome = apply(&conn, &root, &paths, false);
        assert!(!outcome.roster);
        assert_eq!(
            outcome.content,
            BTreeSet::from([
                ("m1".into(), "courses".into(), "c".into()),
                ("m1".into(), "documents".into(), "g".into()),
                ("m1".into(), "files".into(), String::new()),
            ])
        );
        let row = index::get(&conn, "m1", crate::mentor_store::paths::Kind::Guide, "g")
            .unwrap()
            .unwrap();
        assert_eq!(row.title, "G edited");

        // A deleted file is forgotten; mentor.json and the root mean the roster.
        std::fs::remove_file(folder.join("guides/g.md")).unwrap();
        let gone = apply(
            &conn,
            &root,
            &HashSet::from([folder.join("guides/g.md"), folder.join(MENTOR_FILE)]),
            false,
        );
        assert!(gone.roster);
        assert!(gone
            .content
            .contains(&("m1".into(), "documents".into(), "g".into())));
        assert!(
            index::get(&conn, "m1", crate::mentor_store::paths::Kind::Guide, "g")
                .unwrap()
                .is_none()
        );
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn the_watcher_sees_a_file_written_outside_the_app() {
        let root = temp_dir("watch-live");
        let dir = root.join("sources");
        std::fs::create_dir_all(&dir).unwrap();
        let (sender, events) = channel();
        let mut watcher = notify::recommended_watcher(sender).unwrap();
        watcher.watch(&dir, RecursiveMode::NonRecursive).unwrap();
        std::thread::sleep(Duration::from_millis(200));
        std::fs::write(dir.join("a.md"), "x").unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let mut seen = false;
        while Instant::now() < deadline && !seen {
            if let Ok(Ok(event)) = events.recv_timeout(Duration::from_millis(500)) {
                seen = event.paths.iter().any(|p| p.ends_with("a.md"));
            }
        }
        assert!(seen);
        drop(watcher);
        std::fs::remove_dir_all(root).unwrap();
    }
}
