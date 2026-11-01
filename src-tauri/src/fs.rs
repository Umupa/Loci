use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use tauri::{AppHandle, Manager};
use uuid::Uuid;

use crate::dirs_home;

pub(crate) const MAX_TEXT_FILE_BYTES: u64 = 8 * 1024 * 1024;
pub(crate) const MAX_ATTACHMENT_EMBED_BYTES: u64 = 20 * 1024 * 1024;
pub(crate) const MAX_PREVIEW_BYTES: u64 = 25 * 1024 * 1024;
/// Documents opened in a file pane; a scanned book runs far past a preview image.
const MAX_DOCUMENT_BYTES: u64 = 512 * 1024 * 1024;
const MAX_GENERATED_IMAGE_BYTES: u64 = 25 * 1024 * 1024;
const MAX_GENERATED_IMAGE_DATA_BYTES: u64 = MAX_GENERATED_IMAGE_BYTES * 4 / 3 + 4;
const GENERATED_IMAGE_DIR: &str = "generated-images";

#[derive(Serialize, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedImageAsset {
    path: String,
    mime_type: String,
    size: u64,
}

#[derive(Serialize, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectLocation {
    path: String,
    identity: String,
}

/// Resolve a project by filesystem identity when its directory was renamed.
///
/// A rename preserves the directory identity. We only inspect direct siblings
/// of the missing path, which keeps this bounded and avoids a filesystem watch
/// or a broad disk search.
#[tauri::command(async)]
pub fn resolve_project_location(
    path: String,
    identity: Option<String>,
) -> Result<Option<ProjectLocation>, String> {
    resolve_project_location_sync(&path, identity.as_deref())
}

fn resolve_project_location_sync(
    path: &str,
    identity: Option<&str>,
) -> Result<Option<ProjectLocation>, String> {
    let path = expand_home(path);
    if path.is_dir() {
        let identity = directory_identity(&path)?;
        return Ok(Some(ProjectLocation {
            path: path_to_js(&path),
            identity,
        }));
    }

    let Some(identity) = identity.filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let Some(parent) = path.parent() else {
        return Ok(None);
    };
    let entries = match std::fs::read_dir(parent) {
        Ok(entries) => entries,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.to_string()),
    };
    for entry in entries.flatten() {
        let candidate = entry.path();
        if !candidate.is_dir() {
            continue;
        }
        let Ok(candidate_identity) = directory_identity(&candidate) else {
            continue;
        };
        if candidate_identity == identity {
            return Ok(Some(ProjectLocation {
                path: path_to_js(&candidate),
                identity: candidate_identity,
            }));
        }
    }
    Ok(None)
}

#[cfg(unix)]
fn directory_identity(path: &Path) -> Result<String, String> {
    use std::os::unix::fs::MetadataExt;

    let metadata = std::fs::metadata(path).map_err(|error| error.to_string())?;
    Ok(format!("unix:{}:{}", metadata.dev(), metadata.ino()))
}

#[cfg(windows)]
fn directory_identity(path: &Path) -> Result<String, String> {
    use std::fs::OpenOptions;
    use std::os::windows::fs::OpenOptionsExt;
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION, FILE_FLAG_BACKUP_SEMANTICS,
    };

    let file = OpenOptions::new()
        .read(true)
        .custom_flags(FILE_FLAG_BACKUP_SEMANTICS)
        .open(path)
        .map_err(|error| error.to_string())?;
    let mut info = BY_HANDLE_FILE_INFORMATION::default();
    let succeeded = unsafe {
        GetFileInformationByHandle(file.as_raw_handle() as _, std::ptr::addr_of_mut!(info))
    };
    if succeeded == 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    let file_index = (u64::from(info.nFileIndexHigh) << 32) | u64::from(info.nFileIndexLow);
    Ok(format!(
        "windows:{}:{file_index}",
        info.dwVolumeSerialNumber
    ))
}

/// Recover Bash commands that older UI builds saved as a bare "Shell" row.
/// Claude's own transcript retains the complete tool input by tool-use id.
#[tauri::command(async)]
pub fn claude_shell_commands(
    app: AppHandle,
    provider_session_id: String,
    provider_account_id: Option<String>,
    tool_ids: Vec<String>,
) -> Result<HashMap<String, String>, String> {
    if provider_session_id.is_empty()
        || !provider_session_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
    {
        return Err("Invalid Claude provider session id".into());
    }
    if tool_ids.is_empty() {
        return Ok(HashMap::new());
    }
    let config_dir = match provider_account_id.as_deref() {
        Some(id) if id != "default" => crate::harness::provider_account_path(&app, "claude", id)?,
        _ => match std::env::var_os("CLAUDE_CONFIG_DIR") {
            Some(path) => PathBuf::from(path),
            None => {
                PathBuf::from(dirs_home().ok_or("Home directory is unavailable")?).join(".claude")
            }
        },
    };
    let transcript_name = format!("{provider_session_id}.jsonl");
    let root = config_dir.join("projects");
    let Some(path) = std::fs::read_dir(root).ok().and_then(|projects| {
        projects.flatten().find_map(|project| {
            let candidate = project.path().join(&transcript_name);
            candidate.is_file().then_some(candidate)
        })
    }) else {
        return Ok(HashMap::new());
    };
    claude_shell_commands_from_file(&path, &tool_ids)
}

