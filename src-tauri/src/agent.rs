//! An agent's Soul and memory live in its mentor folder (v0.4), beside its
//! sources and courses; until its 0.3 data has moved there, in the app's
//! data folder as before. Habits always stay in the app's data folder: they
//! run things on their own, and a mentor folder copied or imported from
//! elsewhere must not bring jobs with it.
//!
//! ```text
//! ~/Loci/<slug>/                 <app data>/agents/<agent id>/
//! ├── SOUL.md                    └── habits.json
//! ├── MEMORY.md
//! └── memory/<topic>.md, archive.md
//! ```
//!
//! The folder is not a repository; cloned source lives in its `repos/`, each
//! a repository of its own, so a pull request there cannot reach the Soul.
//! Writes still name the hash they read, so the user, the agent's CLI and an
//! editor cannot overwrite each other.
//!
//! Separately, each mentor has a working directory the user can see and the
//! agent works in: cloned source under `repos/`, experiments under `lab/`.
//! It lives in the home folder, `~/Loci/<slug>` (`~/Loci-Dev/<slug>` for
//! Loci Dev), or wherever the user pointed it. The app only ever creates
//! folders there; it never moves or deletes anything.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::Serialize;
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Manager};

const AGENTS_DIR: &str = "agents";
const SOUL_FILE: &str = "SOUL.md";
const MEMORY_FILE: &str = "MEMORY.md";
const MEMORY_DIR: &str = "memory";
const HABITS_FILE: &str = "habits.json";
/// Larger than anything that would load: the soul and memory both have far
/// smaller prompt budgets, this only stops a runaway write.
const FILE_MAX: usize = 256 * 1024;
pub const CONFLICT: &str = "conflict";

/// All windows share this store. Keep initialization and hash-checked writes
/// serialized so only one caller can save over a version of a file.
static FILES_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentFile {
    /// Absent when the file does not exist yet.
    pub text: Option<String>,
    /// Hash of the text, or of "" for a missing file.
    pub hash: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentFiles {
    pub id: String,
    pub dir: String,
    /// Absent until the app seeds it; the seed needs the user's old settings.
    pub soul: Option<String>,
    pub soul_hash: String,
    pub memory: String,
    pub memory_hash: String,
    pub memory_path: String,
    /// Topic notes under memory/, by name without `.md`; not the archive.
    pub topics: Vec<String>,
    /// The same topic notes with their text, so they load like MEMORY.md.
    pub topic_notes: Vec<TopicNote>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TopicNote {
    pub name: String,
    pub text: String,
    pub hash: String,
}

/// Where an agent's files are: its Soul and memory, and its habits.
#[derive(Debug, Clone)]
pub struct Dirs {
    pub files: PathBuf,
    pub habits: PathBuf,
}

impl Dirs {
    /// Both in `<root>/<agent>`, as before v0.4.
    fn legacy(root: &Path, agent: &str) -> Result<Self, String> {
        if !valid_id(agent) {
            return Err("Not an agent id".into());
        }
        let dir = root.join(agent);
        Ok(Self {
            files: dir.clone(),
            habits: dir,
        })
    }
}

/// The files the app reads and writes for an agent, relative to its folder:
/// SOUL.md, MEMORY.md, habits.json, or one `memory/<name>.md`. Nothing nested, nothing
/// hidden, so a path from the agent's CLI can never leave the folder.
fn resolve_file(dirs: &Dirs, relative: &str) -> Result<PathBuf, String> {
    if relative == HABITS_FILE {
        return Ok(dirs.habits.join(relative));
    }
    let dir = &dirs.files;
    if relative == SOUL_FILE || relative == MEMORY_FILE {
        return Ok(dir.join(relative));
    }
    let name = relative
        .strip_prefix("memory/")
        .and_then(|rest| rest.strip_suffix(".md"))
        .ok_or_else(|| format!("Not an agent file: {relative}"))?;
    let valid = !name.is_empty()
        && name.len() <= 80
        && !name.starts_with('.')
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, ' ' | '.' | '-' | '_'));
    if !valid {
        return Err(format!("Not an agent file: {relative}"));
    }
    Ok(dir.join(MEMORY_DIR).join(format!("{name}.md")))
}

