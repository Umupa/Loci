//! Reset uses a reload barrier: no data is deleted until every workspace page
//! has drained its IPC and reloaded into the maintenance entry point.
use std::collections::HashSet;
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

use crate::session_store::SessionStore;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResetStatus {
    id: String,
    phase: String,
    error: Option<String>,
}
struct ResetRun {
    status: ResetStatus,
    ready: HashSet<String>,
    cleaned: HashSet<String>,
}
#[derive(Default)]
struct ResetState {
    run: Option<ResetRun>,
    requests: HashSet<String>,
}
#[derive(Default)]
pub struct WorkspaceReset(Mutex<ResetState>);

const RESET_MARKER: &str = "workspace-reset.pending";

/// A confirmed reset interrupted by Quit or a process crash resumes before any
/// window can restore its old localStorage workspace.
pub fn resume(app: &AppHandle) -> Result<(), String> {
    let marker = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join(RESET_MARKER);
    if marker.try_exists().map_err(|e| e.to_string())? {
        workspace_reset(app.clone(), app.state())?;
    }
    Ok(())
}

pub fn guard(
    handler: impl Fn(tauri::ipc::Invoke) -> bool + Send + Sync + 'static,
) -> impl Fn(tauri::ipc::Invoke) -> bool + Send + Sync + 'static {
    move |invoke| {
        if invoke.message.command().starts_with("workspace_reset") {
            return handler(invoke);
        }
        let app = invoke.message.webview().app_handle().clone();
        let state = app.state::<WorkspaceReset>();
        let request_id = invoke
            .message
            .headers()
            .get("x-loci-request-id")
            .and_then(|value| value.to_str().ok());
        let accepted = state
            .0
            .lock()
            .unwrap()
            .begin_request(invoke.message.command(), request_id);
        if let Err(error) = accepted {
            invoke.resolver.reject(error);
            return true;
        }
        handler(invoke)
    }
}

pub fn is_resetting(app: &AppHandle) -> bool {
    app.state::<WorkspaceReset>()
        .0
        .lock()
        .unwrap()
        .run
        .is_some()
}

#[tauri::command]
pub fn workspace_reset(app: AppHandle, state: State<'_, WorkspaceReset>) -> Result<(), String> {
    let id = uuid::Uuid::new_v4().to_string();
    {
        let mut state = state.0.lock().map_err(|e| e.to_string())?;
        if state.run.is_some() {
            return Err("Workspace reset is already in progress".into());
        }
        record_reset(&app.path().app_data_dir().map_err(|e| e.to_string())?)?;
        state.run = Some(ResetRun {
            status: ResetStatus {
                id: id.clone(),
                phase: "preparing".into(),
                error: None,
            },
            ready: HashSet::new(),
            cleaned: HashSet::new(),
        });
    }
    if let Err(error) = app.emit("workspace-reset-prepare", &id) {
        if let Some(run) = state.0.lock().unwrap().run.as_mut() {
            run.status.phase = "failed".into();
            run.status.error = Some(error.to_string());
        }
        return Err(error.to_string());
    }
    tauri::async_runtime::spawn_blocking(move || {
        // Kill before waiting: a pending stdin write may need the child to die
        // before its IPC can settle. No quit dialog or quit events are involved.
        app.state::<crate::harness::HarnessHost>().kill_all();
        let result = wait_for_pages(&app).and_then(|()| {
            app.state::<crate::harness::HarnessHost>().kill_all();
            let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
            reset_data(&app.state::<SessionStore>(), &dir)?;
            for window in crate::window::workspace_windows(&app) {
                crate::control::window_closed(&app, window.label());
            }
            crate::reminders::reset_workspace(&app);
            Ok(())
        });
        if let Some(run) = app.state::<WorkspaceReset>().0.lock().unwrap().run.as_mut() {
            match result {
                Ok(()) => run.status.phase = "cleared".into(),
                Err(error) => {
                    run.status.phase = "failed".into();
                    run.status.error = Some(error);
                }
            }
        }
    });
    Ok(())
}

