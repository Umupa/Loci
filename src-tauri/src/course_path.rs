//! A mentor's learning path: an ordered list of short courses, with optional
//! prerequisites, kept as `courses/_path.yaml` in its folder. The order and
//! `after` are shown, never enforced: every course stays open.
//!
//! ```yaml
//! schemaVersion: 1
//! title: Sandboxes from the source
//! courses:
//!   - id: sandbox-foundations
//!   - id: cube-internals
//!     after: [sandbox-foundations]
//!   - id: snapshots-compared
//!     title: Snapshot and restore, three ways   # while it is not written yet
//! ```

use serde_json::{json, Map, Value};
use tauri::State;

use crate::mentor_store::{self, paths::Kind};
use crate::session_store::{validate_id, SessionStore};

/// The course id the path file takes in `courses/`; no course may have it.
pub const PATH_ID: &str = "_path";
const SCHEMA_VERSION: u64 = 1;
const COURSES_MAX: usize = 50;
const TITLE_MAX: usize = 200;

fn course_id(value: &Value, label: &str) -> Result<String, String> {
    let id = value
        .as_str()
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| format!("{label} must be a course id"))?;
    if id == PATH_ID
        || id.chars().count() > 80
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err(format!("{label}: {id} is not a course id"));
    }
    Ok(id.to_string())
}

fn title(value: Option<&Value>, label: &str) -> Result<Option<String>, String> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(text)) if text.trim().is_empty() => Ok(None),
        Some(Value::String(text)) if text.chars().count() <= TITLE_MAX => {
            Ok(Some(text.trim().to_string()))
        }
        _ => Err(format!(
            "{label} must be text of at most {TITLE_MAX} characters"
        )),
    }
}

/// Checks a path (as JSON) and returns it normalized: ids trimmed, `after`
/// always a list, unknown keys kept. Each `after` names an earlier course,
/// so a path cannot loop.
pub fn validate(value: Value) -> Result<Value, String> {
    let Value::Object(mut root) = value else {
        return Err("A learning path is a mapping with courses".into());
    };
    root.remove("schemaVersion");
    if let Some(found) = title(root.get("title"), "title")? {
        root.insert("title".into(), json!(found));
    } else {
        root.remove("title");
    }
    let Some(Value::Array(entries)) = root.remove("courses") else {
        return Err("A learning path needs courses: a list of { id, after? }".into());
    };
    if entries.is_empty() {
        return Err("A learning path needs at least one course".into());
    }
    if entries.len() > COURSES_MAX {
        return Err(format!(
            "A learning path holds at most {COURSES_MAX} courses"
        ));
    }
    let mut seen: Vec<String> = Vec::new();
    let mut out = Vec::with_capacity(entries.len());
    for (index, entry) in entries.into_iter().enumerate() {
        let label = format!("Course {}", index + 1);
        let mut entry = match entry {
            // `- some-course` is the same as `- id: some-course`.
            Value::String(id) => Map::from_iter([("id".to_string(), json!(id))]),
            Value::Object(entry) => entry,
            _ => return Err(format!("{label} must be a course id or {{ id, after }}")),
        };
        let id = course_id(entry.get("id").unwrap_or(&Value::Null), &label)?;
        if seen.contains(&id) {
            return Err(format!("{id} is in the path twice"));
        }
        let after: Vec<String> = match entry.remove("after") {
            None | Some(Value::Null) => Vec::new(),
            Some(Value::String(one)) => vec![course_id(&json!(one), &format!("{id} after"))?],
            Some(Value::Array(list)) => list
                .iter()
                .map(|value| course_id(value, &format!("{id} after")))
                .collect::<Result<_, _>>()?,
            Some(_) => return Err(format!("{id}: after is a list of course ids")),
        };
        for before in &after {
            if !seen.contains(before) {
                return Err(format!(
                    "{id}: after names {before}, which must come earlier in the path"
                ));
            }
        }
        entry.insert("id".into(), json!(id));
        if !after.is_empty() {
            entry.insert("after".into(), json!(after));
        }
        match title(entry.get("title"), &format!("{id} title"))? {
            Some(found) => {
                entry.insert("title".into(), json!(found));
            }
            None => {
                entry.remove("title");
            }
        }
        seen.push(id);
        out.push(Value::Object(entry));
    }
    root.insert("courses".into(), Value::Array(out));
    Ok(Value::Object(root))
}

