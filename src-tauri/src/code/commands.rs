//! Tauri commands for code lessons and the code reader.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::git;
use super::lang::{self, Lang, Symbol};

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|e| e.to_string())?
}

fn absolute(file: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(file);
    if !path.is_absolute() {
        return Err("The file must be an absolute path".into());
    }
    Ok(path)
}

/// Where a file is in its repository.
#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RepoPlace {
    pub repo_root: String,
    pub path_in_repo: String,
}

fn place_of(file: &Path) -> Option<(PathBuf, String)> {
    let root = git::repo_root(file)?;
    let inner = git::path_in_repo(&root, file)?;
    Some((root, inner))
}

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CodeText {
    pub text: String,
    /// The full commit it was read at; none for the working tree.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub head: Option<String>,
    #[serde(flatten, skip_serializing_if = "Option::is_none")]
    pub place: Option<RepoPlace>,
}

/// A file's text: at `commit` when one is named, else as it is on disk.
pub fn read(file: &str, commit: Option<&str>) -> Result<CodeText, String> {
    let path = absolute(file)?;
    let located = place_of(&path);
    let place = located.as_ref().map(|(root, inner)| RepoPlace {
        repo_root: root.to_string_lossy().into_owned(),
        path_in_repo: inner.clone(),
    });
    let head = match &located {
        Some((root, _)) => git::head(root).ok().flatten(),
        None => None,
    };
    let Some(commit) = commit else {
        let text = crate::fs::read_text_file_sync(file)?;
        return Ok(CodeText {
            text,
            commit: None,
            head,
            place,
        });
    };
    let Some((root, inner)) = &located else {
        return Err("This file is not in a git repository, so it has no commits".into());
    };
    let full = git::resolve(root, commit)?
        .ok_or_else(|| format!("Commit {commit} is not in this clone"))?;
    let text = git::show(root, &full, inner)?
        .ok_or_else(|| format!("{inner} is not in commit {}", &full[..12]))?;
    Ok(CodeText {
        text,
        commit: Some(full),
        head,
        place,
    })
}

#[tauri::command]
pub async fn code_read(file: String, commit: Option<String>) -> Result<CodeText, String> {
    blocking(move || read(&file, commit.as_deref())).await
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PinQuery {
    pub file: String,
    pub commit: String,
    #[serde(default)]
    pub lines: Option<[u32; 2]>,
}

/// How a pinned file stands against the working tree.
#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PinStatus {
    /// `current` (HEAD is the pin and the file is as it was), `moved` (HEAD
    /// moved, this file did not change), `changed`, `missing-commit`,
    /// `missing-file` (not in that commit) or `no-repo`.
    pub state: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub head: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ahead: Option<u32>,
    /// For `changed` with lines: where they are in the working tree.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_lines: Option<[u32; 2]>,
    /// Whether `current_lines` are the same lines, untouched.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exact: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl PinStatus {
    fn bare(state: &'static str) -> Self {
        PinStatus {
            state,
            commit: None,
            head: None,
            ahead: None,
            current_lines: None,
            exact: None,
            error: None,
        }
    }
}

pub fn pin_status(query: &PinQuery) -> Result<PinStatus, String> {
    let path = absolute(&query.file)?;
    let Some((root, inner)) = place_of(&path) else {
        return Ok(PinStatus::bare("no-repo"));
    };
    let head = git::head(&root)?;
    let Some(commit) = git::resolve(&root, &query.commit)? else {
        return Ok(PinStatus {
            head,
            ..PinStatus::bare("missing-commit")
        });
    };
    let mut status = PinStatus {
        commit: Some(commit.clone()),
        head: head.clone(),
        ahead: if head.as_deref() == Some(commit.as_str()) {
            Some(0)
        } else {
            git::commits_ahead(&root, &commit)?
        },
        ..PinStatus::bare("current")
    };
    let spec = format!("{commit}:{inner}");
    if !git::run(&root, &["cat-file", "-e", &spec])?.ok {
        status.state = "missing-file";
        return Ok(status);
    }
    if git::changed_since(&root, &commit, &inner)? {
        status.state = "changed";
        if let Some(lines) = query.lines {
            if path.exists() {
                let (mapped, exact) = git::map_lines(&root, &commit, &inner, lines)?;
                status.current_lines = Some(mapped);
                status.exact = Some(exact);
            }
        }
    } else if head.as_deref() != Some(commit.as_str()) {
        status.state = "moved";
    }
    Ok(status)
}

