//! The file formats of a mentor's folder.
//!
//! - Markdown with YAML front-matter for sources, guides and notes. The body
//!   after the front-matter is kept byte for byte.
//! - YAML for courses, mapping one to one onto the course JSON the app has
//!   always validated (`course::validate_data` stays the judge).
//! - Excalidraw JSON for canvases, with a `loci` key Excalidraw ignores.
//! - `mentor.json` for who the mentor is.
//!
//! Keys the app does not know are kept when it rewrites a file.

use serde_json::{json, Map, Value};
use serde_yaml_ng::{Mapping, Value as Yaml};

use super::fsio::{iso_from_millis, millis_from_iso};

pub const SCHEMA_VERSION: u64 = 1;

// ---------------------------------------------------------------------------
// Front-matter

/// Splits `---\n<yaml>\n---\n<body>`. Text without front-matter is all body.
pub fn split_front_matter(text: &str) -> Result<(Mapping, &str), String> {
    let rest = match text
        .strip_prefix("---\n")
        .or_else(|| text.strip_prefix("---\r\n"))
    {
        Some(rest) => rest,
        None => return Ok((Mapping::new(), text)),
    };
    let mut offset = 0;
    for line in rest.split_inclusive('\n') {
        let bare = line.trim_end_matches(['\n', '\r']);
        if bare == "---" || bare == "..." {
            let yaml = &rest[..offset];
            let body = &rest[offset + line.len()..];
            let map = if yaml.trim().is_empty() {
                Mapping::new()
            } else {
                match serde_yaml_ng::from_str::<Yaml>(yaml)
                    .map_err(|e| format!("Front-matter is not valid YAML: {e}"))?
                {
                    Yaml::Mapping(map) => map,
                    Yaml::Null => Mapping::new(),
                    _ => return Err("Front-matter must be a list of key: value lines".into()),
                }
            };
            return Ok((map, body));
        }
        offset += line.len();
    }
    Err("Front-matter starts with --- but never ends".into())
}

pub fn join_front_matter(map: &Mapping, body: &str) -> Result<String, String> {
    if map.is_empty() {
        return Ok(body.to_string());
    }
    let yaml = serde_yaml_ng::to_string(map).map_err(|e| e.to_string())?;
    Ok(format!("---\n{yaml}---\n{body}"))
}

fn text_of(value: &Yaml) -> Option<String> {
    match value {
        Yaml::String(text) => Some(text.clone()),
        Yaml::Number(number) => Some(number.to_string()),
        Yaml::Bool(flag) => Some(flag.to_string()),
        _ => None,
    }
}

pub fn get_text(map: &Mapping, key: &str) -> Option<String> {
    map.get(key)
        .and_then(text_of)
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

fn get_time(map: &Mapping, key: &str) -> Option<i64> {
    match map.get(key)? {
        Yaml::Number(number) => number.as_i64(),
        other => text_of(other).and_then(|text| millis_from_iso(&text)),
    }
}

/// Sets a key in place (keeping its position), or removes it for `None`.
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
            .filter(|v| !v.is_empty())
            .map(|v| Yaml::String(v.into())),
    );
}

fn put_time(map: &mut Mapping, key: &str, value: Option<i64>) {
    put(map, key, value.map(|ms| Yaml::String(iso_from_millis(ms))));
}

/// The first `# Heading` of a Markdown body, as a title of last resort.
pub fn first_heading(body: &str) -> Option<String> {
    body.lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix("# "))
        .map(|title| title.trim().chars().take(200).collect::<String>())
        .filter(|title| !title.is_empty())
}

// ---------------------------------------------------------------------------
// Sources and guides

#[derive(Debug, Clone, Default, PartialEq)]
pub struct DocMeta {
    pub title: Option<String>,
    pub subject: Option<String>,
    pub source_url: Option<String>,
    pub version: Option<String>,
    pub fetched_at: Option<i64>,
    pub created_at: Option<i64>,
}

pub fn parse_doc(text: &str) -> Result<(DocMeta, Mapping, String), String> {
    let (map, body) = split_front_matter(text)?;
    let meta = DocMeta {
        title: get_text(&map, "title"),
        subject: get_text(&map, "subject"),
        source_url: get_text(&map, "sourceUrl"),
        version: get_text(&map, "version"),
        fetched_at: get_time(&map, "fetchedAt"),
        created_at: get_time(&map, "createdAt"),
    };
    Ok((meta, map, body.to_string()))
}

/// The file for a source or guide. `existing` keeps keys the app does not set.
pub fn render_doc(existing: Option<Mapping>, meta: &DocMeta, body: &str) -> Result<String, String> {
    let mut map = existing.unwrap_or_default();
    put_text(&mut map, "title", meta.title.as_deref());
    put_text(&mut map, "sourceUrl", meta.source_url.as_deref());
    put_text(&mut map, "version", meta.version.as_deref());
    put_time(&mut map, "fetchedAt", meta.fetched_at);
    put_text(&mut map, "subject", meta.subject.as_deref());
    put_time(&mut map, "createdAt", meta.created_at);
    join_front_matter(&map, body)
}

