//! Jump to definition and find references, by name, across a repository:
//! `git grep -w` narrows the files (at a commit or in the working tree),
//! tree-sitter reads the definitions or identifiers in each. Nothing is
//! indexed ahead of time, so a pinned commit costs the same as HEAD.

use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Serialize;

use super::git;
use super::lang::{self, Lang};

/// Files git grep may hand back for one name.
const CANDIDATES_MAX: usize = 3000;
/// Files larger than this are skipped: generated code, bundles.
const FILE_MAX: usize = 1024 * 1024;
pub const DEFINITIONS_MAX: usize = 50;
pub const REFERENCES_MAX: usize = 500;

/// Every glob the code reader knows, for a search with no language.
fn all_globs() -> Vec<&'static str> {
    let mut globs: Vec<&str> = lang::ALL
        .iter()
        .flat_map(|lang| lang.family_globs().iter().copied())
        .collect();
    globs.sort_unstable();
    globs.dedup();
    globs
}

/// Paths (in the repository) of files where `name` occurs as a word.
pub fn candidates(
    root: &Path,
    commit: Option<&str>,
    name: &str,
    globs: &[&str],
) -> Result<Vec<String>, String> {
    let mut args = vec!["grep", "-l", "-w", "-I", "-F", "-e", name];
    match commit {
        Some(commit) => args.push(commit),
        None => args.push("--untracked"),
    }
    args.push("--");
    args.extend(globs);
    let out = git::run(root, &args)?;
    if !out.ok && out.code != Some(1) {
        return Err("git grep failed".into());
    }
    let prefix = commit.map(|c| format!("{c}:"));
    Ok(String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|line| {
            prefix
                .as_deref()
                .and_then(|p| line.strip_prefix(p))
                .unwrap_or(line)
                .to_string()
        })
        .filter(|path| !path.is_empty())
        .take(CANDIDATES_MAX)
        .collect())
}

/// The texts of `paths` at `commit` (one `git cat-file --batch`), or on disk.
pub fn texts(root: &Path, commit: Option<&str>, paths: &[String]) -> Vec<(String, String)> {
    let Some(commit) = commit else {
        return paths
            .iter()
            .filter_map(|path| {
                let full = root.join(path);
                let meta = std::fs::metadata(&full).ok()?;
                if meta.len() as usize > FILE_MAX {
                    return None;
                }
                let text = String::from_utf8(std::fs::read(full).ok()?).ok()?;
                Some((path.clone(), text))
            })
            .collect();
    };
    batch(root, commit, paths).unwrap_or_default()
}

fn batch(root: &Path, commit: &str, paths: &[String]) -> Result<Vec<(String, String)>, String> {
    let mut child = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(["--no-optional-locks", "cat-file", "--batch"])
        .env("GIT_TERMINAL_PROMPT", "0")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let mut stdin = child.stdin.take().expect("piped stdin");
    let requests: Vec<String> = paths
        .iter()
        .filter(|path| !path.contains('\n'))
        .map(|path| format!("{commit}:{path}\n"))
        .collect();
    let asked: Vec<String> = paths
        .iter()
        .filter(|p| !p.contains('\n'))
        .cloned()
        .collect();
    // Written from a thread so a full output pipe cannot stall the input.
    let writer = std::thread::spawn(move || {
        for request in requests {
            if stdin.write_all(request.as_bytes()).is_err() {
                break;
            }
        }
    });
    let mut reader = BufReader::new(child.stdout.take().expect("piped stdout"));
    let mut out = Vec::new();
    for path in asked {
        let mut header = String::new();
        if reader.read_line(&mut header).map_err(|e| e.to_string())? == 0 {
            break;
        }
        let parts: Vec<&str> = header.split_whitespace().collect();
        if parts.len() != 3 || parts[1] != "blob" {
            continue; // "<spec> missing", or not a file
        }
        let size: usize = parts[2].parse().map_err(|_| "bad cat-file header")?;
        let mut body = vec![0; size + 1];
        reader.read_exact(&mut body).map_err(|e| e.to_string())?;
        body.pop();
        if size <= FILE_MAX && !body.contains(&0) {
            if let Ok(text) = String::from_utf8(body) {
                out.push((path, text));
            }
        }
    }
    let _ = writer.join();
    let _ = child.kill();
    let _ = child.wait();
    Ok(out)
}

