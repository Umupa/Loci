//! A PDF as a first-hand source: `sources/<id>.pdf` and its sidecar
//! `sources/<id>.pdf.yaml` (title, sourceUrl, version, fetchedAt, subject,
//! pages). The sidecar is the source's front matter; the PDF is the text the
//! learner reads. The index keeps the PDF's extracted text so search finds it
//! and the mentor can read it with `documents.read`.
//!
//! Extraction is local (pdf-extract, a pure Rust reader): no network, no
//! external tool, and a scanned PDF that has no text layer still opens in the
//! reader; `library check` reports that its text could not be read.

use std::path::Path;

use serde_yaml_ng::{Mapping, Value as Yaml};

use super::format::{first_heading, get_text, split_front_matter};
use super::fsio::{iso_from_millis, millis_from_iso};

/// A PDF larger than this is not taken in; papers are far smaller.
pub const PDF_MAX: u64 = 100 * 1024 * 1024;
/// The extracted text kept for search and `documents.read`; a long book stops here.
pub const TEXT_MAX: usize = 1_000_000;
/// Between pages of extracted text, so a page number can be found again
/// (`documents.read` returns the pages apart).
pub const PAGE_BREAK: char = '\u{c}';
const PAGE_BREAK_TEXT: &str = "\n\n\u{c}\n\n";

/// What a PDF source's sidecar says.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct PdfMeta {
    pub title: Option<String>,
    pub source_url: Option<String>,
    pub version: Option<String>,
    pub fetched_at: Option<i64>,
    pub subject: Option<String>,
    /// The page count the sidecar was written with; the PDF is the judge.
    pub pages: Option<u32>,
}

/// The sidecar is plain YAML; a `---` front-matter block is read too, so a
/// file saved the way sources are written by hand still works.
pub fn parse_sidecar(text: &str) -> Result<(PdfMeta, Mapping), String> {
    let map = if text.starts_with("---\n") || text.starts_with("---\r\n") {
        split_front_matter(text)?.0
    } else {
        match serde_yaml_ng::from_str::<Yaml>(text)
            .map_err(|e| format!("The sidecar is not valid YAML: {e}"))?
        {
            Yaml::Mapping(map) => map,
            Yaml::Null => Mapping::new(),
            _ => return Err("The sidecar is a list of key: value lines".into()),
        }
    };
    let pages = match map.get("pages") {
        None | Some(Yaml::Null) => None,
        Some(Yaml::Number(number)) => Some(
            number
                .as_u64()
                .filter(|pages| *pages > 0 && *pages <= 100_000)
                .map(|pages| pages as u32)
                .ok_or("pages must be a positive whole number")?,
        ),
        Some(Yaml::String(text)) => Some(
            text.trim()
                .parse::<u32>()
                .ok()
                .filter(|pages| *pages > 0 && *pages <= 100_000)
                .ok_or("pages must be a positive whole number")?,
        ),
        Some(_) => return Err("pages must be a positive whole number".into()),
    };
    let meta = PdfMeta {
        title: get_text(&map, "title"),
        source_url: get_text(&map, "sourceUrl"),
        version: get_text(&map, "version"),
        fetched_at: map.get("fetchedAt").and_then(|value| match value {
            Yaml::Number(number) => number.as_i64(),
            other => text_value(other).and_then(|text| millis_from_iso(&text)),
        }),
        subject: get_text(&map, "subject"),
        pages,
    };
    Ok((meta, map))
}

