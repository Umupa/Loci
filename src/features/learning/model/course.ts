import { transport } from "../../../platform/transport";
import { rosterSettled } from "../../agents/model/mentorStore";
import { isCommit, parseCodeRef } from "./codeRef";

export { isCommit };

export const COURSE_FENCE = "loci-course";
export const DIFF_FENCE = "loci-diff";
/**
 * A course is chapters of lessons. A lesson's text is the mentor's own,
 * written to its folder; the document in the library or file on disk a
 * lesson names is its source. A lesson with neither is planned.
 */
export type CourseEngine = "reading";
export type LearningStatus = "untouched" | "learning" | "mastered";
export type CourseLesson = {
  id: string; title: string;
  /** A document in the agent's library, and optionally the heading to start at. */
  document?: string; section?: string;
  /** Or a file on disk, such as a PDF, and optionally its first and last page. */
  file?: string; pages?: [number, number];
  /** For a source file, which is shown in place: its first and last line. */
  lines?: [number, number];
  /** For a file in a git checkout: the commit the lesson reads it at. */
  commit?: string;
  /**
   * A comparison lesson: the same mechanism in 2–4 places, read one under
   * another. It names no document or file of its own.
   */
  compare?: ComparePart[];
};
/** One place a comparison reads: a file's lines (maybe pinned), a document's section, or pages of a PDF source or PDF file, with the mentor's optional guide note. */
export type ComparePart = {
  label: string; note?: string;
  document?: string; section?: string; pages?: [number, number];
  file?: string; lines?: [number, number]; commit?: string;
};
export const COMPARE_PARTS = { min: 2, max: 4, label: 60, note: 2000 } as const;
export type CourseChapter = { title: string; lessons: CourseLesson[] };
export type CourseData = { engine: "reading"; chapters: CourseChapter[] };
export type ParsedCourse = { id: string; title: string; engine: CourseEngine; data: CourseData; bodies?: Record<string, LessonInput> };
export type CourseWithProgress = {
  id: string; agentId: string; title: string; updatedAt: number; data: CourseData; progress: Map<string, LearningStatus>;
  /** The lessons that have their own text. */
  bodies: Set<string>;
};
/** A lesson's text written with its course: Markdown, or an absolute path to a Markdown file. */
export type LessonInput = { body: string; path?: never } | { path: string; body?: never };
export type CourseParseResult = { course: ParsedCourse; error?: never } | { course?: never; error: string };
export type DiffSpec = { id: string; title: string; file: string; before: string; after: string; runCommand?: string };
export type DiffParseResult = { diff: DiffSpec; error?: never } | { diff?: never; error: string };

