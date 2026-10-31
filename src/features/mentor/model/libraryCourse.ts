import { courseItems, type CourseWithProgress, type LearningStatus } from "../../learning/model/course";

/** The four kinds of things the library column shows, one at a time. */
export const LIBRARY_SEGMENTS = ["courses", "sources", "notes", "files"] as const;
export type LibrarySegment = (typeof LIBRARY_SEGMENTS)[number];

export function isLibrarySegment(value: unknown): value is LibrarySegment {
  return typeof value === "string" && (LIBRARY_SEGMENTS as readonly string[]).includes(value);
}

export type CourseProgressSummary = { read: number; total: number };

/** How far through a course the reader is: lessons read out of all of them. */
export function courseProgress(course: Pick<CourseWithProgress, "data" | "progress">): CourseProgressSummary {
  const items = courseItems(course.data);
  return { read: items.filter((item) => course.progress.get(item.id) === "mastered").length, total: items.length };
}

/**
 * The lesson to continue with, in course order: the open lesson while it is
 * unread, else one already begun, else the first unread one after the last
 * read lesson (or anywhere). Nothing when every lesson is read. The order is
 * a suggestion; every lesson stays open to read.
 */
export function nextLesson(course: Pick<CourseWithProgress, "data" | "progress">, activeId?: string | null): { id: string; title: string } | undefined {
  const items = courseItems(course.data);
  const status = (id: string): LearningStatus => course.progress.get(id) ?? "untouched";
  const active = activeId ? items.find((item) => item.id === activeId) : undefined;
  if (active && status(active.id) !== "mastered") return active;
  const begun = items.find((item) => status(item.id) === "learning");
  if (begun) return begun;
  let lastRead = -1;
  items.forEach((item, at) => { if (status(item.id) === "mastered") lastRead = at; });
  return items.slice(lastRead + 1).find((item) => status(item.id) === "untouched") ?? items.find((item) => status(item.id) === "untouched");
}