fn text_value(value: &Yaml) -> Option<String> {
    match value {
        Yaml::String(text) => Some(text.clone()),
        Yaml::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

fn put(map: &mut Mapping, key: &str, value: Option<Yaml>) {
    match value {
        Some(value) => {
            map.insert(Yaml::String(key.into()), value);
        }
        None => {
            map.remove(key);
        }
    }
}

fn put_text(map: &mut Mapping, key: &str, value: Option<&str>) {
    put(
        map,
        key,
        value
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(|text| Yaml::String(text.into())),
    );
}

/// The sidecar file. `existing` keeps keys the app does not set.
pub fn render_sidecar(existing: Option<Mapping>, meta: &PdfMeta) -> Result<String, String> {
    let mut map = existing.unwrap_or_default();
    put_text(&mut map, "title", meta.title.as_deref());
    put_text(&mut map, "sourceUrl", meta.source_url.as_deref());
    put_text(&mut map, "version", meta.version.as_deref());
    put(
        &mut map,
        "fetchedAt",
        meta.fetched_at.map(|at| Yaml::String(iso_from_millis(at))),
    );
    put_text(&mut map, "subject", meta.subject.as_deref());
    put(
        &mut map,
        "pages",
        meta.pages.map(|pages| Yaml::Number(pages.into())),
    );
    serde_yaml_ng::to_string(&map).map_err(|e| e.to_string())
}

/// A title of last resort from the extracted text: its first line with words.
pub fn title_from_text(text: &str) -> Option<String> {
    first_heading(text).or_else(|| {
        text.lines()
            .map(str::trim)
            .find(|line| line.chars().any(char::is_alphanumeric))
            .map(|line| line.chars().take(200).collect())
    })
}

/// What reading a PDF gave: how many pages, its text, and what stopped the text.
#[derive(Debug, Clone, PartialEq)]
pub struct PdfText {
    pub pages: u32,
    pub text: String,
    pub warning: Option<String>,
}

/// How many pages a PDF has, without reading its text.
pub fn page_count(path: &Path) -> Result<u32, String> {
    guard(|| {
        let doc =
            pdf_extract::Document::load(path).map_err(|e| format!("Not a readable PDF: {e}"))?;
        Ok(doc.get_pages().len() as u32)
    })
}

/// A PDF reader that meets a malformed file must not take the app down: any
/// panic it raises becomes an error for that file, and the app goes on.
fn guard<T>(read: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(read)) {
        Ok(result) => result,
        Err(_) => Err("The PDF reader failed on this file".into()),
    }
}

/// Reads a PDF's text, page by page, locally. A missing text layer (a scan)
/// keeps the page count and says so.
pub fn read_pdf(path: &Path) -> Result<PdfText, String> {
    guard(|| read_pdf_inner(path))
}

fn read_pdf_inner(path: &Path) -> Result<PdfText, String> {
    let doc = pdf_extract::Document::load(path).map_err(|e| format!("Not a readable PDF: {e}"))?;
    let pages = doc.get_pages().len() as u32;
    if pages == 0 {
        return Err("The PDF has no pages".into());
    }
    let extracted = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        pdf_extract::extract_text_by_pages(path)
    }));
    let text = match extracted {
        Ok(Ok(page_texts)) => page_texts
            .iter()
            .map(|page| page.trim())
            .collect::<Vec<_>>()
            .join(PAGE_BREAK_TEXT),
        Ok(Err(error)) => {
            return Ok(PdfText {
                pages,
                text: String::new(),
                warning: Some(format!("The PDF's text could not be read: {error}")),
            })
        }
        Err(_) => {
            return Ok(PdfText {
                pages,
                text: String::new(),
                warning: Some("The PDF's text could not be read".into()),
            })
        }
    };
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Ok(PdfText {
            pages,
            text: String::new(),
            warning: Some("This PDF has no text layer; only its pages can be read".into()),
        });
    }
    let (text, truncated) = if trimmed.len() > TEXT_MAX {
        let cut = floor_char_boundary(trimmed, TEXT_MAX);
        (
            trimmed[..cut].to_string(),
            Some(format!(
                "Only the first {} pages of text are indexed",
                pages
            )),
        )
    } else {
        (trimmed.to_string(), None)
    };
    Ok(PdfText {
        pages,
        text,
        warning: truncated,
    })
}

/// The file in `sidecar`'s folder whose name is the sidecar's name without
/// `.yaml`/`.yml`, in whatever case it was saved (`paper.pdf.yaml` →
/// `paper.pdf`, `Paper.PDF.yaml` → `Paper.PDF`).
fn sibling_ignoring_case(path: &Path, strip: &str, add: &str) -> Option<std::path::PathBuf> {
    let dir = path.parent()?;
    let name = path.file_name()?.to_str()?.to_ascii_lowercase();
    let stem = name.strip_suffix(strip)?;
    let wanted = format!("{stem}{add}");
    std::fs::read_dir(dir)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .find(|candidate| {
            candidate
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.to_ascii_lowercase() == wanted)
        })
}