fn claude_shell_commands_from_file(
    path: &Path,
    tool_ids: &[String],
) -> Result<HashMap<String, String>, String> {
    let wanted: HashSet<&str> = tool_ids.iter().map(String::as_str).collect();
    let file = std::fs::File::open(path).map_err(|error| error.to_string())?;
    let mut commands = HashMap::new();
    for line in BufReader::new(file).lines() {
        let line = line.map_err(|error| error.to_string())?;
        let Ok(record) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };
        if record.get("type").and_then(serde_json::Value::as_str) != Some("assistant") {
            continue;
        }
        let Some(content) = record
            .pointer("/message/content")
            .and_then(serde_json::Value::as_array)
        else {
            continue;
        };
        for block in content {
            let Some(id) = block.get("id").and_then(serde_json::Value::as_str) else {
                continue;
            };
            if wanted.contains(id)
                && block.get("name").and_then(serde_json::Value::as_str) == Some("Bash")
            {
                if let Some(command) = block
                    .pointer("/input/command")
                    .and_then(serde_json::Value::as_str)
                    .filter(|command| !command.trim().is_empty())
                {
                    commands.insert(id.to_owned(), command.to_owned());
                }
            }
        }
        if commands.len() == wanted.len() {
            break;
        }
    }
    Ok(commands)
}

fn resolve_under(parent: &Path, name: &str) -> Result<PathBuf, String> {
    if name.starts_with('/') || name.starts_with('\\') {
        return Err("A file or folder name cannot start with a slash.".into());
    }

    let trimmed = name.trim_end_matches(['/', '\\']);
    if trimmed.is_empty() || trimmed.chars().all(char::is_whitespace) {
        return Err("A file or folder name must be provided.".into());
    }

    let mut dest = parent.to_path_buf();
    for segment in trimmed.split(['/', '\\']) {
        if segment.is_empty() {
            continue;
        }
        if segment == "." || segment == ".." || segment.len() > 255 {
            return Err(format!(
                "The name {trimmed} is not valid as a file or folder name. Please choose a different name."
            ));
        }
        dest.push(segment);
    }

    if !dest.starts_with(parent) {
        return Err("Invalid path".into());
    }
    Ok(dest)
}

fn file_label(path: &Path, fallback: &str) -> String {
    path.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or(fallback)
        .to_string()
}

fn already_exists(label: &str) -> String {
    format!(
        "A file or folder {label} already exists at this location. Please choose a different name."
    )
}

/// Create a file or folder under `parent`. `name` may contain `/` or `\` to
/// nest. Returns the created path.
#[tauri::command(async)]
pub fn create_path(parent: String, name: String, is_dir: bool) -> Result<String, String> {
    let parent_dir = expand_home(&parent);
    let dest = resolve_under(&parent_dir, &name)?;
    let label = file_label(&dest, &name);

    if dest.exists() {
        return Err(already_exists(&label));
    }

    if is_dir {
        std::fs::create_dir_all(&dest).map_err(|e| e.to_string())?;
    } else {
        if let Some(dir) = dest.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        std::fs::File::create_new(&dest).map_err(|e| {
            if e.kind() == ErrorKind::AlreadyExists {
                already_exists(&label)
            } else {
                e.to_string()
            }
        })?;
    }

    Ok(dest.to_string_lossy().into_owned())
}

pub(crate) fn expand_home(path: &str) -> PathBuf {
    if path == "~" {
        return dirs_home()
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(path));
    }
    let rest = path.strip_prefix("~/").or_else(|| {
        if cfg!(windows) {
            path.strip_prefix("~\\")
        } else {
            None
        }
    });
    if let Some(rest) = rest {
        if let Some(home) = dirs_home() {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}

pub(crate) fn path_to_js(path: &Path) -> String {
    let text = path.to_string_lossy();
    if cfg!(windows) {
        text.replace('\\', "/")
    } else {
        text.into_owned()
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathInfo {
    pub path: String,
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
}

/// Metadata for files the composer is attaching (picker, drop, paste).
#[tauri::command(async)]
pub fn inspect_paths(paths: Vec<String>) -> Vec<PathInfo> {
    paths
        .into_iter()
        .filter_map(|path| inspect_path_sync(&path))
        .collect()
}

fn inspect_path_sync(path: &str) -> Option<PathInfo> {
    let path = expand_home(path);
    let meta = std::fs::metadata(&path).ok()?;
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(path.to_str().unwrap_or("attachment"))
        .to_string();
    Some(PathInfo {
        path: path_to_js(&path),
        name,
        size: meta.len(),
        is_dir: meta.is_dir(),
    })
}

/// Base64-encode a file so vision images can be sent inline over ACP.
#[tauri::command]
pub async fn read_file_base64(path: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || read_file_base64_sync(&path))
        .await
        .map_err(|e| e.to_string())?
}

fn read_file_base64_sync(path: &str) -> Result<String, String> {
    let path = expand_home(path);
    let meta = std::fs::metadata(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    if !meta.is_file() {
        return Err("Not a file".into());
    }
    if meta.len() > MAX_ATTACHMENT_EMBED_BYTES {
        return Err(format!(
            "File is too large to attach inline (maximum {} MB).",
            MAX_ATTACHMENT_EMBED_BYTES / 1024 / 1024
        ));
    }
    let bytes = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        bytes,
    ))
}

/// Read a file as raw bytes for the image viewer.
///
/// Returns an `ipc::Response`, which reaches the webview as an ArrayBuffer, so
/// previews skip the 33% base64 inflation that inline attachments pay. The
/// caller decides what the bytes are by sniffing them; this only guards size.
#[tauri::command]
pub async fn read_binary_file(path: String) -> Result<tauri::ipc::Response, String> {
    let bytes = tauri::async_runtime::spawn_blocking(move || read_binary_file_sync(&path))
        .await
        .map_err(|e| e.to_string())??;
    Ok(tauri::ipc::Response::new(bytes))
}

fn read_binary_file_sync(path: &str) -> Result<Vec<u8>, String> {
    let path = expand_home(path);
    let meta = std::fs::metadata(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    if !meta.is_file() {
        return Err("Not a file".into());
    }
    if meta.len() > MAX_PREVIEW_BYTES {
        return Err(format!(
            "File is too large to preview (maximum {} MB).",
            MAX_PREVIEW_BYTES / 1024 / 1024
        ));
    }
    std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))
}

