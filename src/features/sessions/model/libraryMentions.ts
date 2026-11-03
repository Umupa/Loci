import { clip } from "../../agents/model/agentReading";
import { isGuide, listAgentDocuments, type StoredDocument } from "../../agents/model/agentDocuments";
import { courseItems, loadCourse, loadCourseSummaries, type CourseLesson, type CourseWithProgress } from "../../learning/model/course";
import { getReadingDocumentByPath, queryAnnotations } from "../../learning/model/learningStore";
import type { Annotation, AnnotationTarget } from "../../learning/model/types";
import { resourceUrl } from "../../../shared/lib/appResourceLinks";
import { isMarkdownBlockquotePosition } from "./quoteDraft";
import type { LibraryMention } from "./mentionSources";

const TITLE_MAX = 80;
const QUOTE_MAX = 200;
const NOTE_MAX = 200;

const quoted = (text: string) => JSON.stringify(text);
const fileName = (path: string) => path.split(/[\\/]/).filter(Boolean).pop() ?? path;

export function courseMentions(course: Pick<CourseWithProgress, "id" | "title" | "updatedAt" | "data">): LibraryMention[] {
  const lessons = courseItems(course.data);
  const entries: LibraryMention[] = [{
    kind: "course", label: `course/${course.id}`, title: course.title, updatedAt: course.updatedAt,
    where: `${lessons.length} ${lessons.length === 1 ? "lesson" : "lessons"}`,
    reference: `course ${quoted(course.title)}: courses.read ${course.id}`,
  }];
  for (const lesson of lessons) entries.push({
    kind: "lesson", label: `lesson/${course.id}/${lesson.id}`, title: lesson.title, where: course.title,
    courseId: course.id, positionKey: `course:${course.id}:${lesson.id}`, updatedAt: course.updatedAt,
    reference: `lesson ${quoted(lesson.title)} (id ${lesson.id}) of course ${quoted(course.title)}: courses.read ${course.id}`,
  });
  return entries;
}

export function documentMention(document: StoredDocument): LibraryMention {
  const guide = isGuide(document);
  const link = resourceUrl({ kind: "source", id: document.id });
  return {
    kind: guide ? "guide" : "source", label: `${guide ? "guide" : "source"}/${document.id}`, title: document.title,
    ...(document.pdf ? { where: "PDF" } : document.subject ? { where: document.subject } : {}),
    // The reader keeps a PDF's place under its file, other documents under their id.
    positionKey: document.pdf ? `file:${document.pdf.path}` : `document:${document.id}`,
    updatedAt: document.updatedAt,
    reference: `${guide ? "your guide" : document.pdf ? "PDF source" : "source"} ${quoted(document.title)}: ${link} (documents.read ${document.id})`,
  };
}

/** Where a highlight is, the way the picker shows it beside its words. */
function highlightPlace(annotation: Annotation): { page?: number; lines?: [number, number]; section?: string } {
  const page = annotation.anchors[0]?.page;
  if (page) return { page };
  if (annotation.anchor?.lines) return { lines: annotation.anchor.lines };
  const headings = annotation.anchor?.headings;
  return headings?.length ? { section: headings[headings.length - 1] } : {};
}

/**
 * A highlight in a library document, a PDF source or a lesson's file. `document`
 * is the library document it is on; a file highlight has none.
 */
export function highlightMention(annotation: Annotation, document?: Pick<StoredDocument, "id" | "title">): LibraryMention {
  const words = annotation.anchor?.exact ?? annotation.source.quote;
  const place = highlightPlace(annotation);
  const path = annotation.target.kind === "file" ? annotation.target.path : undefined;
  const on = document?.title ?? (path ? fileName(path) : annotation.source.title);
  const at = place.page ? `p. ${place.page}` : place.lines ? `L${place.lines[0]}–${place.lines[1]}` : place.section;
  const quote = clip(words, QUOTE_MAX);
  const link = document
    ? ` ${resourceUrl({ kind: "source", id: document.id, place: { ...(place.page ? { page: place.page } : place.section ? { section: place.section } : {}), quote } })}`
    : "";
  const list = document ? `annotations.list --source ${document.id}` : path ? `annotations.list --file ${path}` : "annotations.list";
  const note = annotation.note.trim() ? `, their note: ${quoted(clip(annotation.note, NOTE_MAX))}` : "";
  return {
    kind: "highlight", label: `highlight/${annotation.id}`, title: clip(words, TITLE_MAX),
    where: at ? `${on} · ${at}` : on, updatedAt: annotation.updatedAt,
    reference: `the learner's highlight in ${quoted(on)}${path ? ` (${path}${place.lines ? ` lines ${place.lines[0]}-${place.lines[1]}` : ""})` : at ? ` (${at})` : ""}: ${quoted(quote)}${note}.${link} (${list})`,
  };
}