// ---------------------------------------------------------------------------
// Notes

#[derive(Debug, Clone, Default, PartialEq)]
pub struct NoteMeta {
    pub title: Option<String>,
    pub slug: Option<String>,
    pub slug_pending: bool,
    pub tags: Vec<String>,
    pub created_at: Option<i64>,
    pub updated_at: Option<i64>,
    pub source_session: Option<String>,
    pub source_cwd: Option<String>,
}

pub fn parse_note(text: &str) -> Result<(NoteMeta, Mapping, String), String> {
    let (map, body) = split_front_matter(text)?;
    let tags = match map.get("tags") {
        Some(Yaml::Sequence(items)) => items.iter().filter_map(text_of).collect(),
        Some(other) => text_of(other)
            .map(|text| text.split(',').map(|t| t.trim().to_string()).collect())
            .unwrap_or_default(),
        None => Vec::new(),
    };
    let meta = NoteMeta {
        title: get_text(&map, "title"),
        slug: get_text(&map, "slug"),
        slug_pending: matches!(map.get("slugPending"), Some(Yaml::Bool(true))),
        tags,
        created_at: get_time(&map, "createdAt"),
        updated_at: get_time(&map, "updatedAt"),
        source_session: get_text(&map, "sourceSession"),
        source_cwd: get_text(&map, "sourceCwd"),
    };
    Ok((meta, map, body.to_string()))
}

pub fn render_note(
    existing: Option<Mapping>,
    meta: &NoteMeta,
    body: &str,
) -> Result<String, String> {
    let mut map = existing.unwrap_or_default();
    put_text(&mut map, "title", meta.title.as_deref());
    put_text(&mut map, "slug", meta.slug.as_deref());
    put(
        &mut map,
        "slugPending",
        meta.slug_pending.then_some(Yaml::Bool(true)),
    );
    put(
        &mut map,
        "tags",
        Some(Yaml::Sequence(
            meta.tags.iter().map(|t| Yaml::String(t.clone())).collect(),
        )),
    );
    put_time(&mut map, "createdAt", meta.created_at);
    put_time(&mut map, "updatedAt", meta.updated_at);
    put_text(&mut map, "sourceSession", meta.source_session.as_deref());
    put_text(&mut map, "sourceCwd", meta.source_cwd.as_deref());
    join_front_matter(&map, body)
}

// ---------------------------------------------------------------------------
// Courses

/// A course read from YAML: what `course_upsert` would have been given.
#[derive(Debug, Clone, PartialEq)]
pub struct CourseFile {
    pub title: String,
    pub engine: String,
    pub data_json: String,
}

/// Reads a course. `resolve` turns a lesson's relative `file:` into an
/// absolute path (against the mentor's folder, then its workdir).
pub fn parse_course(
    text: &str,
    resolve: &dyn Fn(&str) -> Result<String, String>,
) -> Result<CourseFile, String> {
    let value: Value = serde_yaml_ng::from_str(text).map_err(|e| format!("Not valid YAML: {e}"))?;
    let Value::Object(mut root) = value else {
        return Err("A course file is a YAML mapping".into());
    };
    if let Some(version) = root.remove("schemaVersion") {
        if version.as_u64().is_some_and(|v| v > SCHEMA_VERSION) {
            return Err(format!(
                "Written by a newer Loci (schemaVersion {version}); update Loci to read it"
            ));
        }
    }
    root.remove("id");
    let title = match root.remove("title") {
        Some(Value::String(title)) if !title.trim().is_empty() => title.trim().to_string(),
        _ => return Err("A course needs a title".into()),
    };
    let engine = match root.remove("engine") {
        Some(Value::String(engine)) => engine,
        None if root.contains_key("steps") => "build-your-own".into(),
        None => "reading".into(),
        Some(_) => return Err("engine must be reading or build-your-own".into()),
    };
    if let Some(canvas) = root.remove("canvas") {
        root.entry("canvasId").or_insert(canvas);
    }
    if engine == "reading" {
        let chapters = root
            .get_mut("chapters")
            .and_then(Value::as_array_mut)
            .ok_or("A reading course needs chapters")?;
        for chapter in chapters {
            let Some(lessons) = chapter.get_mut("lessons").and_then(Value::as_array_mut) else {
                continue;
            };
            for lesson in lessons {
                if let Value::Object(lesson) = lesson {
                    read_lesson(lesson, resolve)?;
                }
            }
        }
    }
    let data_json = serde_json::to_string(&Value::Object(root)).map_err(|e| e.to_string())?;
    Ok(CourseFile {
        title,
        engine,
        data_json,
    })
}

