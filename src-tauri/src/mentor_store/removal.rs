//! Deleting a mentor. Its own folder goes to the system trash, where the
//! user can still find it (putting it back into the root adopts it again);
//! everything this install kept about it in SQLite is deleted. Folders the
//! user gave it, a workdir outside its folder and the shared `repos/` of 0.3
//! are the user's and are never touched.

use std::path::{Path, PathBuf};

use rusqlite::Connection;
use serde::Serialize;

use super::paths::{MENTOR_FILE, REMOVED_MENTOR_FILE, SHARED_REPOS};
use super::{index, registry};

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Removed {
    /// The mentor folder that went to the trash.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub trashed: Option<String>,
    /// A mentor folder outside the root (imported where it was): left where
    /// it is, with `mentor.json` renamed so nothing reads it as a mentor.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kept: Option<String>,
}

/// Where the mentor's files are, as this install sees them.
pub struct Places<'a> {
    pub root: &'a Path,
    /// `<app data>/agents`: habits, and the Soul of a mentor not yet migrated.
    pub agents_dir: Option<&'a Path>,
}

/// `folder` itself when it is a mentor folder directly in `root` (after
/// resolving links and `..`), so nothing outside the root can be trashed.
fn own_folder(root: &Path, folder: &Path) -> Option<PathBuf> {
    let root = root.canonicalize().ok()?;
    let folder = folder.canonicalize().ok()?;
    let name = folder.file_name()?.to_str()?;
    (folder.parent() == Some(root.as_path()) && name != SHARED_REPOS).then_some(folder)
}

/// Deletes the rows of every table that holds something of this mentor.
/// The learning tables name no mentor: their rows go when they point at a
/// library document of the mentor or at a file in its folder.
fn forget(
    conn: &Connection,
    id: &str,
    session: Option<&str>,
    folders: &[String],
) -> Result<(), String> {
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    let run = |sql: &str, args: &[&dyn rusqlite::ToSql]| -> Result<(), String> {
        tx.execute(sql, args)
            .map(drop)
            .map_err(|e| format!("{e}: {sql}"))
    };
    registry::remove(&tx, id).map_err(|e| e.to_string())?;
    index::forget_mentor(&tx, id).map_err(|e| e.to_string())?;
    for table in [
        "lesson_progress",
        "lesson_questions",
        "mentor_state",
        "course_progress",
        "courses",
        "agent_documents",
    ] {
        run(&format!("DELETE FROM {table} WHERE agent_id = ?1"), &[&id])?;
    }
    if let Some(session) = session {
        // The window deletes its conversation first; this covers the CLI and
        // a window that failed half way. Pages are deleted by hand because
        // foreign keys are not enforced on every connection.
        for table in ["agent_transcript_pages", "in_flight_sessions"] {
            run(
                &format!("DELETE FROM {table} WHERE session_id = ?1"),
                &[&session],
            )?;
        }
        run("DELETE FROM sessions WHERE id = ?1", &[&session])?;
    }
    let document_key = format!("{id}/");
    run(
        "DELETE FROM pdf_annotations WHERE target_kind = 'document' AND substr(target_key, 1, length(?1)) = ?1",
        &[&document_key],
    )?;
    run(
        "DELETE FROM learning_sources WHERE json_extract(source_json, '$.kind') = 'document'
           AND json_extract(source_json, '$.agentId') = ?1",
        &[&id],
    )?;
    for folder in folders {
        let prefix = format!("{}/", folder.trim_end_matches('/'));
        let inside =
            |column: &str| format!("({column} = ?1 OR substr({column}, 1, length(?2)) = ?2)");
        run(
            &format!(
                "DELETE FROM pdf_annotations WHERE target_kind = 'file' AND {}",
                inside("target_key")
            ),
            &[folder, &prefix],
        )?;
        run(
            &format!(
                "DELETE FROM pdf_annotations WHERE target_kind = 'pdf' AND target_key IN
                   (SELECT id FROM reading_documents WHERE {})",
                inside("path")
            ),
            &[folder, &prefix],
        )?;
        run(
            &format!("DELETE FROM reading_documents WHERE {}", inside("path")),
            &[folder, &prefix],
        )?;
        run(
            &format!(
                "DELETE FROM learning_sources WHERE json_extract(source_json, '$.kind') IN ('file', 'pdf')
                   AND {}",
                inside("json_extract(source_json, '$.path')")
            ),
            &[folder, &prefix],
        )?;
    }
    tx.commit().map_err(|e| e.to_string())
}