fn wait_for_pages(app: &AppHandle) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        let state = app.state::<WorkspaceReset>();
        let mut guard = state.0.lock().map_err(|e| e.to_string())?;
        let labels: Vec<String> = crate::window::workspace_windows(app)
            .iter()
            .map(|window| window.label().to_owned())
            .collect();
        if guard.can_clear(&labels) {
            guard
                .run
                .as_mut()
                .ok_or("Workspace reset was interrupted")?
                .status
                .phase = "clearing".into();
            return Ok(());
        }
        drop(guard);
        if Instant::now() >= deadline {
            return Err("A window did not finish saving before reset. Restart Loci and try again; workspace data was not deleted.".into());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[tauri::command]
pub fn workspace_reset_status(
    app: AppHandle,
    state: State<'_, WorkspaceReset>,
) -> Result<Option<ResetStatus>, String> {
    let windows = crate::window::workspace_windows(&app);
    let mut guard = state.0.lock().unwrap();
    if guard.run.as_ref().is_some_and(|run| {
        run.status.phase == "cleared"
            && !run.cleaned.is_empty()
            && windows
                .iter()
                .all(|window| run.cleaned.contains(window.label()))
    }) {
        let marker = app
            .path()
            .app_data_dir()
            .map_err(|e| e.to_string())?
            .join(RESET_MARKER);
        std::fs::remove_file(&marker).map_err(|e| format!("{}: {e}", marker.display()))?;
        guard.run = None;
    }
    Ok(guard.run.as_ref().map(|run| run.status.clone()))
}

#[tauri::command]
pub fn workspace_reset_ready(
    window: WebviewWindow,
    state: State<'_, WorkspaceReset>,
    id: String,
) -> Result<(), String> {
    let mut guard = state.0.lock().map_err(|e| e.to_string())?;
    let run = guard
        .run
        .as_mut()
        .filter(|run| run.status.id == id)
        .ok_or("No matching workspace reset")?;
    run.ready.insert(window.label().to_owned());
    Ok(())
}

#[tauri::command]
pub fn workspace_reset_cleaned(
    window: WebviewWindow,
    state: State<'_, WorkspaceReset>,
    id: String,
) -> Result<(), String> {
    let mut guard = state.0.lock().map_err(|e| e.to_string())?;
    let run = guard
        .run
        .as_mut()
        .filter(|run| run.status.id == id && run.status.phase == "cleared")
        .ok_or("Workspace reset has not finished")?;
    run.cleaned.insert(window.label().to_owned());
    Ok(())
}

#[tauri::command]
pub fn workspace_reset_request_finished(state: State<'_, WorkspaceReset>, request_id: String) {
    state.0.lock().unwrap().requests.remove(&request_id);
}

impl ResetState {
    fn begin_request(
        &mut self,
        command: &str,
        request_id: Option<&str>,
    ) -> Result<(), &'static str> {
        if self.run.is_some() {
            return Err("Workspace reset in progress");
        }
        // This command unloads its caller before an acknowledgement can arrive.
        if command == "destroy_window" {
            return Ok(());
        }
        let request_id = request_id.ok_or("Missing workspace request ticket")?;
        self.requests.insert(request_id.to_owned());
        Ok(())
    }

    fn can_clear(&self, windows: &[String]) -> bool {
        self.requests.is_empty()
            && self
                .run
                .as_ref()
                .is_some_and(|run| windows.iter().all(|label| run.ready.contains(label)))
    }
}

fn record_reset(dir: &Path) -> Result<(), String> {
    let marker = dir.join(RESET_MARKER);
    // Do not follow a pre-existing link when recording destructive intent.
    match std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&marker)
    {
        Ok(file) => file.sync_all().map_err(|e| e.to_string()),
        Err(error)
            if error.kind() == std::io::ErrorKind::AlreadyExists
                && marker.is_file()
                && !marker.is_symlink() =>
        {
            Ok(())
        }
        Err(error) => Err(format!("{}: {error}", marker.display())),
    }
}