/// A course JSON whose lesson files may be relative to the mentor's folder
/// or use the shorthands below, with every file made absolute.
pub fn resolve_lesson_files(
    data_json: &str,
    resolve: &dyn Fn(&str) -> Result<String, String>,
) -> Result<String, String> {
    let mut data: Value =
        serde_json::from_str(data_json).map_err(|e| format!("Invalid course JSON: {e}"))?;
    for chapter in data
        .get_mut("chapters")
        .and_then(Value::as_array_mut)
        .into_iter()
        .flatten()
    {
        for lesson in chapter
            .get_mut("lessons")
            .and_then(Value::as_array_mut)
            .into_iter()
            .flatten()
        {
            if let Value::Object(lesson) = lesson {
                if lesson.contains_key("file") || lesson.contains_key("compare") {
                    read_lesson(lesson, resolve)?;
                }
            }
        }
    }
    serde_json::to_string(&data).map_err(|e| e.to_string())
}

/// Lesson shorthands: `document: id#section`, `file: path#L12-40` or `#p7-9`,
/// and `file: repos/<repo>@<sha>:path`, a file pinned to a commit (the
/// lesson gains `commit`; `file` is the path in the working tree). A
/// comparison's parts take the same shorthands.
fn read_lesson(
    lesson: &mut Map<String, Value>,
    resolve: &dyn Fn(&str) -> Result<String, String>,
) -> Result<(), String> {
    if let Some(Value::Array(parts)) = lesson.get_mut("compare") {
        for part in parts {
            if let Value::Object(part) = part {
                read_place(part, resolve)?;
            }
        }
    }
    read_place(lesson, resolve)
}

fn read_place(
    lesson: &mut Map<String, Value>,
    resolve: &dyn Fn(&str) -> Result<String, String>,
) -> Result<(), String> {
    if let Some(Value::String(document)) = lesson.get("document").cloned() {
        if let Some((id, section)) = document.split_once('#') {
            lesson.insert("document".into(), json!(id.trim()));
            if !lesson.contains_key("section") && !section.trim().is_empty() {
                lesson.insert("section".into(), json!(section.trim()));
            }
        }
    }
    if let Some(Value::String(file)) = lesson.get("file").cloned() {
        let (path, fragment) = match file.rsplit_once('#') {
            Some((path, fragment)) => (path.to_string(), Some(fragment.to_string())),
            None => (file.clone(), None),
        };
        if let Some(fragment) = fragment {
            let (key, range) = if let Some(range) = fragment.strip_prefix('L') {
                ("lines", range)
            } else if let Some(range) = fragment.strip_prefix('p') {
                ("pages", range)
            } else {
                return Err(format!("Not a place in a file: #{fragment}"));
            };
            if !lesson.contains_key(key) {
                let (from, to) = range.split_once('-').unwrap_or((range, range));
                let from: u32 = from
                    .trim_start_matches('L')
                    .parse()
                    .map_err(|_| format!("Not a range: #{fragment}"))?;
                let to: u32 = to
                    .trim_start_matches('L')
                    .parse()
                    .map_err(|_| format!("Not a range: #{fragment}"))?;
                lesson.insert(key.into(), json!([from, to]));
            }
        }
        let path = match pinned(&path) {
            Some((path, commit)) => {
                lesson.entry("commit").or_insert(json!(commit));
                path
            }
            None => path,
        };
        let absolute = if std::path::Path::new(&path).is_absolute() {
            path
        } else {
            resolve(&path)?
        };
        lesson.insert("file".into(), json!(absolute));
    }
    Ok(())
}

/// `repos/<repo>@<sha>:path/in/repo` → (`repos/<repo>/path/in/repo`, sha).
pub fn pinned(path: &str) -> Option<(String, String)> {
    let (repo, rest) = path.split_once('@')?;
    let (sha, inner) = rest.split_once(':')?;
    if repo.is_empty() || inner.is_empty() || !crate::course::is_commit(sha) {
        return None;
    }
    Some((
        format!(
            "{}/{}",
            repo.trim_end_matches('/'),
            inner.trim_start_matches('/')
        ),
        sha.to_ascii_lowercase(),
    ))
}

/// The pin shorthand for a lesson file in a git checkout: `<repo>@<sha>:<path
/// in repo>`, with `<repo>` as `relativize` writes it. None when the file is
/// in no repository Loci can see.
fn pin_shorthand(file: &str, commit: &str, relativize: &dyn Fn(&str) -> String) -> Option<String> {
    let path = std::path::Path::new(file);
    let root = path
        .ancestors()
        .skip(1)
        .find(|dir| dir.join(".git").exists())?;
    let inner = path.strip_prefix(root).ok()?.to_str()?.replace('\\', "/");
    let repo = relativize(root.to_str()?);
    Some(format!("{repo}@{commit}:{inner}"))
}

