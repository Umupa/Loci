//! Course ids are chosen by an agent, just like agent-document ids. Structure
//! and progress share that agent scope; another agent can reuse the same slug.
//!
//! A reading course holds no text of its own: it is chapters of lessons, each
//! naming a document in the agent's library or a file on disk to read. A
//! build-your-own course keeps its code steps.

use std::collections::HashSet;

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use tauri::State;

use crate::mentor_store::{self, index, paths::Kind, MentorCtx};
use crate::session_store::{now_millis, validate_id, SessionStore};

const TITLE_MAX: usize = 200;
const DATA_MAX: usize = 50_000_000;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Course {
    pub id: String,
    pub agent_id: String,
    pub engine: String,
    pub title: String,
    pub data_json: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseUpsert {
    pub id: String,
    pub agent_id: String,
    pub engine: String,
    pub title: String,
    pub data_json: String,
}

/// One row of the Courses list: enough to show it without its structure.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseSummary {
    pub id: String,
    pub agent_id: String,
    pub engine: String,
    pub title: String,
    pub updated_at: i64,
    pub item_count: usize,
    pub mastered_count: usize,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseProgressItem {
    pub item_id: String,
    pub status: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Step {
    id: String,
    title: String,
    summary: String,
    file: String,
    before: String,
    after: String,
    explanation: String,
    #[serde(
        default,
        deserialize_with = "optional_text",
        skip_serializing_if = "Option::is_none"
    )]
    run_command: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct BuildCourse {
    steps: Vec<Step>,
}

/// What to read: a document in the agent's library, optionally from one of
/// its headings, or a file such as a PDF, optionally a range of its pages.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Lesson {
    id: String,
    title: String,
    #[serde(
        default,
        deserialize_with = "optional_text",
        skip_serializing_if = "Option::is_none"
    )]
    document: Option<String>,
    #[serde(
        default,
        deserialize_with = "optional_text",
        skip_serializing_if = "Option::is_none"
    )]
    section: Option<String>,
    #[serde(
        default,
        deserialize_with = "optional_text",
        skip_serializing_if = "Option::is_none"
    )]
    file: Option<String>,
    #[serde(
        default,
        deserialize_with = "page_range",
        skip_serializing_if = "Option::is_none"
    )]
    pages: Option<[u32; 2]>,
    /// For a source file read in place: its first and last line.
    #[serde(
        default,
        deserialize_with = "page_range",
        skip_serializing_if = "Option::is_none"
    )]
    lines: Option<[u32; 2]>,
}

#[derive(Serialize, Deserialize)]
struct Chapter {
    title: String,
    lessons: Vec<Lesson>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReadingCourse {
    chapters: Vec<Chapter>,
    #[serde(
        default,
        deserialize_with = "optional_text",
        skip_serializing_if = "Option::is_none"
    )]
    canvas_id: Option<String>,
}

// A missing optional field is fine; a supplied null or non-string is not a
// valid course field. This matches the fence parser's external contract.
fn optional_text<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<String>, D::Error> {
    String::deserialize(deserializer).map(Some)
}

fn page_range<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<[u32; 2]>, D::Error> {
    <[u32; 2]>::deserialize(deserializer).map(Some)
}

pub fn ensure_courses_table(conn: &Connection) -> rusqlite::Result<()> {
    // The first courses table named its two kinds in a CHECK, which SQLite
    // cannot alter. Move its rows into tables without it. The old tables are
    // renamed first so that dropping them cascades into nothing kept.
    let old: Option<String> = conn
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'courses'",
            [],
            |row| row.get(0),
        )
        .optional()?;
    let rebuild = old.is_some_and(|sql| sql.contains("CHECK (engine IN"));
    if rebuild {
        conn.execute_batch(
            "ALTER TABLE course_progress RENAME TO course_progress_old;
             ALTER TABLE courses RENAME TO courses_old;",
        )?;
    }
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS courses (
           agent_id TEXT NOT NULL,
           id TEXT NOT NULL,
           engine TEXT NOT NULL,
           title TEXT NOT NULL,
           data_json TEXT NOT NULL,
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL,
           PRIMARY KEY (agent_id, id)
         );
         CREATE TABLE IF NOT EXISTS course_progress (
           agent_id TEXT NOT NULL,
           course_id TEXT NOT NULL,
           item_id TEXT NOT NULL,
           status TEXT NOT NULL CHECK (status IN ('untouched', 'learning', 'mastered')),
           PRIMARY KEY (agent_id, course_id, item_id),
           FOREIGN KEY (agent_id, course_id) REFERENCES courses(agent_id, id) ON DELETE CASCADE
         );",
    )?;
    if rebuild {
        conn.execute_batch(
            "INSERT INTO courses SELECT agent_id, id, engine, title, data_json, created_at, updated_at FROM courses_old;
             INSERT INTO course_progress SELECT agent_id, course_id, item_id, status FROM course_progress_old;
             DROP TABLE course_progress_old;
             DROP TABLE courses_old;",
        )?;
    }
    conn.execute_batch(
        "CREATE INDEX IF NOT EXISTS courses_agent_updated_idx
           ON courses (agent_id, updated_at DESC, id);",
    )
}

// ---------------------------------------------------------------------------
// A mentor whose courses are in its folder: courses/<id>.yaml, with progress
// in lesson_progress (which outlives a file's brief absence).

fn course_from_row(row: index::Row) -> Option<Course> {
    Some(Course {
        engine: row.meta.get("engine")?.as_str()?.to_string(),
        data_json: row.body?,
        id: row.id,
        agent_id: row.agent_id,
        title: row.title,
        created_at: row.created_at,
        updated_at: row.updated_at,
    })
}