/// The PDF beside a sidecar, whatever case its name has.
pub fn pdf_beside_sidecar(sidecar: &Path) -> Option<std::path::PathBuf> {
    sibling_ignoring_case(sidecar, ".yaml", "")
        .or_else(|| sibling_ignoring_case(sidecar, ".yml", ""))
        .filter(|candidate| candidate.is_file())
}

/// The sidecar that belongs beside a PDF, whichever extension it has.
pub fn sidecar_beside_pdf(pdf: &Path) -> Option<std::path::PathBuf> {
    sibling_ignoring_case(pdf, ".pdf", ".pdf.yaml")
        .or_else(|| sibling_ignoring_case(pdf, ".pdf", ".pdf.yml"))
}

/// PDFs and sidecars in `sources/` that are not a pair, with what to say:
/// `(file to name, id, what is wrong)`. A PDF alone is not a source yet, and
/// a sidecar alone names a PDF that is gone.
pub fn pair_problems(sources: &std::path::Path) -> Vec<(std::path::PathBuf, String, String)> {
    let mut problems = Vec::new();
    let Ok(entries) = std::fs::read_dir(sources) else {
        return problems;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Some(name) = path
            .file_name()
            .and_then(|n| n.to_str())
            .map(str::to_string)
        else {
            continue;
        };
        if !entry.file_type().is_ok_and(|kind| kind.is_file()) || super::paths::ignored_name(&name)
        {
            continue;
        }
        let lower = name.to_ascii_lowercase();
        let Some(id) = super::paths::pdf_source_id(&name).map(str::to_string) else {
            continue;
        };
        if !super::paths::valid_content_id(&id) {
            problems.push((
                path.clone(),
                id,
                "Rename it: source ids use only letters, digits, - and _".into(),
            ));
        } else if lower.ends_with(".pdf") && sidecar_beside_pdf(&path).is_none() {
            problems.push((
                path.clone(),
                id.clone(),
                format!("{name} has no sidecar ({id}.pdf.yaml), so it is not in the library"),
            ));
        } else if !lower.ends_with(".pdf") {
            let pdf = pdf_beside_sidecar(&path).unwrap_or_else(|| path.with_extension(""));
            if !pdf.is_file() {
                problems.push((
                    path.clone(),
                    id,
                    format!(
                        "{} is missing; restore it beside the sidecar",
                        pdf.file_name()
                            .and_then(|n| n.to_str())
                            .unwrap_or("The PDF")
                    ),
                ));
            }
        }
    }
    problems
}

/// The largest char boundary at or below `at`, so a cut never splits a character.
fn floor_char_boundary(text: &str, at: usize) -> usize {
    if at >= text.len() {
        return text.len();
    }
    let mut cut = at;
    while cut > 0 && !text.is_char_boundary(cut) {
        cut -= 1;
    }
    cut
}

