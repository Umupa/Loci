import type { AgentReading } from "../../agents/model/agentReading";
import type { OpenCourseDetail } from "../../learning/model/course";
import type { AgentDocument } from "../../sessions/model/cards";

/** What a mentor's reader shows. Opening anything replaces it. */
export type MentorPage =
  | { kind: "course"; course: OpenCourseDetail }
  | { kind: "document"; document: AgentDocument }
  | { kind: "note"; id: string }
  | { kind: "canvas"; id: string }
  /** `commit`: source code read as it was at that commit (read-only). */
  | { kind: "file"; path: string; commit?: string }
  /** A session a mentor started, or any conversation a link points to. Never remembered. */
  | { kind: "session"; id: string };

export type MentorLesson = { id: string; title: string };

/** The page as it is remembered between visits: identifiers only, never contents. */
export function storedPage(page: MentorPage | undefined, lesson?: MentorLesson): MentorPage | undefined {
  if (!page || page.kind === "session") return undefined;
  if (page.kind === "course") {
    const { courseId, agentId, title } = page.course;
    const itemId = lesson?.id ?? page.course.itemId;
    return { kind: "course", course: { courseId, agentId, title, ...(itemId ? { itemId } : {}) } };
  }
  if (page.kind === "document") {
    const { id, title, subject } = page.document;
    return { kind: "document", document: { id, title, body: "", ...(subject ? { subject } : {}) } };
  }
  return page;
}

const text = (value: unknown): value is string => typeof value === "string" && value.length > 0;

/** A remembered page read back from storage, or nothing when it is not one. */
export function parseStoredPage(value: unknown): MentorPage | undefined {
  if (!value || typeof value !== "object") return undefined;
  const page = value as Record<string, unknown>;
  if (page.kind === "course" && page.course && typeof page.course === "object") {
    const course = page.course as Record<string, unknown>;
    if (!text(course.courseId) || !text(course.agentId)) return undefined;
    return { kind: "course", course: { courseId: course.courseId, agentId: course.agentId, title: typeof course.title === "string" ? course.title : course.courseId,
      ...(text(course.itemId) ? { itemId: course.itemId } : {}) } };
  }
  if (page.kind === "document" && page.document && typeof page.document === "object") {
    const document = page.document as Record<string, unknown>;
    if (!text(document.id)) return undefined;
    return { kind: "document", document: { id: document.id, title: typeof document.title === "string" ? document.title : "Document", body: "",
      ...(text(document.subject) ? { subject: document.subject } : {}) } };
  }
  if ((page.kind === "note" || page.kind === "canvas") && text(page.id)) return { kind: page.kind, id: page.id };
  if (page.kind === "file" && text(page.path)) return { kind: "file", path: page.path, ...(text(page.commit) && /^[0-9a-f]{7,40}$/i.test(page.commit) ? { commit: page.commit } : {}) };
  return undefined;
}

/** What the conversation is told is being read beside it. */
export function readingOf(page: MentorPage | undefined, lesson: MentorLesson | undefined): AgentReading | undefined {
  if (page?.kind === "course") return { kind: "course", courseId: page.course.courseId, title: page.course.title ?? page.course.courseId,
    ...(lesson ? { lessonId: lesson.id, lessonTitle: lesson.title } : {}) };
  if (page?.kind === "document") return { kind: "document", id: page.document.id, title: page.document.title };
  if (page?.kind === "note") return { kind: "note", id: page.id };
  if (page?.kind === "canvas") return { kind: "canvas", id: page.id };
  if (page?.kind === "file") return { kind: "file", path: page.path, ...(page.commit ? { commit: page.commit } : {}) };
  return undefined;
}

/** Whether two pages show the same thing, whatever lesson or revision. */
export function samePage(a: MentorPage | undefined, b: MentorPage | undefined): boolean {
  if (!a || !b || a.kind !== b.kind) return false;
  if (a.kind === "course") return a.course.courseId === (b as typeof a).course.courseId;
  if (a.kind === "document") return a.document.id === (b as typeof a).document.id;
  if (a.kind === "file") return a.path === (b as typeof a).path && a.commit === (b as typeof a).commit;
  return a.id === (b as typeof a).id;
}

export function fileName(path: string): string {
  return path.split(/[\\/]/).filter(Boolean).pop() ?? path;
}