/// Reads `courses/_path.yaml`.
pub fn parse(text: &str) -> Result<Value, String> {
    let value: Value = serde_yaml_ng::from_str(text).map_err(|e| format!("Not valid YAML: {e}"))?;
    if let Some(version) = value.get("schemaVersion").and_then(Value::as_u64) {
        if version > SCHEMA_VERSION {
            return Err(format!(
                "Written by a newer Loci (schemaVersion {version}); update Loci to read it"
            ));
        }
    }
    validate(value)
}

/// Writes the path as YAML, keys in reading order.
pub fn render(path: &Value) -> Result<String, String> {
    use serde_yaml_ng::{Mapping, Value as Yaml};
    fn ordered(object: &Map<String, Value>, first: &[&str]) -> Yaml {
        let mut map = Mapping::new();
        let mut rest: Vec<&String> = object
            .keys()
            .filter(|k| !first.contains(&k.as_str()))
            .collect();
        rest.sort();
        for key in first
            .iter()
            .filter(|key| object.contains_key(**key))
            .map(|key| key.to_string())
            .chain(rest.into_iter().cloned())
        {
            let value = &object[&key];
            let yaml = match (key.as_str(), value) {
                ("courses", Value::Array(items)) => Yaml::Sequence(
                    items
                        .iter()
                        .map(|item| match item {
                            Value::Object(entry) => ordered(entry, &["id", "title", "after"]),
                            other => serde_yaml_ng::to_value(other).unwrap_or(Yaml::Null),
                        })
                        .collect(),
                ),
                _ => serde_yaml_ng::to_value(value).unwrap_or(Yaml::Null),
            };
            map.insert(Yaml::String(key), yaml);
        }
        Yaml::Mapping(map)
    }
    let Value::Object(object) = validate(path.clone())? else {
        unreachable!("validate returns a mapping");
    };
    let mut with_version = Map::new();
    with_version.insert("schemaVersion".into(), json!(SCHEMA_VERSION));
    with_version.extend(object);
    serde_yaml_ng::to_string(&ordered(
        &with_version,
        &["schemaVersion", "title", "courses"],
    ))
    .map_err(|e| e.to_string())
}

fn ctx(conn: &rusqlite::Connection, agent_id: &str) -> Result<mentor_store::MentorCtx, String> {
    mentor_store::ctx_for(conn, agent_id)?.ok_or_else(|| {
        "A learning path needs the mentor's folder; this mentor's content is not in one yet".into()
    })
}

/// The path as the app reads it: the path itself, or why the file could not
/// be read (it keeps its last good reading).
pub fn read_path(conn: &rusqlite::Connection, agent_id: &str) -> Result<Value, String> {
    let ctx = ctx(conn, agent_id)?;
    let Some(row) = mentor_store::current(conn, &ctx, Kind::Course, PATH_ID)? else {
        return Ok(json!({ "path": null }));
    };
    let path = row
        .body
        .as_deref()
        .and_then(|body| serde_json::from_str::<Value>(body).ok());
    Ok(json!({
        "path": path,
        "file": row.rel_path,
        "updatedAt": row.updated_at,
        "error": row.error,
    }))
}

/// Replaces the path with `path` (the JSON form of the file).
pub fn write_path(
    conn: &rusqlite::Connection,
    agent_id: &str,
    path: &Value,
) -> Result<Value, String> {
    let text = render(path)?;
    let ctx = ctx(conn, agent_id)?;
    let row = mentor_store::write_content(conn, &ctx, Kind::Course, PATH_ID, &text)?;
    let saved = row
        .body
        .as_deref()
        .and_then(|body| serde_json::from_str::<Value>(body).ok());
    Ok(json!({ "path": saved, "file": row.rel_path, "updatedAt": row.updated_at }))
}

#[tauri::command(async)]
pub fn course_path_read(store: State<'_, SessionStore>, agent_id: String) -> Result<Value, String> {
    validate_id(&agent_id, "agent")?;
    read_path(&*store.lock_conn()?, &agent_id)
}

