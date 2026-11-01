//! Read-only git for code lessons: where a file's repository is, what a
//! file was at a commit, and whether it changed since. Never touches the
//! network, never takes locks, never writes.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// Text read at a commit is capped like a file read from disk.
pub const SHOW_MAX: usize = 4 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(10);

/// What a git run gave: its exit status and its standard output.
pub struct Output {
    pub ok: bool,
    pub code: Option<i32>,
    pub stdout: Vec<u8>,
}

/// Runs git in `repo`, with no prompt, no optional locks and a time limit.
pub fn run(repo: &Path, args: &[&str]) -> Result<Output, String> {
    let mut child = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("--no-optional-locks")
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_OPTIONAL_LOCKS", "0")
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                "git is not installed".to_string()
            } else {
                format!("Could not run git: {e}")
            }
        })?;
    let mut stdout = child.stdout.take().expect("piped stdout");
    let reader = std::thread::spawn(move || {
        let mut out = Vec::new();
        let _ = (&mut stdout)
            .take(SHOW_MAX as u64 * 4)
            .read_to_end(&mut out);
        out
    });
    let started = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            break status;
        }
        if started.elapsed() > TIMEOUT {
            let _ = child.kill();
            let _ = child.wait();
            return Err("git took too long".into());
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let stdout = reader.join().unwrap_or_default();
    Ok(Output {
        ok: status.success(),
        code: status.code(),
        stdout,
    })
}

fn text(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

/// The work tree holding `file`: the nearest folder above it with `.git`.
pub fn repo_root(file: &Path) -> Option<PathBuf> {
    file.ancestors()
        .skip(1)
        .find(|dir| dir.join(".git").exists())
        .map(Path::to_path_buf)
}

/// `file`'s path inside its repository, with forward slashes.
pub fn path_in_repo(root: &Path, file: &Path) -> Option<String> {
    let relative = file.strip_prefix(root).ok()?;
    let parts: Vec<&str> = relative
        .components()
        .map(|part| part.as_os_str().to_str())
        .collect::<Option<_>>()?;
    (!parts.is_empty()).then(|| parts.join("/"))
}

/// A revision as a full commit id, if the repository has it.
pub fn resolve(repo: &Path, rev: &str) -> Result<Option<String>, String> {
    if rev.starts_with('-') {
        return Ok(None);
    }
    let spec = format!("{rev}^{{commit}}");
    let out = run(repo, &["rev-parse", "--verify", "--quiet", &spec])?;
    Ok(out.ok.then(|| text(&out)).filter(|sha| sha.len() == 40))
}

pub fn head(repo: &Path) -> Result<Option<String>, String> {
    resolve(repo, "HEAD")
}

/// The file's text at `commit`. `Ok(None)` when the commit has no such file.
pub fn show(repo: &Path, commit: &str, path: &str) -> Result<Option<String>, String> {
    let spec = format!("{commit}:{path}");
    let out = run(repo, &["show", "--no-textconv", &spec])?;
    if !out.ok {
        return Ok(None);
    }
    if out.stdout.len() > SHOW_MAX {
        return Err(format!(
            "File is too large to read (maximum {} MB).",
            SHOW_MAX / 1024 / 1024
        ));
    }
    if out.stdout.contains(&0) {
        return Err("Binary files cannot be read as text.".into());
    }
    String::from_utf8(out.stdout)
        .map(Some)
        .map_err(|_| "File is not valid UTF-8.".into())
}

/// Whether the file in the working tree differs from the file at `commit`.
pub fn changed_since(repo: &Path, commit: &str, path: &str) -> Result<bool, String> {
    let out = run(
        repo,
        &["diff", "--quiet", "--no-ext-diff", commit, "--", path],
    )?;
    match out.code {
        Some(0) => Ok(false),
        Some(1) => Ok(true),
        _ => Err("git could not compare the file".into()),
    }
}

/// How many commits HEAD is ahead of `commit` (None when unrelated).
pub fn commits_ahead(repo: &Path, commit: &str) -> Result<Option<u32>, String> {
    let range = format!("{commit}..HEAD");
    let out = run(repo, &["rev-list", "--count", &range])?;
    Ok(out.ok.then(|| text(&out).parse().ok()).flatten())
}

/// Where lines `[first, last]` of the file at `commit` are in the working
/// tree, and whether they are exactly those lines (no hunk touched them).
pub fn map_lines(
    repo: &Path,
    commit: &str,
    path: &str,
    lines: [u32; 2],
) -> Result<([u32; 2], bool), String> {
    let out = run(
        repo,
        &[
            "diff",
            "-U0",
            "--no-ext-diff",
            "--no-color",
            commit,
            "--",
            path,
        ],
    )?;
    let hunks = parse_hunks(&String::from_utf8_lossy(&out.stdout));
    Ok(map_range(&hunks, lines))
}

/// One `@@ -a,b +c,d @@` header.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Hunk {
    old_start: u32,
    old_count: u32,
    new_start: u32,
    new_count: u32,
}