function object(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label} must be an object.`);
  return value as Record<string, unknown>;
}
function string(value: unknown, label: string, allowEmpty = false): string {
  if (typeof value !== "string" || (!allowEmpty && !value.trim())) throw new Error(`${label} must be ${allowEmpty ? "a string" : "a non-empty string"}.`);
  return value;
}
function id(value: unknown, label: string): string {
  const text = string(value, label);
  if (!/^[A-Za-z0-9_-]+$/.test(text)) throw new Error(`${label} must contain only letters, digits, hyphens or underscores.`);
  return text;
}
function optionalString(value: unknown, label: string): string | undefined {
  return value === undefined ? undefined : string(value, label);
}
function errorText(cause: unknown): string { return cause instanceof Error ? cause.message : String(cause); }

function frontMatter(source: string, fence: string) {
  const text = source.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
  const front = text.match(/^\s*---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
  if (!front) throw new Error(`${fence} requires front matter with id and title.`);
  const fields: Record<string, string> = Object.create(null);
  for (const line of front[1].split("\n")) {
    if (!line.trim() || line.trim().startsWith("#")) continue;
    const field = line.match(/^\s*([A-Za-z][A-Za-z-]*)\s*:\s*(.*?)\s*$/);
    if (!field) throw new Error(`${fence} metadata must use one field per line.`);
    const key = field[1].toLowerCase();
    if (Object.prototype.hasOwnProperty.call(fields, key)) throw new Error(`${fence} has duplicate metadata: ${key}.`);
    fields[key] = field[2].replace(/^(["'])(.*)\1$/, "$2");
  }
  return { fields, body: text.slice(front[0].length) };
}

/** Validate both generated JSON and stored JSON at their shared trust boundary. */
export function parseCourseData(engine: unknown, value: unknown): CourseData {
  const raw = object(value, "Course body");
  if (raw.engine !== undefined && raw.engine !== engine) throw new Error("Course body engine does not match metadata.");
  if (engine === "domain-navigation" || engine === "build-your-own") throw new Error("This course was written in an earlier format. Ask the agent to write it again.");
  if (engine !== "reading") throw new Error(`Unknown course engine: ${String(engine)}.`);
  if (!Array.isArray(raw.chapters) || raw.chapters.length === 0) throw new Error("A course needs a non-empty chapters array.");
  const chapters = raw.chapters.map((value, index): CourseChapter => {
    const chapter = object(value, `Chapter ${index + 1}`);
    const label = `Chapter ${index + 1}`;
    if (!Array.isArray(chapter.lessons) || chapter.lessons.length === 0) throw new Error(`${label} needs a non-empty lessons array.`);
    return { title: string(chapter.title, `${label} title`), lessons: chapter.lessons.map((value, at) => lesson(value, `${label} lesson ${at + 1}`)) };
  });
  const lessonIds = chapters.flatMap((chapter) => chapter.lessons.map((entry) => entry.id));
  if (new Set(lessonIds).size !== lessonIds.length) throw new Error("Course lessons contain duplicate ids.");
  return { engine, chapters };
}

function lesson(value: unknown, label: string): CourseLesson {
  const raw = object(value, label);
  const base = { id: id(raw.id, `${label} id`), title: string(raw.title, `${label} title`) };
  if (raw.compare !== undefined) return { ...base, compare: compareParts(raw, label) };
  const document = optionalString(raw.document, `${label} document`);
  let file = optionalString(raw.file, `${label} file`);
  let pinned: string | undefined;
  let fragmentLines: [number, number] | undefined;
  // A mentor's folder resolves relative files and the pin shorthand
  // repos/<repo>@<sha>:path#L12-40; other places keep absolute paths.
  if (file !== undefined && !/^(?:\/|[A-Za-z]:[\\/])/.test(file)) {
    const ref = parseCodeRef(file);
    if (ref.path.split(/[\\/]/).some((part) => part === ".." || part === "")) throw new Error(`${label} file must be an absolute path or a path inside the mentor's folder.`);
    file = ref.path;
    pinned = ref.commit;
    fragmentLines = ref.lines;
  }
  if (document !== undefined && file !== undefined) throw new Error(`${label} names both a document and a file; its source is one of them.`);
  if (document === undefined && file === undefined) {
    // Only a title: the lesson has its own text, or is planned.
    for (const field of ["section", "pages", "lines", "commit"]) if (raw[field] !== undefined) throw new Error(`${label}: ${field} belongs to a document or file.`);
    return base;
  }
  const range = (value: unknown, name: string): [number, number] => {
    if (!Array.isArray(value) || value.length !== 2 || !value.every((n) => Number.isSafeInteger(n) && n > 0) || value[1] < value[0]) throw new Error(`${label} ${name} must be [first, last].`);
    return [value[0], value[1]];
  };
  if (document !== undefined) {
    // A PDF source names a page (`document: paper#p7` or `pages: [7, 9]`); any other
    // fragment is a heading, as `document: kvm#4.1 KVM_CREATE_VM` always was.
    const hash = document.indexOf("#");
    const documentId = (hash < 0 ? document : document.slice(0, hash)).trim();
    const fragment = hash < 0 ? undefined : document.slice(hash + 1).trim();
    if (!/^[\p{L}\p{N}_-]{1,80}$/u.test(documentId)) throw new Error(`${label} document must be a document id.`);
    if (raw.lines !== undefined) throw new Error(`${label}: lines belong to a file.`);
    if (raw.commit !== undefined) throw new Error(`${label}: commit belongs to a file.`);
    const shorthand = fragment ? /^p([1-9]\d{0,5})(?:-([1-9]\d{0,5}))?$/.exec(fragment) : null;
    const explicit = raw.pages === undefined ? undefined : range(raw.pages, "pages");
    const pages = explicit ?? (shorthand ? [Number(shorthand[1]), shorthand[2] ? Number(shorthand[2]) : Number(shorthand[1])] as [number, number] : undefined);
    const section = typeof raw.section === "string" ? raw.section.trim() || undefined : optionalString(raw.section, `${label} section`);
    const heading = section ?? (fragment && !shorthand ? fragment : undefined);
    if (heading && pages) throw new Error(`${label}: name a section or pages, not both.`);
    return { ...base, document: documentId, ...(heading ? { section: heading } : {}), ...(pages ? { pages } : {}) };
  }
  if (raw.section !== undefined) throw new Error(`${label}: section belongs to a document.`);
  if (raw.pages !== undefined && raw.lines !== undefined) throw new Error(`${label}: name pages or lines, not both.`);
  const commit = optionalString(raw.commit, `${label} commit`) ?? pinned;
  const lines = raw.lines ?? (raw.pages === undefined ? fragmentLines : undefined);
  if (commit !== undefined && !isCommit(commit)) throw new Error(`${label} commit must be a commit id (7 to 40 hex digits).`);
  const pin = commit ? { commit: commit.toLowerCase() } : {};
  if (lines !== undefined) return { ...base, file, lines: range(lines, "lines"), ...pin };
  if (raw.pages === undefined) return { ...base, file, ...pin };
  return { ...base, file, pages: range(raw.pages, "pages"), ...pin };
}