/// Raw bytes of a document shown in a file pane (PDF).
#[tauri::command]
pub async fn read_document_file(path: String) -> Result<tauri::ipc::Response, String> {
    tauri::async_runtime::spawn_blocking(move || read_document_file_sync(&path))
        .await
        .map_err(|e| e.to_string())?
        .map(tauri::ipc::Response::new)
}

fn read_document_file_sync(path: &str) -> Result<Vec<u8>, String> {
    let path = expand_home(path);
    let meta = std::fs::metadata(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    if !meta.is_file() {
        return Err("Not a file".into());
    }
    if meta.len() > MAX_DOCUMENT_BYTES {
        return Err(format!(
            "File is too large to open (maximum {} MB).",
            MAX_DOCUMENT_BYTES / 1024 / 1024
        ));
    }
    std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))
}

/// Persist a pasted blob so non-image attachments have a real path.
#[tauri::command]
pub async fn write_attachment(name: String, data: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || write_attachment_sync(&name, &data))
        .await
        .map_err(|e| e.to_string())?
}

fn write_attachment_sync(name: &str, data: &str) -> Result<String, String> {
    let bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, data)
        .map_err(|_| "Attachment data is not valid base64.".to_string())?;
    if bytes.len() as u64 > MAX_ATTACHMENT_EMBED_BYTES {
        return Err(format!(
            "File is too large to attach (maximum {} MB).",
            MAX_ATTACHMENT_EMBED_BYTES / 1024 / 1024
        ));
    }
    let dir = std::env::temp_dir().join("loci-attachments");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let path = dir.join(format!(
        "{}-{}-{}",
        std::process::id(),
        stamp,
        safe_attachment_name(name)
    ));
    // A pasted screenshot can be a picture of whatever was on screen, so keep
    // it owner-only rather than at the umask default of 0644 in a shared /tmp.
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(&path)
        .and_then(|mut file| file.write_all(&bytes))
        .map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(path.to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn save_generated_image(
    app: AppHandle,
    data: String,
    name: String,
) -> Result<GeneratedImageAsset, String> {
    tauri::async_runtime::spawn_blocking(move || save_generated_image_sync(&app, &data, &name))
        .await
        .map_err(|e| e.to_string())?
}

fn save_generated_image_sync(
    app: &AppHandle,
    data: &str,
    name: &str,
) -> Result<GeneratedImageAsset, String> {
    if data.len() as u64 > MAX_GENERATED_IMAGE_DATA_BYTES {
        return Err(format!(
            "Generated image is too large (maximum {} MB).",
            MAX_GENERATED_IMAGE_BYTES / 1024 / 1024
        ));
    }
    let encoded: String = data
        .chars()
        .filter(|ch| !ch.is_ascii_whitespace())
        .collect();
    let bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        .map_err(|_| "Generated image data is not valid base64.".to_string())?;
    if bytes.is_empty() || bytes.len() as u64 > MAX_GENERATED_IMAGE_BYTES {
        return Err(format!(
            "Generated image is too large (maximum {} MB).",
            MAX_GENERATED_IMAGE_BYTES / 1024 / 1024
        ));
    }
    if !is_png(&bytes) {
        return Err("Generated image data is not a PNG image.".into());
    }
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join(GENERATED_IMAGE_DIR);
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let safe_name = safe_attachment_name(name);
    let destination = dir.join(format!("{}-{}.png", Uuid::new_v4(), safe_name));
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&destination)
        .map_err(|e| format!("{}: {e}", destination.display()))?;
    if let Err(error) = file.write_all(&bytes) {
        let _ = std::fs::remove_file(&destination);
        return Err(format!("{}: {error}", destination.display()));
    }
    Ok(GeneratedImageAsset {
        path: destination.to_string_lossy().into_owned(),
        mime_type: "image/png".into(),
        size: bytes.len() as u64,
    })
}

#[tauri::command]
pub async fn delete_generated_images(app: AppHandle, paths: Vec<String>) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || delete_generated_images_sync(&app, &paths))
        .await
        .map_err(|e| e.to_string())?
}