/// Where a search starts: a file (and maybe a place in it) or a repository.
pub struct Origin {
    pub file: PathBuf,
    pub root: Option<PathBuf>,
    /// The file's path in the repository; none for a repository or a loose file.
    pub inner: Option<String>,
    pub commit: Option<String>,
    pub lang: Option<Lang>,
}

impl Origin {
    pub fn new(file: &Path, commit: Option<&str>) -> Result<Origin, String> {
        if !file.is_absolute() {
            return Err("The file must be an absolute path".into());
        }
        let is_dir = file.is_dir();
        let root = if is_dir && file.join(".git").exists() {
            Some(file.to_path_buf())
        } else {
            git::repo_root(file)
        };
        if is_dir && root.is_none() {
            return Err("This folder is not a git repository".into());
        }
        let inner = match (&root, is_dir) {
            (Some(root), false) => git::path_in_repo(root, file),
            _ => None,
        };
        let commit = match (commit, &root) {
            (Some(rev), Some(root)) => Some(
                git::resolve(root, rev)?
                    .ok_or_else(|| format!("Commit {rev} is not in this clone"))?,
            ),
            (Some(_), None) => return Err("This file is not in a git repository".into()),
            (None, _) => None,
        };
        Ok(Origin {
            file: file.to_path_buf(),
            lang: if is_dir {
                None
            } else {
                Lang::of(&file.to_string_lossy())
            },
            root,
            inner,
            commit,
        })
    }

    /// The origin file's own text.
    pub fn text(&self) -> Result<String, String> {
        let file = self.file.to_string_lossy();
        Ok(super::commands::read(&file, self.commit.as_deref())?.text)
    }

    /// The name at a place in the origin file.
    pub fn name_at(&self, line: u32, column: u32) -> Result<String, String> {
        let lang = self
            .lang
            .ok_or("Loci cannot read symbols in this kind of file")?;
        lang::identifier_at(lang, &self.text()?, line, column)
            .ok_or_else(|| format!("No name at line {line}, column {column}"))
    }

    /// The files to look in for `name`: (absolute path, path in repo, text).
    fn files(&self, name: &str) -> Result<Vec<(PathBuf, String, String)>, String> {
        let Some(root) = &self.root else {
            // A file outside any repository is searched alone.
            let name_of = self.file.to_string_lossy().into_owned();
            return Ok(vec![(self.file.clone(), name_of, self.text()?)]);
        };
        let globs = match self.lang {
            Some(lang) => lang.family_globs().to_vec(),
            None => all_globs(),
        };
        let mut paths = candidates(root, self.commit.as_deref(), name, &globs)?;
        // The origin file first: its own definitions rank first.
        if let Some(inner) = &self.inner {
            paths.retain(|path| path != inner);
            paths.insert(0, inner.clone());
        }
        Ok(texts(root, self.commit.as_deref(), &paths)
            .into_iter()
            .map(|(path, text)| (root.join(&path), path, text))
            .collect())
    }
}

/// Runs `work` over the files on every core, keeping their order.
fn per_file<T: Send>(
    files: &[(PathBuf, String, String)],
    work: impl Fn(&PathBuf, &str, &str) -> T + Sync,
) -> Vec<T> {
    let threads = std::thread::available_parallelism()
        .map_or(4, |n| n.get())
        .min(8);
    if files.len() < 16 || threads < 2 {
        return files.iter().map(|(f, p, t)| work(f, p, t)).collect();
    }
    let chunk = files.len().div_ceil(threads);
    std::thread::scope(|scope| {
        let handles: Vec<_> = files
            .chunks(chunk)
            .map(|part| {
                let work = &work;
                scope.spawn(move || {
                    part.iter()
                        .map(|(f, p, t)| work(f, p, t))
                        .collect::<Vec<T>>()
                })
            })
            .collect();
        handles
            .into_iter()
            .flat_map(|handle| handle.join().unwrap_or_default())
            .collect()
    })
}

