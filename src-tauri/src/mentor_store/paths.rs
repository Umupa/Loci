//! Where a mentor's folder is and how its files are named.
//!
//! The mentors root is `~/Loci` for the installed app, `~/Loci-Dev` for Loci
//! Dev and `~/Loci-Dev-<suffix>` for any other build (a QA bundle), so
//! development and QA never write into the user's folders. A folder directly
//! under the root is a mentor when, and only when, it holds `mentor.json`.

use std::path::{Component, Path, PathBuf};

use unicode_normalization::UnicodeNormalization;

/// The file that makes a folder a mentor's.
pub const MENTOR_FILE: &str = "mentor.json";
/// A mentor that was removed keeps its folder; this name stops it from being
/// adopted again on the next start.
pub const REMOVED_MENTOR_FILE: &str = "mentor.removed.json";
/// The shared clone root of 0.3 (`~/Loci/repos`); never a mentor.
pub const SHARED_REPOS: &str = "repos";
const SLUG_MAX: usize = 40;
const SLUG_TRIES: usize = 99;
pub const ID_MAX: usize = 80;

/// What a file in a mentor's folder holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    Source,
    Guide,
    Course,
    Note,
    Canvas,
}

pub const KINDS: [Kind; 5] = [
    Kind::Source,
    Kind::Guide,
    Kind::Course,
    Kind::Note,
    Kind::Canvas,
];

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Source => "source",
            Kind::Guide => "guide",
            Kind::Course => "course",
            Kind::Note => "note",
            Kind::Canvas => "canvas",
        }
    }

    pub fn parse(value: &str) -> Option<Kind> {
        KINDS.into_iter().find(|kind| kind.as_str() == value)
    }

    /// The folder this kind lives in.
    pub fn dir(self) -> &'static str {
        match self {
            Kind::Source => "sources",
            Kind::Guide => "guides",
            Kind::Course => "courses",
            Kind::Note => "notes",
            Kind::Canvas => "canvases",
        }
    }

    /// The extension the app writes.
    pub fn ext(self) -> &'static str {
        match self {
            Kind::Source | Kind::Guide | Kind::Note => "md",
            Kind::Course => "yaml",
            Kind::Canvas => "excalidraw",
        }
    }

    /// Extensions read as this kind.
    fn reads(self, ext: &str) -> bool {
        match self {
            Kind::Course => ext == "yaml" || ext == "yml",
            // A PDF source is `sources/<id>.pdf` with a `sources/<id>.pdf.yaml`
            // sidecar; the sidecar is the file that is read and indexed.
            Kind::Source => ext == "md" || ext == "yaml" || ext == "yml",
            other => ext == other.ext(),
        }
    }

    /// Whether the index keeps the file's text for search.
    pub fn searchable(self) -> bool {
        matches!(self, Kind::Source | Kind::Guide | Kind::Note)
    }
}

/// The mentors root for a build. `override_root` is honoured only away from
/// the installed app.
pub fn mentors_root_for(identifier: &str, home: &Path, override_root: Option<&str>) -> PathBuf {
    let release = identifier == crate::flavor::RELEASE_IDENTIFIER;
    if !release {
        if let Some(root) = override_root.map(str::trim).filter(|r| !r.is_empty()) {
            let root = PathBuf::from(root);
            if root.is_absolute() {
                return root;
            }
        }
    }
    if release {
        return home.join("Loci");
    }
    if identifier == "com.loci.desktop.dev" {
        return home.join("Loci-Dev");
    }
    let suffix: String = identifier
        .rsplit('.')
        .next()
        .unwrap_or("qa")
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-')
        .collect();
    home.join(format!(
        "Loci-Dev-{}",
        if suffix.is_empty() { "qa" } else { &suffix }
    ))
}

/// An id that can name a file: letters of any script, digits, `-` and `_`.
pub fn valid_content_id(id: &str) -> bool {
    !id.is_empty()
        && id.chars().count() <= ID_MAX
        && !id.starts_with('.')
        && id
            .chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '_')
}