fn file_courses(conn: &Connection, ctx: &MentorCtx) -> Result<Vec<Course>, String> {
    let mut out = Vec::new();
    for row in index::list(conn, &ctx.agent, &[Kind::Course]).map_err(|e| e.to_string())? {
        if let Some(full) =
            index::get(conn, &ctx.agent, Kind::Course, &row.id).map_err(|e| e.to_string())?
        {
            out.extend(course_from_row(full));
        }
    }
    Ok(out)
}

fn file_course(conn: &Connection, ctx: &MentorCtx, id: &str) -> Result<Option<Course>, String> {
    Ok(mentor_store::current(conn, ctx, Kind::Course, id)?.and_then(course_from_row))
}

fn file_progress(
    conn: &Connection,
    agent_id: &str,
    course_id: &str,
) -> rusqlite::Result<Vec<CourseProgressItem>> {
    let mut statement = conn.prepare(
        "SELECT item_id, status FROM lesson_progress WHERE agent_id = ?1 AND course_id = ?2 ORDER BY item_id",
    )?;
    let rows = statement.query_map(params![agent_id, course_id], |row| {
        Ok(CourseProgressItem {
            item_id: row.get(0)?,
            status: row.get(1)?,
        })
    })?;
    rows.collect()
}

fn file_save_course(
    conn: &Connection,
    ctx: &MentorCtx,
    course: &CourseUpsert,
) -> Result<Course, String> {
    validate_id(&course.id, "course")?;
    require_text(&course.title, "title")?;
    if course.title.chars().count() > TITLE_MAX {
        return Err("A course title must be at most 200 characters".into());
    }
    let (data_json, ids) = validate_data(&course.engine, &course.data_json)?;
    let title = course.title.trim();
    let existing = file_course(conn, ctx, &course.id)?;
    if let Some(saved) = &existing {
        if saved.engine == course.engine && saved.title == title && saved.data_json == data_json {
            return Ok(saved.clone());
        }
    }
    let relativize = |path: &str| ctx.relativize(path);
    let text =
        crate::mentor_store::format::render_course(title, &course.engine, &data_json, &relativize)?;
    let row = mentor_store::write_content(conn, ctx, Kind::Course, &course.id, &text)?;
    // Progress of lessons the revision removed goes, as it always has.
    let engine_changed = existing
        .as_ref()
        .is_some_and(|saved| saved.engine != course.engine);
    for progress in file_progress(conn, &ctx.agent, &course.id).map_err(|e| e.to_string())? {
        if engine_changed || !ids.contains(&progress.item_id) {
            conn.execute(
                "DELETE FROM lesson_progress WHERE agent_id = ?1 AND course_id = ?2 AND item_id = ?3",
                params![ctx.agent, course.id, progress.item_id],
            )
            .map_err(|e| e.to_string())?;
        }
    }
    course_from_row(row).ok_or_else(|| "The saved course could not be read back".into())
}