pub fn parse_hunks(diff: &str) -> Vec<Hunk> {
    fn side(text: &str) -> Option<(u32, u32)> {
        let (start, count) = text.split_once(',').unwrap_or((text, "1"));
        Some((start.parse().ok()?, count.parse().ok()?))
    }
    diff.lines()
        .filter_map(|line| {
            let rest = line.strip_prefix("@@ -")?;
            let (old, rest) = rest.split_once(" +")?;
            let (new, _) = rest.split_once(" @@")?;
            let (old_start, old_count) = side(old)?;
            let (new_start, new_count) = side(new)?;
            Some(Hunk {
                old_start,
                old_count,
                new_start,
                new_count,
            })
        })
        .collect()
}

/// Maps one old line to the new file; false when a hunk changed that line.
fn map_line(hunks: &[Hunk], line: u32) -> (u32, bool) {
    let mut delta: i64 = 0;
    for hunk in hunks {
        if hunk.old_count == 0 {
            // Lines inserted after old line `old_start`.
            if line > hunk.old_start {
                delta += i64::from(hunk.new_count);
            }
            continue;
        }
        let end = hunk.old_start + hunk.old_count; // first old line after it
        if line >= end {
            delta += i64::from(hunk.new_count) - i64::from(hunk.old_count);
        } else if line >= hunk.old_start {
            return (hunk.new_start.max(1), false);
        }
    }
    ((i64::from(line) + delta).max(1) as u32, true)
}

pub fn map_range(hunks: &[Hunk], [first, last]: [u32; 2]) -> ([u32; 2], bool) {
    let (from, a) = map_line(hunks, first);
    let (to, b) = map_line(hunks, last);
    // A hunk inside the range changes it even when both ends survive.
    let touched = hunks.iter().any(|hunk| {
        if hunk.old_count == 0 {
            // Inserted between old lines `old_start` and `old_start + 1`.
            hunk.old_start >= first && hunk.old_start < last
        } else {
            hunk.old_start <= last && hunk.old_start + hunk.old_count > first
        }
    });
    ([from, to.max(from)], a && b && !touched)
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;

    /// A git repository in a temp folder, committing with a fixed identity.
    pub fn repo(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("loci-git-{label}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        git(&dir, &["init", "-q", "-b", "main"]);
        dir
    }

    pub fn git(dir: &Path, args: &[&str]) -> String {
        let out = Command::new("git")
            .arg("-C")
            .arg(dir)
            .args([
                "-c",
                "user.name=t",
                "-c",
                "user.email=t@t",
                "-c",
                "commit.gpgsign=false",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "git {args:?}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8_lossy(&out.stdout).trim().to_string()
    }

    pub fn commit(dir: &Path, files: &[(&str, &str)]) -> String {
        for (path, text) in files {
            let path = dir.join(path);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
        }
        git(dir, &["add", "-A"]);
        git(dir, &["commit", "-q", "-m", "c"]);
        git(dir, &["rev-parse", "HEAD"])
    }
}

#[cfg(test)]
mod tests {
    use super::testing::*;
    use super::*;

    #[test]
    fn reads_a_file_at_a_commit_and_sees_it_change() {
        let dir = repo("show");
        let first = commit(&dir, &[("src/main.go", "a\nb\nc\nd\ne\n")]);
        let file = dir.join("src/main.go");
        assert_eq!(repo_root(&file).unwrap(), dir);
        assert_eq!(path_in_repo(&dir, &file).unwrap(), "src/main.go");
        assert_eq!(head(&dir).unwrap().unwrap(), first);
        assert_eq!(resolve(&dir, &first[..7]).unwrap().unwrap(), first);
        assert_eq!(resolve(&dir, "0000000").unwrap(), None);
        assert_eq!(resolve(&dir, "--all").unwrap(), None);
        assert!(!changed_since(&dir, &first, "src/main.go").unwrap());

        commit(&dir, &[("src/main.go", "new\na\nb\nc\nX\ne\n")]);
        assert_eq!(
            show(&dir, &first, "src/main.go").unwrap().unwrap(),
            "a\nb\nc\nd\ne\n"
        );
        assert_eq!(show(&dir, &first, "nope.go").unwrap(), None);
        assert!(changed_since(&dir, &first, "src/main.go").unwrap());
        assert_eq!(commits_ahead(&dir, &first).unwrap(), Some(1));
        // b..c moved down one line; d was rewritten.
        assert_eq!(
            map_lines(&dir, &first, "src/main.go", [2, 3]).unwrap(),
            ([3, 4], true)
        );
        assert!(!map_lines(&dir, &first, "src/main.go", [3, 5]).unwrap().1);
        // Uncommitted edits count as changes too.
        let second = head(&dir).unwrap().unwrap();
        std::fs::write(&file, "dirty\n").unwrap();
        assert!(changed_since(&dir, &second, "src/main.go").unwrap());
        std::fs::remove_dir_all(dir).ok();
    }

    #[test]
    fn maps_lines_through_hunks() {
        let hunks = parse_hunks("@@ -0,0 +1,2 @@\n+x\n+y\n@@ -10,3 +12 @@\n-a\n-b\n-c\n+z\n");
        assert_eq!(hunks.len(), 2);
        assert_eq!(map_range(&hunks, [1, 5]), ([3, 7], true));
        assert_eq!(map_range(&hunks, [14, 20]), ([14, 20], true));
        assert!(!map_range(&hunks, [9, 11]).1);
        assert_eq!(map_range(&[], [4, 8]), ([4, 8], true));
    }
}
