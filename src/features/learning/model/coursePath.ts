import { invoke } from "@tauri-apps/api/core";
import { COURSES_CHANGED_EVENT, type CourseChangedDetail, type CourseSummary } from "./course";

/**
 * A mentor's learning path: its short courses in order, each with optional
 * prerequisites (`after`). Shown, never enforced: every course stays open.
 * Kept as `courses/_path.yaml` in the mentor's folder.
 */
export type PathCourse = { id: string; after?: string[]; title?: string };
export type LearningPath = { title?: string; courses: PathCourse[] };
/** The path file's id among courses. */
export const PATH_ID = "_path";

/** The path as read, or none; `error` when the file is broken (the last good path is kept). */
export type PathRead = { path: LearningPath | null; file?: string; updatedAt?: number; error?: string | null };

export function loadCoursePath(agentId: string): Promise<PathRead> {
  return invoke<PathRead>("course_path_read", { agentId });
}

/** Replaces the path; every view of the mentor's courses hears of it. */
export async function saveCoursePath(agentId: string, path: LearningPath): Promise<PathRead> {
  const saved = await invoke<PathRead>("course_path_write", { agentId, path });
  if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent<CourseChangedDetail>(COURSES_CHANGED_EVENT, { detail: { agentId, courseId: PATH_ID } }));
  return saved;
}

/** One course on the path, as the library shows it. */
export type PathStep = {
  id: string; title: string; position: number;
  /** Not written yet: the path names it ahead of time. */
  planned: boolean;
  read: number; total: number;
  /** Its prerequisites, and those not read to the end yet (a hint, never a lock). */
  after: { id: string; title: string }[];
  pending: { id: string; title: string }[];
};

/** The path's courses with their progress, and the mentor's courses that are not on it. */
export function pathSteps(path: LearningPath, courses: readonly CourseSummary[]): { steps: PathStep[]; others: CourseSummary[] } {
  const byId = new Map(courses.map((course) => [course.id, course]));
  const titleOf = (id: string) => byId.get(id)?.title ?? path.courses.find((entry) => entry.id === id)?.title ?? id;
  const finished = (id: string) => { const course = byId.get(id); return !!course && course.itemCount > 0 && course.masteredCount >= course.itemCount; };
  const steps = path.courses.map((entry, index): PathStep => {
    const course = byId.get(entry.id);
    const after = (entry.after ?? []).map((id) => ({ id, title: titleOf(id) }));
    return {
      id: entry.id, title: course?.title ?? entry.title ?? entry.id, position: index + 1, planned: !course,
      read: course?.masteredCount ?? 0, total: course?.itemCount ?? 0,
      after, pending: after.filter((item) => !finished(item.id)),
    };
  });
  const onPath = new Set(path.courses.map((entry) => entry.id));
  return { steps, others: courses.filter((course) => !onPath.has(course.id)) };
}

/** A path as a mentor or a file gives it, checked before it is saved. */
export function parsePathInput(input: unknown): LearningPath {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("A learning path is an object with courses");
  const raw = input as Record<string, unknown>;
  if (!Array.isArray(raw.courses) || !raw.courses.length) throw new Error("A learning path needs courses: a list of { id, after? }");
  const courses = raw.courses.map((entry, index): PathCourse => {
    const item = typeof entry === "string" ? { id: entry } : entry;
    if (!item || typeof item !== "object" || Array.isArray(item)) throw new Error(`Course ${index + 1} must be a course id or { id, after }`);
    const value = item as Record<string, unknown>;
    if (typeof value.id !== "string" || !/^[A-Za-z0-9_-]{1,80}$/.test(value.id) || value.id === PATH_ID) throw new Error(`Course ${index + 1}: id must be a course id`);
    const after = value.after === undefined ? undefined : Array.isArray(value.after) ? value.after : [value.after];
    if (after && !after.every((id) => typeof id === "string")) throw new Error(`${value.id}: after is a list of course ids`);
    return { ...value, id: value.id, ...(after?.length ? { after: after as string[] } : {}), ...(typeof value.title === "string" && value.title.trim() ? { title: value.title.trim() } : {}) } as PathCourse;
  });
  return { ...raw, ...(typeof raw.title === "string" && raw.title.trim() ? { title: raw.title.trim() } : {}), courses } as LearningPath;
}
