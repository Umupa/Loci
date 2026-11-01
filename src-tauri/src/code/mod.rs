//! Code reading: files at a pinned commit, and (later) symbols, definitions
//! and references. Read-only, local and lightweight: git and tree-sitter.

pub mod commands;
pub mod git;
pub mod lang;
pub mod nav;

use serde_json::Value;

/// Pinned lessons name full commit ids: a short one is expanded in the
/// lesson's repository, and one the clone does not have is refused. Without
/// git, pins are kept as written.
pub fn expand_pins(data_json: &str) -> Result<String, String> {
    let mut data: Value =
        serde_json::from_str(data_json).map_err(|e| format!("Invalid course JSON: {e}"))?;
    let lessons = data
        .get_mut("chapters")
        .and_then(Value::as_array_mut)
        .into_iter()
        .flatten()
        .filter_map(|chapter| chapter.get_mut("lessons").and_then(Value::as_array_mut))
        .flatten();
    for lesson in lessons {
        let (Some(file), Some(commit)) = (
            lesson
                .get("file")
                .and_then(Value::as_str)
                .map(str::to_string),
            lesson
                .get("commit")
                .and_then(Value::as_str)
                .map(str::to_string),
        ) else {
            continue;
        };
        let id = lesson
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or("?")
            .to_string();
        let Some(root) = git::repo_root(std::path::Path::new(&file)) else {
            return Err(format!(
                "Lesson {id}: {file} is not in a git repository, so it cannot be pinned"
            ));
        };
        match git::resolve(&root, &commit) {
            Ok(Some(full)) => lesson["commit"] = Value::String(full),
            Ok(None) => {
                return Err(format!(
                    "Lesson {id}: commit {commit} is not in {} (fetch it first: git -C {} fetch --depth=1 origin {commit})",
                    root.display(),
                    root.display()
                ))
            }
            Err(error) if error.contains("not installed") => {}
            Err(error) => return Err(format!("Lesson {id}: {error}")),
        }
    }
    serde_json::to_string(&data).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::git::testing::*;

    #[test]
    fn short_pins_expand_and_unknown_ones_are_refused() {
        let dir = repo("expand");
        let sha = commit(&dir, &[("a.go", "package a\n")]);
        let file = dir.join("a.go").to_string_lossy().into_owned();
        let course = |commit: &str| {
            serde_json::json!({"chapters": [{"title": "C", "lessons": [
                {"id": "a", "title": "A", "file": file, "commit": commit},
                {"id": "b", "title": "B", "document": "d"}
            ]}]})
            .to_string()
        };
        let expanded: serde_json::Value =
            serde_json::from_str(&super::expand_pins(&course(&sha[..7])).unwrap()).unwrap();
        assert_eq!(
            expanded["chapters"][0]["lessons"][0]["commit"],
            sha.as_str()
        );
        assert!(super::expand_pins(&course("abcdef0"))
            .unwrap_err()
            .contains("fetch"));
        std::fs::remove_dir_all(dir).ok();
    }
}
