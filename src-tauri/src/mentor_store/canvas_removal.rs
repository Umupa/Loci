//! Canvases were removed in 0.6. Their tables go, and so does each mentor's
//! `canvases/` folder: nothing reads them any more, and a drawing that stayed
//! behind would only be a surprise the next time the user opens the folder.

use std::path::Path;

use rusqlite::Connection;

use super::registry;
use crate::session_store::now_millis;

/// Recorded in `schema_migrations` once the canvases are gone.
pub const VERSION: i64 = 60;
const FOLDER: &str = "canvases";

/// Runs once per database; every step is safe to repeat, so a start that
/// stops halfway simply finishes on the next one.
pub fn run(conn: &Connection) -> rusqlite::Result<()> {
    let done: i64 = conn.query_row(
        "SELECT COUNT(*) FROM schema_migrations WHERE version = ?1",
        [VERSION],
        |row| row.get(0),
    )?;
    if done > 0 {
        return Ok(());
    }
    conn.execute_batch(
        "DROP TABLE IF EXISTS canvas_checkpoints;
         DROP TABLE IF EXISTS canvases;
         DELETE FROM mentor_content WHERE kind = 'canvas';",
    )?;
    let mut complete = true;
    for record in registry::list(conn)? {
        if let Err(error) = remove_folder(&record.folder) {
            eprintln!(
                "Loci could not remove {}: {error}",
                record.folder.join(FOLDER).display()
            );
            complete = false;
        }
    }
    // A folder that could not go is tried again on the next start.
    if complete {
        conn.execute(
            "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?1, ?2)",
            rusqlite::params![VERSION, now_millis()],
        )?;
    }
    Ok(())
}

/// Removes `<mentor>/canvases` and nothing else. A link there is removed as a
/// link, never followed into whatever it points at.
fn remove_folder(mentor: &Path) -> std::io::Result<()> {
    let path = mentor.join(FOLDER);
    match std::fs::symlink_metadata(&path) {
        Ok(meta) if meta.is_dir() => std::fs::remove_dir_all(&path),
        Ok(_) => std::fs::remove_file(&path),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mentor_store::testing::{register, temp_dir};
    use crate::session_store::SessionStore;

    fn table_exists(conn: &Connection, name: &str) -> bool {
        conn.query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [name],
            |row| row.get::<_, i64>(0),
        )
        .unwrap()
            > 0
    }

    fn forget(conn: &Connection) {
        conn.execute(
            "DELETE FROM schema_migrations WHERE version = ?1",
            [VERSION],
        )
        .unwrap();
    }

    #[test]
    fn drops_the_tables_and_each_mentors_canvases_folder_only() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("canvas-removal");
        let folder = root.join("lens");
        register(&conn, "m1", &folder);
        std::fs::create_dir_all(folder.join("canvases/nested")).unwrap();
        std::fs::write(folder.join("canvases/k.excalidraw"), "{}").unwrap();
        std::fs::create_dir_all(folder.join("notes")).unwrap();
        std::fs::write(folder.join("notes/n.md"), "kept").unwrap();
        // A 0.5 database: the tables and an indexed drawing.
        forget(&conn);
        conn.execute_batch(
            "CREATE TABLE canvases (id TEXT PRIMARY KEY);
             CREATE TABLE canvas_checkpoints (checkpoint_id TEXT PRIMARY KEY);
             INSERT INTO mentor_content (agent_id,kind,id,rel_path,title,hash,size,mtime_ns,created_at,updated_at,indexed_at)
               VALUES ('m1','canvas','k','canvases/k.excalidraw','K','h',2,0,1,1,1);",
        )
        .unwrap();

        run(&conn).unwrap();
        assert!(!table_exists(&conn, "canvases"));
        assert!(!table_exists(&conn, "canvas_checkpoints"));
        let indexed: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM mentor_content WHERE kind = 'canvas'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(indexed, 0);
        assert!(!folder.join("canvases").exists());
        assert_eq!(
            std::fs::read_to_string(folder.join("notes/n.md")).unwrap(),
            "kept"
        );
        assert!(folder.join("mentor.json").is_file());

        // Recorded: a canvases folder made later is left alone.
        std::fs::create_dir_all(folder.join("canvases")).unwrap();
        run(&conn).unwrap();
        assert!(folder.join("canvases").is_dir());
        // And running it again from scratch does no harm.
        forget(&conn);
        run(&conn).unwrap();
        run(&conn).unwrap();
        assert!(!folder.join("canvases").exists());
        assert!(folder.join("notes/n.md").is_file());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn a_linked_canvases_folder_is_unlinked_not_emptied() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let root = temp_dir("canvas-removal-link");
        let folder = root.join("lens");
        register(&conn, "m1", &folder);
        let elsewhere = root.join("elsewhere");
        std::fs::create_dir_all(&elsewhere).unwrap();
        std::fs::write(elsewhere.join("keep.txt"), "the user's").unwrap();
        std::os::unix::fs::symlink(&elsewhere, folder.join("canvases")).unwrap();
        forget(&conn);
        run(&conn).unwrap();
        assert!(std::fs::symlink_metadata(folder.join("canvases")).is_err());
        assert!(elsewhere.join("keep.txt").is_file());
        std::fs::remove_dir_all(root).unwrap();
    }
}
