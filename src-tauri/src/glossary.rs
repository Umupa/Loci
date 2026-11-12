//! A mentor's glossary: the terms its lessons introduce, each with a one-line
//! definition and the lesson that teaches it, kept as `glossary.yaml` in its
//! folder. The reader underlines a term where a lesson uses it.
//!
//! ```yaml
//! schemaVersion: 1
//! terms:
//!   - term: watch
//!     aliases: [watches]
//!     definition: A client's subscription to changes of one kind of object.
//!     course: k8s
//!     lesson: watch-and-list
//! ```

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::State;

use crate::mentor_store;
use crate::session_store::{validate_id, SessionStore};

pub const GLOSSARY_FILE: &str = "glossary.yaml";
const SCHEMA_VERSION: u64 = 1;
const TERMS_MAX: usize = 2000;
const TERM_MAX: usize = 80;
const ALIASES_MAX: usize = 8;
const DEFINITION_MAX: usize = 400;

/// One read-modify-write at a time, so two batches never lose each other's terms.
static LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Term {
    pub term: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub aliases: Vec<String>,
    pub definition: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub course: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lesson: Option<String>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct File {
    #[serde(default)]
    schema_version: Option<u64>,
    #[serde(default)]
    terms: Vec<Term>,
}

fn key(term: &str) -> String {
    term.trim().to_lowercase()
}

/// A term as it may be kept: trimmed, bounded, its lesson named with its course.
fn checked(mut term: Term) -> Result<Term, String> {
    term.term = term.term.trim().to_string();
    term.definition = term.definition.trim().to_string();
    let count = term.term.chars().count();
    if count == 0 || count > TERM_MAX {
        return Err(format!("A term is 1-{TERM_MAX} characters: {}", term.term));
    }
    if term.definition.is_empty() || term.definition.chars().count() > DEFINITION_MAX {
        return Err(format!(
            "{}: the definition is one line of at most {DEFINITION_MAX} characters",
            term.term
        ));
    }
    if term.definition.contains('\n') {
        return Err(format!("{}: the definition is one line", term.term));
    }
    term.aliases = term
        .aliases
        .into_iter()
        .map(|alias| alias.trim().to_string())
        .filter(|alias| !alias.is_empty() && key(alias) != key(&term.term))
        .collect();
    term.aliases.dedup_by_key(|alias| key(alias));
    if term.aliases.len() > ALIASES_MAX
        || term
            .aliases
            .iter()
            .any(|alias| alias.chars().count() > TERM_MAX)
    {
        return Err(format!(
            "{}: at most {ALIASES_MAX} aliases of {TERM_MAX} characters",
            term.term
        ));
    }
    if let Some(course) = &term.course {
        validate_id(course, "course")?;
    }
    if let Some(lesson) = &term.lesson {
        validate_id(lesson, "lesson")?;
        if term.course.is_none() {
            return Err(format!("{}: a lesson is named with its course", term.term));
        }
    }
    Ok(term)
}

fn path(folder: &Path) -> PathBuf {
    folder.join(GLOSSARY_FILE)
}

pub fn read(folder: &Path) -> Result<Vec<Term>, String> {
    let text = match std::fs::read_to_string(path(folder)) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(format!("{GLOSSARY_FILE}: {error}")),
    };
    if text.trim().is_empty() {
        return Ok(Vec::new());
    }
    let file: File = serde_yaml_ng::from_str(&text).map_err(|e| format!("{GLOSSARY_FILE}: {e}"))?;
    Ok(file.terms)
}

fn write(folder: &Path, terms: Vec<Term>) -> Result<(), String> {
    let file = File {
        schema_version: Some(SCHEMA_VERSION),
        terms,
    };
    let text = serde_yaml_ng::to_string(&file).map_err(|e| e.to_string())?;
    mentor_store::fsio::write_atomic(&path(folder), text.as_bytes())
}

/// Adds terms, or replaces those already there under the same name (any case).
pub fn upsert(folder: &Path, batch: Vec<Term>) -> Result<(usize, usize), String> {
    let batch = batch
        .into_iter()
        .map(checked)
        .collect::<Result<Vec<_>, _>>()?;
    let _guard = LOCK.lock().map_err(|e| e.to_string())?;
    let mut terms = read(folder)?;
    for term in batch.iter().cloned() {
        match terms
            .iter_mut()
            .find(|kept| key(&kept.term) == key(&term.term))
        {
            Some(kept) => *kept = term,
            None => terms.push(term),
        }
    }
    if terms.len() > TERMS_MAX {
        return Err(format!("A glossary keeps at most {TERMS_MAX} terms"));
    }
    let total = terms.len();
    write(folder, terms)?;
    Ok((batch.len(), total))
}