/// A place in a repository a search found.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Hit {
    pub file: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path_in_repo: Option<String>,
    pub line: u32,
    pub column: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub container: Option<String>,
    pub preview: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Definitions {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    pub definitions: Vec<Hit>,
}

fn vendored(path: &str) -> bool {
    path.split('/').any(|part| {
        matches!(
            part,
            "vendor" | "third_party" | "third-party" | "node_modules" | "external" | "deps"
        )
    })
}

fn parent(path: &str) -> &str {
    path.rsplit_once('/').map_or("", |(dir, _)| dir)
}

/// Definitions of `name`, best first: real definitions before prototypes,
/// the project's own before vendored code, then the same file, the same
/// folder, the same language.
pub fn definitions(origin: &Origin, name: &str) -> Result<Definitions, String> {
    let here = origin.inner.clone().unwrap_or_default();
    type Rank = (bool, bool, bool, bool, bool, String, u32);
    let files = origin.files(name)?;
    let mut found: Vec<(Rank, Hit)> = per_file(&files, |full, path, text| {
        let Some(lang) = Lang::of(path) else {
            return Vec::new();
        };
        lang::symbols(lang, text)
            .into_iter()
            .filter(|symbol| symbol.name == name && symbol.kind != "impl")
            .map(|symbol| {
                let rank = (
                    vendored(path) && !vendored(&here),
                    symbol.kind == "prototype",
                    path != here,
                    parent(path) != parent(&here),
                    Some(lang) != origin.lang,
                    path.to_string(),
                    symbol.line,
                );
                let hit = Hit {
                    file: full.to_string_lossy().into_owned(),
                    path_in_repo: origin.root.as_ref().map(|_| path.to_string()),
                    line: symbol.line,
                    column: symbol.column,
                    kind: Some(symbol.kind),
                    container: symbol.container,
                    preview: lang::preview(text, symbol.line),
                };
                (rank, hit)
            })
            .collect::<Vec<_>>()
    })
    .into_iter()
    .flatten()
    .collect();
    found.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(Definitions {
        name: name.to_string(),
        commit: origin.commit.clone(),
        definitions: found
            .into_iter()
            .take(DEFINITIONS_MAX)
            .map(|(_, hit)| hit)
            .collect(),
    })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct References {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    /// Always `name`: matched by name, not resolved like a compiler would.
    #[serde(rename = "match")]
    pub matched: &'static str,
    pub total: usize,
    pub truncated: bool,
    pub references: Vec<Hit>,
}

/// Every place `name` is used as an identifier, the origin file first.
pub fn references(origin: &Origin, name: &str, limit: usize) -> Result<References, String> {
    let limit = limit.clamp(1, REFERENCES_MAX);
    let files = origin.files(name)?;
    let all = per_file(&files, |full, path, text| {
        let Some(lang) = Lang::of(path) else {
            return Vec::new();
        };
        lang::occurrences(lang, text, name)
            .into_iter()
            .map(|found| Hit {
                file: full.to_string_lossy().into_owned(),
                path_in_repo: origin.root.as_ref().map(|_| path.to_string()),
                line: found.line,
                column: found.column,
                kind: None,
                container: None,
                preview: found.preview,
            })
            .collect::<Vec<_>>()
    });
    let total = all.iter().map(Vec::len).sum();
    let items: Vec<Hit> = all.into_iter().flatten().take(limit).collect();
    Ok(References {
        name: name.to_string(),
        commit: origin.commit.clone(),
        matched: "name",
        total,
        truncated: total > items.len(),
        references: items,
    })
}

#[cfg(test)]
mod tests {
    use super::super::git::testing::*;
    use super::*;

    fn fixture() -> (PathBuf, String) {
        let dir = repo("nav");
        let first = commit(
            &dir,
            &[
                ("vm/vm.go", "package vm\n\ntype VM struct{}\n\nfunc Start(v *VM) error { return nil }\n"),
                ("cmd/main.go", "package main\n\nimport \"x/vm\"\n\nfunc main() {\n\tvm.Start(nil)\n\tvm.Start(nil)\n}\n"),
                ("vendor/lib/lib.go", "package lib\n\nfunc Start() {}\n"),
                ("src/run.c", "int start(void);\nint start(void) { return 0; }\n"),
                ("README.md", "Start here\n"),
            ],
        );
        (dir, first)
    }

    #[test]
    fn definitions_rank_the_project_before_vendored_code() {
        let (dir, first) = fixture();
        let origin = Origin::new(&dir.join("cmd/main.go"), None).unwrap();
        assert_eq!(origin.name_at(6, 5).unwrap(), "Start");
        let found = definitions(&origin, "Start").unwrap();
        let places: Vec<_> = found
            .definitions
            .iter()
            .map(|hit| (hit.path_in_repo.clone().unwrap(), hit.line))
            .collect();
        assert_eq!(
            places,
            vec![("vm/vm.go".into(), 5), ("vendor/lib/lib.go".into(), 3)]
        );
        assert_eq!(
            found.definitions[0].preview,
            "func Start(v *VM) error { return nil }"
        );

        // C: the definition comes before the prototype.
        let c = Origin::new(&dir.join("src/run.c"), None).unwrap();
        let found = definitions(&c, "start").unwrap();
        assert_eq!(found.definitions[0].kind.as_deref(), Some("function"));
        assert_eq!(found.definitions[1].kind.as_deref(), Some("prototype"));

        // At a commit, the file as it was then.
        commit(
            &dir,
            &[(
                "vm/vm.go",
                "package vm\n\n\n\ntype VM struct{}\n\nfunc Start(v *VM) error { return nil }\n",
            )],
        );
        let then = Origin::new(&dir.join("cmd/main.go"), Some(&first[..8])).unwrap();
        assert_eq!(then.commit.as_deref(), Some(first.as_str()));
        assert_eq!(definitions(&then, "Start").unwrap().definitions[0].line, 5);
        let now = Origin::new(&dir.join("cmd/main.go"), None).unwrap();
        assert_eq!(definitions(&now, "Start").unwrap().definitions[0].line, 7);
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn references_by_name_with_a_limit() {
        let (dir, first) = fixture();
        let origin = Origin::new(&dir.join("vm/vm.go"), None).unwrap();
        let found = references(&origin, "Start", 500).unwrap();
        assert_eq!(found.matched, "name");
        let places: Vec<_> = found
            .references
            .iter()
            .map(|hit| (hit.path_in_repo.clone().unwrap(), hit.line))
            .collect();
        assert_eq!(places[0], ("vm/vm.go".into(), 5));
        assert!(places.contains(&("cmd/main.go".into(), 6)));
        assert!(places.contains(&("cmd/main.go".into(), 7)));
        // Words in Markdown and C files are not Go references.
        assert_eq!(found.total, 4);
        let few = references(&origin, "Start", 2).unwrap();
        assert_eq!(
            (few.total, few.truncated, few.references.len()),
            (4, true, 2)
        );

        // A repository with no language searches every language.
        let repo_origin = Origin::new(&dir, Some(&first)).unwrap();
        assert_eq!(references(&repo_origin, "start", 500).unwrap().total, 2);
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    #[ignore = "reads the acceptance repositories in ~/Loci/repos; run by hand for timings"]
    fn timings_on_the_acceptance_repositories() {
        let home = dirs::home_dir().unwrap().join("Loci/repos");
        for (file, name) in [
            ("TencentCloud/CubeSandbox", "Start"),
            ("e2b-dev/runtime", "Close"),
            ("perplexityai/SPACE", "run"),
        ] {
            let root = home.join(file);
            if !root.exists() {
                continue;
            }
            let started = std::time::Instant::now();
            let origin = Origin::new(&root, None).unwrap();
            let defs = definitions(&origin, name).unwrap();
            let after_defs = started.elapsed();
            let refs = references(&origin, name, 500).unwrap();
            eprintln!(
                "{file} {name}: {} definitions in {:?}; {} references in {:?}",
                defs.definitions.len(),
                after_defs,
                refs.total,
                started.elapsed() - after_defs
            );
        }
    }
}