const COURSE_KEYS: [&str; 6] = [
    "schemaVersion",
    "title",
    "engine",
    "canvas",
    "chapters",
    "steps",
];
const LESSON_KEYS: [&str; 9] = [
    "id", "title", "document", "section", "file", "lines", "pages", "commit", "compare",
];
const PART_KEYS: [&str; 7] = [
    "label", "file", "document", "section", "lines", "commit", "note",
];
const STEP_KEYS: [&str; 8] = [
    "id",
    "title",
    "summary",
    "file",
    "before",
    "after",
    "explanation",
    "runCommand",
];

/// Writes a course as YAML. `relativize` turns an absolute file inside the
/// mentor's folder into a path relative to it; others stay absolute.
pub fn render_course(
    title: &str,
    engine: &str,
    data_json: &str,
    relativize: &dyn Fn(&str) -> String,
) -> Result<String, String> {
    let data: Value = serde_json::from_str(data_json).map_err(|e| e.to_string())?;
    let mut root = Map::new();
    root.insert("schemaVersion".into(), json!(SCHEMA_VERSION));
    root.insert("title".into(), json!(title));
    root.insert("engine".into(), json!(engine));
    if let Some(Value::Object(object)) = Some(data) {
        for (key, value) in object {
            match key.as_str() {
                "engine" => {}
                "canvasId" => {
                    root.insert("canvas".into(), value);
                }
                "chapters" => {
                    let chapters = value
                        .as_array()
                        .into_iter()
                        .flatten()
                        .map(|chapter| {
                            let mut chapter = chapter.clone();
                            if let Some(lessons) =
                                chapter.get_mut("lessons").and_then(Value::as_array_mut)
                            {
                                for lesson in lessons.iter_mut() {
                                    write_place(lesson, relativize);
                                    if let Some(parts) =
                                        lesson.get_mut("compare").and_then(Value::as_array_mut)
                                    {
                                        for part in parts {
                                            write_place(part, relativize);
                                        }
                                    }
                                }
                            }
                            chapter
                        })
                        .collect();
                    root.insert("chapters".into(), Value::Array(chapters));
                }
                _ => {
                    root.insert(key, value);
                }
            }
        }
    }
    let yaml = ordered(&Value::Object(root), &COURSE_KEYS);
    serde_yaml_ng::to_string(&yaml).map_err(|e| e.to_string())
}

/// A lesson's or part's file as the course file names it: the pin shorthand
/// when it is pinned, else relative to the mentor's folder when inside it.
fn write_place(place: &mut Value, relativize: &dyn Fn(&str) -> String) {
    let Some(Value::String(file)) = place.get("file").cloned() else {
        return;
    };
    let commit = place
        .get("commit")
        .and_then(Value::as_str)
        .map(str::to_string);
    let short = commit
        .as_deref()
        .and_then(|commit| pin_shorthand(&file, commit, relativize));
    match short {
        Some(short) => {
            place["file"] = json!(short);
            if let Value::Object(place) = place {
                place.remove("commit");
            }
        }
        None => place["file"] = json!(relativize(&file)),
    }
}

/// JSON → YAML with the keys in reading order instead of alphabetical.
fn ordered(value: &Value, keys: &[&str]) -> Yaml {
    match value {
        Value::Object(object) => {
            let mut map = Mapping::new();
            let mut rest: Vec<&String> = object.keys().collect();
            rest.sort();
            for key in keys
                .iter()
                .filter(|k| object.contains_key(**k))
                .map(|k| k.to_string())
                .chain(
                    rest.into_iter()
                        .filter(|k| !keys.contains(&k.as_str()))
                        .cloned(),
                )
            {
                let child_keys: &[&str] = match key.as_str() {
                    "chapters" => &["title", "lessons"],
                    "lessons" => &LESSON_KEYS,
                    "compare" => &PART_KEYS,
                    "steps" => &STEP_KEYS,
                    _ => &[],
                };
                map.insert(
                    Yaml::String(key.clone()),
                    ordered(&object[&key], child_keys),
                );
            }
            Yaml::Mapping(map)
        }
        Value::Array(items) => Yaml::Sequence(items.iter().map(|i| ordered(i, keys)).collect()),
        other => serde_yaml_ng::to_value(other).unwrap_or(Yaml::Null),
    }
}

// ---------------------------------------------------------------------------
// Canvases

#[derive(Debug, Clone, Default, PartialEq)]
pub struct CanvasMeta {
    pub title: Option<String>,
    pub tags: Vec<String>,
    pub created_at: Option<i64>,
    pub updated_at: Option<i64>,
}