/// Takes terms out by name (any case); returns how many were there.
pub fn remove(folder: &Path, names: &[String]) -> Result<usize, String> {
    let _guard = LOCK.lock().map_err(|e| e.to_string())?;
    let mut terms = read(folder)?;
    let before = terms.len();
    terms.retain(|term| !names.iter().any(|name| key(name) == key(&term.term)));
    let removed = before - terms.len();
    if removed > 0 {
        write(folder, terms)?;
    }
    Ok(removed)
}

const NO_FOLDER: &str =
    "This mentor's library is in the old store, which keeps no glossary; make a new mentor";

fn folder(store: &SessionStore, agent_id: &str) -> Result<PathBuf, String> {
    validate_id(agent_id, "agent")?;
    let conn = store.lock_conn()?;
    Ok(mentor_store::ctx_for(&conn, agent_id)?
        .ok_or(NO_FOLDER)?
        .folder)
}

#[tauri::command(async)]
pub fn glossary_read(
    store: State<'_, SessionStore>,
    agent_id: String,
) -> Result<Vec<Term>, String> {
    let folder = match folder(&store, &agent_id) {
        Ok(folder) => folder,
        // An old mentor simply has no glossary to show.
        Err(error) if error == NO_FOLDER => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };
    read(&folder)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Saved {
    saved: usize,
    total: usize,
}

#[tauri::command(async)]
pub fn glossary_write(
    store: State<'_, SessionStore>,
    agent_id: String,
    terms: Vec<Term>,
) -> Result<Saved, String> {
    let (saved, total) = upsert(&folder(&store, &agent_id)?, terms)?;
    Ok(Saved { saved, total })
}

#[tauri::command(async)]
pub fn glossary_remove(
    store: State<'_, SessionStore>,
    agent_id: String,
    terms: Vec<String>,
) -> Result<usize, String> {
    remove(&folder(&store, &agent_id)?, &terms)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn term(name: &str, definition: &str) -> Term {
        Term {
            term: name.into(),
            aliases: vec![],
            definition: definition.into(),
            course: Some("k8s".into()),
            lesson: Some("watch".into()),
        }
    }

    #[test]
    fn terms_are_added_replaced_by_name_and_removed() {
        let dir = crate::mentor_store::testing::temp_dir("glossary");
        assert_eq!(read(dir.as_path()).unwrap(), vec![]);
        let mut watch = term("watch", "A subscription to changes.");
        watch.aliases = vec!["watches".into(), "Watch".into()];
        assert_eq!(
            upsert(
                dir.as_path(),
                vec![watch, term("PLEG", "The pod lifecycle event generator.")]
            )
            .unwrap(),
            (2, 2)
        );
        let kept = read(dir.as_path()).unwrap();
        // An alias that is the term itself is dropped.
        assert_eq!(kept[0].aliases, vec!["watches".to_string()]);
        assert_eq!(
            upsert(dir.as_path(), vec![term("Watch", "A stream of changes.")]).unwrap(),
            (1, 2)
        );
        assert_eq!(
            read(dir.as_path()).unwrap()[0].definition,
            "A stream of changes."
        );
        let text = std::fs::read_to_string(dir.as_path().join(GLOSSARY_FILE)).unwrap();
        assert!(text.starts_with("schemaVersion: 1\nterms:\n"), "{text}");
        assert_eq!(
            remove(dir.as_path(), &["pleg".into(), "nothing".into()]).unwrap(),
            1
        );
        assert_eq!(read(dir.as_path()).unwrap().len(), 1);
    }

    #[test]
    fn a_term_needs_a_one_line_definition_and_its_lesson_needs_its_course() {
        let dir = crate::mentor_store::testing::temp_dir("glossary");
        assert!(upsert(dir.as_path(), vec![term(" ", "x")]).is_err());
        assert!(upsert(dir.as_path(), vec![term("a", "two\nlines")]).is_err());
        let mut loose = term("a", "b");
        loose.course = None;
        assert!(upsert(dir.as_path(), vec![loose])
            .unwrap_err()
            .contains("with its course"));
        assert!(!dir.as_path().join(GLOSSARY_FILE).exists());
    }
}