/// Where the app writes this kind's file with this id.
pub fn content_path(folder: &Path, kind: Kind, id: &str) -> PathBuf {
    folder.join(kind.dir()).join(format!("{id}.{}", kind.ext()))
}

/// The PDF of a source: `sources/<id>.pdf`.
pub fn pdf_source_path(folder: &Path, id: &str) -> PathBuf {
    folder.join(Kind::Source.dir()).join(format!("{id}.pdf"))
}

/// Its sidecar, which holds the source's front matter: `sources/<id>.pdf.yaml`.
pub fn pdf_sidecar_path(folder: &Path, id: &str) -> PathBuf {
    folder
        .join(Kind::Source.dir())
        .join(format!("{id}.pdf.yaml"))
}

/// The sidecar an id already has, under whichever of the two extensions it
/// was saved (`.yaml` is what the app writes).
pub fn existing_pdf_sidecar(folder: &Path, id: &str) -> Option<PathBuf> {
    [".yaml", ".yml"]
        .into_iter()
        .map(|ext| {
            folder
                .join(Kind::Source.dir())
                .join(format!("{id}.pdf{ext}"))
        })
        .find(|candidate| candidate.is_file())
}

/// The id a `<id>.pdf` or `<id>.pdf.yaml` file names, when its name is one.
pub fn pdf_source_id(name: &str) -> Option<&str> {
    let lower = name.to_ascii_lowercase();
    let stem = lower
        .strip_suffix(".pdf.yaml")
        .or_else(|| lower.strip_suffix(".pdf.yml"))
        .or_else(|| lower.strip_suffix(".pdf"))?;
    (!stem.is_empty()).then(|| &name[..stem.len()])
}

/// Whether this is the sidecar of a PDF source (the file the index reads).
pub fn is_pdf_sidecar(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|name| {
            let lower = name.to_ascii_lowercase();
            (lower.ends_with(".pdf.yaml") || lower.ends_with(".pdf.yml"))
                && lower.len() > ".pdf.yaml".len()
        })
}

/// Temporary, hidden or backup files editors leave beside the real ones.
pub fn ignored_name(name: &str) -> bool {
    name.starts_with('.')
        || name.starts_with('#')
        || name.ends_with('~')
        || name.ends_with(".tmp")
        || name.ends_with(".swp")
        || name.contains(".conflict-")
        || name.contains(".from-0.3.")
}

/// The kind and id a path in a mentor's folder names, if it is content.
/// Names are read back in NFC, as macOS may hand them over decomposed.
pub fn classify(folder: &Path, path: &Path) -> Option<(Kind, String)> {
    let relative = path.strip_prefix(folder).ok()?;
    let mut parts = relative.components();
    let dir = match parts.next()? {
        Component::Normal(dir) => dir.to_str()?,
        _ => return None,
    };
    let name = match parts.next()? {
        Component::Normal(name) => name.to_str()?,
        _ => return None,
    };
    if parts.next().is_some() || ignored_name(name) {
        return None;
    }
    let kind = KINDS.into_iter().find(|kind| kind.dir() == dir)?;
    let (stem, ext) = name.rsplit_once('.')?;
    if !kind.reads(&ext.to_ascii_lowercase()) {
        return None;
    }
    // `sources/<id>.pdf.yaml` is the sidecar of a PDF source, named by `<id>`.
    let stem = if kind == Kind::Source
        && (ext.eq_ignore_ascii_case("yaml") || ext.eq_ignore_ascii_case("yml"))
    {
        match stem.rsplit_once('.') {
            Some((base, pdf)) if pdf.eq_ignore_ascii_case("pdf") => base,
            _ => return None,
        }
    } else {
        stem
    };
    let id: String = stem.nfc().collect();
    valid_content_id(&id).then_some((kind, id))
}

