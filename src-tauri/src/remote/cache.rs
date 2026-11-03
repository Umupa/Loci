//! What a connected window last read from its host, kept on this device so
//! the window can still show it while the host is offline: the replies to
//! `Read` commands (roster, documents, notes, PDF bytes, ...) and the
//! window's mirror of the host's sessions.
//!
//! One folder per host under `<app data>/remote-cache/`, one file per reply,
//! named by a hash of the command and its arguments. Reading a file marks it
//! used; past `HOST_CACHE_LIMIT` the least recently used go first. Removing a
//! device, or leaving the group, deletes what was kept for it.

use std::path::{Path, PathBuf};
use std::time::SystemTime;

use serde_json::Value;
use sha2::{Digest, Sha256};

use super::gateway::Reply;

/// The most kept for one host.
pub const HOST_CACHE_LIMIT: u64 = 256 * 1024 * 1024;
/// A reply larger than this is not kept: one PDF must not push out everything else.
pub const ENTRY_LIMIT: usize = 32 * 1024 * 1024;

const JSON: u8 = b'J';
const BYTES: u8 = b'B';

/// The folder every host's cache lives in.
pub fn root(app_data: &Path) -> PathBuf {
    app_data.join("remote-cache")
}

/// A host's name on disk: its device id, or `loopback`; anything else is hashed.
fn host_dir(root: &Path, host: &str) -> PathBuf {
    let safe = !host.is_empty()
        && host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    root.join(if safe {
        host.to_owned()
    } else {
        hex(&Sha256::digest(host.as_bytes()))
    })
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// The key a command's reply is kept under.
pub fn key(cmd: &str, args: &Value) -> String {
    format!("{cmd}\0{args}")
}

pub struct HostCache {
    dir: PathBuf,
    limit: u64,
}

impl HostCache {
    pub fn new(root: &Path, host: &str, limit: u64) -> Self {
        Self {
            dir: host_dir(root, host),
            limit,
        }
    }

    fn path(&self, key: &str) -> PathBuf {
        self.dir.join(hex(&Sha256::digest(key.as_bytes())))
    }

    /// Keeps a reply, then makes room. Failing to keep one is not an error:
    /// the window still has the reply it asked for.
    pub fn put(&self, key: &str, reply: &Reply) {
        let mut file = Vec::new();
        match reply {
            Reply::Json(value) => {
                file.push(JSON);
                file.extend_from_slice(value.to_string().as_bytes());
            }
            Reply::Bytes(bytes) => {
                file.push(BYTES);
                file.extend_from_slice(bytes);
            }
        }
        if file.len() > ENTRY_LIMIT + 1 || std::fs::create_dir_all(&self.dir).is_err() {
            return;
        }
        if std::fs::write(self.path(key), &file).is_ok() {
            self.evict();
        }
    }

    /// The reply kept under `key`, marking it used.
    pub fn get(&self, key: &str) -> Option<Reply> {
        let path = self.path(key);
        let file = std::fs::read(&path).ok()?;
        let _ = std::fs::File::options()
            .write(true)
            .open(&path)
            .and_then(|handle| handle.set_modified(SystemTime::now()));
        match file.split_first()? {
            (&JSON, json) => serde_json::from_slice(json).ok().map(Reply::Json),
            (&BYTES, bytes) => Some(Reply::Bytes(bytes.to_vec())),
            _ => None,
        }
    }

    /// Deletes the least recently used replies until the host fits its limit.
    fn evict(&self) {
        let Ok(entries) = std::fs::read_dir(&self.dir) else {
            return;
        };
        let mut files: Vec<(SystemTime, u64, PathBuf)> = entries
            .flatten()
            .filter_map(|entry| {
                let meta = entry.metadata().ok()?;
                Some((meta.modified().ok()?, meta.len(), entry.path()))
            })
            .collect();
        let mut total: u64 = files.iter().map(|(_, size, _)| size).sum();
        files.sort_by_key(|(used, _, _)| *used);
        for (_, size, path) in files {
            if total <= self.limit {
                break;
            }
            if std::fs::remove_file(path).is_ok() {
                total -= size;
            }
        }
    }
}

/// Deletes what was kept for one host, or for every host.
pub fn clear(root: &Path, host: Option<&str>) {
    let _ = std::fs::remove_dir_all(match host {
        Some(host) => host_dir(root, host),
        None => root.to_path_buf(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn temp_root(name: &str) -> PathBuf {
        let root =
            std::env::temp_dir().join(format!("loci-cache-test-{name}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    fn json_of(reply: Option<Reply>) -> Option<Value> {
        match reply? {
            Reply::Json(value) => Some(value),
            Reply::Bytes(_) => None,
        }
    }

    #[test]
    fn keeps_json_and_bytes_per_host() {
        let root = temp_root("keeps");
        let laptop = HostCache::new(&root, "laptop-id", HOST_CACHE_LIMIT);
        let other = HostCache::new(&root, "other-id", HOST_CACHE_LIMIT);
        let notes = key("notes_list", &json!({}));
        laptop.put(&notes, &Reply::Json(json!([{"id": "n1"}])));
        laptop.put("pdf", &Reply::Bytes(vec![1, 2, 3]));
        assert_eq!(json_of(laptop.get(&notes)), Some(json!([{"id": "n1"}])));
        assert!(matches!(laptop.get("pdf"), Some(Reply::Bytes(bytes)) if bytes == vec![1, 2, 3]));
        assert!(other.get(&notes).is_none());
        assert_ne!(
            key("notes_get", &json!({"id": "a"})),
            key("notes_get", &json!({"id": "b"}))
        );
        clear(&root, None);
    }

    #[test]
    fn lets_the_least_recently_used_go_first() {
        let root = temp_root("evicts");
        let cache = HostCache::new(&root, "host", 25);
        cache.put("old", &Reply::Bytes(vec![0; 10]));
        std::thread::sleep(std::time::Duration::from_millis(20));
        cache.put("read-again", &Reply::Bytes(vec![0; 10]));
        std::thread::sleep(std::time::Duration::from_millis(20));
        // Reading "old" makes it the most recently used.
        assert!(cache.get("old").is_some());
        std::thread::sleep(std::time::Duration::from_millis(20));
        cache.put("new", &Reply::Bytes(vec![0; 10]));
        assert!(cache.get("old").is_some());
        assert!(cache.get("new").is_some());
        assert!(cache.get("read-again").is_none());
        clear(&root, None);
    }

    #[test]
    fn does_not_keep_a_reply_larger_than_an_entry_may_be() {
        let root = temp_root("large");
        let cache = HostCache::new(&root, "host", HOST_CACHE_LIMIT);
        cache.put("huge", &Reply::Bytes(vec![0; ENTRY_LIMIT + 1]));
        assert!(cache.get("huge").is_none());
        clear(&root, None);
    }

    #[test]
    fn forgets_one_host_or_all_of_them() {
        let root = temp_root("clears");
        let (a, b) = (
            HostCache::new(&root, "a", HOST_CACHE_LIMIT),
            HostCache::new(&root, "b", HOST_CACHE_LIMIT),
        );
        a.put("k", &Reply::Json(json!(1)));
        b.put("k", &Reply::Json(json!(2)));
        clear(&root, Some("a"));
        assert!(a.get("k").is_none());
        assert_eq!(json_of(b.get("k")), Some(json!(2)));
        clear(&root, None);
        assert!(b.get("k").is_none());
        // A host id that is not a plain name still gets a folder of its own, inside the root.
        let odd = HostCache::new(&root, "../escape", HOST_CACHE_LIMIT);
        assert!(odd.dir.starts_with(&root));
    }
}