function compareParts(raw: Record<string, unknown>, label: string): ComparePart[] {
  if (["document", "file", "section", "lines", "pages", "commit"].some((key) => raw[key] !== undefined)) throw new Error(`${label}: a comparison names its places in compare, not document or file.`);
  if (!Array.isArray(raw.compare) || raw.compare.length < COMPARE_PARTS.min || raw.compare.length > COMPARE_PARTS.max) throw new Error(`${label}: compare must list 2 to 4 parts.`);
  const labels = new Set<string>();
  return raw.compare.map((value, index): ComparePart => {
    const at = `${label} part ${index + 1}`;
    const part = object(value, at);
    const name = string(part.label, `${at} label`).trim();
    if ([...name].length > COMPARE_PARTS.label) throw new Error(`${at} label must be at most ${COMPARE_PARTS.label} characters.`);
    if (labels.has(name.toLowerCase())) throw new Error(`${at} label ${name} is used twice.`);
    labels.add(name.toLowerCase());
    const note = optionalString(part.note, `${at} note`);
    if (note !== undefined && [...note].length > COMPARE_PARTS.note) throw new Error(`${at} note must be at most ${COMPARE_PARTS.note} characters.`);
    // A part is read as a lesson of its own would be.
    const place = lesson({ ...part, id: "part", title: name, label: undefined, note: undefined, compare: undefined }, at);
    const { id: _id, title: _title, ...where } = place;
    if (where.document === undefined && where.file === undefined) throw new Error(`${at} must name a document or a file.`);
    return { label: name, ...where, ...(note !== undefined ? { note } : {}) };
  });
}

/** The places a lesson reads: its parts for a comparison, else itself. */
export function lessonPlaces(lesson: CourseLesson): (ComparePart | CourseLesson)[] {
  return lesson.compare ?? [lesson];
}

export function parseCourse(source: string): CourseParseResult {
  try {
    const { fields, body } = frontMatter(source, COURSE_FENCE);
    const courseId = id(fields.id, "Course id");
    const title = string(fields.title, "Course title");
    if ([...title].length > 200) throw new Error("Course title must be at most 200 characters.");
    let json: unknown;
    try { json = JSON.parse(body.replace(/\n---[ \t]*\n?$/, "").trim()); }
    catch { throw new Error("loci-course body must be valid JSON."); }
    const data = parseCourseData(fields.engine ?? "reading", json);
    return { course: { id: courseId, title, engine: data.engine, data } };
  } catch (cause) { return { error: errorText(cause) }; }
}