pub(crate) fn delete_generated_images_sync(
    app: &AppHandle,
    paths: &[String],
) -> Result<(), String> {
    let root = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join(GENERATED_IMAGE_DIR)
        .canonicalize()
        .map_err(|error| format!("Generated image directory is unavailable: {error}"))?;
    for path in paths {
        let candidate = match PathBuf::from(path).canonicalize() {
            Ok(candidate) => candidate,
            Err(error) if error.kind() == ErrorKind::NotFound => continue,
            Err(error) => return Err(error.to_string()),
        };
        if !candidate.starts_with(&root) || !candidate.is_file() {
            return Err("Invalid generated image path".into());
        }
        std::fs::remove_file(candidate).map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn is_png(bytes: &[u8]) -> bool {
    bytes.len() >= 8 && bytes.starts_with(&[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
}

fn safe_attachment_name(name: &str) -> String {
    let leaf = Path::new(name)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("attachment");
    let cleaned: String = leaf
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '.' || ch == '-' || ch == '_' {
                ch
            } else {
                '-'
            }
        })
        .collect();
    let trimmed = cleaned.trim_matches('.').trim_matches('-');
    if trimmed.is_empty() {
        "attachment".into()
    } else {
        trimmed.chars().take(80).collect()
    }
}

/// Read a reasonably sized UTF-8 skill or configuration file.
#[tauri::command]
pub async fn read_text_file(path: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || read_text_file_sync(&path))
        .await
        .map_err(|e| e.to_string())?
}

pub(crate) fn read_text_file_sync(path: &str) -> Result<String, String> {
    let path = expand_home(path);
    let meta = std::fs::metadata(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    if !meta.is_file() {
        return Err("Not a file".into());
    }
    if meta.len() > MAX_TEXT_FILE_BYTES {
        return Err(format!(
            "File is too large to read (maximum {} MB).",
            MAX_TEXT_FILE_BYTES / 1024 / 1024
        ));
    }

    let bytes = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    if bytes.contains(&0) {
        return Err("Binary files cannot be read as text.".into());
    }
    String::from_utf8(bytes).map_err(|_| "File is not valid UTF-8.".into())
}

/// Atomically replace a text file from a temporary file in the same directory.
#[tauri::command]
pub async fn write_text_file(path: String, content: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || write_text_file_sync(&path, &content))
        .await
        .map_err(|e| e.to_string())?
}

fn write_text_file_sync(path: &str, content: &str) -> Result<(), String> {
    if content.len() as u64 > MAX_TEXT_FILE_BYTES {
        return Err(format!(
            "File is too large to save (maximum {} MB).",
            MAX_TEXT_FILE_BYTES / 1024 / 1024
        ));
    }

    let requested = expand_home(path);
    let destination = if requested.exists() {
        std::fs::canonicalize(&requested).map_err(|e| format!("{}: {e}", requested.display()))?
    } else {
        requested
    };
    if destination.is_dir() {
        return Err("Cannot save text to a directory.".into());
    }

    let parent = destination
        .parent()
        .ok_or_else(|| "File has no parent directory.".to_string())?;
    let name = destination
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "Invalid file name.".to_string())?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    let mut temporary = None;
    for attempt in 0..100 {
        let candidate = parent.join(format!(
            ".{name}.loci-{}-{stamp}-{attempt}.tmp",
            std::process::id()
        ));
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(file) => {
                temporary = Some((candidate, file));
                break;
            }
            Err(error) if error.kind() == ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("{}: {error}", candidate.display())),
        }
    }

    let (temporary_path, mut file) =
        temporary.ok_or_else(|| "Could not create a temporary save file.".to_string())?;
    let write_result = (|| -> Result<(), String> {
        file.write_all(content.as_bytes())
            .map_err(|e| e.to_string())?;
        file.sync_all().map_err(|e| e.to_string())?;
        if let Ok(meta) = std::fs::metadata(&destination) {
            std::fs::set_permissions(&temporary_path, meta.permissions())
                .map_err(|e| e.to_string())?;
        }
        drop(file);
        std::fs::rename(&temporary_path, &destination).map_err(|e| e.to_string())?;
        if let Ok(dir) = std::fs::File::open(parent) {
            let _ = dir.sync_all();
        }
        Ok(())
    })();

    if write_result.is_err() {
        let _ = std::fs::remove_file(&temporary_path);
    }
    write_result
}

fn delete_path_sync(path: &str) -> Result<(), String> {
    let path = expand_home(path);
    if !path.exists() {
        return Err(format!("{}: No such file or directory", path.display()));
    }
    if path.is_dir() {
        std::fs::remove_dir_all(&path).map_err(|e| format!("{}: {e}", path.display()))
    } else {
        std::fs::remove_file(&path).map_err(|e| format!("{}: {e}", path.display()))
    }
}

#[tauri::command]
pub async fn delete_path(path: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || delete_path_sync(&path))
        .await
        .map_err(|e| e.to_string())?
}

#[derive(Serialize, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DirEntry {
    name: String,
    path: String,
    is_dir: bool,
    /// Dotfiles: hidden from the Files tree unless the user asks for them.
    hidden: bool,
}

/// Immediate children of `path` (project tree). Folders first, then files.
#[tauri::command(async)]
pub fn list_dir(path: String) -> Result<Vec<DirEntry>, String> {
    list_dir_sync(&expand_home(&path))
}

