//! Files that let a terminal outside Loci reach the running app: where it
//! listens (`endpoint.json`), the local token (`cli-token`), and whether
//! command-line access is on (`cli.json`). They live in `<app data>/control`,
//! readable only by the current user. The app writes them; the `loci` CLI
//! reads them. Each Loci build has its own data folder, so Loci Dev and QA
//! builds never answer for the installed app.
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

pub const ENDPOINT_FILE: &str = "endpoint.json";
pub const TOKEN_FILE: &str = "cli-token";
pub const SETTINGS_FILE: &str = "cli.json";

/// `com.loci.desktop`, `com.loci.desktop.dev`, `com.loci.desktop.qa-1`, ...
pub fn valid_identifier(value: &str) -> bool {
    value.starts_with("com.loci.")
        && value.len() <= 128
        && value.split('.').all(|part| {
            !part.is_empty() && part.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
        })
}

/// The folder Tauri uses as `app_data_dir` for an identifier.
pub fn app_data_dir(identifier: &str) -> Result<PathBuf, String> {
    if !valid_identifier(identifier) {
        return Err(format!("Not a Loci app identifier: {identifier}"));
    }
    dirs::data_dir()
        .map(|dir| dir.join(identifier))
        .ok_or_else(|| "Cannot find this user's application data folder".into())
}