/// A real one-page-per-string PDF, with a correct cross-reference table, so
/// tests read text through the same reader the app uses.
#[cfg(test)]
pub(crate) fn sample_pdf(pages: &[&str]) -> Vec<u8> {
    let count = pages.len();
    let font = 3 + 2 * count;
    let kids: Vec<String> = (0..count).map(|i| format!("{} 0 R", 3 + 2 * i)).collect();
    let mut objects = vec![
        "<< /Type /Catalog /Pages 2 0 R >>".to_string(),
        format!(
            "<< /Type /Pages /Kids [{}] /Count {count} >>",
            kids.join(" ")
        ),
    ];
    for (index, text) in pages.iter().enumerate() {
        let content = format!("BT /F1 12 Tf 72 700 Td ({text}) Tj ET");
        objects.push(format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents {} 0 R /Resources << /Font << /F1 {font} 0 R >> >> >>",
            4 + 2 * index
        ));
        objects.push(format!(
            "<< /Length {} >>\nstream\n{content}\nendstream",
            content.len()
        ));
    }
    objects.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".into());
    let mut out = String::from("%PDF-1.4\n");
    let mut offsets = Vec::new();
    for (index, body) in objects.iter().enumerate() {
        offsets.push(out.len());
        out.push_str(&format!("{} 0 obj\n{body}\nendobj\n", index + 1));
    }
    let xref = out.len();
    out.push_str(&format!(
        "xref\n0 {}\n0000000000 65535 f \n",
        objects.len() + 1
    ));
    for offset in offsets {
        out.push_str(&format!("{offset:010} 00000 n \n"));
    }
    out.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
        objects.len() + 1
    ));
    out.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_sidecar_round_trips_and_keeps_keys_it_does_not_set() {
        let meta = PdfMeta {
            title: Some("Firecracker: Lightweight Virtualization".into()),
            source_url: Some("https://www.usenix.org/system/files/nsdi20-paper-agache.pdf".into()),
            version: Some("NSDI '20".into()),
            fetched_at: Some(1_793_491_200_000),
            subject: Some("Virtualization".into()),
            pages: Some(15),
        };
        let mut extra = Mapping::new();
        extra.insert(
            Yaml::String("license".into()),
            Yaml::String("USENIX".into()),
        );
        let text = render_sidecar(Some(extra), &meta).unwrap();
        assert!(text.starts_with("license: USENIX\ntitle: 'Firecracker:"));
        let (read, map) = parse_sidecar(&text).unwrap();
        assert_eq!(read, meta);
        assert_eq!(get_text(&map, "license").as_deref(), Some("USENIX"));
        // Front matter, a quoted page count, and a missing one all read.
        let (meta, _) =
            parse_sidecar("---\ntitle: Paper\nsourceUrl: https://x.org/p.pdf\npages: '7'\n---\n")
                .unwrap();
        assert_eq!(meta.pages, Some(7));
        assert_eq!(meta.title.as_deref(), Some("Paper"));
        assert_eq!(parse_sidecar("title: P\n").unwrap().0.pages, None);
        assert!(parse_sidecar("title: [unclosed").is_err());
        assert!(parse_sidecar("pages: many").is_err());
        assert!(parse_sidecar("pages: 0").is_err());
    }

    #[test]
    fn a_pdf_is_read_page_by_page_with_its_local_text() {
        let dir = std::env::temp_dir().join(format!("loci-pdf-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("paper.pdf");
        std::fs::write(&path, sample_pdf(&["Sandbox page one", "Sandbox page two"])).unwrap();
        let read = read_pdf(&path).unwrap();
        assert_eq!(read.pages, 2);
        assert!(read.text.contains("Sandbox page one"));
        assert!(read.text.contains("Sandbox page two"));
        assert_eq!(read.warning, None);
        std::fs::write(dir.join("broken.pdf"), b"not a pdf").unwrap();
        assert!(read_pdf(&dir.join("broken.pdf")).is_err());
        // A file that looks like a PDF and is not one is an error, never a crash.
        std::fs::write(
            dir.join("garbage.pdf"),
            b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\ntrailer\n%%EOF\n",
        )
        .unwrap();
        assert!(read_pdf(&dir.join("garbage.pdf")).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_pdf_and_its_sidecar_find_each_other_whatever_their_case() {
        let dir = std::env::temp_dir().join(format!("loci-pair-{}", uuid::Uuid::new_v4()));
        let sources = dir.join("sources");
        std::fs::create_dir_all(&sources).unwrap();
        std::fs::write(sources.join("Paper.PDF"), sample_pdf(&["Text"])).unwrap();
        std::fs::write(sources.join("Paper.PDF.yaml"), "title: P\n").unwrap();
        let pdf = sources.join("Paper.PDF");
        let sidecar = sidecar_beside_pdf(&pdf).unwrap();
        assert_eq!(sidecar.file_name().unwrap(), "Paper.PDF.yaml");
        assert_eq!(pdf_beside_sidecar(&sidecar).unwrap(), pdf);
        assert!(pair_problems(&sources).is_empty());

        // A PDF alone is not a source yet; a sidecar alone names a gone PDF.
        std::fs::write(sources.join("lone.pdf"), sample_pdf(&["Text"])).unwrap();
        std::fs::write(sources.join("orphan.pdf.yaml"), "title: O\n").unwrap();
        let problems = pair_problems(&sources);
        assert_eq!(problems.len(), 2);
        assert!(problems
            .iter()
            .any(|(path, id, error)| path.ends_with("lone.pdf")
                && *id == "lone"
                && error.contains("no sidecar")));
        assert!(problems
            .iter()
            .any(|(path, _, error)| path.ends_with("orphan.pdf.yaml")
                && error.contains("orphan.pdf is missing")));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_cut_in_extracted_text_never_splits_a_character() {
        assert_eq!(floor_char_boundary("h\u{e9}llo", 2), 1);
        assert_eq!(floor_char_boundary("plain", 99), 5);
    }
}