fn list_dir_sync(dir: &Path) -> Result<Vec<DirEntry>, String> {
    let reader = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;

    let mut out = Vec::new();
    for ent in reader {
        let Ok(ent) = ent else { continue };
        let name = ent.file_name();
        let Some(name) = name.to_str() else { continue };
        if name == ".DS_Store" {
            continue;
        }
        let path = ent.path();
        let is_dir = ent
            .file_type()
            .map(|t| t.is_dir() || (t.is_symlink() && path.is_dir()))
            .unwrap_or_else(|_| path.is_dir());
        out.push(DirEntry {
            hidden: name.starts_with('.'),
            name: name.to_string(),
            path: path_to_js(&path),
            is_dir,
        });
    }

    out.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| compare_natural_names(&a.name, &b.name))
    });
    Ok(out)
}

const MAX_PROJECT_FILES: usize = 20_000;
const MAX_WALK_DIRS: usize = 4_000;

#[derive(Serialize, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectFile {
    name: String,
    path: String,
    relative: String,
    is_dir: bool,
}

/// Every file and folder under `cwd`, for finding by name or path. The walk is
/// breadth-first and bounded, and never descends into dot folders or
/// `node_modules`, so a large folder still answers quickly.
#[tauri::command]
pub async fn list_project_files(cwd: String) -> Result<Vec<ProjectFile>, String> {
    tauri::async_runtime::spawn_blocking(move || list_project_files_sync(&expand_home(&cwd)))
        .await
        .map_err(|e| e.to_string())?
}

fn list_project_files_sync(root: &Path) -> Result<Vec<ProjectFile>, String> {
    if !root.is_dir() {
        return Err(format!("{}: Not a directory", root.display()));
    }
    let mut out = Vec::new();
    let mut queue = std::collections::VecDeque::from([root.to_path_buf()]);
    let mut walked = 0;
    while let Some(dir) = queue.pop_front() {
        walked += 1;
        if walked > MAX_WALK_DIRS {
            break;
        }
        let Ok(entries) = list_dir_sync(&dir) else {
            continue;
        };
        for entry in entries {
            if entry.hidden || (entry.is_dir && entry.name == "node_modules") {
                continue;
            }
            let path = PathBuf::from(&entry.path);
            let Ok(relative) = path.strip_prefix(root) else {
                continue;
            };
            if out.len() >= MAX_PROJECT_FILES {
                return Ok(out);
            }
            out.push(ProjectFile {
                relative: path_to_js(relative),
                name: entry.name,
                path: entry.path,
                is_dir: entry.is_dir,
            });
            if entry.is_dir {
                queue.push_back(path);
            }
        }
    }
    Ok(out)
}

fn compare_natural_names(a: &str, b: &str) -> std::cmp::Ordering {
    use std::cmp::Ordering;

    let (a, b) = (a.as_bytes(), b.as_bytes());
    let (mut i, mut j) = (0, 0);
    while i < a.len() && j < b.len() {
        if a[i].is_ascii_digit() && b[j].is_ascii_digit() {
            let a_start = i;
            let b_start = j;
            while i < a.len() && a[i].is_ascii_digit() {
                i += 1;
            }
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            let a_digits = &a[a_start..i];
            let b_digits = &b[b_start..j];
            let a_value = a_digits
                .iter()
                .position(|digit| *digit != b'0')
                .map_or(&a_digits[a_digits.len()..], |start| &a_digits[start..]);
            let b_value = b_digits
                .iter()
                .position(|digit| *digit != b'0')
                .map_or(&b_digits[b_digits.len()..], |start| &b_digits[start..]);
            let order = a_value
                .len()
                .cmp(&b_value.len())
                .then_with(|| a_value.cmp(b_value));
            if order != Ordering::Equal {
                return order;
            }
        } else {
            let order = a[i].to_ascii_lowercase().cmp(&b[j].to_ascii_lowercase());
            if order != Ordering::Equal {
                return order;
            }
            i += 1;
            j += 1;
        }
    }
    (a.len() - i).cmp(&(b.len() - j)).then_with(|| a.cmp(b))
}

const MAX_STAT_FILES: usize = 64;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileMtime {
    path: String,
    mtime_ms: Option<u64>,
}

fn file_mtime_ms(meta: &std::fs::Metadata) -> Option<u64> {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
}

/// Metadata only — used to notice disk changes on currently open editors.
#[tauri::command(async)]
pub fn stat_files(paths: Vec<String>) -> Result<Vec<FileMtime>, String> {
    if paths.len() > MAX_STAT_FILES {
        return Err("Too many paths".into());
    }
    Ok(paths
        .into_iter()
        .map(|path| {
            let expanded = expand_home(&path);
            let mtime_ms = std::fs::metadata(&expanded)
                .ok()
                .filter(|meta| meta.is_file())
                .and_then(|meta| file_mtime_ms(&meta));
            FileMtime { path, mtime_ms }
        })
        .collect())
}

fn same_entry(a: &Path, b: &Path) -> bool {
    if a == b {
        return true;
    }
    let Ok(a_meta) = std::fs::metadata(a) else {
        return false;
    };
    let Ok(b_meta) = std::fs::metadata(b) else {
        return false;
    };
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        a_meta.dev() == b_meta.dev() && a_meta.ino() == b_meta.ino()
    }
    #[cfg(not(unix))]
    {
        let _ = (a_meta, b_meta);
        match (std::fs::canonicalize(a), std::fs::canonicalize(b)) {
            (Ok(left), Ok(right)) => left == right,
            _ => false,
        }
    }
}

