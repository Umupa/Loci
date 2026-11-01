import type { CourseLesson, CourseWithProgress } from "./course";
import { getReadingDocumentByPath, queryAnnotations } from "./learningStore";
import type { Annotation, AnnotationTarget } from "./types";

/** Highlights on a lesson or a source, and how many of them carry a note. */
export type MarkCount = { highlights: number; notes: number };

export function countMarks(annotations: readonly Annotation[]): MarkCount {
  return { highlights: annotations.length, notes: annotations.filter((entry) => entry.note.trim()).length };
}

const key = (text: string) => text.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
const sameTarget = (a: AnnotationTarget, b: AnnotationTarget) => JSON.stringify(a) === JSON.stringify(b);

/** The place a lesson (or one part of a comparison) reads. */
type Place = Pick<CourseLesson, "document" | "section" | "file" | "pages" | "lines">;

/** What a lesson's highlights are kept on: its library document, its PDF, or its file. Null for a PDF never opened. */
export async function lessonTarget(agentId: string, lesson: Place): Promise<AnnotationTarget | null> {
  if (lesson.document) return { kind: "document", agentId, documentId: lesson.document };
  if (!lesson.file) return null;
  if (/\.pdf$/i.test(lesson.file)) {
    const document = await getReadingDocumentByPath(lesson.file).catch(() => null);
    return document ? { kind: "pdf", documentId: document.id } : null;
  }
  return { kind: "file", path: lesson.file };
}

/** Whether a mark on a lesson's target lies in the part the lesson reads: its section, pages or lines. */
export function inLesson(lesson: Place, annotation: Annotation): boolean {
  if (lesson.document) {
    const section = lesson.section?.trim();
    if (!section) return true;
    const wanted = key(section);
    // A lesson's section is a heading; "the first that contains the name" when none is named exactly.
    return !!annotation.anchor?.headings?.some((heading) => key(heading) === wanted || key(heading).includes(wanted));
  }
  if (lesson.pages) {
    const [first, last] = lesson.pages;
    return annotation.anchors.some((anchor) => anchor.page >= first && anchor.page <= last);
  }
  if (lesson.lines) {
    const lines = annotation.anchor?.lines;
    return !lines || (lines[0] <= lesson.lines[1] && lines[1] >= lesson.lines[0]);
  }
  return true;
}

/** Each reading lesson's own marks, fetched in one call. */
export async function lessonAnnotations(course: Pick<CourseWithProgress, "agentId" | "data">): Promise<Map<string, Annotation[]>> {
  const result = new Map<string, Annotation[]>();
  if (course.data.engine !== "reading") return result;
  const lessons = course.data.chapters.flatMap((chapter) => chapter.lessons);
  // A comparison's marks are those of each of its parts.
  const places = lessons.flatMap((lesson) => (lesson.compare ?? [lesson]).map((place) => ({ lesson: lesson.id, place })));
  const targets = await Promise.all(places.map(({ place }) => lessonTarget(course.agentId, place)));
  const unique = targets.filter((target, index): target is AnnotationTarget => !!target && targets.findIndex((other) => other && sameTarget(other, target)) === index);
  const marks = await queryAnnotations(unique);
  for (const lesson of lessons) result.set(lesson.id, []);
  places.forEach(({ lesson, place }, index) => {
    const target = targets[index];
    if (!target) return;
    const list = result.get(lesson)!;
    for (const mark of marks) if (sameTarget(mark.target, target) && inLesson(place, mark) && !list.includes(mark)) list.push(mark);
  });
  return result;
}

/** Highlight and note counts per lesson of a course. */
export async function lessonMarkCounts(course: Pick<CourseWithProgress, "agentId" | "data">): Promise<Map<string, MarkCount>> {
  const marks = await lessonAnnotations(course);
  return new Map([...marks].map(([id, list]) => [id, countMarks(list)]));
}

/** Highlight and note counts on one library document. */
export async function sourceMarkCount(agentId: string, documentId: string): Promise<MarkCount> {
  return countMarks(await queryAnnotations([{ kind: "document", agentId, documentId }]));
}