/**
 * A fence with front matter and no body points at a course the agent already
 * saved with `courses.write`, instead of carrying the course itself.
 */
export function parseCourseLink(source: string): { id: string; title: string } | null {
  try {
    const { fields, body } = frontMatter(source, COURSE_FENCE);
    if (body.trim()) return null;
    return { id: id(fields.id, "Course id"), title: string(fields.title, "Course title") };
  } catch { return null; }
}

/** What a lesson may weigh: a long chapter, not a book. */
export const LESSON_MAX = 512 * 1024;

/**
 * The `courses.write` input: the fence's front matter fields plus its JSON
 * body, as one object. A lesson may carry its text as `body`, or as
 * `bodyPath` (an absolute path to a Markdown file); the text is written to
 * its own file and never into the course.
 */
export function parseCourseInput(input: Record<string, unknown>): ParsedCourse {
  const courseId = id(input.id, "id");
  const title = string(input.title, "title");
  if ([...title].length > 200) throw new Error("title must be at most 200 characters.");
  const { id: _id, title: _title, engine, ...body } = input;
  const bodies: Record<string, LessonInput> = {};
  const chapters = Array.isArray(body.chapters) ? body.chapters.map((chapter) => {
    if (!chapter || typeof chapter !== "object" || !Array.isArray((chapter as { lessons?: unknown }).lessons)) return chapter;
    const lessons = (chapter as { lessons: unknown[] }).lessons.map((entry) => {
      if (!entry || typeof entry !== "object") return entry;
      const { body: text, bodyPath, ...lesson } = entry as Record<string, unknown>;
      const lessonId = typeof lesson.id === "string" ? lesson.id : undefined;
      if (text !== undefined && bodyPath !== undefined) throw new Error(`Lesson ${lessonId ?? "?"}: give body or bodyPath, not both.`);
      if (lessonId && text !== undefined) {
        if (typeof text !== "string" || !text.trim()) throw new Error(`Lesson ${lessonId}: body must be non-empty Markdown.`);
        if (text.length > LESSON_MAX) throw new Error(`Lesson ${lessonId}: body must be at most 512 KB; split it.`);
        bodies[lessonId] = { body: text };
      } else if (lessonId && bodyPath !== undefined) {
        if (typeof bodyPath !== "string" || !/^(?:\/|[A-Za-z]:[\\/])/.test(bodyPath)) throw new Error(`Lesson ${lessonId}: bodyPath must be an absolute path to a Markdown file.`);
        bodies[lessonId] = { path: bodyPath };
      }
      return lesson;
    });
    return { ...(chapter as object), lessons };
  }) : body.chapters;
  const data = parseCourseData(engine ?? "reading", { ...body, ...(chapters !== undefined ? { chapters } : {}) });
  return { id: courseId, title, engine: data.engine, data, ...(Object.keys(bodies).length ? { bodies } : {}) };
}

/** Delimiter lines are structural; every byte inside the code sections is kept. */
export function parseDiff(source: string): DiffParseResult {
  try {
    const { fields, body } = frontMatter(source, DIFF_FENCE);
    const beforeMarkers = [...body.matchAll(/^=== BEFORE ===[ \t]*(?:\n|$)/gm)];
    const afterMarkers = [...body.matchAll(/^=== AFTER ===[ \t]*(?:\n|$)/gm)];
    if (beforeMarkers.length !== 1 || afterMarkers.length !== 1) throw new Error("loci-diff needs exactly one BEFORE and one AFTER delimiter line.");
    const beforeMarker = beforeMarkers[0], afterMarker = afterMarkers[0];
    if (body.slice(0, beforeMarker.index).trim() || afterMarker.index! < beforeMarker.index! + beforeMarker[0].length) throw new Error("loci-diff sections must be ordered BEFORE, then AFTER.");
    const before = body.slice(beforeMarker.index! + beforeMarker[0].length, afterMarker.index);
    return { diff: {
      id: id(fields.id, "Diff id"), title: string(fields.title, "Diff title"), file: fields.file === undefined ? "file" : string(fields.file, "Diff file"),
      before: /^\(empty file\)(?:\n)?$/.test(before) ? "" : before,
      after: body.slice(afterMarker.index! + afterMarker[0].length),
      ...(fields.run !== undefined ? { runCommand: string(fields.run, "Diff run command") } : {}),
    } };
  } catch (cause) { return { error: errorText(cause) }; }
}