#[tauri::command(async)]
pub fn course_path_write(
    store: State<'_, SessionStore>,
    agent_id: String,
    path: Value,
) -> Result<Value, String> {
    validate_id(&agent_id, "agent")?;
    // Checked before the database is locked.
    render(&path)?;
    write_path(&*store.lock_conn()?, &agent_id, &path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_path_reads_writes_back_and_keeps_unknown_keys() {
        let yaml = "schemaVersion: 1\ntitle: Sandboxes\nnote: mine\ncourses:\n  - basics\n  - id: cube\n    after: basics\n    level: 2\n  - id: compare\n    title: Three ways\n    after: [basics, cube]\n";
        let path = parse(yaml).unwrap();
        assert_eq!(path["title"], "Sandboxes");
        assert_eq!(path["note"], "mine");
        assert_eq!(path["courses"][0], json!({ "id": "basics" }));
        assert_eq!(
            path["courses"][1],
            json!({ "id": "cube", "after": ["basics"], "level": 2 })
        );
        assert_eq!(path["courses"][2]["after"], json!(["basics", "cube"]));
        let written = render(&path).unwrap();
        assert!(written.starts_with("schemaVersion: 1\ntitle: Sandboxes\ncourses:\n- id: basics\n"));
        assert!(written
            .contains("- id: compare\n  title: Three ways\n  after:\n  - basics\n  - cube\n"));
        assert_eq!(parse(&written).unwrap(), path);
    }

    #[test]
    fn the_path_file_lives_beside_courses_and_is_never_a_course() {
        use crate::mentor_store::{index, testing};
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        crate::course::ensure_courses_table(&conn).unwrap();
        index::ensure_tables(&conn).unwrap();
        let folder = testing::temp_dir("path");
        testing::register(&conn, "m1", &folder);
        assert_eq!(read_path(&conn, "m1").unwrap()["path"], Value::Null);
        let saved = write_path(
            &conn,
            "m1",
            &json!({ "courses": ["a", { "id": "b", "after": ["a"] }] }),
        )
        .unwrap();
        assert_eq!(saved["file"], "courses/_path.yaml");
        assert_eq!(saved["path"]["courses"][1]["after"], json!(["a"]));
        let text = std::fs::read_to_string(folder.join("courses/_path.yaml")).unwrap();
        assert!(text.starts_with("schemaVersion: 1\ncourses:\n- id: a\n"));
        // Not a course: no listing, no summary.
        let listed = index::list(&conn, "m1", &[Kind::Course]).unwrap();
        assert_eq!(listed.len(), 1);
        assert!(crate::course::tests_support::courses_of(&conn, "m1").is_empty());

        // Edited by hand, it is read again; a broken edit keeps the last good path and says why.
        std::fs::write(
            folder.join("courses/_path.yaml"),
            "courses:\n  - a\n  - c\n",
        )
        .unwrap();
        assert_eq!(
            read_path(&conn, "m1").unwrap()["path"]["courses"][1]["id"],
            "c"
        );
        std::fs::write(
            folder.join("courses/_path.yaml"),
            "courses:\n  - id: c\n    after: [z]\n",
        )
        .unwrap();
        let broken = read_path(&conn, "m1").unwrap();
        assert_eq!(broken["path"]["courses"][1]["id"], "c");
        assert!(broken["error"].as_str().unwrap().contains("earlier"));
        assert!(write_path(&conn, "nobody", &json!({ "courses": ["a"] })).is_err());
        std::fs::remove_dir_all(folder).ok();
    }

    #[test]
    fn prerequisites_come_earlier_and_ids_are_course_ids() {
        let bad = |yaml: &str| parse(yaml).unwrap_err();
        assert!(bad("courses:\n  - id: a\n    after: [b]\n  - id: b\n").contains("earlier"));
        assert!(bad("courses:\n  - id: a\n    after: [a]\n").contains("earlier"));
        assert!(bad("courses:\n  - a\n  - a\n").contains("twice"));
        assert!(bad("courses:\n  - _path\n").contains("not a course id"));
        assert!(bad("courses:\n  - '../x'\n").contains("not a course id"));
        assert!(bad("courses: []\n").contains("at least one"));
        assert!(bad("title: x\n").contains("needs courses"));
        assert!(bad("schemaVersion: 9\ncourses: [a]\n").contains("newer"));
    }
}