fn split_stem_ext(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

fn unique_name_in(dir: &Path, name: &str) -> String {
    let (stem, ext) = split_stem_ext(name);
    let mut n = 0u32;
    loop {
        let candidate = match n {
            0 => name.to_string(),
            1 => format!("{stem} copy{ext}"),
            _ => format!("{stem} copy {n}{ext}"),
        };
        if !dir.join(&candidate).exists() {
            return candidate;
        }
        n += 1;
        if n > 1000 {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            return format!("{stem} copy {stamp}{ext}");
        }
    }
}

fn copy_recursive(from: &Path, to: &Path) -> Result<(), String> {
    let meta = std::fs::metadata(from).map_err(|e| format!("{}: {e}", from.display()))?;
    if meta.is_dir() {
        std::fs::create_dir(to).map_err(|e| format!("{}: {e}", to.display()))?;
        for ent in std::fs::read_dir(from).map_err(|e| format!("{}: {e}", from.display()))? {
            let ent = ent.map_err(|e| e.to_string())?;
            copy_recursive(&ent.path(), &to.join(ent.file_name()))?;
        }
        Ok(())
    } else {
        std::fs::copy(from, to)
            .map(|_| ())
            .map_err(|e| format!("{}: {e}", to.display()))
    }
}

fn rename_path_sync(path: &str, name: &str) -> Result<String, String> {
    let from = expand_home(path);
    if !from.exists() {
        return Err(format!("{}: No such file or directory", from.display()));
    }
    let parent = from
        .parent()
        .ok_or_else(|| "File has no parent directory.".to_string())?;
    let dest = resolve_under(parent, name)?;
    if same_entry(&from, &dest) {
        if from == dest {
            return Ok(from.to_string_lossy().into_owned());
        }
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let tmp = parent.join(format!(".{}.loci-rename-{stamp}", file_label(&from, "tmp")));
        std::fs::rename(&from, &tmp).map_err(|e| e.to_string())?;
        if let Err(e) = std::fs::rename(&tmp, &dest) {
            let _ = std::fs::rename(&tmp, &from);
            return Err(e.to_string());
        }
        return Ok(dest.to_string_lossy().into_owned());
    }
    if dest.exists() {
        return Err(already_exists(&file_label(&dest, name)));
    }
    if dest.starts_with(&from) {
        return Err("Cannot move a folder into itself.".into());
    }
    if let Some(dir) = dest.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    std::fs::rename(&from, &dest).map_err(|e| e.to_string())?;
    Ok(dest.to_string_lossy().into_owned())
}

/// Rename `path` to `name` (relative to the current parent; `/` nests).
#[tauri::command]
pub async fn rename_path(path: String, name: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || rename_path_sync(&path, &name))
        .await
        .map_err(|e| e.to_string())?
}

fn trash_path_sync(path: &str) -> Result<(), String> {
    let path = expand_home(path);
    if std::fs::symlink_metadata(&path).is_err() {
        return Err(format!("{}: No such file or directory", path.display()));
    }
    trash::delete(&path).map_err(|e| format!("{}: {e}", path.display()))
}

/// Move a file or folder to the system trash, so a delete from the Files tree
/// can be undone the way it can in the system file manager.
#[tauri::command]
pub async fn trash_path(path: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || trash_path_sync(&path))
        .await
        .map_err(|e| e.to_string())?
}

fn dir_contains(dir: &Path, dest_parent: &Path) -> bool {
    let dir = std::fs::canonicalize(dir).unwrap_or_else(|_| dir.to_path_buf());
    let dest_parent =
        std::fs::canonicalize(dest_parent).unwrap_or_else(|_| dest_parent.to_path_buf());
    dest_parent.starts_with(&dir)
}

fn copy_path_sync(from: &str, dest_parent: &str) -> Result<String, String> {
    let from = expand_home(from);
    if !from.exists() {
        return Err(format!("{}: No such file or directory", from.display()));
    }
    let dest_parent = expand_home(dest_parent);
    if !dest_parent.is_dir() {
        return Err(format!("{} is not a folder", dest_parent.display()));
    }
    if from.is_dir() && dir_contains(&from, &dest_parent) {
        return Err("Cannot paste a folder into itself.".into());
    }
    let name = unique_name_in(
        &dest_parent,
        &file_label(&from, from.to_str().unwrap_or("copy")),
    );
    let dest = dest_parent.join(&name);
    copy_recursive(&from, &dest)?;
    Ok(dest.to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn copy_path(from: String, dest_parent: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || copy_path_sync(&from, &dest_parent))
        .await
        .map_err(|e| e.to_string())?
}

fn move_path_sync(from: &str, dest_parent: &str) -> Result<String, String> {
    let from = expand_home(from);
    if !from.exists() {
        return Err(format!("{}: No such file or directory", from.display()));
    }
    let dest_parent = expand_home(dest_parent);
    if !dest_parent.is_dir() {
        return Err(format!("{} is not a folder", dest_parent.display()));
    }
    if from.is_dir() && dir_contains(&from, &dest_parent) {
        return Err("Cannot paste a folder into itself.".into());
    }
    let name = file_label(&from, from.to_str().unwrap_or("item"));
    let dest = dest_parent.join(&name);
    if same_entry(&from, &dest) {
        return Ok(from.to_string_lossy().into_owned());
    }
    if dest.exists() {
        return Err(already_exists(&name));
    }
    std::fs::rename(&from, &dest).map_err(|e| e.to_string())?;
    Ok(dest.to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn move_path(from: String, dest_parent: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || move_path_sync(&from, &dest_parent))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub fn reveal_path(path: String) -> Result<(), String> {
    let path = expand_home(&path);
    if !path.exists() {
        return Err(format!("{}: No such file or directory", path.display()));
    }
    #[cfg(target_os = "macos")]
    {
        let path_str = path.to_str().ok_or_else(|| "Invalid path".to_string())?;
        let status = Command::new("open")
            .args(["-R", path_str])
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("Could not reveal in Finder.".into());
        }
        Ok(())
    }

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        // explorer.exe returns 1 even when it opened the folder.
        let path_str = path.to_string_lossy().replace('/', "\\");
        // `.arg` would wrap the whole `/select,...` switch in quotes when the
        // path has spaces; explorer ignores a quoted switch and opens its
        // default folder instead. Only the path itself may be quoted.
        Command::new("explorer")
            .raw_arg(format!("/select,\"{path_str}\""))
            .spawn()
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        let parent = path
            .parent()
            .ok_or_else(|| "File has no parent directory.".to_string())?;
        let status = Command::new("xdg-open")
            .arg(parent)
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("Could not open the containing folder.".into());
        }
        Ok(())
    }
}

