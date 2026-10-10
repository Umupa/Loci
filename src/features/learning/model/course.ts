import { invoke } from "@tauri-apps/api/core";

export const COURSE_FENCE = "loci-course";
export const DIFF_FENCE = "loci-diff";
/**
 * A reading course is chapters of lessons, each naming what to read: a
 * document in the agent's library or a file on disk. It holds no text of its
 * own. A build-your-own course is a sequence of code steps.
 */
export type CourseEngine = "build-your-own" | "reading";
export type LearningStatus = "untouched" | "learning" | "mastered";
export type CourseStep = {
  id: string; title: string; summary: string; file: string;
  before: string; after: string; explanation: string; runCommand?: string;
};
export type CourseLesson = {
  id: string; title: string;
  /** A document in the agent's library, and optionally the heading to start at. */
  document?: string; section?: string;
  /** Or a file on disk, such as a PDF, and optionally its first and last page. */
  file?: string; pages?: [number, number];
};
export type CourseChapter = { title: string; lessons: CourseLesson[] };
export type CourseData =
  | { engine: "build-your-own"; steps: CourseStep[] }
  | { engine: "reading"; chapters: CourseChapter[]; canvasId?: string };
export type ParsedCourse = { id: string; title: string; engine: CourseEngine; canvasId?: string; data: CourseData };
export type CourseWithProgress = { id: string; agentId: string; title: string; updatedAt: number; data: CourseData; progress: Map<string, LearningStatus> };
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
export function parseCourseData(engine: unknown, value: unknown, canvasId?: string): CourseData {
  const raw = object(value, "Course body");
  if (raw.engine !== undefined && raw.engine !== engine) throw new Error("Course body engine does not match metadata.");
  if (engine === "build-your-own") {
    if (!Array.isArray(raw.steps) || raw.steps.length === 0) throw new Error("A build-your-own course needs a non-empty steps array.");
    const steps = raw.steps.map((value, index): CourseStep => {
      const step = object(value, `Step ${index + 1}`);
      const label = `Step ${index + 1}`;
      return {
        id: id(step.id, `${label} id`), title: string(step.title, `${label} title`),
        summary: string(step.summary, `${label} summary`), file: string(step.file, `${label} file`),
        before: string(step.before, `${label} before`, true), after: string(step.after, `${label} after`, true),
        explanation: string(step.explanation, `${label} explanation`, true),
        ...(step.runCommand !== undefined ? { runCommand: optionalString(step.runCommand, `${label} runCommand`) } : {}),
      };
    });
    if (new Set(steps.map((step) => step.id)).size !== steps.length) throw new Error("Course steps contain duplicate ids.");
    return { engine, steps };
  }
  if (engine === "domain-navigation") throw new Error("This course was written in an earlier format. Ask the agent to write it again.");
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
  const storedCanvas = optionalString(raw.canvasId, "canvasId");
  if (canvasId && storedCanvas && canvasId !== storedCanvas) throw new Error("canvas-id does not match the course body's canvasId.");
  const canvas = canvasId ?? storedCanvas;
  return { engine, chapters, ...(canvas ? { canvasId: canvas } : {}) };
}

function lesson(value: unknown, label: string): CourseLesson {
  const raw = object(value, label);
  const base = { id: id(raw.id, `${label} id`), title: string(raw.title, `${label} title`) };
  const document = optionalString(raw.document, `${label} document`);
  const file = optionalString(raw.file, `${label} file`);
  if ((document === undefined) === (file === undefined)) throw new Error(`${label} must name exactly one of document or file.`);
  if (document !== undefined) {
    if (!/^[\p{L}\p{N}_-]{1,80}$/u.test(document)) throw new Error(`${label} document must be a document id.`);
    if (raw.pages !== undefined) throw new Error(`${label}: pages belong to a file.`);
    const section = optionalString(raw.section, `${label} section`);
    return { ...base, document, ...(section ? { section } : {}) };
  }
  if (raw.section !== undefined) throw new Error(`${label}: section belongs to a document.`);
  if (!/^(?:\/|[A-Za-z]:[\\/])/.test(file!)) throw new Error(`${label} file must be an absolute path.`);
  if (raw.pages === undefined) return { ...base, file };
  const pages = raw.pages;
  if (!Array.isArray(pages) || pages.length !== 2 || !pages.every((page) => Number.isSafeInteger(page) && page > 0) || pages[1] < pages[0]) throw new Error(`${label} pages must be [first, last].`);
  return { ...base, file, pages: [pages[0], pages[1]] };
}

export function parseCourse(source: string): CourseParseResult {
  try {
    const { fields, body } = frontMatter(source, COURSE_FENCE);
    const courseId = id(fields.id, "Course id");
    const title = string(fields.title, "Course title");
    if ([...title].length > 200) throw new Error("Course title must be at most 200 characters.");
    const canvasId = optionalString(fields["canvas-id"], "canvas-id");
    let json: unknown;
    try { json = JSON.parse(body.replace(/\n---[ \t]*\n?$/, "").trim()); }
    catch { throw new Error("loci-course body must be valid JSON."); }
    // Chapters of things to read is what a course is; only code steps say otherwise.
    const data = parseCourseData(fields.engine ?? "reading", json, canvasId);
    return { course: { id: courseId, title, engine: data.engine, data, ...(data.engine === "reading" && data.canvasId ? { canvasId: data.canvasId } : {}) } };
  } catch (cause) { return { error: errorText(cause) }; }
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
  return data.engine === "build-your-own" ? data.steps : data.chapters.flatMap((chapter) => chapter.lessons);
}

export async function loadCourse(courseId: string, agentId: string): Promise<CourseWithProgress | null> {
  const [rawValue, progressValue] = await Promise.all([
    invoke<unknown>("course_get", { id: courseId, agentId }),
    invoke<unknown>("course_progress_get", { courseId, agentId }),
  ]);
  if (rawValue === null) return null;
  const raw = object(rawValue, "Stored course");
  if (raw.id !== courseId || raw.agentId !== agentId) throw new Error("The stored course belongs to a different conversation.");
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
  return { id: courseId, agentId, title, updatedAt: raw.updatedAt, data, progress };
}

export const OPEN_COURSE_EVENT = "loci:open-course";
export type OpenCourseDetail = { courseId: string; agentId: string; title: string; sourceSessionId?: string };
export function openCourse(detail: OpenCourseDetail) {
  window.dispatchEvent(new CustomEvent<OpenCourseDetail>(OPEN_COURSE_EVENT, { detail }));
}
export const NAVIGATE_CONCEPT_EVENT = "loci:navigate-concept";
export type NavigateConceptDetail = { courseId: string; conceptId: string; canvasId?: string; agentId?: string };