/// Deletes a mentor: its folder (when it is one in the root) and its app-data
/// folder to the trash through `trash`, then its rows. Nothing is deleted from
/// SQLite when the trash refuses, so a failure can be retried.
pub fn remove(
    conn: &Connection,
    places: &Places<'_>,
    id: &str,
    trash: impl Fn(&Path) -> Result<(), String>,
) -> Result<Removed, String> {
    crate::session_store::validate_id(id, "agent")?;
    let record = registry::get(conn, id).map_err(|e| e.to_string())?;
    let mut removed = Removed {
        trashed: None,
        kept: None,
    };
    let mut folders = Vec::new();
    if let Some(record) = record.as_ref().filter(|r| r.folder.is_dir()) {
        folders.push(record.folder.to_string_lossy().into_owned());
        match own_folder(places.root, &record.folder) {
            Some(own) => {
                if own != record.folder {
                    folders.push(own.to_string_lossy().into_owned());
                }
                trash(&own)?;
                removed.trashed = Some(own.to_string_lossy().into_owned());
            }
            None => {
                let file = record.folder.join(MENTOR_FILE);
                if file.is_file() {
                    std::fs::rename(&file, record.folder.join(REMOVED_MENTOR_FILE))
                        .map_err(|e| format!("{}: {e}", file.display()))?;
                }
                removed.kept = Some(record.folder.to_string_lossy().into_owned());
            }
        }
    }
    if let Some(dir) = places.agents_dir.map(|dir| dir.join(id)) {
        if dir.is_dir() {
            trash(&dir)?;
        }
    }
    let session = record.as_ref().and_then(|r| r.session_id.as_deref());
    forget(conn, id, session, &folders)?;
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mentor_store::testing::{register, temp_dir};
    use crate::session_store::SessionStore;
    use std::cell::RefCell;

    /// Stands in for the system trash: moves into `bin` and records what went.
    fn move_to<'a>(
        bin: &'a Path,
        moved: &'a RefCell<Vec<PathBuf>>,
    ) -> impl Fn(&Path) -> Result<(), String> + 'a {
        move |path: &Path| {
            let target = bin.join(moved.borrow().len().to_string());
            std::fs::rename(path, target).map_err(|e| e.to_string())?;
            moved.borrow_mut().push(path.to_path_buf());
            Ok(())
        }
    }

    fn count(conn: &Connection, sql: &str) -> i64 {
        conn.query_row(sql, [], |row| row.get(0)).unwrap()
    }

    /// One row in every table for `id`, its files under `folder`.
    fn seed(conn: &Connection, id: &str, folder: &Path, session: &str) {
        let f = folder.to_string_lossy();
        let mut record = registry::get(conn, id).unwrap().unwrap();
        record.session_id = Some(session.into());
        registry::upsert(conn, &record).unwrap();
        std::fs::create_dir_all(folder.join("guides")).unwrap();
        std::fs::write(folder.join("guides/g.md"), "# G").unwrap();
        index::reconcile(
            conn,
            &super::super::MentorCtx {
                agent: id.into(),
                folder: folder.into(),
                workdir: None,
            },
        )
        .unwrap();
        conn.execute_batch(&format!(
            "INSERT INTO lesson_progress VALUES ('{id}', 'c', 'l', 'learning', 1);
             INSERT INTO mentor_state VALUES ('{id}', 'places', '{{}}', 1);
             INSERT INTO mentor_state VALUES ('{id}', 'view', '{{}}', 1);
             INSERT INTO courses VALUES ('{id}', 'c', 'e', 'C', '{{}}', 1, 1);
             INSERT INTO course_progress VALUES ('{id}', 'c', 'i', 'learning');
             INSERT INTO agent_documents (agent_id, id, title, body, created_at, updated_at) VALUES ('{id}', 'd', 'D', 'b', 1, 1);
             INSERT INTO sessions (id, cwd, harness, model, runtime_mode, title, created_at, updated_at)
               VALUES ('{session}', '{f}', 'h', 'm', 'r', 't', 1, 1);
             INSERT INTO agent_transcript_pages VALUES ('{session}', 0, 'b', '[]', 1);
             INSERT INTO reading_documents VALUES ('{id}-pdf', '{f}/sources/p.pdf', 'P', 'x', 1, 1);
             INSERT INTO pdf_annotations (id, document_id, source_id, anchors_json, note, discussions_json, created_at, updated_at, target_kind, target_key)
               VALUES ('{id}-a1', '{id}-pdf', 's', '[]', '', '[]', 1, 1, 'pdf', '{id}-pdf'),
                      ('{id}-a2', '', 's', '[]', '', '[]', 1, 1, 'document', '{id}/d'),
                      ('{id}-a3', '', 's', '[]', '', '[]', 1, 1, 'file', '{f}/guides/g.md');
             INSERT INTO learning_sources VALUES ('{id}-s1', '{{\"kind\":\"document\",\"agentId\":\"{id}\"}}', 1),
                                                 ('{id}-s2', '{{\"kind\":\"file\",\"path\":\"{f}/guides/g.md\"}}', 1);"
        ))
        .unwrap();
    }

    const TABLES: [&str; 13] = [
        "mentors",
        "mentor_content",
        "lesson_progress",
        "mentor_state",
        "courses",
        "course_progress",
        "agent_documents",
        "sessions",
        "agent_transcript_pages",
        "reading_documents",
        "pdf_annotations",
        "learning_sources",
        "mentor_content_fts",
    ];

    fn totals(conn: &Connection) -> Vec<i64> {
        TABLES
            .iter()
            .map(|t| count(conn, &format!("SELECT COUNT(*) FROM {t}")))
            .collect()
    }

    #[test]
    fn a_deleted_mentor_goes_to_the_trash_with_everything_kept_about_it() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let home = temp_dir("removal");
        let root = home.join("Loci");
        let bin = home.join("bin");
        let agents = home.join("data/agents");
        std::fs::create_dir_all(&bin).unwrap();
        // The 0.3 shared clones and a folder the user gave the mentor.
        std::fs::create_dir_all(root.join(SHARED_REPOS).join("kept")).unwrap();
        let given = home.join("project");
        std::fs::create_dir_all(&given).unwrap();
        let lens = root.join("lens");
        let other = root.join("other");
        register(&conn, "m-1", &lens);
        seed(&conn, "m-1", &lens, "s-1");
        let before_other = totals(&conn);
        register(&conn, "m-2", &other);
        seed(&conn, "m-2", &other, "s-2");
        let with_both = totals(&conn);
        std::fs::create_dir_all(agents.join("m-1")).unwrap();
        std::fs::write(agents.join("m-1/habits.json"), "[]").unwrap();
        std::fs::create_dir_all(lens.join("repos/fc")).unwrap();

        let moved = RefCell::new(Vec::new());
        let places = Places {
            root: &root,
            agents_dir: Some(&agents),
        };
        let removed = remove(&conn, &places, "m-1", move_to(&bin, &moved)).unwrap();

        assert!(!lens.exists());
        assert!(!agents.join("m-1").exists());
        assert_eq!(moved.borrow().len(), 2);
        assert!(removed.trashed.unwrap().ends_with("lens"));
        // What is the user's stays.
        assert!(root.join(SHARED_REPOS).join("kept").is_dir());
        assert!(given.is_dir());
        assert!(other.join(MENTOR_FILE).is_file());
        // Every table is back to what the other mentor alone put there.
        let after = totals(&conn);
        for (i, table) in TABLES.iter().enumerate() {
            assert_eq!(
                after[i],
                with_both[i] - before_other[i],
                "{table} still holds m-1's rows, or lost m-2's"
            );
            assert!(after[i] > 0, "{table} lost m-2's rows");
        }
        assert!(registry::get(&conn, "m-2").unwrap().is_some());
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn a_mentor_folder_outside_the_root_is_never_trashed() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let home = temp_dir("removal-outside");
        let root = home.join("Loci");
        std::fs::create_dir_all(&root).unwrap();
        let imported = home.join("elsewhere/lens");
        register(&conn, "m-1", &imported);
        seed(&conn, "m-1", &imported, "s-1");
        let places = Places {
            root: &root,
            agents_dir: None,
        };
        let trash = |path: &Path| -> Result<(), String> { panic!("trashed {}", path.display()) };
        let removed = remove(&conn, &places, "m-1", trash).unwrap();
        assert_eq!(
            removed.kept.as_deref(),
            Some(imported.to_string_lossy().as_ref())
        );
        assert!(imported.join("guides/g.md").is_file());
        assert!(imported.join(REMOVED_MENTOR_FILE).is_file());
        assert_eq!(count(&conn, "SELECT COUNT(*) FROM mentors"), 0);
        assert_eq!(count(&conn, "SELECT COUNT(*) FROM pdf_annotations"), 0);

        // Nor is the root itself, or its shared repos/, whatever the registry says.
        for folder in [
            root.clone(),
            root.join(SHARED_REPOS),
            root.join("lens/../.."),
        ] {
            std::fs::create_dir_all(&folder).unwrap();
            assert_eq!(own_folder(&root, &folder), None, "{}", folder.display());
        }
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn nothing_is_forgotten_when_the_trash_refuses() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("removal-refused");
        let lens = root.join("lens");
        register(&conn, "m-1", &lens);
        let places = Places {
            root: &root,
            agents_dir: None,
        };
        let error = remove(
            &conn,
            &places,
            "m-1",
            |_: &Path| Err("no trash".to_string()),
        );
        assert_eq!(error, Err("no trash".to_string()));
        assert!(lens.join(MENTOR_FILE).is_file());
        assert!(registry::get(&conn, "m-1").unwrap().is_some());
        std::fs::remove_dir_all(root).unwrap();
    }
}