/** Everything to work through, in the order shown: that order is the order to study in. */
export function courseItems(data: CourseData): { id: string; title: string }[] {
  return data.chapters.flatMap((chapter) => chapter.lessons);
}

export async function loadCourse(courseId: string, agentId: string): Promise<CourseWithProgress | null> {
  const [rawValue, progressValue] = await Promise.all([
    transport.call<unknown>("course_get", { id: courseId, agentId }),
    transport.call<unknown>("course_progress_get", { courseId, agentId }),
  ]);
  if (rawValue === null) return null;
  const raw = object(rawValue, "Stored course");
  if (raw.id !== courseId || raw.agentId !== agentId) throw new Error("The stored course belongs to a different conversation.");
  const bodies = new Set(Array.isArray(raw.bodies) ? raw.bodies.filter((entry): entry is string => typeof entry === "string") : []);
  const title = string(raw.title, "Stored course title");
  if (typeof raw.updatedAt !== "number" || !Number.isSafeInteger(raw.updatedAt) || raw.updatedAt < 0) throw new Error("Stored course updatedAt must be a valid timestamp.");
  let json: unknown;
  try { json = JSON.parse(string(raw.dataJson, "Stored course dataJson")); }
  catch { throw new Error("Stored course data is not valid JSON."); }
  const data = parseCourseData(raw.engine, json);
  const knownIds = new Set(courseItems(data).map((item) => item.id));
  if (!Array.isArray(progressValue)) throw new Error("Stored course progress must be an array.");
  const progress = new Map<string, LearningStatus>();
  for (const value of progressValue) {
    const item = object(value, "Progress item");
    const itemId = id(item.itemId, "Progress item id");
    if (!knownIds.has(itemId) || progress.has(itemId)) throw new Error(`Stored progress references an unknown or duplicate item: ${itemId}.`);
    if (item.status !== "untouched" && item.status !== "learning" && item.status !== "mastered") throw new Error(`Invalid learning status for ${itemId}.`);
    progress.set(itemId, item.status);
  }
  return { id: courseId, agentId, title, updatedAt: raw.updatedAt, data, progress, bodies };
}

/** Fired on `window` after a course is saved or deleted; no courseId means all of the owner's courses. */
export const COURSES_CHANGED_EVENT = "loci:courses-changed";
export type CourseChangedDetail = { agentId: string; courseId?: string };

export type CourseSummary = {
  id: string; agentId: string; engine: CourseEngine; title: string; updatedAt: number;
  itemCount: number; masteredCount: number;
};

function coursesChanged(detail: CourseChangedDetail) {
  if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent<CourseChangedDetail>(COURSES_CHANGED_EVENT, { detail }));
}

export async function saveCourse(agentId: string, course: ParsedCourse): Promise<void> {
  // A new mentor must have its folder before its first course is saved.
  await rosterSettled();
  await transport.call("course_upsert", { course: { id: course.id, agentId, engine: course.engine, title: course.title, dataJson: JSON.stringify(course.data), ...(course.bodies ? { bodies: course.bodies } : {}) } });
  coursesChanged({ agentId, courseId: course.id });
}

/** Every stored course; callers keep the ones owned by a current agent. */
export function loadCourseSummaries(): Promise<CourseSummary[]> {
  return transport.call<CourseSummary[]>("course_list_all");
}