pub fn control_dir(app_data_dir: &Path) -> PathBuf {
    app_data_dir.join("control")
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Endpoint {
    pub endpoint: String,
    pub pid: u32,
    pub version: String,
    pub identifier: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Settings {
    enabled: bool,
}

pub fn ensure_private_dir(dir: &Path) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| format!("Cannot create {}: {e}", dir.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Written whole under a temporary name, then renamed: a reader never sees half a file,
/// and the file is private before it holds anything.
pub fn write_private(path: &Path, contents: &str) -> Result<(), String> {
    let dir = path.parent().ok_or("A file needs a folder")?;
    ensure_private_dir(dir)?;
    let temp = dir.join(format!(
        ".{}.{}",
        path.file_name().and_then(|n| n.to_str()).unwrap_or("file"),
        uuid::Uuid::new_v4().simple()
    ));
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = (|| {
        let mut file = options.open(&temp).map_err(|e| e.to_string())?;
        file.write_all(contents.as_bytes())
            .map_err(|e| e.to_string())?;
        file.sync_all().map_err(|e| e.to_string())?;
        fs::rename(&temp, path).map_err(|e| e.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

/// Refuses a file another user could read or change: its token would not be secret.
pub fn check_private(path: &Path) -> Result<(), String> {
    let meta = fs::symlink_metadata(path).map_err(|e| format!("{}: {e}", path.display()))?;
    if !meta.is_file() {
        return Err(format!("{} is not a regular file", path.display()));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        // SAFETY: geteuid has no preconditions and cannot fail.
        let uid = unsafe { libc::geteuid() };
        if meta.uid() != uid {
            return Err(format!("{} belongs to another user", path.display()));
        }
        if meta.mode() & 0o077 != 0 {
            return Err(format!(
                "{} can be read by other users; remove it and let Loci create a new one",
                path.display()
            ));
        }
    }
    Ok(())
}

pub fn new_token() -> String {
    format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    )
}

fn valid_token(token: &str) -> bool {
    token.len() == 64 && token.chars().all(|c| c.is_ascii_hexdigit())
}

/// The token in the file, when it is private and well formed.
pub fn read_token(dir: &Path) -> Result<String, String> {
    let path = dir.join(TOKEN_FILE);
    check_private(&path)?;
    let token = fs::read_to_string(&path)
        .map_err(|e| e.to_string())?
        .trim()
        .to_string();
    if !valid_token(&token) {
        return Err(format!("{} is not a Loci token", path.display()));
    }
    Ok(token)
}

/// The token to accept: the one on disk when it is still good, a new one otherwise.
pub fn ensure_token(dir: &Path) -> Result<String, String> {
    if let Ok(token) = read_token(dir) {
        return Ok(token);
    }
    rotate_token(dir)
}

pub fn rotate_token(dir: &Path) -> Result<String, String> {
    let token = new_token();
    write_private(&dir.join(TOKEN_FILE), &format!("{token}\n"))?;
    Ok(token)
}

pub fn remove_token(dir: &Path) {
    let _ = fs::remove_file(dir.join(TOKEN_FILE));
}

/// Command-line access is on unless the user turned it off.
pub fn access_enabled(dir: &Path) -> bool {
    fs::read_to_string(dir.join(SETTINGS_FILE))
        .ok()
        .and_then(|raw| serde_json::from_str::<Settings>(&raw).ok())
        .is_none_or(|settings| settings.enabled)
}

pub fn set_access_enabled(dir: &Path, enabled: bool) -> Result<(), String> {
    let raw = serde_json::to_string(&Settings { enabled }).map_err(|e| e.to_string())?;
    write_private(&dir.join(SETTINGS_FILE), &format!("{raw}\n"))
}

pub fn write_endpoint(dir: &Path, endpoint: &Endpoint) -> Result<(), String> {
    let raw = serde_json::to_string(endpoint).map_err(|e| e.to_string())?;
    write_private(&dir.join(ENDPOINT_FILE), &format!("{raw}\n"))
}

pub fn read_endpoint(dir: &Path) -> Result<Endpoint, String> {
    let path = dir.join(ENDPOINT_FILE);
    check_private(&path)?;
    let raw = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    serde_json::from_str(&raw).map_err(|_| format!("{} is damaged", path.display()))
}

/// Removes the endpoint on exit, unless another copy of this build has written its own since.
pub fn remove_endpoint(dir: &Path, pid: u32) {
    if read_endpoint(dir).is_ok_and(|endpoint| endpoint.pid == pid) {
        let _ = fs::remove_file(dir.join(ENDPOINT_FILE));
    }
}

/// Compares secrets in time that does not depend on where they differ.
pub fn same_secret(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("loci-cli-access-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn identifiers_must_belong_to_loci() {
        assert!(valid_identifier("com.loci.desktop"));
        assert!(valid_identifier("com.loci.desktop.qa-1"));
        assert!(!valid_identifier("com.other.app"));
        assert!(!valid_identifier("com.loci.desktop/../x"));
        assert!(!valid_identifier("com.loci..x"));
        assert!(app_data_dir("../etc").is_err());
        let dir = app_data_dir("com.loci.desktop.qa").unwrap();
        assert!(dir.ends_with("com.loci.desktop.qa"));
        assert_eq!(dir.parent(), dirs::data_dir().as_deref());
    }

    #[test]
    fn tokens_are_created_kept_rotated_and_removed() {
        let dir = control_dir(&temp_dir());
        assert!(read_token(&dir).is_err());
        let first = ensure_token(&dir).unwrap();
        assert_eq!(first.len(), 64);
        assert_eq!(ensure_token(&dir).unwrap(), first);
        assert_eq!(read_token(&dir).unwrap(), first);
        let second = rotate_token(&dir).unwrap();
        assert_ne!(first, second);
        assert_eq!(read_token(&dir).unwrap(), second);
        remove_token(&dir);
        assert!(read_token(&dir).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn files_are_private_and_shared_ones_are_refused() {
        use std::os::unix::fs::PermissionsExt;
        let dir = control_dir(&temp_dir());
        ensure_token(&dir).unwrap();
        let path = dir.join(TOKEN_FILE);
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            fs::metadata(&dir).unwrap().permissions().mode() & 0o777,
            0o700
        );
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(read_token(&dir).unwrap_err().contains("other users"));
        // A shared token is never reused: a fresh one replaces it.
        let fresh = ensure_token(&dir).unwrap();
        assert_eq!(read_token(&dir).unwrap(), fresh);
    }

    #[test]
    fn access_is_on_until_turned_off() {
        let dir = control_dir(&temp_dir());
        assert!(access_enabled(&dir));
        set_access_enabled(&dir, false).unwrap();
        assert!(!access_enabled(&dir));
        set_access_enabled(&dir, true).unwrap();
        assert!(access_enabled(&dir));
    }

    #[test]
    fn the_endpoint_is_removed_only_by_its_own_process() {
        let dir = control_dir(&temp_dir());
        let endpoint = Endpoint {
            endpoint: "127.0.0.1:4000".into(),
            pid: 7,
            version: "0.3.0".into(),
            identifier: "com.loci.desktop.qa".into(),
        };
        write_endpoint(&dir, &endpoint).unwrap();
        assert_eq!(read_endpoint(&dir).unwrap(), endpoint);
        remove_endpoint(&dir, 8);
        assert!(read_endpoint(&dir).is_ok());
        remove_endpoint(&dir, 7);
        assert!(read_endpoint(&dir).is_err());
    }

    #[test]
    fn secrets_compare_whole() {
        assert!(same_secret("abc", "abc"));
        assert!(!same_secret("abc", "abd"));
        assert!(!same_secret("abc", "abcd"));
    }
}