#[tauri::command]
pub async fn open_path_with_default_app(path: String) -> Result<(), String> {
    // The Tauri opener command needs a static path scope, and its detached
    // launcher cannot report a failing `open` process back to the UI.
    tauri::async_runtime::spawn_blocking(move || {
        let path = expand_home(&path);
        if !path.is_absolute() {
            return Err("Expected an absolute file path".to_string());
        }
        std::fs::metadata(&path).map_err(|error| format!("{}: {error}", path.display()))?;
        open::that(&path).map_err(|error| error.to_string())
    })
    .await
    .map_err(|error| error.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn generated_image_validation_accepts_png_only() {
        assert!(is_png(&[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
        assert!(!is_png(&[0xff, 0xd8, 0xff, 0x00]));
        assert!(!is_png(b"<html>"));
        assert!(!is_png(&[]));
    }

    #[test]
    fn project_location_follows_a_sibling_rename() {
        let parent = tmp("project-location-rename");
        let original = parent.0.join("loci");
        let renamed = parent.0.join("loci-personal");
        std::fs::create_dir(&original).unwrap();

        let first = resolve_project_location_sync(&path_to_js(&original), None)
            .unwrap()
            .unwrap();
        assert_eq!(first.path, path_to_js(&original));

        std::fs::rename(&original, &renamed).unwrap();
        let resolved = resolve_project_location_sync(&path_to_js(&original), Some(&first.identity))
            .unwrap()
            .unwrap();
        assert_eq!(resolved.path, path_to_js(&renamed));
        assert_eq!(resolved.identity, first.identity);
    }

    #[test]
    fn project_location_does_not_guess_without_a_saved_identity() {
        let parent = tmp("project-location-missing");
        let missing = parent.0.join("old-name");
        std::fs::create_dir(parent.0.join("some-project")).unwrap();

        assert_eq!(
            resolve_project_location_sync(&path_to_js(&missing), None).unwrap(),
            None
        );
    }

    #[test]
    fn skill_text_files_round_trip_without_leaving_a_temporary_file() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("loci-text-{}-{stamp}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("example.rs");
        std::fs::write(&path, "fn old() {}\n").unwrap();
        let path_string = path.to_string_lossy().into_owned();

        assert_eq!(read_text_file_sync(&path_string).unwrap(), "fn old() {}\n");
        write_text_file_sync(&path_string, "fn new() {}\n").unwrap();
        assert_eq!(read_text_file_sync(&path_string).unwrap(), "fn new() {}\n");

        let names: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        assert_eq!(names, vec![std::ffi::OsString::from("example.rs")]);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn binary_reads_return_bytes_and_refuse_directories() {
        let dir = tmp("binary-read");
        let file = dir.0.join("shot.png");
        std::fs::write(&file, [0x89, b'P', b'N', b'G', 0x0d]).unwrap();

        let bytes = read_binary_file_sync(&file.to_string_lossy()).unwrap();
        assert_eq!(bytes, vec![0x89, b'P', b'N', b'G', 0x0d]);
        assert!(read_binary_file_sync(&dir.0.to_string_lossy()).is_err());
    }

    #[test]
    fn inspect_paths_reports_files_and_directories() {
        let dir = tmp("inspect-paths");
        let file = dir.0.join("notes.md");
        std::fs::write(&file, "hello\n").unwrap();
        let infos = inspect_paths(vec![
            file.to_string_lossy().into_owned(),
            dir.0.to_string_lossy().into_owned(),
        ]);
        assert_eq!(infos.len(), 2);
        let notes = infos.iter().find(|info| info.name == "notes.md").unwrap();
        assert!(!notes.is_dir);
        assert_eq!(notes.size, 6);
        let folder = infos.iter().find(|info| info.is_dir).unwrap();
        assert_eq!(folder.path, path_to_js(&dir.0));
    }

    #[test]
    fn attachment_bytes_round_trip_through_temp_dir() {
        let encoded =
            read_file_base64_sync(&write_attachment_sync("shot.png", "aGVsbG8=").unwrap()).unwrap();
        assert_eq!(encoded, "aGVsbG8=");
        assert_eq!(safe_attachment_name("../../secret.png"), "secret.png");
        assert_eq!(safe_attachment_name(""), "attachment");
    }

    struct Tmp(PathBuf);
    impl Drop for Tmp {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn tmp(label: &str) -> Tmp {
        loop {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let seq = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
            let dir = std::env::temp_dir()
                .join(format!("loci-{label}-{}-{stamp}-{seq}", std::process::id()));
            match std::fs::create_dir(&dir) {
                Ok(()) => return Tmp(dir),
                Err(error) if error.kind() == ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("{}", error),
            }
        }
    }

    #[test]
    fn claude_shell_commands_match_only_requested_bash_tool_ids() {
        let dir = tmp("claude-shell-commands");
        let path = dir.0.join("session.jsonl");
        let records = [
            serde_json::json!({"type":"assistant","message":{"content":[
                {"type":"tool_use","id":"toolu_one","name":"Bash","input":{"command":"npm test"}},
                {"type":"tool_use","id":"toolu_read","name":"Read","input":{"command":"ignore"}}
            ]}}),
            serde_json::json!({"type":"assistant","message":{"content":[
                {"type":"tool_use","id":"toolu_two","name":"Bash","input":{"command":"pwd"}}
            ]}}),
        ];
        std::fs::write(&path, records.map(|record| record.to_string()).join("\n")).unwrap();
        let commands =
            claude_shell_commands_from_file(&path, &["toolu_one".into(), "toolu_read".into()])
                .unwrap();
        assert_eq!(
            commands,
            HashMap::from([("toolu_one".into(), "npm test".into())])
        );
    }
    #[test]
    fn list_dir_sorts_naturally_with_folders_first_and_marks_dotfiles() {
        let dir = tmp("list-dir-natural-sort");
        for name in [
            "chapter-100.md",
            "chapter-9.md",
            "Chapter-2.md",
            ".env",
            ".DS_Store",
        ] {
            std::fs::write(dir.0.join(name), "").unwrap();
        }
        for name in ["volume-10", "volume-2"] {
            std::fs::create_dir(dir.0.join(name)).unwrap();
        }

        let entries = list_dir_sync(&dir.0).unwrap();
        let names: Vec<_> = entries.iter().map(|entry| entry.name.as_str()).collect();
        assert_eq!(
            names,
            [
                "volume-2",
                "volume-10",
                ".env",
                "Chapter-2.md",
                "chapter-9.md",
                "chapter-100.md",
            ]
        );
        let hidden: Vec<_> = entries
            .iter()
            .filter(|e| e.hidden)
            .map(|e| e.name.as_str())
            .collect();
        assert_eq!(hidden, [".env"]);
        assert!(entries[0].is_dir && !entries[2].is_dir);
    }

    #[test]
    fn stat_files_returns_mtime_for_existing_files_only() {
        let dir = tmp("stat-files");
        let path = dir.0.join("notes.md");
        std::fs::write(&path, "hi\n").unwrap();
        let path_string = path.to_string_lossy().into_owned();
        let missing = dir.0.join("gone.md").to_string_lossy().into_owned();

        let stats = stat_files(vec![path_string.clone(), missing.clone()]).unwrap();
        assert_eq!(stats[0].path, path_string);
        assert!(stats[0].mtime_ms.is_some());
        assert_eq!(stats[1].path, missing);
        assert!(stats[1].mtime_ms.is_none());
    }

    #[test]
    fn rename_copy_and_move_keep_existing_entries() {
        let dir = tmp("rename-copy-move");
        let root = dir.0.to_string_lossy().into_owned();
        let report = dir.0.join("report.pdf");
        std::fs::write(&report, "pdf").unwrap();
        std::fs::write(dir.0.join("taken.pdf"), "other").unwrap();
        std::fs::create_dir(dir.0.join("archive")).unwrap();
        let report = report.to_string_lossy().into_owned();

        assert!(rename_path_sync(&report, "taken.pdf").is_err());
        let renamed = rename_path_sync(&report, "final.pdf").unwrap();
        assert!(renamed.ends_with("final.pdf"));

        let copy = copy_path_sync(&renamed, &root).unwrap();
        assert!(copy.ends_with("final copy.pdf"));

        let archive = dir.0.join("archive").to_string_lossy().into_owned();
        let moved = move_path_sync(&renamed, &archive).unwrap();
        assert_eq!(std::fs::read_to_string(&moved).unwrap(), "pdf");
        assert!(!Path::new(&renamed).exists());
        assert!(move_path_sync(&archive, &archive).is_err());
        assert!(copy_path_sync(&copy, &archive).is_ok());
    }
    #[test]
    fn project_files_skip_dot_folders_and_dependencies() {
        let dir = tmp("project-files");
        for folder in ["papers/2024", ".git", "node_modules/pkg"] {
            std::fs::create_dir_all(dir.0.join(folder)).unwrap();
        }
        for file in [
            "readme.md",
            "papers/2024/survey.pdf",
            ".git/config",
            "node_modules/pkg/index.js",
        ] {
            std::fs::write(dir.0.join(file), "").unwrap();
        }

        let mut found: Vec<_> = list_project_files_sync(&dir.0)
            .unwrap()
            .into_iter()
            .map(|file| (file.relative, file.is_dir))
            .collect();
        found.sort();
        assert_eq!(
            found,
            [
                ("papers".to_string(), true),
                ("papers/2024".to_string(), true),
                ("papers/2024/survey.pdf".to_string(), false),
                ("readme.md".to_string(), false),
            ]
        );
    }
}