#[tauri::command]
pub async fn code_pin_status(query: PinQuery) -> Result<PinStatus, String> {
    blocking(move || pin_status(&query)).await
}

#[derive(Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Resolved {
    pub commit: String,
    #[serde(flatten)]
    pub place: RepoPlace,
}

/// The repository of `file` and `rev` (HEAD when left out) as a full commit.
pub fn resolve(file: &str, rev: Option<&str>) -> Result<Resolved, String> {
    let path = absolute(file)?;
    let (root, inner) =
        place_of(&path).ok_or("This file is not in a git repository, so it cannot be pinned")?;
    let rev = rev.unwrap_or("HEAD");
    let commit = git::resolve(&root, rev)?.ok_or_else(|| {
        format!("{rev} is not a commit in this clone (fetch it first: git fetch --depth=1 origin {rev})")
    })?;
    Ok(Resolved {
        commit,
        place: RepoPlace {
            repo_root: root.to_string_lossy().into_owned(),
            path_in_repo: inner,
        },
    })
}

#[tauri::command]
pub async fn code_resolve(file: String, rev: Option<String>) -> Result<Resolved, String> {
    blocking(move || resolve(&file, rev.as_deref())).await
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Symbols {
    /// The language it was read as; none when Loci cannot read its symbols.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<&'static str>,
    pub symbols: Vec<Symbol>,
}

/// The outline of a file, at `commit` or as it is on disk.
pub fn symbols(file: &str, commit: Option<&str>) -> Result<Symbols, String> {
    let Some(language) = Lang::of(file) else {
        return Ok(Symbols {
            language: None,
            symbols: Vec::new(),
        });
    };
    let text = read(file, commit)?.text;
    Ok(Symbols {
        language: Some(language.id()),
        symbols: lang::symbols(language, &text),
    })
}

#[tauri::command]
pub async fn code_symbols(file: String, commit: Option<String>) -> Result<Symbols, String> {
    blocking(move || symbols(&file, commit.as_deref())).await
}

#[cfg(test)]
mod tests {
    use super::super::git::testing::*;
    use super::*;

    #[test]
    fn a_pin_is_current_then_moved_then_changed() {
        let dir = repo("pin");
        let pin = commit(&dir, &[("a.go", "1\n2\n3\n"), ("b.go", "x\n")]);
        let file = dir.join("a.go").to_string_lossy().into_owned();
        let query = |lines| PinQuery {
            file: file.clone(),
            commit: pin[..7].to_string(),
            lines,
        };
        let status = pin_status(&query(None)).unwrap();
        assert_eq!((status.state, status.ahead), ("current", Some(0)));
        assert_eq!(status.commit.as_deref(), Some(pin.as_str()));

        commit(&dir, &[("b.go", "y\n")]);
        let status = pin_status(&query(None)).unwrap();
        assert_eq!((status.state, status.ahead), ("moved", Some(1)));

        commit(&dir, &[("a.go", "0\n1\n2\n3\n")]);
        let status = pin_status(&query(Some([2, 3]))).unwrap();
        assert_eq!(status.state, "changed");
        assert_eq!(status.current_lines, Some([3, 4]));
        assert_eq!(status.exact, Some(true));

        let read_back = read(&file, Some(&pin[..7])).unwrap();
        assert_eq!(read_back.text, "1\n2\n3\n");
        assert_eq!(read_back.commit.as_deref(), Some(pin.as_str()));
        assert_eq!(read_back.place.unwrap().path_in_repo, "a.go");
        assert_eq!(read(&file, None).unwrap().text, "0\n1\n2\n3\n");

        let missing = PinQuery {
            commit: "abcdef0".into(),
            ..query(None)
        };
        assert_eq!(pin_status(&missing).unwrap().state, "missing-commit");
        let elsewhere =
            std::env::temp_dir().join(format!("loci-norepo-{}.go", uuid::Uuid::new_v4()));
        std::fs::write(&elsewhere, "x").unwrap();
        let loose = PinQuery {
            file: elsewhere.to_string_lossy().into_owned(),
            ..query(None)
        };
        assert_eq!(pin_status(&loose).unwrap().state, "no-repo");
        assert!(read(&loose.file, Some("abcdef0")).is_err());
        std::fs::remove_file(elsewhere).ok();

        let resolved = resolve(&file, None).unwrap();
        assert_eq!(resolved.commit, git::head(&dir).unwrap().unwrap());
        assert!(resolve(&file, Some("nope")).unwrap_err().contains("fetch"));
        std::fs::remove_dir_all(dir).ok();
    }
}