fn reset_data(store: &SessionStore, dir: &Path) -> Result<(), String> {
    let mut conn = store.lock_conn()?;
    let transaction = conn.transaction().map_err(|e| e.to_string())?;
    // Discover tables from the live schema, including legacy feature tables.
    // SQLite's internal tables and migration history must survive verbatim.
    let tables = {
        let mut statement = transaction.prepare(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT GLOB 'sqlite_*' AND name != 'schema_migrations'"
        ).map_err(|e| e.to_string())?;
        let rows = statement
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?
    };
    transaction
        .execute_batch("PRAGMA defer_foreign_keys = ON;")
        .map_err(|e| e.to_string())?;
    for table in tables {
        transaction
            .execute(
                &format!("DELETE FROM \"{}\"", table.replace('"', "\"\"")),
                [],
            )
            .map_err(|e| format!("Could not clear {table}: {e}"))?;
    }
    for name in ["agents", "project-logos", "note-assets", "generated-images"] {
        remove_path(&dir.join(name))?;
    }
    let backgrounds = dir.join("backgrounds");
    // Global backgrounds are settings assets; deleting them would silently
    // break loci.chatBackgroundPath even though its localStorage value survived.
    if backgrounds.is_symlink() {
        return Err("Refusing to reset a symlinked backgrounds directory".into());
    }
    match std::fs::read_dir(&backgrounds) {
        Ok(entries) => {
            for entry in entries {
                let entry = entry.map_err(|e| e.to_string())?;
                let name = entry.file_name();
                let name = name.to_string_lossy();
                if name != "chat-background" && !name.starts_with("chat-background.") {
                    remove_path(&entry.path())?;
                }
            }
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(format!("{}: {error}", backgrounds.display())),
    }
    transaction.commit().map_err(|e| e.to_string())
}

fn remove_path(path: &Path) -> Result<(), String> {
    let metadata = match std::fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(format!("{}: {error}", path.display())),
    };
    let result = if metadata.is_dir() && !metadata.file_type().is_symlink() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    };
    result.map_err(|e| format!("{}: {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestDir(std::path::PathBuf);
    impl TestDir {
        fn new() -> Self {
            let path =
                std::env::temp_dir().join(format!("loci-reset-test-{}", uuid::Uuid::new_v4()));
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }
        fn write(&self, name: &str) {
            let path = self.0.join(name);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, name).unwrap();
        }
    }
    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn seed(store: &SessionStore) {
        store.lock_conn().unwrap().execute_batch(
            "INSERT INTO sessions (id,cwd,harness,model,runtime_mode,title,created_at,updated_at) VALUES ('s','/repo','claude','model','supervised','title',1,1);
             INSERT INTO in_flight_sessions VALUES ('s','/repo',0);
             INSERT INTO workspace_snapshot VALUES (1,'{}',1);
             INSERT INTO session_reminders VALUES ('s',1,NULL);
             INSERT INTO agent_transcript_pages VALUES ('s',0,'b','[]',1);
             INSERT INTO agent_documents (agent_id,id,title,body,created_at,updated_at) VALUES ('a','d','title','body',1,1);
             INSERT INTO canvases (id,created_at,updated_at) VALUES ('c',1,1);
             INSERT INTO canvas_checkpoints VALUES ('cp','c','{}',1);
             INSERT INTO notes (id,slug,title,created_at,updated_at) VALUES ('n','note','title',1,1);
             INSERT INTO courses VALUES ('a','course','domain-navigation','title','{}',1,1);
             INSERT INTO course_progress VALUES ('a','course','item','learning');
             INSERT INTO learning_sources VALUES ('source','{}',1);
             INSERT INTO reading_documents VALUES ('doc','/document.pdf','title','fingerprint',1,1);
             INSERT INTO pdf_annotations VALUES ('annotation','doc','source','[]','note','[]',1,1);"
        ).unwrap();
    }
    fn table_counts(store: &SessionStore) -> Vec<(String, i64)> {
        let conn = store.lock_conn().unwrap();
        let mut query = conn.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name").unwrap();
        query
            .query_map([], |row| row.get::<_, String>(0))
            .unwrap()
            .map(|name| {
                let name = name.unwrap();
                let count = conn
                    .query_row(&format!("SELECT COUNT(*) FROM \"{name}\""), [], |row| {
                        row.get(0)
                    })
                    .unwrap();
                (name, count)
            })
            .collect()
    }
    fn schema(store: &SessionStore) -> Vec<(String, String)> {
        let conn = store.lock_conn().unwrap();
        let mut query = conn
            .prepare("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name")
            .unwrap();
        query
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap()
    }
    fn migrations(store: &SessionStore) -> Vec<(i64, i64)> {
        let conn = store.lock_conn().unwrap();
        let mut query = conn
            .prepare("SELECT version,applied_at FROM schema_migrations ORDER BY version")
            .unwrap();
        query
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap()
    }

    fn run() -> ResetRun {
        ResetRun {
            status: ResetStatus {
                id: "test".into(),
                phase: "preparing".into(),
                error: None,
            },
            ready: HashSet::new(),
            cleaned: HashSet::new(),
        }
    }

    #[test]
    fn normal_window_close_needs_no_ticket_and_does_not_block_a_later_reset() {
        let mut state = ResetState::default();
        state.begin_request("destroy_window", None).unwrap();
        state.run = Some(run());
        state.run.as_mut().unwrap().ready.insert("main".into());
        assert!(state.can_clear(&["main".into()]));
        assert!(state.begin_request("destroy_window", None).is_err());
    }

    #[test]
    fn replacement_page_cannot_bypass_an_old_pages_pending_request() {
        let mut state = ResetState::default();
        state
            .begin_request("session_upsert", Some("old-page:1"))
            .unwrap();
        state.run = Some(run());
        state.run.as_mut().unwrap().ready.insert("main".into());
        assert!(!state.can_clear(&["main".into()]));
        assert!(state
            .begin_request("session_upsert", Some("late-write"))
            .is_err());
        state.requests.remove("old-page:1");
        assert!(state.can_clear(&["main".into()]));
    }

    #[test]
    fn closed_windows_only_stop_blocking_when_their_requests_have_finished() {
        let mut state = ResetState::default();
        state
            .begin_request("session_upsert", Some("closed-window:1"))
            .unwrap();
        state.run = Some(run());
        state.run.as_mut().unwrap().ready.insert("main".into());
        assert!(!state.can_clear(&["main".into(), "window-1".into()]));
        assert!(!state.can_clear(&["main".into()]));
        state.requests.remove("closed-window:1");
        assert!(state.can_clear(&["main".into()]));
        assert!(!state.can_clear(&["main".into(), "new-window".into()]));
        assert!(ResetState::default()
            .begin_request("session_upsert", None)
            .is_err());
    }

    #[test]
    fn reset_intent_survives_data_cleanup_until_pages_have_cleared_storage() {
        let dir = TestDir::new();
        let store = SessionStore::open_in_memory().unwrap();
        seed(&store);
        record_reset(&dir.0).unwrap();
        reset_data(&store, &dir.0).unwrap();
        assert!(dir.0.join(RESET_MARKER).is_file());
        // Restart can safely finish the same confirmed reset after any phase.
        record_reset(&dir.0).unwrap();
        reset_data(&store, &dir.0).unwrap();
        assert!(dir.0.join(RESET_MARKER).is_file());
    }

    #[test]
    fn reset_clears_every_user_table_and_owned_files_but_preserves_settings_assets() {
        let dir = TestDir::new();
        let store = SessionStore::open(dir.0.join("loci.db")).unwrap();
        seed(&store);
        assert_eq!(
            table_counts(&store).len(),
            15,
            "Update fixtures when the schema grows"
        );
        assert!(table_counts(&store).iter().all(|(_, count)| *count == 1));
        let schema_before = schema(&store);
        let migrations_before = migrations(&store);
        let deleted = [
            "agents/a/SOUL.md",
            "agents/a/MEMORY.md",
            "agents/a/habits.json",
            "agents/a/memory/page.md",
            "project-logos/logo.png",
            "backgrounds/project-abc.png",
            "note-assets/image.png",
            "generated-images/image.png",
        ];
        let kept = [
            "backgrounds/chat-background.png",
            "wallpaper-cache/theme/image.jpg",
            "provider-accounts/config.json",
            "preferences.json",
        ];
        for name in deleted.iter().chain(&kept) {
            dir.write(name);
        }
        reset_data(&store, &dir.0).unwrap();
        for (table, count) in table_counts(&store) {
            assert_eq!(count, i64::from(table == "schema_migrations"), "{table}");
        }
        assert_eq!(schema(&store), schema_before);
        assert_eq!(migrations(&store), migrations_before);
        for name in deleted {
            assert!(!dir.0.join(name).exists(), "{name}");
        }
        for name in kept {
            assert_eq!(std::fs::read_to_string(dir.0.join(name)).unwrap(), name);
        }
        reset_data(&store, &dir.0).unwrap(); // Idempotent with already missing directories.
    }

    #[test]
    fn reset_handles_missing_feature_tables_and_clears_legacy_tables() {
        let store = SessionStore::open_in_memory().unwrap();
        store.lock_conn().unwrap().execute_batch("DROP TABLE course_progress; DROP TABLE courses; CREATE TABLE legacy_feature(value TEXT); INSERT INTO legacy_feature VALUES ('old');").unwrap();
        let dir = TestDir::new();
        reset_data(&store, &dir.0).unwrap();
        assert!(table_counts(&store).contains(&("legacy_feature".into(), 0)));
        assert_eq!(migrations(&store).len(), 1);
    }

    #[test]
    fn database_error_rolls_back_all_deletes_and_does_not_remove_files() {
        let store = SessionStore::open_in_memory().unwrap();
        seed(&store);
        store.lock_conn().unwrap().execute_batch("CREATE TRIGGER fail_reset BEFORE DELETE ON notes BEGIN SELECT RAISE(ABORT, 'test failure'); END;").unwrap();
        let dir = TestDir::new();
        dir.write("agents/a/SOUL.md");
        let before = table_counts(&store);
        assert!(reset_data(&store, &dir.0)
            .unwrap_err()
            .contains("test failure"));
        assert_eq!(table_counts(&store), before);
        assert!(dir.0.join("agents/a/SOUL.md").exists());
    }

    #[cfg(unix)]
    #[test]
    fn reset_does_not_follow_directory_symlinks_into_project_files() {
        let store = SessionStore::open_in_memory().unwrap();
        let dir = TestDir::new();
        let project = TestDir::new();
        project.write("SOUL.md");
        std::os::unix::fs::symlink(&project.0, dir.0.join("agents")).unwrap();
        reset_data(&store, &dir.0).unwrap();
        assert!(project.0.join("SOUL.md").exists());
        assert!(!dir.0.join("agents").exists());
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_backgrounds_fail_safely_and_roll_back_database() {
        let store = SessionStore::open_in_memory().unwrap();
        seed(&store);
        let dir = TestDir::new();
        let external = TestDir::new();
        external.write("chat-background.png");
        std::os::unix::fs::symlink(&external.0, dir.0.join("backgrounds")).unwrap();
        let before = table_counts(&store);
        assert!(reset_data(&store, &dir.0).is_err());
        assert_eq!(table_counts(&store), before);
        assert!(external.0.join("chat-background.png").exists());
    }
}