/// A path relative to the mentor's folder, refusing `..` and absolute parts.
pub fn relative_inside(folder: &Path, relative: &str) -> Result<PathBuf, String> {
    let path = Path::new(relative);
    if relative.is_empty()
        || path
            .components()
            .any(|part| !matches!(part, Component::Normal(_)))
    {
        return Err(format!("Not a path inside the mentor's folder: {relative}"));
    }
    Ok(folder.join(path))
}

/// The folder name for a mentor: its name in lowercase ASCII words, else its
/// role's, else `mentor-<id>`. Mirrors `workdirSlug` in TypeScript, with the
/// role as a second chance for names written in other scripts.
pub fn mentor_slug(name: Option<&str>, role: Option<&str>, id: &str) -> String {
    for text in [name, role].into_iter().flatten() {
        let slug = ascii_slug(text);
        if !slug.is_empty() && slug != SHARED_REPOS {
            return slug;
        }
    }
    let short: String = id
        .chars()
        .filter(char::is_ascii_alphanumeric)
        .take(8)
        .collect::<String>()
        .to_ascii_lowercase();
    format!("mentor-{short}")
}

fn ascii_slug(text: &str) -> String {
    let mut out = String::new();
    let mut dash = false;
    for c in text.nfkd().filter(|c| c.is_ascii()) {
        let c = c.to_ascii_lowercase();
        if c.is_ascii_alphanumeric() {
            out.push(c);
            dash = false;
        } else if !out.is_empty() && !dash {
            out.push('-');
            dash = true;
        }
    }
    let cut: String = out.chars().take(SLUG_MAX).collect();
    cut.trim_matches('-').to_string()
}

