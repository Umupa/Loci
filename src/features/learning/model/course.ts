import { invoke } from "@tauri-apps/api/core";

export const COURSE_FENCE = "loci-course";
export const DIFF_FENCE = "loci-diff";
export type CourseEngine = "build-your-own" | "domain-navigation";
export type LearningStatus = "untouched" | "learning" | "mastered";
export type CourseStep = {
  id: string; title: string; summary: string; file: string;
  before: string; after: string; explanation: string; runCommand?: string;
};
export type CourseConcept = {
  id: string; title: string; content: string; prerequisites: string[];
  leadsTo: string[]; simulationHtml?: string;
};
export type CourseData =
  | { engine: "build-your-own"; steps: CourseStep[] }
  | { engine: "domain-navigation"; learningPath: string[]; canvasId?: string; concepts: CourseConcept[] };
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
function ids(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array.`);
  const list = value.map((item) => id(item, label));
  if (new Set(list).size !== list.length) throw new Error(`${label} contains duplicate ids.`);
  return list;
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
  if (engine !== "domain-navigation") throw new Error(`Unknown course engine: ${String(engine)}.`);
  if (!Array.isArray(raw.concepts) || raw.concepts.length === 0) throw new Error("A domain-navigation course needs a non-empty concepts array.");
  const concepts = raw.concepts.map((value, index): CourseConcept => {
    const concept = object(value, `Concept ${index + 1}`);
    const label = `Concept ${index + 1}`;
    return {
      id: id(concept.id, `${label} id`), title: string(concept.title, `${label} title`),
      content: string(concept.content, `${label} content`, true),
      prerequisites: ids(concept.prerequisites, `${label} prerequisites`), leadsTo: ids(concept.leadsTo, `${label} leadsTo`),
      ...(concept.simulationHtml !== undefined ? { simulationHtml: optionalString(concept.simulationHtml, `${label} simulationHtml`) } : {}),
    };
  });
  const knownIds = new Set(concepts.map((concept) => concept.id));
  if (knownIds.size !== concepts.length) throw new Error("Course concepts contain duplicate ids.");
  const learningPath = ids(raw.learningPath, "learningPath");
  for (const target of learningPath) if (!knownIds.has(target)) throw new Error(`learningPath references unknown concept: ${target}.`);
  for (const concept of concepts) {
    for (const target of [...concept.prerequisites, ...concept.leadsTo]) {
      if (!knownIds.has(target)) throw new Error(`${concept.id} references unknown concept: ${target}.`);
      if (target === concept.id) throw new Error(`${concept.id} cannot reference itself.`);
    }
  }
  const storedCanvas = optionalString(raw.canvasId, "canvasId");
  if (canvasId && storedCanvas && canvasId !== storedCanvas) throw new Error("canvas-id does not match the course body's canvasId.");
  const canvas = canvasId ?? storedCanvas;
  return { engine, concepts, learningPath, ...(canvas ? { canvasId: canvas } : {}) };
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
    const data = parseCourseData(fields.engine, json, canvasId);
    return { course: { id: courseId, title, engine: data.engine, data, ...(data.engine === "domain-navigation" && data.canvasId ? { canvasId: data.canvasId } : {}) } };
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

export function courseItems(data: CourseData): { id: string; title: string }[] {
  if (data.engine === "build-your-own") return data.steps;
  const byId = new Map(data.concepts.map((concept) => [concept.id, concept]));
  const pathIds = new Set(data.learningPath);
  return [...data.learningPath.map((id) => byId.get(id)!), ...data.concepts.filter((concept) => !pathIds.has(concept.id))];
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