/** Fired on `window` when a lesson's status changes, from any pane or command. */
export const PROGRESS_EVENT = "loci:course-progress";
export type ProgressDetail = { courseId: string; agentId: string; itemId: string; status: LearningStatus };

/** Records how far the user is with one lesson, and tells every open view. */
export async function setLessonStatus(courseId: string, agentId: string, itemId: string, status: LearningStatus): Promise<void> {
  await transport.call("course_progress_set", { courseId, agentId, itemId, status });
  if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent<ProgressDetail>(PROGRESS_EVENT, { detail: { courseId, agentId, itemId, status } }));
}

/**
 * Starts a course over: every lesson read or begun goes back to unread, and
 * every view of it is told. Highlights and notes are kept.
 */
export async function resetCourseProgress(courseId: string, agentId: string): Promise<void> {
  const course = await loadCourse(courseId, agentId);
  if (!course) throw new Error("This course is no longer there.");
  for (const [itemId, status] of course.progress) {
    if (status !== "untouched") await setLessonStatus(courseId, agentId, itemId, "untouched");
  }
  coursesChanged({ agentId, courseId });
}

/** One course, or with no id every course the agent owns. */
export async function deleteCourse(agentId: string, id?: string): Promise<void> {
  await transport.call("course_delete", { agentId, id: id ?? null });
  coursesChanged({ agentId, ...(id === undefined ? {} : { courseId: id }) });
}

export const OPEN_COURSE_EVENT = "loci:open-course";
export type OpenCourseDetail = { courseId: string; agentId: string; title: string; sourceSessionId?: string; itemId?: string; openRequest?: number };
export function openCourse(detail: OpenCourseDetail) {
  window.dispatchEvent(new CustomEvent<OpenCourseDetail>(OPEN_COURSE_EVENT, { detail }));
}

/** A lesson's text as it is now, and the file it is kept in. */
export type LessonText = { courseId: string; lessonId: string; body: string; path: string; updatedAt: number };

/** A lesson's own text, or null when it has none: it is planned, or read from its source. */
export function loadLessonText(agentId: string, courseId: string, lessonId: string): Promise<LessonText | null> {
  return transport.call<LessonText | null>("course_lesson_get", { agentId, courseId, lessonId });
}

/** Writes one lesson's text, leaving the rest of its course as it is. */
export async function saveLessonText(agentId: string, courseId: string, lessonId: string, lesson: LessonInput): Promise<LessonText> {
  await rosterSettled();
  const saved = await transport.call<LessonText>("course_lesson_set", { agentId, courseId, lessonId, lesson });
  coursesChanged({ agentId, courseId });
  return saved;
}

/** Whether a lesson names something to read beside its text. */
export function lessonHasSource(lesson: CourseLesson): boolean {
  return lesson.document !== undefined || lesson.file !== undefined || lesson.compare !== undefined;
}

/** A lesson only titled so far: no text of its own and nothing to read. */
export function lessonPlanned(course: Partial<Pick<CourseWithProgress, "bodies">>, lesson: CourseLesson): boolean {
  return !course.bodies?.has(lesson.id) && !lessonHasSource(lesson);
}

/** The key a reader is asked to show a place in a lesson's text under. */
export function lessonPlaceKey(courseId: string, lessonId: string): string {
  return `lesson:${courseId}/${lessonId}`;
}

/** The lesson a file is the text of, when it is `courses/<course>/<lesson>.md` in a mentor's folder. */
export function lessonOfFile(folder: string | undefined, path: string): { courseId: string; lessonId: string } | null {
  if (!folder) return null;
  const base = folder.replace(/[\\/]+$/, "");
  const rest = path.startsWith(`${base}/`) || path.startsWith(`${base}\\`) ? path.slice(base.length + 1).replace(/\\/g, "/") : null;
  const match = rest ? /^courses\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_-]+)\.md$/.exec(rest) : null;
  return match ? { courseId: match[1], lessonId: match[2] } : null;
}