/** The files a reading course's lessons read, other than PDFs, whose highlights belong to the mentor too. */
function lessonFiles(courses: readonly CourseWithProgress[]): string[] {
  const paths = new Set<string>();
  for (const course of courses) {
    if (course.data.engine !== "reading") continue;
    for (const lesson of course.data.chapters.flatMap((chapter) => chapter.lessons) as CourseLesson[])
      for (const place of lesson.compare ?? [lesson]) if (place.file && !/\.pdf$/i.test(place.file)) paths.add(place.file);
  }
  return [...paths];
}

/**
 * Everything in a mentor's library `@` can point at. A part that fails to
 * load is left out, so the rest can still be mentioned.
 */
export async function loadLibraryMentions(agentId: string): Promise<LibraryMention[]> {
  const [summaries, documents] = await Promise.all([
    loadCourseSummaries().then((all) => all.filter((course) => course.agentId === agentId)).catch(() => []),
    listAgentDocuments(agentId).catch(() => [] as StoredDocument[]),
  ]);
  const courses = (await Promise.all(summaries.map((summary) => loadCourse(summary.id, agentId).catch(() => null))))
    .filter((course): course is CourseWithProgress => !!course);
  // A PDF's highlights are kept on its reading record, found by its file.
  const pdfs = await Promise.all(documents.map(async (document) =>
    document.pdf ? { document, record: await getReadingDocumentByPath(document.pdf.path).catch(() => null) } : undefined));
  const targets: AnnotationTarget[] = [
    ...documents.filter((document) => !document.pdf).map((document): AnnotationTarget => ({ kind: "document", agentId, documentId: document.id })),
    ...pdfs.flatMap((pdf) => pdf?.record ? [{ kind: "pdf", documentId: pdf.record.id } as AnnotationTarget] : []),
    ...lessonFiles(courses).map((path): AnnotationTarget => ({ kind: "file", path })),
  ];
  const annotations = await queryAnnotations(targets).catch(() => [] as Annotation[]);
  const byRecord = new Map(pdfs.flatMap((pdf) => pdf?.record ? [[pdf.record.id, pdf.document] as const] : []));
  const byId = new Map(documents.map((document) => [document.id, document]));
  const documentOf = (annotation: Annotation) =>
    annotation.target.kind === "document" ? byId.get(annotation.target.documentId)
      : annotation.target.kind === "pdf" ? byRecord.get(annotation.target.documentId) : undefined;
  return [
    ...courses.flatMap(courseMentions),
    ...documents.map(documentMention),
    ...annotations.map((annotation) => highlightMention(annotation, documentOf(annotation))),
  ];
}

const LIBRARY_TOKEN = /(^|\s)@((?:course|lesson|source|guide|highlight)\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)?)/g;

/** The library labels a message mentions, in order, once each; quoted lines are not the user's mentions. */
export function libraryLabelsIn(text: string): string[] {
  const found: string[] = [];
  LIBRARY_TOKEN.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = LIBRARY_TOKEN.exec(text))) {
    const start = match.index + (match[1] ?? "").length;
    if (isMarkdownBlockquotePosition(text, start)) continue;
    if (!found.includes(match[2]!)) found.push(match[2]!);
  }
  return found;
}

/**
 * The message with a list of what its library mentions are and how to read
 * each, so `@lesson/fc/jailer` reaches the mentor as a lesson it can open.
 * Labels that name nothing in the library are left as typed.
 */
export function withLibraryMentions(text: string, library: readonly LibraryMention[]): string {
  const labels = libraryLabelsIn(text);
  const lines = labels.flatMap((label) => {
    const entry = library.find((item) => item.label === label);
    return entry ? [`- @${label}: ${entry.reference}`] : [];
  });
  if (!lines.length) return text;
  return [text.trimEnd(), "", "---", "Mentioned from your library:", ...lines].join("\n");
}

/** At send: resolve a mentor turn's library mentions, loading the library only when there are some. */
export async function applyLibraryMentionsToTurn(text: string, agentId: string): Promise<string> {
  if (!libraryLabelsIn(text).length) return text;
  return withLibraryMentions(text, await loadLibraryMentions(agentId));
}