fn file_set_progress(
    conn: &Connection,
    ctx: &MentorCtx,
    course_id: &str,
    item_id: &str,
    status: &str,
) -> Result<(), String> {
    let course = file_course(conn, ctx, course_id)?.ok_or("Course not found")?;
    let (_, ids) = validate_data(&course.engine, &course.data_json)?;
    if !ids.contains(item_id) {
        return Err(format!("Course item not found: {item_id}"));
    }
    conn.execute(
        "INSERT INTO lesson_progress (agent_id, course_id, item_id, status, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(agent_id, course_id, item_id) DO UPDATE SET status = excluded.status, updated_at = excluded.updated_at",
        params![ctx.agent, course_id, item_id, status, now_millis()],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// Every course in a mentor's folder, as the cross-mentor list shows them.
fn file_summaries(conn: &Connection) -> Result<Vec<CourseSummary>, String> {
    let mut out = Vec::new();
    for row in index::all(conn, Kind::Course).map_err(|e| e.to_string())? {
        let Some(course) = course_from_row(row) else {
            continue;
        };
        let ids = validate_data(&course.engine, &course.data_json)
            .map(|(_, ids)| ids)
            .unwrap_or_default();
        let mastered = file_progress(conn, &course.agent_id, &course.id)
            .map_err(|e| e.to_string())?
            .into_iter()
            .filter(|p| p.status == "mastered" && ids.contains(&p.item_id))
            .count();
        out.push(CourseSummary {
            item_count: item_count(&course.engine, &course.data_json),
            mastered_count: mastered,
            id: course.id,
            agent_id: course.agent_id,
            engine: course.engine,
            title: course.title,
            updated_at: course.updated_at,
        });
    }
    Ok(out)
}

#[tauri::command(async)]
pub fn course_list(
    store: State<'_, SessionStore>,
    agent_id: String,
) -> Result<Vec<Course>, String> {
    validate_id(&agent_id, "agent")?;
    let conn = store.lock_conn()?;
    if let Some(ctx) = mentor_store::ctx_for(&conn, &agent_id)? {
        return file_courses(&conn, &ctx);
    }
    list_courses(&conn, &agent_id).map_err(|e| e.to_string())
}

/// Every course, newest first. Owners are not checked here: the caller keeps
/// the ones whose owner is still an agent.
#[tauri::command(async)]
pub fn course_list_all(store: State<'_, SessionStore>) -> Result<Vec<CourseSummary>, String> {
    let conn = store.lock_conn()?;
    let mut all = list_summaries(&conn).map_err(|e| e.to_string())?;
    all.extend(file_summaries(&conn)?);
    all.sort_by(|a, b| b.updated_at.cmp(&a.updated_at).then(a.id.cmp(&b.id)));
    Ok(all)
}

/// Removes one course, or with no id every course the agent owns. Progress
/// goes with it.
#[tauri::command(async)]
pub fn course_delete(
    store: State<'_, SessionStore>,
    agent_id: String,
    id: Option<String>,
) -> Result<(), String> {
    validate_id(&agent_id, "agent")?;
    if let Some(id) = &id {
        validate_id(id, "course")?;
    }
    let conn = store.lock_conn()?;
    if let Some(ctx) = mentor_store::ctx_for(&conn, &agent_id)? {
        // Without an id the mentor is being deleted: its folder stays.
        if let Some(id) = &id {
            mentor_store::remove_content(&conn, &ctx, Kind::Course, id)?;
        }
        return Ok(());
    }
    delete_courses(&conn, &agent_id, id.as_deref()).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn course_get(
    store: State<'_, SessionStore>,
    agent_id: String,
    id: String,
) -> Result<Option<Course>, String> {
    validate_id(&agent_id, "agent")?;
    validate_id(&id, "course")?;
    let conn = store.lock_conn()?;
    if let Some(ctx) = mentor_store::ctx_for(&conn, &agent_id)? {
        return file_course(&conn, &ctx, &id);
    }
    get_course(&conn, &agent_id, &id).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn course_upsert(
    store: State<'_, SessionStore>,
    course: CourseUpsert,
) -> Result<Course, String> {
    validate_id(&course.agent_id, "agent")?;
    let conn = store.lock_conn()?;
    if let Some(ctx) = mentor_store::ctx_for(&conn, &course.agent_id)? {
        return file_save_course(&conn, &ctx, &course);
    }
    save_course(&conn, &course)
}

#[tauri::command(async)]
pub fn course_progress_get(
    store: State<'_, SessionStore>,
    agent_id: String,
    course_id: String,
) -> Result<Vec<CourseProgressItem>, String> {
    validate_id(&agent_id, "agent")?;
    validate_id(&course_id, "course")?;
    let conn = store.lock_conn()?;
    if mentor_store::ctx_for(&conn, &agent_id)?.is_some() {
        return file_progress(&conn, &agent_id, &course_id).map_err(|e| e.to_string());
    }
    get_progress(&conn, &agent_id, &course_id).map_err(|e| e.to_string())
}

#[tauri::command(async)]
pub fn course_progress_set(
    store: State<'_, SessionStore>,
    agent_id: String,
    course_id: String,
    item_id: String,
    status: String,
) -> Result<(), String> {
    let conn = store.lock_conn()?;
    if let Some(ctx) = mentor_store::ctx_for(&conn, &agent_id)? {
        validate_id(&course_id, "course")?;
        validate_id(&item_id, "course item")?;
        if !matches!(status.as_str(), "untouched" | "learning" | "mastered") {
            return Err(format!("Unknown learning status: {status}"));
        }
        return file_set_progress(&conn, &ctx, &course_id, &item_id, &status);
    }
    set_progress(&conn, &agent_id, &course_id, &item_id, &status)
}

fn require_text(value: &str, label: &str) -> Result<(), String> {
    if value.trim().is_empty() {
        return Err(format!("Course {label} cannot be empty"));
    }
    Ok(())
}

fn item_ids<'a>(ids: impl Iterator<Item = &'a str>) -> Result<HashSet<String>, String> {
    let mut unique = HashSet::new();
    for id in ids {
        validate_id(id, "course item")?;
        if !unique.insert(id.to_owned()) {
            return Err(format!("Duplicate course item id: {id}"));
        }
    }
    if unique.is_empty() {
        return Err("A course needs at least one item".into());
    }
    Ok(unique)
}

/// A document id as the library accepts it: letters of any script, digits,
/// hyphens and underscores.
fn validate_id_text(id: &str) -> Result<(), String> {
    if id.is_empty()
        || id.chars().count() > 80
        || !id
            .chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '_')
    {
        return Err(format!("Not a document id: {id}"));
    }
    Ok(())
}

fn require_object_items(value: &serde_json::Value, field: &str) -> Result<(), String> {
    let items = value[field]
        .as_array()
        .ok_or_else(|| format!("Course {field} must be an array"))?;
    if items.iter().any(|item| !item.is_object()) {
        return Err(format!("Course {field} must contain objects"));
    }
    Ok(())
}

/// Typed deserialization keeps progress and other unknown fields out of the
/// stored structure. Item ids are the contract used to preserve progress.
pub(crate) fn validate_data(engine: &str, raw: &str) -> Result<(String, HashSet<String>), String> {
    if raw.len() > DATA_MAX {
        return Err("Course data is too large".into());
    }
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|e| format!("Invalid course JSON: {e}"))?;
    if !value.is_object() {
        return Err("Course data must be a JSON object".into());
    }
    if value.get("engine").is_some_and(|value| value != engine) {
        return Err("Course data engine does not match the course engine".into());
    }
    match engine {
        "build-your-own" => {
            require_object_items(&value, "steps")?;
            let data: BuildCourse = serde_json::from_value(value)
                .map_err(|e| format!("Invalid build-your-own course: {e}"))?;
            let ids = item_ids(data.steps.iter().map(|step| step.id.as_str()))?;
            for step in &data.steps {
                require_text(&step.title, "step title")?;
                require_text(&step.summary, "step summary")?;
                require_text(&step.file, "step file")?;
                if let Some(command) = &step.run_command {
                    require_text(command, "run command")?;
                }
            }
            Ok((
                serde_json::to_string(&data).map_err(|e| e.to_string())?,
                ids,
            ))
        }
        "reading" => {
            require_object_items(&value, "chapters")?;
            for chapter in value["chapters"].as_array().into_iter().flatten() {
                require_object_items(chapter, "lessons")?;
            }
            let data: ReadingCourse = serde_json::from_value(value)
                .map_err(|e| format!("Invalid reading course: {e}"))?;
            let lessons = || data.chapters.iter().flat_map(|chapter| &chapter.lessons);
            let ids = item_ids(lessons().map(|lesson| lesson.id.as_str()))?;
            if let Some(canvas) = &data.canvas_id {
                require_text(canvas, "canvas id")?;
            }
            for chapter in &data.chapters {
                require_text(&chapter.title, "chapter title")?;
                if chapter.lessons.is_empty() {
                    return Err(format!("Chapter {} has no lessons", chapter.title));
                }
            }
            for lesson in lessons() {
                require_text(&lesson.title, "lesson title")?;
                match (&lesson.document, &lesson.file) {
                    (Some(document), None) => {
                        validate_id_text(document)?;
                        if lesson.lines.is_some() {
                            return Err(format!("Lesson {}: lines belong to a file", lesson.id));
                        }
                        // A document kept as a PDF opens at its pages.
                        if lesson.section.is_some() && lesson.pages.is_some() {
                            return Err(format!(
                                "Lesson {}: name a section or pages, not both",
                                lesson.id
                            ));
                        }
                    }
                    (None, Some(file)) => {
                        if !std::path::Path::new(file).is_absolute() {
                            return Err(format!(
                                "Lesson {}: file must be an absolute path",
                                lesson.id
                            ));
                        }
                        if lesson.section.is_some() {
                            return Err(format!(
                                "Lesson {}: section belongs to a document",
                                lesson.id
                            ));
                        }
                    }
                    _ => {
                        return Err(format!(
                            "Lesson {} must name exactly one of document or file",
                            lesson.id
                        ))
                    }
                }
                if lesson
                    .pages
                    .is_some_and(|[from, to]| from == 0 || to < from)
                {
                    return Err(format!("Lesson {}: pages must be [first, last]", lesson.id));
                }
                if lesson
                    .lines
                    .is_some_and(|[from, to]| from == 0 || to < from)
                {
                    return Err(format!("Lesson {}: lines must be [first, last]", lesson.id));
                }
                if lesson.pages.is_some() && lesson.lines.is_some() {
                    return Err(format!(
                        "Lesson {}: name pages or lines, not both",
                        lesson.id
                    ));
                }
            }
            Ok((
                serde_json::to_string(&data).map_err(|e| e.to_string())?,
                ids,
            ))
        }
        "domain-navigation" => Err(
            "This course was written in an earlier format. Ask the agent to write it again.".into(),
        ),
        _ => Err(format!("Unknown course engine: {engine}")),
    }
}

fn list_courses(conn: &Connection, agent_id: &str) -> rusqlite::Result<Vec<Course>> {
    let mut statement = conn.prepare(
        "SELECT id, agent_id, engine, title, data_json, created_at, updated_at
         FROM courses WHERE agent_id = ?1 ORDER BY updated_at DESC, id",
    )?;
    let rows = statement.query_map([agent_id], read_course)?;
    rows.collect()
}

fn list_summaries(conn: &Connection) -> rusqlite::Result<Vec<CourseSummary>> {
    let mut statement = conn.prepare(
        "SELECT c.id, c.agent_id, c.engine, c.title, c.data_json, c.updated_at,
                (SELECT COUNT(*) FROM course_progress p
                  WHERE p.agent_id = c.agent_id AND p.course_id = c.id AND p.status = 'mastered')
         FROM courses c
         WHERE NOT EXISTS (SELECT 1 FROM mentors m WHERE m.id = c.agent_id AND m.migrated_at IS NOT NULL)
         ORDER BY c.updated_at DESC, c.id",
    )?;
    let rows = statement.query_map([], |row| {
        let engine: String = row.get(2)?;
        let data: String = row.get(4)?;
        Ok(CourseSummary {
            id: row.get(0)?,
            agent_id: row.get(1)?,
            item_count: item_count(&engine, &data),
            engine,
            title: row.get(3)?,
            updated_at: row.get(5)?,
            mastered_count: row.get::<_, i64>(6)?.max(0) as usize,
        })
    })?;
    rows.collect()
}

/// Lessons or steps in stored data; stored data was validated on save.
fn item_count(engine: &str, data_json: &str) -> usize {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(data_json) else {
        return 0;
    };
    match engine {
        "build-your-own" => value["steps"].as_array().map_or(0, Vec::len),
        _ => value["chapters"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|chapter| chapter["lessons"].as_array().map_or(0, Vec::len))
            .sum(),
    }
}

fn delete_courses(conn: &Connection, agent_id: &str, id: Option<&str>) -> rusqlite::Result<()> {
    // Progress rows cascade from their course.
    match id {
        Some(id) => conn.execute(
            "DELETE FROM courses WHERE agent_id = ?1 AND id = ?2",
            params![agent_id, id],
        )?,
        None => conn.execute("DELETE FROM courses WHERE agent_id = ?1", [agent_id])?,
    };
    Ok(())
}

fn get_course(conn: &Connection, agent_id: &str, id: &str) -> rusqlite::Result<Option<Course>> {
    conn.query_row(
        "SELECT id, agent_id, engine, title, data_json, created_at, updated_at
         FROM courses WHERE agent_id = ?1 AND id = ?2",
        params![agent_id, id],
        read_course,
    )
    .optional()
}

fn read_course(row: &rusqlite::Row<'_>) -> rusqlite::Result<Course> {
    Ok(Course {
        id: row.get(0)?,
        agent_id: row.get(1)?,
        engine: row.get(2)?,
        title: row.get(3)?,
        data_json: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}

fn save_course(conn: &Connection, course: &CourseUpsert) -> Result<Course, String> {
    validate_id(&course.agent_id, "agent")?;
    validate_id(&course.id, "course")?;
    require_text(&course.title, "title")?;
    if course.title.chars().count() > TITLE_MAX {
        return Err("A course title must be at most 200 characters".into());
    }
    let (data_json, ids) = validate_data(&course.engine, &course.data_json)?;
    let title = course.title.trim();
    // A revision and pruning removed-item progress are one write. Failed
    // pruning must not leave the new structure with the old progress.
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    let existing = get_course(&tx, &course.agent_id, &course.id).map_err(|e| e.to_string())?;
    if let Some(saved) = &existing {
        if saved.engine == course.engine && saved.title == title && saved.data_json == data_json {
            tx.commit().map_err(|e| e.to_string())?;
            return Ok(saved.clone());
        }
    }
    let now = now_millis();
    let created_at = existing.as_ref().map_or(now, |saved| saved.created_at);
    let updated_at = match &existing {
        Some(saved) => now.max(
            saved
                .updated_at
                .checked_add(1)
                .ok_or("Course timestamp overflow")?,
        ),
        None => now,
    };
    tx.execute(
        "INSERT INTO courses (agent_id, id, engine, title, data_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(agent_id, id) DO UPDATE SET
           engine = excluded.engine, title = excluded.title,
           data_json = excluded.data_json, updated_at = excluded.updated_at",
        params![
            course.agent_id,
            course.id,
            course.engine,
            title,
            data_json,
            created_at,
            updated_at
        ],
    )
    .map_err(|e| e.to_string())?;
    let engine_changed = existing
        .as_ref()
        .is_some_and(|saved| saved.engine != course.engine);
    for progress in get_progress(&tx, &course.agent_id, &course.id).map_err(|e| e.to_string())? {
        if engine_changed || !ids.contains(&progress.item_id) {
            tx.execute(
                "DELETE FROM course_progress WHERE agent_id = ?1 AND course_id = ?2 AND item_id = ?3",
                params![course.agent_id, course.id, progress.item_id],
            )
            .map_err(|e| e.to_string())?;
        }
    }
    let saved = get_course(&tx, &course.agent_id, &course.id)
        .map_err(|e| e.to_string())?
        .ok_or("Saved course is missing")?;
    tx.commit().map_err(|e| e.to_string())?;
    Ok(saved)
}

fn get_progress(
    conn: &Connection,
    agent_id: &str,
    course_id: &str,
) -> rusqlite::Result<Vec<CourseProgressItem>> {
    let mut statement = conn.prepare(
        "SELECT item_id, status FROM course_progress
         WHERE agent_id = ?1 AND course_id = ?2 ORDER BY item_id",
    )?;
    let rows = statement.query_map(params![agent_id, course_id], |row| {
        Ok(CourseProgressItem {
            item_id: row.get(0)?,
            status: row.get(1)?,
        })
    })?;
    rows.collect()
}

fn set_progress(
    conn: &Connection,
    agent_id: &str,
    course_id: &str,
    item_id: &str,
    status: &str,
) -> Result<(), String> {
    validate_id(agent_id, "agent")?;
    validate_id(course_id, "course")?;
    validate_id(item_id, "course item")?;
    if !matches!(status, "untouched" | "learning" | "mastered") {
        return Err(format!("Unknown learning status: {status}"));
    }
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    let course = get_course(&tx, agent_id, course_id)
        .map_err(|e| e.to_string())?
        .ok_or("Course not found")?;
    let (_, ids) = validate_data(&course.engine, &course.data_json)?;
    if !ids.contains(item_id) {
        return Err(format!("Course item not found: {item_id}"));
    }
    tx.execute(
        "INSERT INTO course_progress (agent_id, course_id, item_id, status)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(agent_id, course_id, item_id) DO UPDATE SET status = excluded.status",
        params![agent_id, course_id, item_id, status],
    )
    .map_err(|e| e.to_string())?;
    tx.commit().map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn summaries_count_items_and_mastered_and_delete_cascades() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        ensure_courses_table(&conn).unwrap();
        crate::mentor_store::index::ensure_tables(&conn).unwrap();
        save_course(&conn, &reading("agent-a")).unwrap();
        save_course(&conn, &build("agent-b", &["one", "two", "three"])).unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "pod", "mastered").unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s01", "learning").unwrap();

        let all = list_summaries(&conn).unwrap();
        let a = all
            .iter()
            .find(|course| course.agent_id == "agent-a")
            .unwrap();
        assert_eq!((a.item_count, a.mastered_count), (3, 1));
        let b = all
            .iter()
            .find(|course| course.agent_id == "agent-b")
            .unwrap();
        assert_eq!(
            (b.item_count, b.mastered_count, b.engine.as_str()),
            (3, 0, "build-your-own")
        );

        delete_courses(&conn, "agent-a", Some("agent-loop")).unwrap();
        assert!(get_progress(&conn, "agent-a", "agent-loop")
            .unwrap()
            .is_empty());
        delete_courses(&conn, "agent-b", None).unwrap();
        assert!(list_summaries(&conn).unwrap().is_empty());
    }

    fn build(agent: &str, ids: &[&str]) -> CourseUpsert {
        CourseUpsert {
            id: "agent-loop".into(),
            agent_id: agent.into(),
            engine: "build-your-own".into(),
            title: "Build an agent".into(),
            data_json: json!({"steps": ids.iter().map(|id| json!({
                "id": id, "title": format!("Step {id}"), "summary": "Add a loop",
                "file": "main.py", "before": "", "after": "while True:\n    pass\n",
                "explanation": "", "runCommand": "python main.py"
            })).collect::<Vec<_>>()})
            .to_string(),
        }
    }

    fn reading(agent: &str) -> CourseUpsert {
        CourseUpsert {
            engine: "reading".into(),
            data_json: json!({
                "canvasId": "map-1",
                "chapters": [
                    {"title": "Workloads", "lessons": [
                        {"id": "s01", "title": "Containers", "document": "k8s-containers"},
                        {"id": "pod", "title": "Pod lifecycle", "document": "k8s-pods",
                         "section": "Pod lifecycle"}
                    ]},
                    {"title": "Papers", "lessons": [
                        {"id": "borg", "title": "Borg", "file": "/home/u/borg.pdf",
                         "pages": [1, 12]}
                    ]}
                ]
            })
            .to_string(),
            ..build(agent, &["s01"])
        }
    }

    #[test]
    fn structure_and_progress_survive_reopening_the_store_in_both_engines() {
        let dir = std::env::temp_dir().join(format!("loci-course-{}", uuid::Uuid::new_v4()));
        let path = dir.join("loci.db");
        let saved = {
            let store = SessionStore::open(path.clone()).unwrap();
            let conn = store.lock_conn().unwrap();
            let first = save_course(&conn, &build("agent-a", &["s01", "s02"])).unwrap();
            let second = save_course(&conn, &reading("agent-b")).unwrap();
            set_progress(&conn, "agent-a", "agent-loop", "s01", "mastered").unwrap();
            set_progress(&conn, "agent-b", "agent-loop", "pod", "learning").unwrap();
            (first, second)
        };
        let store = SessionStore::open(path).unwrap();
        let conn = store.lock_conn().unwrap();
        assert_eq!(
            get_course(&conn, "agent-a", "agent-loop").unwrap(),
            Some(saved.0)
        );
        assert_eq!(
            get_course(&conn, "agent-b", "agent-loop").unwrap(),
            Some(saved.1)
        );
        for (agent, item, status) in [
            ("agent-a", "s01", "mastered"),
            ("agent-b", "pod", "learning"),
        ] {
            assert_eq!(
                get_progress(&conn, agent, "agent-loop").unwrap(),
                vec![CourseProgressItem {
                    item_id: item.into(),
                    status: status.into()
                }]
            );
            assert_eq!(list_courses(&conn, agent).unwrap().len(), 1);
        }
        assert!(get_course(&conn, "agent-c", "agent-loop")
            .unwrap()
            .is_none());
        assert!(get_progress(&conn, "agent-c", "agent-loop")
            .unwrap()
            .is_empty());
        drop(conn);
        drop(store);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn revisions_preserve_existing_items_and_prune_removed_items_only_for_their_agent() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let original = save_course(&conn, &build("agent-a", &["s01", "s02"])).unwrap();
        save_course(&conn, &build("agent-b", &["s02"])).unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s01", "mastered").unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s02", "learning").unwrap();
        set_progress(&conn, "agent-b", "agent-loop", "s02", "mastered").unwrap();

        let revised = save_course(&conn, &build("agent-a", &["s01", "s03"])).unwrap();
        assert_eq!(revised.created_at, original.created_at);
        assert!(revised.updated_at > original.updated_at);
        assert_eq!(
            get_progress(&conn, "agent-a", "agent-loop").unwrap(),
            vec![CourseProgressItem {
                item_id: "s01".into(),
                status: "mastered".into()
            }]
        );
        assert_eq!(
            get_progress(&conn, "agent-b", "agent-loop").unwrap()[0].status,
            "mastered"
        );
        let unchanged = save_course(&conn, &build("agent-a", &["s01", "s03"])).unwrap();
        assert_eq!(unchanged, revised);
        // A step and a lesson sharing an id do not share learning semantics.
        save_course(&conn, &reading("agent-a")).unwrap();
        assert!(get_progress(&conn, "agent-a", "agent-loop")
            .unwrap()
            .is_empty());
    }

    #[test]
    fn invalid_course_input_does_not_replace_the_saved_course_or_progress() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let original = save_course(&conn, &build("agent-a", &["s01"])).unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s01", "mastered").unwrap();
        let mut invalid = vec![
            build("agent-a", &[]),
            build("agent-a", &["s01", "s01"]),
            build("agent-a", &["../bad"]),
        ];
        for raw in ["null", "[]", "{broken", r#"{"steps":[{"id":"s01"}]}"#] {
            let mut course = build("agent-a", &["s01"]);
            course.data_json = raw.into();
            invalid.push(course);
        }
        // Serde structs can accept positional arrays; the external format
        // requires an object with a named steps field.
        let mut positional = build("agent-a", &["s01"]);
        let data: serde_json::Value = serde_json::from_str(&positional.data_json).unwrap();
        positional.data_json = json!([data["steps"]]).to_string();
        invalid.push(positional);
        let mut positional_item = build("agent-a", &["s01"]);
        positional_item.data_json = json!({"steps": [[
            "s01", "Step", "Summary", "main.py", "", "", "", "python main.py"
        ]]})
        .to_string();
        invalid.push(positional_item);
        for (field, value) in [
            ("title", ""),
            ("agent", "../other"),
            ("id", "bad/id"),
            ("engine", "unknown"),
        ] {
            let mut course = build("agent-a", &["s01"]);
            match field {
                "title" => course.title = value.into(),
                "agent" => course.agent_id = value.into(),
                "id" => course.id = value.into(),
                _ => course.engine = value.into(),
            }
            invalid.push(course);
        }
        for course in invalid {
            assert!(save_course(&conn, &course).is_err(), "{course:?}");
        }
        assert_eq!(
            get_course(&conn, "agent-a", "agent-loop").unwrap(),
            Some(original)
        );
        assert_eq!(
            get_progress(&conn, "agent-a", "agent-loop").unwrap()[0].status,
            "mastered"
        );
    }

    #[test]
    fn empty_document_sections_allow_whole_document_reading() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        for section in ["", "  "] {
            let mut course = reading("agent-a");
            let mut data: serde_json::Value = serde_json::from_str(&course.data_json).unwrap();
            data["chapters"][0]["lessons"][0]["section"] = json!(section);
            course.data_json = data.to_string();
            assert!(save_course(&conn, &course).is_ok());
        }
    }

    #[test]
    fn course_fields_and_references_are_validated_before_writing() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let mut course = reading("agent-a");
        let base: serde_json::Value = serde_json::from_str(&course.data_json).unwrap();
        for mutation in [
            json!({"chapters": []}),
            json!({"chapters": [{"title": "Empty", "lessons": []}]}),
            json!({"chapters": [{"title": " ", "lessons": [
                {"id": "a", "title": "A", "document": "a"}]}]}),
            json!({"canvasId": null}),
            json!({"canvasId": " "}),
            json!({"engine": "build-your-own"}),
        ] {
            let mut data = base.clone();
            data.as_object_mut()
                .unwrap()
                .extend(mutation.as_object().unwrap().clone());
            course.data_json = data.to_string();
            assert!(save_course(&conn, &course).is_err(), "{mutation}");
        }
        // The first lesson names a document, the last a file.
        for (chapter, field, value) in [
            (0, "id", json!("pod")),
            (0, "document", json!(null)),
            (0, "document", json!("../notes")),
            (0, "file", json!("/home/u/also.pdf")),
            (0, "lines", json!([1, 2])),
            (0, "section", json!(42)),
            (1, "file", json!("borg.pdf")),
            (1, "section", json!("Intro")),
            (1, "pages", json!([3, 2])),
            (1, "pages", json!([0, 2])),
            (1, "pages", json!("1-12")),
            (1, "lines", json!([1, 2])),
        ] {
            let mut data = base.clone();
            data["chapters"][chapter]["lessons"][0][field] = value;
            course.data_json = data.to_string();
            assert!(save_course(&conn, &course).is_err(), "{field}");
        }
        // A document kept as a PDF opens at its pages; pages and a section
        // never name the same place.
        let mut paged = base.clone();
        paged["chapters"][0]["lessons"][0]["pages"] = json!([7, 9]);
        crate::course::validate_data("reading", &paged.to_string()).unwrap();
        paged["chapters"][0]["lessons"][0]["section"] = json!("Intro");
        assert!(crate::course::validate_data("reading", &paged.to_string()).is_err());
        let mut neither = base.clone();
        neither["chapters"][0]["lessons"][0]
            .as_object_mut()
            .unwrap()
            .remove("document");
        course.data_json = neither.to_string();
        assert!(save_course(&conn, &course).is_err());
        course.data_json = base.to_string();
        course.engine = "domain-navigation".into();
        assert!(save_course(&conn, &course)
            .unwrap_err()
            .contains("earlier format"));
        let mut course = build("agent-a", &["s01"]);
        let base: serde_json::Value = serde_json::from_str(&course.data_json).unwrap();
        for (field, value) in [
            ("summary", json!("")),
            ("file", json!(" ")),
            ("after", json!(false)),
            ("runCommand", json!(null)),
        ] {
            let mut data = base.clone();
            data["steps"][0][field] = value;
            course.data_json = data.to_string();
            assert!(save_course(&conn, &course).is_err(), "{field}");
        }
        assert!(list_courses(&conn, "agent-a").unwrap().is_empty());
    }

    #[test]
    fn the_first_courses_table_is_rebuilt_with_its_courses_and_progress() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "PRAGMA foreign_keys = ON;
             CREATE TABLE courses (
               agent_id TEXT NOT NULL, id TEXT NOT NULL,
               engine TEXT NOT NULL CHECK (engine IN ('build-your-own', 'domain-navigation')),
               title TEXT NOT NULL, data_json TEXT NOT NULL,
               created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
               PRIMARY KEY (agent_id, id)
             );
             CREATE TABLE course_progress (
               agent_id TEXT NOT NULL, course_id TEXT NOT NULL, item_id TEXT NOT NULL,
               status TEXT NOT NULL CHECK (status IN ('untouched', 'learning', 'mastered')),
               PRIMARY KEY (agent_id, course_id, item_id),
               FOREIGN KEY (agent_id, course_id) REFERENCES courses(agent_id, id) ON DELETE CASCADE
             );
             CREATE INDEX courses_agent_updated_idx ON courses (agent_id, updated_at DESC, id);
             INSERT INTO courses VALUES ('agent-a', 'old', 'build-your-own', 'Old', '{}', 1, 2);
             INSERT INTO course_progress VALUES ('agent-a', 'old', 's01', 'mastered');",
        )
        .unwrap();
        ensure_courses_table(&conn).unwrap();
        crate::mentor_store::index::ensure_tables(&conn).unwrap();
        ensure_courses_table(&conn).unwrap();
        crate::mentor_store::index::ensure_tables(&conn).unwrap();
        assert_eq!(
            get_progress(&conn, "agent-a", "old").unwrap()[0].status,
            "mastered"
        );
        save_course(&conn, &reading("agent-a")).unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "borg", "learning").unwrap();
        // Progress still goes with its course.
        conn.execute("DELETE FROM courses WHERE id = 'old'", [])
            .unwrap();
        assert!(get_progress(&conn, "agent-a", "old").unwrap().is_empty());
    }

    #[test]
    fn progress_rejects_missing_course_missing_item_and_invalid_status_without_mutation() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let original = save_course(&conn, &build("agent-a", &["s01"])).unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s01", "learning").unwrap();
        for (agent, id, item, status) in [
            ("agent-b", "agent-loop", "s01", "mastered"),
            ("agent-a", "missing", "s01", "mastered"),
            ("agent-a", "agent-loop", "missing", "mastered"),
            ("agent-a", "agent-loop", "s01", "done"),
            ("../agent", "agent-loop", "s01", "mastered"),
            ("agent-a", "agent-loop", "../item", "mastered"),
        ] {
            assert!(set_progress(&conn, agent, id, item, status).is_err());
        }
        assert_eq!(
            get_progress(&conn, "agent-a", "agent-loop").unwrap()[0].status,
            "learning"
        );
        set_progress(&conn, "agent-a", "agent-loop", "s01", "mastered").unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s01", "untouched").unwrap();
        assert_eq!(
            get_progress(&conn, "agent-a", "agent-loop").unwrap()[0].status,
            "untouched"
        );
        assert_eq!(
            get_course(&conn, "agent-a", "agent-loop").unwrap(),
            Some(original)
        );
    }

    #[test]
    fn a_database_failure_rolls_back_structure_revision_and_progress_cleanup() {
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let original = save_course(&conn, &build("agent-a", &["s01", "s02"])).unwrap();
        set_progress(&conn, "agent-a", "agent-loop", "s02", "mastered").unwrap();
        conn.execute_batch(
            "CREATE TRIGGER reject_progress_delete BEFORE DELETE ON course_progress
             BEGIN SELECT RAISE(ABORT, 'injected cleanup failure'); END;",
        )
        .unwrap();
        let error = save_course(&conn, &build("agent-a", &["s01"])).unwrap_err();
        assert!(error.contains("injected cleanup failure"));
        assert_eq!(
            get_course(&conn, "agent-a", "agent-loop").unwrap(),
            Some(original)
        );
        assert_eq!(
            get_progress(&conn, "agent-a", "agent-loop").unwrap()[0].item_id,
            "s02"
        );
    }

    #[test]
    fn json_contract_uses_camel_case_and_structure_cannot_supply_progress() {
        let mut input = serde_json::to_value(json!({
            "id": "test", "agentId": "agent-a", "engine": "build-your-own",
            "title": "Test", "dataJson": build("agent-a", &["s01"]).data_json,
        }))
        .unwrap();
        let mut data: serde_json::Value =
            serde_json::from_str(input["dataJson"].as_str().unwrap()).unwrap();
        data["steps"][0]["status"] = json!("mastered");
        input["dataJson"] = json!(data.to_string());
        let course: CourseUpsert = serde_json::from_value(input).unwrap();
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let saved = save_course(&conn, &course).unwrap();
        assert!(!saved.data_json.contains("status"));
        assert!(get_progress(&conn, "agent-a", "test").unwrap().is_empty());
        let response = serde_json::to_value(saved).unwrap();
        assert_eq!(response["agentId"], "agent-a");
        assert!(response["dataJson"].is_string());
        assert!(response["createdAt"].is_number());
        assert!(response.get("agent_id").is_none());
        assert_eq!(
            serde_json::to_value(CourseProgressItem {
                item_id: "s01".into(),
                status: "mastered".into()
            })
            .unwrap(),
            json!({"itemId": "s01", "status": "mastered"})
        );
    }

    #[test]
    fn a_mentor_with_a_folder_keeps_its_courses_as_yaml_and_progress_outlives_the_file() {
        use crate::mentor_store::testing::{register, temp_dir};
        let store = SessionStore::open_in_memory().unwrap();
        let conn = store.lock_conn().unwrap();
        let folder = temp_dir("courses");
        register(&conn, "agent", &folder);
        let ctx = mentor_store::ctx_for(&conn, "agent").unwrap().unwrap();
        let code = folder.join("repos/fc/src/lib.rs");
        std::fs::create_dir_all(code.parent().unwrap()).unwrap();
        std::fs::write(&code, "fn main() {}\n").unwrap();
        let data = serde_json::json!({"chapters":[{"title":"One","lessons":[
            {"id":"a","title":"A","document":"virtio","section":"Rings"},
            {"id":"b","title":"B","file": code.to_string_lossy(),"lines":[1,1]}]}]});
        let upsert = |data: &serde_json::Value, title: &str| CourseUpsert {
            id: "c1".into(),
            agent_id: "agent".into(),
            engine: "reading".into(),
            title: title.into(),
            data_json: data.to_string(),
        };
        let saved = file_save_course(&conn, &ctx, &upsert(&data, "Sandbox")).unwrap();
        assert_eq!(saved.title, "Sandbox");
        let yaml = std::fs::read_to_string(folder.join("courses/c1.yaml")).unwrap();
        assert!(yaml.contains("file: repos/fc/src/lib.rs"), "{yaml}");
        assert_eq!(file_courses(&conn, &ctx).unwrap().len(), 1);
        let read: serde_json::Value =
            serde_json::from_str(&file_course(&conn, &ctx, "c1").unwrap().unwrap().data_json)
                .unwrap();
        assert_eq!(
            read["chapters"][0]["lessons"][1]["file"],
            code.to_string_lossy().as_ref()
        );

        file_set_progress(&conn, &ctx, "c1", "a", "mastered").unwrap();
        file_set_progress(&conn, &ctx, "c1", "b", "learning").unwrap();
        assert!(file_set_progress(&conn, &ctx, "c1", "zz", "learning").is_err());
        let summaries = file_summaries(&conn).unwrap();
        assert_eq!(
            (summaries[0].item_count, summaries[0].mastered_count),
            (2, 1)
        );

        // A revision that drops a lesson drops its progress.
        let fewer = serde_json::json!({"chapters":[{"title":"One","lessons":[{"id":"a","title":"A","document":"virtio"}]}]});
        file_save_course(&conn, &ctx, &upsert(&fewer, "Sandbox")).unwrap();
        assert_eq!(file_progress(&conn, "agent", "c1").unwrap().len(), 1);

        // The file briefly gone (an editor's save, a checkout) keeps progress.
        std::fs::remove_file(folder.join("courses/c1.yaml")).unwrap();
        assert!(file_course(&conn, &ctx, "c1").unwrap().is_none());
        assert_eq!(file_progress(&conn, "agent", "c1").unwrap().len(), 1);
        std::fs::write(folder.join("courses/c1.yaml"), "title: Edited by hand\nchapters:\n  - title: One\n    lessons:\n      - id: a\n        title: A\n        document: virtio#Rings\n").unwrap();
        let edited = file_course(&conn, &ctx, "c1").unwrap().unwrap();
        assert_eq!(edited.title, "Edited by hand");
        assert_eq!(file_summaries(&conn).unwrap()[0].mastered_count, 1);
        std::fs::remove_dir_all(folder).unwrap();
    }
}