/// An `.excalidraw` file: the scene, plus a `loci` key with its title.
pub fn parse_canvas(text: &str) -> Result<(CanvasMeta, String), String> {
    let value: Value = serde_json::from_str(text).map_err(|e| format!("Not valid JSON: {e}"))?;
    let Value::Object(mut scene) = value else {
        return Err("An .excalidraw file is a JSON object".into());
    };
    let loci = scene.remove("loci").unwrap_or(Value::Null);
    for key in ["type", "version", "source"] {
        scene.remove(key);
    }
    let meta = CanvasMeta {
        title: loci["title"].as_str().map(str::to_string),
        tags: loci["tags"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|t| t.as_str().map(str::to_string))
            .collect(),
        created_at: loci["createdAt"]
            .as_str()
            .and_then(millis_from_iso)
            .or_else(|| loci["createdAt"].as_i64()),
        updated_at: loci["updatedAt"].as_i64(),
    };
    let data = serde_json::to_string(&Value::Object(scene)).map_err(|e| e.to_string())?;
    Ok((meta, data))
}

pub fn render_canvas(meta: &CanvasMeta, data_json: &str) -> Result<String, String> {
    let value: Value =
        serde_json::from_str(data_json).map_err(|e| format!("Canvas data is not JSON: {e}"))?;
    let Value::Object(scene) = value else {
        return Err("Canvas data must be a JSON object".into());
    };
    let mut file = Map::new();
    file.insert("type".into(), json!("excalidraw"));
    file.insert("version".into(), json!(2));
    file.insert("source".into(), json!("loci"));
    for (key, value) in scene {
        if !matches!(key.as_str(), "type" | "version" | "source" | "loci") {
            file.insert(key, value);
        }
    }
    let mut loci = Map::new();
    if let Some(title) = &meta.title {
        loci.insert("title".into(), json!(title));
    }
    loci.insert("tags".into(), json!(meta.tags));
    if let Some(created) = meta.created_at {
        loci.insert("createdAt".into(), json!(iso_from_millis(created)));
    }
    if let Some(updated) = meta.updated_at {
        // A number: it is also the revision a guarded write compares.
        loci.insert("updatedAt".into(), json!(updated));
    }
    file.insert("loci".into(), Value::Object(loci));
    serde_json::to_string(&Value::Object(file)).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// mentor.json

const MENTOR_KEYS: [&str; 10] = [
    "schemaVersion",
    "id",
    "name",
    "role",
    "avatar",
    "color",
    "workdir",
    "folders",
    "defaults",
    "createdAt",
];

pub fn parse_mentor(text: &str) -> Result<Map<String, Value>, String> {
    match serde_json::from_str::<Value>(text).map_err(|e| format!("mentor.json: {e}"))? {
        Value::Object(map) => {
            if !map.get("id").and_then(Value::as_str).is_some_and(|id| {
                !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
            }) {
                return Err("mentor.json needs an id".into());
            }
            Ok(map)
        }
        _ => Err("mentor.json must be a JSON object".into()),
    }
}

/// `mentor.json`, pretty-printed with its keys in a stable reading order.
pub fn render_mentor(map: &Map<String, Value>) -> Result<String, String> {
    let mut rest: Vec<&String> = map
        .keys()
        .filter(|k| !MENTOR_KEYS.contains(&k.as_str()))
        .collect();
    rest.sort();
    let mut yaml = Mapping::new();
    for key in MENTOR_KEYS
        .iter()
        .map(|k| k.to_string())
        .filter(|k| map.contains_key(k))
        .chain(rest.into_iter().cloned())
    {
        yaml.insert(
            Yaml::String(key.clone()),
            serde_yaml_ng::to_value(&map[&key]).map_err(|e| e.to_string())?,
        );
    }
    let mut text = serde_json::to_string_pretty(&yaml).map_err(|e| e.to_string())?;
    text.push('\n');
    Ok(text)
}

/// Newer files are read but never rewritten by an older Loci.
pub fn mentor_is_newer(map: &Map<String, Value>) -> bool {
    map.get("schemaVersion")
        .and_then(Value::as_u64)
        .is_some_and(|version| version > SCHEMA_VERSION)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_source_keeps_its_body_byte_for_byte_and_unknown_keys() {
        let body = "# Virtqueues\n\n  indented\r\nline with --- inside\n---\nnot front-matter\n";
        let meta = DocMeta {
            title: Some("Virtio: Virtqueues".into()),
            source_url: Some("https://example.com/v".into()),
            version: Some("1.2".into()),
            fetched_at: Some(1_793_491_200_000),
            created_at: Some(1_793_491_200_000),
            subject: None,
        };
        let mut extra = Mapping::new();
        extra.insert(Yaml::String("license".into()), Yaml::String("CC".into()));
        let text = render_doc(Some(extra), &meta, body).unwrap();
        let (read, map, read_body) = parse_doc(&text).unwrap();
        assert_eq!(read, meta);
        assert_eq!(read_body, body);
        assert_eq!(get_text(&map, "license").as_deref(), Some("CC"));
        assert!(text.starts_with("---\nlicense: CC\ntitle: 'Virtio: Virtqueues'\n"));
    }

    #[test]
    fn a_file_without_front_matter_is_all_body_and_versions_may_be_numbers() {
        let (meta, _, body) = parse_doc("# Hello\ntext").unwrap();
        assert_eq!(meta, DocMeta::default());
        assert_eq!(body, "# Hello\ntext");
        assert_eq!(first_heading(&body).as_deref(), Some("Hello"));
        let (meta, _, _) =
            parse_doc("---\ntitle: X\nversion: 1.2\nfetchedAt: 2026-11-01\n---\nb").unwrap();
        assert_eq!(meta.version.as_deref(), Some("1.2"));
        assert_eq!(meta.fetched_at, Some(1_793_491_200_000));
        assert!(parse_doc("---\ntitle: [unclosed\n---\n").is_err());
        assert!(parse_doc("---\ntitle: x\n").is_err());
    }

    #[test]
    fn a_note_round_trips() {
        let meta = NoteMeta {
            title: Some("KVM 笔记".into()),
            slug: Some("kvm".into()),
            slug_pending: false,
            tags: vec!["kvm".into(), "virt".into()],
            created_at: Some(1),
            updated_at: Some(2),
            source_session: Some("s1".into()),
            source_cwd: None,
        };
        let text = render_note(None, &meta, "body\n").unwrap();
        let (read, _, body) = parse_note(&text).unwrap();
        assert_eq!(read, meta);
        assert_eq!(body, "body\n");
    }

    fn resolve(path: &str) -> Result<String, String> {
        Ok(format!("/m/x/{path}"))
    }

    #[test]
    fn a_course_yaml_reads_as_the_course_json_and_writes_back() {
        let yaml = "schemaVersion: 1\ntitle: Sandbox\nengine: reading\ncanvas: overview\nchapters:\n  - title: KVM\n    lessons:\n      - id: a\n        title: API\n        document: 'kvm-api#4.1 KVM_CREATE_VM'\n      - id: b\n        title: Loop\n        file: repos/fc/src/lib.rs#L120-188\n      - id: c\n        title: Paper\n        file: /abs/paper.pdf#p7\n      - id: d\n        title: Pinned\n        file: repos/fc@0123abc:src/vmm.rs\n";
        let course = parse_course(yaml, &resolve).unwrap();
        assert_eq!(course.title, "Sandbox");
        assert_eq!(course.engine, "reading");
        let data: Value = serde_json::from_str(&course.data_json).unwrap();
        assert_eq!(data["canvasId"], "overview");
        let lessons = &data["chapters"][0]["lessons"];
        assert_eq!(lessons[0]["document"], "kvm-api");
        assert_eq!(lessons[0]["section"], "4.1 KVM_CREATE_VM");
        assert_eq!(lessons[1]["file"], "/m/x/repos/fc/src/lib.rs");
        assert_eq!(lessons[1]["lines"], json!([120, 188]));
        assert_eq!(lessons[2]["file"], "/abs/paper.pdf");
        assert_eq!(lessons[2]["pages"], json!([7, 7]));
        assert_eq!(lessons[3]["file"], "/m/x/repos/fc/src/vmm.rs");
        assert_eq!(lessons[3]["commit"], "0123abc");
        assert_eq!(lessons[1].get("commit"), None);
        crate::course::validate_data(&course.engine, &course.data_json).unwrap();

        let relativize = |path: &str| path.strip_prefix("/m/x/").unwrap_or(path).to_string();
        let written = render_course(
            &course.title,
            &course.engine,
            &course.data_json,
            &relativize,
        )
        .unwrap();
        assert!(written
            .starts_with("schemaVersion: 1\ntitle: Sandbox\nengine: reading\ncanvas: overview\n"));
        assert!(written.contains("file: repos/fc/src/lib.rs"));
        assert!(written.contains("  - id: a\n    title: API\n    document: kvm-api\n"));
        let again = parse_course(&written, &resolve).unwrap();
        let normalized = |raw: &str| serde_json::from_str::<Value>(raw).unwrap();
        assert_eq!(normalized(&again.data_json), normalized(&course.data_json));
    }

    #[test]
    fn a_pinned_lesson_writes_back_as_the_pin_shorthand() {
        let folder = crate::mentor_store::testing::temp_dir("pin");
        std::fs::create_dir_all(folder.join("repos/e2b-dev/runtime/.git")).unwrap();
        let base = format!("{}/", folder.display());
        let resolve = |path: &str| Ok(format!("{base}{path}"));
        let sha = "3f2a9c1e3f2a9c1e3f2a9c1e3f2a9c1e3f2a9c1e";
        let yaml = format!("title: T\nchapters:\n  - title: C\n    lessons:\n      - id: a\n        title: Main\n        file: repos/e2b-dev/runtime@{sha}:packages/envd/main.go#L40-88\n      - id: b\n        title: Loose\n        file: notes.go\n        commit: abcdef0\n");
        let course = parse_course(&yaml, &resolve).unwrap();
        crate::course::validate_data(&course.engine, &course.data_json).unwrap();
        let data: Value = serde_json::from_str(&course.data_json).unwrap();
        let lesson = &data["chapters"][0]["lessons"][0];
        assert_eq!(
            lesson["file"],
            json!(format!("{base}repos/e2b-dev/runtime/packages/envd/main.go"))
        );
        assert_eq!(lesson["commit"], sha);
        assert_eq!(lesson["lines"], json!([40, 88]));

        let relativize = |path: &str| path.strip_prefix(&base).unwrap_or(path).to_string();
        let written = render_course("T", "reading", &course.data_json, &relativize).unwrap();
        assert!(written.contains(&format!(
            "file: repos/e2b-dev/runtime@{sha}:packages/envd/main.go\n"
        )));
        // A file in no repository keeps its commit as a key of its own.
        assert!(written.contains("file: notes.go\n    commit: abcdef0\n"));
        let again = parse_course(&written, &resolve).unwrap();
        let normalized = |raw: &str| serde_json::from_str::<Value>(raw).unwrap();
        assert_eq!(normalized(&again.data_json), normalized(&course.data_json));
        std::fs::remove_dir_all(folder).ok();
    }

    #[test]
    fn a_comparison_lesson_round_trips_with_its_parts() {
        let folder = crate::mentor_store::testing::temp_dir("compare");
        std::fs::create_dir_all(folder.join("repos/e2b-dev/runtime/.git")).unwrap();
        let base = format!("{}/", folder.display());
        let resolve = |path: &str| Ok(format!("{base}{path}"));
        let sha = "3f2a9c1e3f2a9c1e3f2a9c1e3f2a9c1e3f2a9c1e";
        let yaml = format!("title: T\nchapters:\n  - title: C\n    lessons:\n      - id: restore\n        title: Restoring a sandbox\n        compare:\n          - label: E2B\n            file: repos/e2b-dev/runtime@{sha}:packages/orchestrator/restore.go#L40-88\n            note: Starts from a snapshot file.\n          - label: Cube\n            file: repos/cube/src/restore.rs#L3-9\n          - label: Spec\n            document: 'virtio#2.6 Virtqueues'\n");
        let course = parse_course(&yaml, &resolve).unwrap();
        crate::course::validate_data(&course.engine, &course.data_json).unwrap();
        let data: Value = serde_json::from_str(&course.data_json).unwrap();
        let parts = &data["chapters"][0]["lessons"][0]["compare"];
        assert_eq!(
            parts[0]["file"],
            json!(format!(
                "{base}repos/e2b-dev/runtime/packages/orchestrator/restore.go"
            ))
        );
        assert_eq!(parts[0]["commit"], sha);
        assert_eq!(parts[0]["lines"], json!([40, 88]));
        assert_eq!(parts[0]["note"], "Starts from a snapshot file.");
        assert_eq!(
            parts[1]["file"],
            json!(format!("{base}repos/cube/src/restore.rs"))
        );
        assert_eq!(parts[1].get("commit"), None);
        assert_eq!(parts[2]["document"], "virtio");
        assert_eq!(parts[2]["section"], "2.6 Virtqueues");

        let relativize = |path: &str| path.strip_prefix(&base).unwrap_or(path).to_string();
        let written = render_course("T", "reading", &course.data_json, &relativize).unwrap();
        assert!(
            written.contains(&format!(
                "    compare:\n    - label: E2B\n      file: repos/e2b-dev/runtime@{sha}:packages/orchestrator/restore.go\n      lines:\n"
            )),
            "{written}"
        );
        assert!(written.contains("    - label: Cube\n      file: repos/cube/src/restore.rs\n"));
        assert!(written.contains(
            "    - label: Spec\n      document: virtio\n      section: 2.6 Virtqueues\n"
        ));
        let again = parse_course(&written, &resolve).unwrap();
        let normalized = |raw: &str| serde_json::from_str::<Value>(raw).unwrap();
        assert_eq!(normalized(&again.data_json), normalized(&course.data_json));
        // Course JSON from courses.write resolves parts the same way.
        let raw =
            json!({"chapters": [{"title": "C", "lessons": [{"id": "x", "title": "X", "compare": [
                {"label": "A", "file": format!("repos/e2b-dev/runtime@{}:a.go#L1-2", &sha[..7])},
                {"label": "B", "document": "d#Intro"}
            ]}]}]})
            .to_string();
        let data: Value =
            serde_json::from_str(&resolve_lesson_files(&raw, &resolve).unwrap()).unwrap();
        let parts = &data["chapters"][0]["lessons"][0]["compare"];
        assert_eq!(
            parts[0]["file"],
            json!(format!("{base}repos/e2b-dev/runtime/a.go"))
        );
        assert_eq!(parts[0]["commit"], &sha[..7]);
        assert_eq!(parts[1]["section"], "Intro");
        std::fs::remove_dir_all(folder).ok();
    }

    #[test]
    fn course_json_from_a_mentor_may_use_folder_paths_and_pins() {
        let raw = r#"{"chapters":[{"title":"C","lessons":[{"id":"a","title":"A","file":"repos/fc@0123abc:src/vmm.rs#L3-9"},{"id":"b","title":"B","file":"/abs/x.pdf","pages":[1,2]},{"id":"c","title":"C","document":"d"}]}]}"#;
        let data: Value =
            serde_json::from_str(&resolve_lesson_files(raw, &resolve).unwrap()).unwrap();
        let lessons = &data["chapters"][0]["lessons"];
        assert_eq!(lessons[0]["file"], "/m/x/repos/fc/src/vmm.rs");
        assert_eq!(lessons[0]["commit"], "0123abc");
        assert_eq!(lessons[0]["lines"], json!([3, 9]));
        assert_eq!(lessons[1]["file"], "/abs/x.pdf");
        assert_eq!(lessons[2].get("file"), None);
    }

    #[test]
    fn a_pin_is_a_commit_id_on_a_file() {
        let bad = |lesson: &str| {
            let raw = format!(r#"{{"chapters":[{{"title":"C","lessons":[{lesson}]}}]}}"#);
            crate::course::validate_data("reading", &raw).unwrap_err()
        };
        assert!(bad(r#"{"id":"a","title":"A","file":"/x.go","commit":"xyz"}"#).contains("commit"));
        assert!(bad(r#"{"id":"a","title":"A","file":"/x.go","commit":"abc"}"#).contains("commit"));
        assert!(
            bad(r#"{"id":"a","title":"A","document":"d","commit":"abcdef0"}"#).contains("commit")
        );
        assert_eq!(pinned("repos/x@nothex:a.go"), None);
        assert_eq!(
            pinned("repos/x@ABCDEF0:a.go"),
            Some(("repos/x/a.go".into(), "abcdef0".into()))
        );
    }

    #[test]
    fn a_build_course_and_bad_courses() {
        let yaml = "title: Build\nsteps:\n  - id: s1\n    title: One\n    summary: S\n    file: main.rs\n    before: ''\n    after: \"fn main() {}\\n\"\n    explanation: E\n";
        let course = parse_course(yaml, &resolve).unwrap();
        assert_eq!(course.engine, "build-your-own");
        crate::course::validate_data(&course.engine, &course.data_json).unwrap();
        assert!(parse_course("title: x\nchapters: 3", &resolve).is_err());
        assert!(parse_course("chapters: []", &resolve).is_err());
        assert!(
            parse_course("schemaVersion: 9\ntitle: x\nchapters: []", &resolve)
                .unwrap_err()
                .contains("newer")
        );
        assert!(parse_course(
            "title: x\nchapters:\n  - title: c\n    lessons:\n      - id: a\n        title: t\n        file: a#Q1\n",
            &resolve
        )
        .is_err());
    }

    #[test]
    fn a_canvas_is_an_excalidraw_file_with_loci_metadata() {
        let data = r#"{"elements":[{"id":"e"}],"appState":{},"files":{}}"#;
        let meta = CanvasMeta {
            title: Some("Overview".into()),
            tags: vec!["kvm".into()],
            created_at: Some(1_793_491_200_000),
            updated_at: Some(5),
        };
        let text = render_canvas(&meta, data).unwrap();
        let file: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(file["type"], "excalidraw");
        assert_eq!(file["loci"]["title"], "Overview");
        let (read, read_data) = parse_canvas(&text).unwrap();
        assert_eq!(read, meta);
        assert_eq!(
            serde_json::from_str::<Value>(&read_data).unwrap(),
            serde_json::from_str::<Value>(data).unwrap()
        );
    }

    #[test]
    fn mentor_json_is_ordered_and_keeps_unknown_keys() {
        let map =
            parse_mentor(r#"{"zeta":1,"name":"A","id":"abc-1","schemaVersion":1,"avatar":"nova"}"#)
                .unwrap();
        let text = render_mentor(&map).unwrap();
        assert!(text.starts_with("{\n  \"schemaVersion\": 1,\n  \"id\": \"abc-1\",\n  \"name\": \"A\",\n  \"avatar\": \"nova\",\n  \"zeta\": 1\n}"));
        assert!(parse_mentor(r#"{"name":"x"}"#).is_err());
        assert!(parse_mentor(r#"{"id":"../x"}"#).is_err());
        assert!(mentor_is_newer(
            &parse_mentor(r#"{"id":"a","schemaVersion":2}"#).unwrap()
        ));
    }
}