fn topics(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir.join(MEMORY_DIR))
        .map(|entries| {
            entries
                .flatten()
                .filter(|entry| entry.path().is_file())
                .filter_map(|entry| {
                    let name = entry.file_name().to_string_lossy().into_owned();
                    let topic = name.strip_suffix(".md")?.to_string();
                    (topic != "archive" && !topic.starts_with('.')).then_some(topic)
                })
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

fn agents_root(app: &AppHandle) -> Result<PathBuf, String> {
    let data = app.path().app_data_dir().map_err(|e| e.to_string())?;
    Ok(data.join(AGENTS_DIR))
}

pub fn content_hash(text: &str) -> String {
    Sha256::digest(text.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// Write beside the target and rename over it, so a crash mid-write leaves
/// the old file whole. Owner-only, since memory can hold personal details.
fn write_atomic(path: &Path, text: &str) -> Result<(), String> {
    use std::io::Write;

    let temp = path.with_extension("md.tmp");
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&temp)
        .map_err(|e| format!("{}: {e}", temp.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // A temporary file left by an older version may have wider permissions.
        file.set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|e| format!("{}: {e}", temp.display()))?;
    }
    file.write_all(text.as_bytes())
        .map_err(|e| format!("{}: {e}", temp.display()))?;
    drop(file);
    std::fs::rename(&temp, path).map_err(|e| format!("{}: {e}", path.display()))
}

fn read_optional(path: &Path) -> Result<Option<String>, String> {
    match std::fs::read_to_string(path) {
        Ok(text) => Ok(Some(text)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("{}: {e}", path.display())),
    }
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
}

/// The agent's folders, created with an empty memory on first use.
fn agent_dir(dirs: &Dirs) -> Result<PathBuf, String> {
    let dir = dirs.files.clone();
    std::fs::create_dir_all(dir.join(MEMORY_DIR)).map_err(|e| format!("{}: {e}", dir.display()))?;
    std::fs::create_dir_all(&dirs.habits).map_err(|e| format!("{}: {e}", dirs.habits.display()))?;
    let memory = dir.join(MEMORY_FILE);
    if !memory.exists() {
        write_atomic(&memory, "")?;
    }
    Ok(dir)
}

fn load(dirs: &Dirs, agent: &str) -> Result<AgentFiles, String> {
    let _guard = FILES_LOCK.lock().map_err(|e| e.to_string())?;
    let dir = agent_dir(dirs)?;
    let soul = read_optional(&dir.join(SOUL_FILE))?;
    let memory_path = dir.join(MEMORY_FILE);
    let memory = read_optional(&memory_path)?.unwrap_or_default();
    let names = topics(&dir);
    let mut topic_notes = Vec::with_capacity(names.len());
    for name in &names {
        let text =
            read_optional(&dir.join(MEMORY_DIR).join(format!("{name}.md")))?.unwrap_or_default();
        topic_notes.push(TopicNote {
            name: name.clone(),
            hash: content_hash(&text),
            text,
        });
    }
    Ok(AgentFiles {
        id: agent.to_string(),
        soul_hash: content_hash(soul.as_deref().unwrap_or("")),
        soul,
        memory_hash: content_hash(&memory),
        memory,
        memory_path: memory_path.to_string_lossy().into_owned(),
        topics: names,
        topic_notes,
        dir: dir.to_string_lossy().into_owned(),
    })
}

fn read(dirs: &Dirs, relative: &str) -> Result<AgentFile, String> {
    let _guard = FILES_LOCK.lock().map_err(|e| e.to_string())?;
    agent_dir(dirs)?;
    let text = read_optional(&resolve_file(dirs, relative)?)?;
    Ok(AgentFile {
        hash: content_hash(text.as_deref().unwrap_or("")),
        text,
    })
}

/// Saves only over the text the editor opened, so the user never overwrites
/// what the agent wrote while they were typing. No hash means overwrite.
fn save(
    dirs: &Dirs,
    relative: &str,
    text: &str,
    expected_hash: Option<&str>,
) -> Result<String, String> {
    if text.len() > FILE_MAX {
        return Err(format!("{relative} is too large"));
    }
    let _guard = FILES_LOCK.lock().map_err(|e| e.to_string())?;
    agent_dir(dirs)?;
    let path = resolve_file(dirs, relative)?;
    if let Some(expected) = expected_hash {
        let current = read_optional(&path)?.unwrap_or_default();
        if content_hash(&current) != expected {
            return Err(CONFLICT.into());
        }
    }
    write_atomic(&path, text)?;
    Ok(content_hash(text))
}

/// The agent's mentor folder when its content is in one, else app data.
fn dirs_for(app: &AppHandle, agent: &str) -> Result<Dirs, String> {
    let mut dirs = Dirs::legacy(&agents_root(app)?, agent)?;
    let store = app.state::<crate::session_store::SessionStore>();
    let conn = store.lock_conn()?;
    if let Some(folder) =
        crate::mentor_store::registry::active_folder(&conn, agent).map_err(|e| e.to_string())?
    {
        dirs.files = folder;
    }
    Ok(dirs)
}

#[tauri::command]
pub async fn agent_load(app: AppHandle, agent: String) -> Result<AgentFiles, String> {
    let dirs = dirs_for(&app, &agent)?;
    tauri::async_runtime::spawn_blocking(move || load(&dirs, &agent))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn agent_read(app: AppHandle, agent: String, path: String) -> Result<AgentFile, String> {
    let dirs = dirs_for(&app, &agent)?;
    tauri::async_runtime::spawn_blocking(move || read(&dirs, &path))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn agent_save(
    app: AppHandle,
    agent: String,
    path: String,
    text: String,
    expected_hash: Option<String>,
) -> Result<String, String> {
    let dirs = dirs_for(&app, &agent)?;
    tauri::async_runtime::spawn_blocking(move || {
        save(&dirs, &path, &text, expected_hash.as_deref())
    })
    .await
    .map_err(|e| e.to_string())?
}

/// The folder every default workdir goes into, by flavor.
const REPOS_DIR: &str = "repos";
/// How many `<slug>-N` names to try before giving up.
const SLUG_TRIES: usize = 99;

fn workdir_root(app: &AppHandle) -> Result<PathBuf, String> {
    // The same root as mentors' folders, by build (see mentor_store::paths).
    Ok(app.state::<crate::mentor_store::MentorsRoot>().path())
}

fn valid_slug(slug: &str) -> bool {
    !slug.is_empty()
        && slug.len() <= 40
        && !slug.starts_with('-')
        && !slug.ends_with('-')
        && slug
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

/// A new, empty folder `<root>/<slug>` (or `<slug>-2`, …) with `repos/` in
/// it. An existing folder is never reused, so nothing of the user's is
/// adopted or written into by accident.
fn create_workdir(root: &Path, slug: &str) -> Result<PathBuf, String> {
    if !valid_slug(slug) || slug == REPOS_DIR {
        return Err(format!("Not a folder name: {slug}"));
    }
    std::fs::create_dir_all(root).map_err(|e| format!("{}: {e}", root.display()))?;
    for attempt in 1..=SLUG_TRIES {
        let name = if attempt == 1 {
            slug.to_string()
        } else {
            format!("{slug}-{attempt}")
        };
        let dir = root.join(&name);
        match std::fs::create_dir(&dir) {
            Ok(()) => {
                std::fs::create_dir(dir.join(REPOS_DIR))
                    .map_err(|e| format!("{}: {e}", dir.display()))?;
                return Ok(dir);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("{}: {e}", dir.display())),
        }
    }
    Err(format!("No free folder name for {slug}"))
}

/// A workdir already chosen: an existing folder is used as it is, with
/// nothing created inside it; a missing one is created.
fn ensure_workdir(path: &Path) -> Result<PathBuf, String> {
    if !path.is_absolute() {
        return Err(format!("Not an absolute path: {}", path.display()));
    }
    match std::fs::metadata(path) {
        Ok(meta) if meta.is_dir() => Ok(path.to_path_buf()),
        Ok(_) => Err(format!("Not a folder: {}", path.display())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            std::fs::create_dir_all(path).map_err(|e| format!("{}: {e}", path.display()))?;
            Ok(path.to_path_buf())
        }
        Err(e) => Err(format!("{}: {e}", path.display())),
    }
}

/// Creates a mentor's default workdir and returns its absolute path.
#[tauri::command]
pub async fn agent_workdir_create(app: AppHandle, slug: String) -> Result<String, String> {
    let root = workdir_root(&app)?;
    tauri::async_runtime::spawn_blocking(move || create_workdir(&root, &slug))
        .await
        .map_err(|e| e.to_string())?
        .map(|dir| dir.to_string_lossy().into_owned())
}

/// Makes sure a mentor's chosen workdir exists and returns its path.
#[tauri::command]
pub async fn agent_workdir_ensure(path: String) -> Result<String, String> {
    let path = crate::fs::expand_home(&path);
    tauri::async_runtime::spawn_blocking(move || ensure_workdir(&path))
        .await
        .map_err(|e| e.to_string())?
        .map(|dir| dir.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load_at(root: &Path, agent: &str) -> Result<AgentFiles, String> {
        load(&Dirs::legacy(root, agent)?, agent)
    }

    fn temp_root() -> PathBuf {
        let root = std::env::temp_dir().join(format!("agent-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn creates_one_folder_per_agent_with_empty_memory() {
        let root = temp_root();
        let first = load_at(&root, "agent-a").unwrap();
        let again = load_at(&root, "agent-a").unwrap();
        let other = load_at(&root, "agent-b").unwrap();
        assert_eq!(first.id, "agent-a");
        assert_eq!(first.dir, again.dir);
        assert_ne!(first.dir, other.dir);
        assert_eq!(first.soul, None);
        assert_eq!(first.memory, "");
        assert!(Path::new(&first.dir).join("memory").is_dir());
        assert!(load_at(&root, "../x").is_err());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn refuses_to_overwrite_a_changed_file() {
        let root = temp_root();
        let files = load_at(&root, "m").unwrap();
        let hash = save(
            &Dirs::legacy(&root, "m").unwrap(),
            MEMORY_FILE,
            "- a",
            Some(&files.memory_hash),
        )
        .unwrap();
        assert_eq!(
            save(
                &Dirs::legacy(&root, "m").unwrap(),
                MEMORY_FILE,
                "- b",
                Some(&files.memory_hash)
            ),
            Err(CONFLICT.into())
        );
        save(
            &Dirs::legacy(&root, "m").unwrap(),
            MEMORY_FILE,
            "- c",
            Some(&hash),
        )
        .unwrap();
        save(&Dirs::legacy(&root, "m").unwrap(), SOUL_FILE, "soul", None).unwrap();
        let loaded = load_at(&root, "m").unwrap();
        assert_eq!(loaded.memory, "- c");
        assert_eq!(loaded.soul.as_deref(), Some("soul"));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn writes_private_files_even_with_a_leftover_public_temp_file() {
        use std::os::unix::fs::PermissionsExt;

        let root = temp_root();
        let path = root.join(MEMORY_FILE);
        write_atomic(&path, "private memory").unwrap();
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );

        let temp = path.with_extension("md.tmp");
        std::fs::write(&temp, "leftover").unwrap();
        std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o644)).unwrap();
        write_atomic(&path, "new private memory").unwrap();
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            "new private memory"
        );
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!temp.exists());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn concurrent_habit_claims_only_save_over_a_version_once() {
        use std::sync::{Arc, Barrier};

        let root = temp_root();
        let hash = save(&Dirs::legacy(&root, "m").unwrap(), HABITS_FILE, "[]", None).unwrap();
        let barrier = Arc::new(Barrier::new(8));
        let claims: Vec<_> = (0..8)
            .map(|index| {
                let root = root.clone();
                let hash = hash.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    let text = format!("[{{\"claimedBy\":{index}}}]");
                    barrier.wait();
                    let result = save(
                        &Dirs::legacy(&root, "m").unwrap(),
                        HABITS_FILE,
                        &text,
                        Some(&hash),
                    );
                    (text, result)
                })
            })
            .collect();
        let results: Vec<_> = claims
            .into_iter()
            .map(|claim| claim.join().unwrap())
            .collect();
        let winners: Vec<_> = results
            .iter()
            .filter(|(_, result)| result.is_ok())
            .collect();
        assert_eq!(winners.len(), 1);
        for (_, result) in results.iter().filter(|(_, result)| result.is_err()) {
            assert_eq!(result.as_ref().unwrap_err(), CONFLICT);
        }
        let saved = read(&Dirs::legacy(&root, "m").unwrap(), HABITS_FILE).unwrap();
        assert_eq!(saved.text.as_ref(), Some(&winners[0].0));
        assert_eq!(saved.hash, content_hash(&winners[0].0));
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn reads_and_writes_topics_inside_the_folder_only() {
        let root = temp_root();
        save(
            &Dirs::legacy(&root, "m").unwrap(),
            "memory/releases.md",
            "# Releases",
            None,
        )
        .unwrap();
        save(
            &Dirs::legacy(&root, "m").unwrap(),
            "memory/archive.md",
            "- old",
            None,
        )
        .unwrap();
        let loaded = load_at(&root, "m").unwrap();
        assert_eq!(loaded.topics, vec!["releases".to_string()]);
        assert_eq!(loaded.topic_notes.len(), 1);
        assert_eq!(loaded.topic_notes[0].text, "# Releases");
        let topic = read(&Dirs::legacy(&root, "m").unwrap(), "memory/releases.md").unwrap();
        assert_eq!(topic.text.as_deref(), Some("# Releases"));
        assert_eq!(
            read(&Dirs::legacy(&root, "m").unwrap(), "memory/none.md")
                .unwrap()
                .text,
            None
        );
        save(
            &Dirs::legacy(&root, "m").unwrap(),
            "habits.json",
            "[]",
            None,
        )
        .unwrap();
        for path in [
            "../x.md",
            "memory/../SOUL.md",
            "memory/a/b.md",
            "memory/.hidden.md",
            "notes.md",
        ] {
            assert!(
                save(&Dirs::legacy(&root, "m").unwrap(), path, "x", None).is_err(),
                "{path}"
            );
        }
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn creates_a_fresh_workdir_and_never_reuses_an_existing_folder() {
        let root = temp_root();
        std::fs::create_dir_all(root.join("lens")).unwrap();
        std::fs::write(root.join("lens").join("keep.md"), "mine").unwrap();
        let dir = create_workdir(&root, "lens").unwrap();
        assert_eq!(dir, root.join("lens-2"));
        assert!(dir.join("repos").is_dir());
        assert_eq!(
            std::fs::read_to_string(root.join("lens").join("keep.md")).unwrap(),
            "mine"
        );
        assert!(!root.join("lens").join("repos").exists());
        assert_eq!(create_workdir(&root, "lens").unwrap(), root.join("lens-3"));
        let fresh = create_workdir(&root, "mentor").unwrap();
        assert_eq!(fresh, root.join("mentor"));
        for slug in ["", "repos", "../x", "A", "a b", "-a", "a-", &"a".repeat(41)] {
            assert!(create_workdir(&root, slug).is_err(), "{slug}");
        }
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn ensures_a_chosen_workdir_without_writing_into_it() {
        let root = temp_root();
        let existing = root.join("sandbox-study");
        std::fs::create_dir_all(&existing).unwrap();
        assert_eq!(ensure_workdir(&existing).unwrap(), existing);
        assert_eq!(std::fs::read_dir(&existing).unwrap().count(), 0);
        let missing = root.join("a").join("b");
        assert_eq!(ensure_workdir(&missing).unwrap(), missing);
        assert!(missing.is_dir());
        let file = root.join("file");
        std::fs::write(&file, "x").unwrap();
        assert!(ensure_workdir(&file).is_err());
        assert!(ensure_workdir(Path::new("relative/dir")).is_err());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn soul_and_memory_live_in_the_mentor_folder_and_habits_stay_in_app_data() {
        let root = temp_root();
        let dirs = Dirs {
            files: root.join("Loci/repo-lens"),
            habits: root.join("app/agents/m"),
        };
        save(&dirs, SOUL_FILE, "soul", None).unwrap();
        save(&dirs, "memory/kvm.md", "topic", None).unwrap();
        save(&dirs, HABITS_FILE, "[]", None).unwrap();
        assert!(root.join("Loci/repo-lens/SOUL.md").is_file());
        assert!(root.join("Loci/repo-lens/memory/kvm.md").is_file());
        assert!(root.join("app/agents/m/habits.json").is_file());
        assert!(!root.join("Loci/repo-lens/habits.json").exists());
        let files = load(&dirs, "m").unwrap();
        assert_eq!(files.soul.as_deref(), Some("soul"));
        assert_eq!(files.dir, root.join("Loci/repo-lens").to_string_lossy());
        std::fs::remove_dir_all(root).unwrap();
    }
}