/// A new, empty folder `<root>/<slug>` (or `<slug>-2`, ...). An existing
/// folder is never reused, so nothing of the user's is adopted by accident.
pub fn create_folder(root: &Path, slug: &str) -> Result<PathBuf, String> {
    std::fs::create_dir_all(root).map_err(|e| format!("{}: {e}", root.display()))?;
    for attempt in 1..=SLUG_TRIES {
        let name = if attempt == 1 {
            slug.to_string()
        } else {
            format!("{slug}-{attempt}")
        };
        if name == SHARED_REPOS {
            continue;
        }
        let dir = root.join(&name);
        match std::fs::create_dir(&dir) {
            Ok(()) => return Ok(dir),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("{}: {e}", dir.display())),
        }
    }
    Err(format!("No free folder name for {slug}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_build_has_its_own_root_and_only_debug_builds_take_an_override() {
        let home = Path::new("/home/u");
        assert_eq!(
            mentors_root_for("com.loci.desktop", home, Some("/tmp/x")),
            PathBuf::from("/home/u/Loci")
        );
        assert_eq!(
            mentors_root_for("com.loci.desktop.dev", home, None),
            PathBuf::from("/home/u/Loci-Dev")
        );
        assert_eq!(
            mentors_root_for("com.loci.desktop.qa", home, None),
            PathBuf::from("/home/u/Loci-Dev-qa")
        );
        assert_eq!(
            mentors_root_for("com.loci.desktop.qa", home, Some("/tmp/m")),
            PathBuf::from("/tmp/m")
        );
        assert_eq!(
            mentors_root_for("com.loci.desktop.qa", home, Some("relative")),
            PathBuf::from("/home/u/Loci-Dev-qa")
        );
    }

    #[test]
    fn content_files_are_recognised_by_folder_and_extension() {
        let folder = Path::new("/m/x");
        assert_eq!(
            classify(folder, Path::new("/m/x/sources/virtio.md")),
            Some((Kind::Source, "virtio".into()))
        );
        assert_eq!(
            classify(folder, Path::new("/m/x/courses/a.yml")),
            Some((Kind::Course, "a".into()))
        );
        assert_eq!(classify(folder, Path::new("/m/x/sources/.a.md.swp")), None);
        assert_eq!(classify(folder, Path::new("/m/x/sources/a.md~")), None);
        assert_eq!(classify(folder, Path::new("/m/x/sources/a.txt")), None);
        assert_eq!(classify(folder, Path::new("/m/x/sources/sub/a.md")), None);
        assert_eq!(classify(folder, Path::new("/m/x/repos/a.md")), None);
        // A PDF source is read through its sidecar; the PDF alone is not a file to index.
        assert_eq!(
            classify(folder, Path::new("/m/x/sources/paper.pdf.yaml")),
            Some((Kind::Source, "paper".into()))
        );
        assert_eq!(
            classify(folder, Path::new("/m/x/sources/Paper.PDF.yml")),
            Some((Kind::Source, "Paper".into()))
        );
        assert_eq!(classify(folder, Path::new("/m/x/sources/paper.pdf")), None);
        assert_eq!(classify(folder, Path::new("/m/x/sources/a.yaml")), None);
        assert_eq!(
            classify(folder, Path::new("/m/x/sources/.paper.pdf.yaml")),
            None
        );
        assert!(is_pdf_sidecar(Path::new("/m/x/sources/paper.pdf.yaml")));
        assert!(!is_pdf_sidecar(Path::new("/m/x/sources/paper.pdf")));
        assert_eq!(pdf_source_id("paper.pdf"), Some("paper"));
        assert_eq!(pdf_source_id("paper.pdf.yaml"), Some("paper"));
        assert_eq!(pdf_source_id("paper.pdf.yml"), Some("paper"));
        assert_eq!(pdf_source_id("paper.md"), None);
        assert_eq!(
            pdf_source_path(Path::new("/m/x"), "paper"),
            PathBuf::from("/m/x/sources/paper.pdf")
        );
        assert_eq!(
            pdf_sidecar_path(Path::new("/m/x"), "paper"),
            PathBuf::from("/m/x/sources/paper.pdf.yaml")
        );
        assert_eq!(
            classify(folder, Path::new("/m/x/notes/n.conflict-20261101-1200.md")),
            None
        );
    }

    #[test]
    fn decomposed_names_are_read_as_composed_ids() {
        let folder = Path::new("/m/x");
        let decomposed = "caf\u{65}\u{301}";
        let (_, id) = classify(
            folder,
            &folder.join("guides").join(format!("{decomposed}.md")),
        )
        .unwrap();
        assert_eq!(id, "caf\u{e9}");
        let (_, id) = classify(folder, Path::new("/m/x/guides/内核.md")).unwrap();
        assert_eq!(id, "内核");
    }

    #[test]
    fn paths_cannot_leave_the_folder() {
        let folder = Path::new("/m/x");
        assert!(relative_inside(folder, "../y").is_err());
        assert!(relative_inside(folder, "/etc/passwd").is_err());
        assert!(relative_inside(folder, "a/./b").is_ok());
        assert_eq!(
            relative_inside(folder, "repos/a/b.rs").unwrap(),
            PathBuf::from("/m/x/repos/a/b.rs")
        );
    }

    #[test]
    fn slugs_fall_back_from_name_to_role_to_id() {
        assert_eq!(mentor_slug(Some("Repo Lens"), None, "x"), "repo-lens");
        assert_eq!(
            mentor_slug(Some("沙箱导师"), Some("Sandbox internals guide"), "x"),
            "sandbox-internals-guide"
        );
        assert_eq!(
            mentor_slug(Some("沙箱导师"), None, "EAE55CB6-fd9c"),
            "mentor-eae55cb6"
        );
        assert_eq!(mentor_slug(Some("repos"), None, "ab"), "mentor-ab");
    }

    #[test]
    fn a_taken_folder_name_gets_a_number() {
        let root = std::env::temp_dir().join(format!("loci-paths-{}", uuid::Uuid::new_v4()));
        let first = create_folder(&root, "a").unwrap();
        let second = create_folder(&root, "a").unwrap();
        assert_eq!(first, root.join("a"));
        assert_eq!(second, root.join("a-2"));
        std::fs::remove_dir_all(root).unwrap();
    }
}
