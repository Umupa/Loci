import { courseItems, lessonPlanned, type CourseLesson, type CourseWithProgress, type LearningStatus } from "../../learning/model/course";

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
export function nextLesson(course: Pick<CourseWithProgress, "data" | "progress"> & { bodies?: Set<string> }, activeId?: string | null): { id: string; title: string } | undefined {
  // A planned lesson has nothing to read yet.
  const bodies = course.bodies;
  const items = courseItems(course.data).filter((item) => !bodies || !lessonPlanned({ bodies }, item));
  const status = (id: string): LearningStatus => course.progress.get(id) ?? "untouched";
  const active = activeId ? items.find((item) => item.id === activeId) : undefined;
  if (active && status(active.id) !== "mastered") return active;
  const begun = items.find((item) => status(item.id) === "learning");
  if (begun) return begun;
  let lastRead = -1;
  items.forEach((item, at) => { if (status(item.id) === "mastered") lastRead = at; });
  return items.slice(lastRead + 1).find((item) => status(item.id) === "untouched") ?? items.find((item) => status(item.id) === "untouched");
}

/**
 * A course's title without the ordinal a mentor sometimes starts it with
 * ("一、", "2.", "(3)"): the path already shows the order. Only for display;
 * the course keeps its title.
 */
export function withoutOrdinal(title: string): string {
  const shown = title.replace(/^\s*(?:[一二三四五六七八九十百]+\s*[、.．]|\d{1,3}\s*(?:[、．)）]|\.(?!\d))|[(（]\d{1,3}[)）])\s*/u, "");
  return shown.trim() ? shown : title;
}

/** What a lesson reads: a source, code shown in place, or a comparison. */
export type LessonKind = "source" | "code" | "compare";

export function lessonKind(lesson: Pick<CourseLesson, "compare" | "file" | "pages">): LessonKind {
  if (lesson.compare) return "compare";
  // A PDF on disk is a source read in the original; any other file is code.
  if (lesson.file && !lesson.pages && !/\.pdf$/i.test(lesson.file)) return "code";
  return "source";
}

/** How far a course is read, as its marker on the path draws it. */
export function courseState(read: number, total: number): LearningStatus {
  return total > 0 && read >= total ? "mastered" : read > 0 ? "learning" : "untouched";
}
