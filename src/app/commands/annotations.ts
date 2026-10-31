import { readAgentDocument } from "../../features/agents/model/agentDocuments";
import { countMarks, inLesson, lessonAnnotations, lessonTarget } from "../../features/learning/model/annotationCounts";
import { courseItems, loadCourse, type CourseLesson } from "../../features/learning/model/course";
import { deleteAnnotation, getAnnotation, listAnnotations, upsertAnnotation } from "../../features/learning/model/learningStore";
import { headingsAtOffset, plainMarkdown } from "../../features/learning/model/markdownText";
import { anchorInText, findInText, linesOf } from "../../features/learning/model/textAnchor";
import type { Annotation, AnnotationTarget, LearningSource, TextAnchor } from "../../features/learning/model/types";
import { annotationPlace } from "../../features/learning/model/annotationPlace";
import { readTextFile } from "../../platform/tauri/fs";
import { RELEASE_IDENTIFIER } from "../../features/updates/model/updates";
import type { CommandContext } from "./context";
import { resolveMentor } from "./mentor";
import { lineSpan } from "./reader";
import { CommandError, field, type CommandDefinition, type CommandMeta } from "./registry";

/**
 * Highlights and notes from the command line: what the learner marked in a
 * source, a file or a course's lessons, and how many. Mentors may read them;
 * adding, noting and deleting are for a terminal (tests, an outside mentor).
 */

const mentor = field("mentor", "string", "The mentor whose library it is, by id or name (a mentor's own turn: itself)", { max: 200 });
const source = field("source", "string", "A source or document id from the mentor's library");
const file = field("file", "string", "An absolute path of a text or source file", { max: 4096 });
const QUOTE_MAX = 2000;

function isAbsolute(path: string): boolean {
  return path.startsWith("/") || /^[A-Za-z]:[\\/]/.test(path) || path.startsWith("\\\\");
}

/** A mark as a terminal reads it: where it is, its words and its note. */
export function shownMark(annotation: Annotation) {
  return {
    id: annotation.id,
    target: annotation.target,
    place: annotationPlace(annotation),
    quote: annotation.anchor?.exact ?? annotation.source.quote,
    ...(annotation.anchor?.headings?.length ? { section: annotation.anchor.headings } : {}),
    ...(annotation.anchor?.lines ? { lines: annotation.anchor.lines } : {}),
    ...(annotation.anchors.length ? { pages: annotation.anchors.map((anchor) => anchor.page) } : {}),
    note: annotation.note,
    discussions: annotation.discussions.length,
    createdAt: annotation.createdAt,
    updatedAt: annotation.updatedAt,
  };
}

/** Exactly one of the fields named, or a usage error. */
function one(input: Record<string, unknown>, names: string[]): string {
  const chosen = names.filter((name) => input[name] !== undefined);
  if (chosen.length !== 1) throw new CommandError(`Name exactly one of ${names.map((name) => `--${name}`).join(", ")}`, "usage");
  return chosen[0];
}

async function lessonOf(agentId: string, courseId: string, lessonId: string): Promise<CourseLesson> {
  const course = await loadCourse(courseId, agentId);
  if (!course) throw new CommandError(`No course ${courseId} for this mentor`, "not_found");
  const lesson = courseItems(course.data).find((item) => item.id === lessonId) as CourseLesson | undefined;
  if (!lesson) throw new CommandError(`No lesson ${lessonId} in ${courseId}`, "not_found");
  return lesson;
}

/** Find a quoted passage in a library document or a file, and anchor it there. */
export function anchorQuote(text: string, quote: string, options: { markdown: boolean; section?: string; lines?: [number, number] }): TextAnchor | null {
  const wanted = quote.replace(/\s+/g, " ").trim();
  if (!wanted) return null;
  if (options.markdown) {
    const plain = plainMarkdown(text);
    // Within the named section (up to the next heading of its level or above), else anywhere.
    let [from, to] = [0, plain.text.length];
    if (options.section) {
      const line = plain.headings.findIndex((chain) => chain[chain.length - 1]?.toLowerCase() === options.section!.trim().toLowerCase());
      if (line < 0) throw new CommandError(`No section "${options.section}" in this source`, "not_found");
      const depth = plain.headings[line].length;
      const next = plain.headings.findIndex((chain, index) => index > line && chain.length <= depth && JSON.stringify(chain) !== JSON.stringify(plain.headings[line]));
      [from, to] = [plain.lineStarts[line], next < 0 ? plain.text.length : plain.lineStarts[next]];
    }
    const probe = { exact: wanted, prefix: "", suffix: "", start: 0, end: 0 };
    const inSection = findInText(plain.text.slice(from, to), probe);
    const found = inSection ? [inSection[0] + from, inSection[1] + from] as const : findInText(plain.text, { ...probe, start: from, end: from });
    if (!found) return null;
    return anchorInText(plain.text, found[0], found[1], { headings: headingsAtOffset(plain, found[0]) });
  }
  const near = options.lines ? text.split("\n").slice(0, options.lines[0] - 1).join("\n").length : 0;
  const found = findInText(text, { exact: wanted, prefix: "", suffix: "", start: near, end: near });
  if (!found) return null;
  return anchorInText(text, found[0], found[1], { lines: linesOf(text, found[0], found[1]) });
}

/** --yes is honoured away from the installed app; there Loci still asks. */
async function confirmed(ctx: CommandContext, input: Record<string, unknown>): Promise<boolean> {
  if (input.yes === true && (await ctx.identifier()) !== RELEASE_IDENTIFIER) return true;
  return typeof window !== "undefined" && typeof window.confirm === "function" && window.confirm("Delete this highlight and its note?");
}

function targetFor(ctx: CommandContext, input: Record<string, unknown>, meta: CommandMeta): { target: AnnotationTarget; agentId?: string } {
  if (input.file !== undefined) {
    if (!isAbsolute(input.file as string)) throw new CommandError("--file takes an absolute path", "usage");
    return { target: { kind: "file", path: input.file as string } };
  }
  const agent = resolveMentor(ctx, input.mentor, meta);
  return { target: { kind: "document", agentId: agent.id, documentId: input.source as string }, agentId: agent.id };
}

export const annotationCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "annotations.list",
    summary: "The learner's highlights and notes on a source, a file or a course's lessons, in reading order.",
    fields: [mentor, source, file, field("course", "string", "A course id: the marks on its lessons"), field("lesson", "string", "One lesson of that course")],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const kind = one(input, ["source", "file", "course"]);
      if (input.lesson !== undefined && kind !== "course") throw new CommandError("--lesson goes with --course", "usage");
      if (kind === "course") {
        const agent = resolveMentor(ctx, input.mentor, meta);
        if (input.lesson !== undefined) {
          const lesson = await lessonOf(agent.id, input.course as string, input.lesson as string);
          const target = await lessonTarget(agent.id, lesson);
          const marks = target ? (await listAnnotations(target)).filter((mark) => inLesson(lesson, mark)) : [];
          return { mentor: agent.id, course: input.course, lesson: lesson.id, annotations: marks.map(shownMark) };
        }
        const course = await loadCourse(input.course as string, agent.id);
        if (!course) throw new CommandError(`No course ${String(input.course)} for this mentor`, "not_found");
        const marks = await lessonAnnotations(course);
        return { mentor: agent.id, course: course.id, lessons: Object.fromEntries([...marks].map(([id, list]) => [id, list.map(shownMark)])) };
      }
      const { target, agentId } = targetFor(ctx, input, meta);
      return { ...(agentId ? { mentor: agentId } : {}), target, annotations: (await listAnnotations(target)).map(shownMark) };
    },
  },
  {
    name: "annotations.counts",
    summary: "How many highlights and notes a course's lessons (or one source) have, as the course outline shows.",
    fields: [mentor, field("course", "string", "A course id"), source],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const kind = one(input, ["course", "source"]);
      const agent = resolveMentor(ctx, input.mentor, meta);
      if (kind === "source") return { mentor: agent.id, source: input.source, ...countMarks(await listAnnotations({ kind: "document", agentId: agent.id, documentId: input.source as string })) };
      const course = await loadCourse(input.course as string, agent.id);
      if (!course) throw new CommandError(`No course ${String(input.course)} for this mentor`, "not_found");
      const marks = await lessonAnnotations(course);
      const lessons = Object.fromEntries([...marks].map(([id, list]) => [id, countMarks(list)]));
      return { mentor: agent.id, course: course.id, lessons, total: countMarks([...marks.values()].flat()) };
    },
  },
  {
    name: "annotations.add",
    summary: "Highlight a passage of a source or a text file, found by its words, optionally with a note.",
    fields: [
      mentor, source, file,
      field("quote", "string", "The passage, verbatim from the text", { required: true, max: QUOTE_MAX }),
      field("section", "string", "The heading it is under, in a source (picks among repeats)", { max: 300 }),
      field("lines", "string", "Lines it is near, in a file: 12 or 12-40"),
      field("note", "string", "A note on it", { max: 64 * 1024 }),
    ],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const kind = one(input, ["source", "file"]);
      if (input.section !== undefined && kind !== "source") throw new CommandError("--section goes with --source", "usage");
      if (input.lines !== undefined && kind !== "file") throw new CommandError("--lines goes with --file", "usage");
      const { target, agentId } = targetFor(ctx, input, meta);
      const id = crypto.randomUUID();
      let anchor: TextAnchor | null;
      let cited: LearningSource;
      if (target.kind === "document") {
        const found = await readAgentDocument(target.agentId, target.documentId);
        if (found?.body == null) throw new CommandError(`No source ${target.documentId} in this mentor's library`, "not_found");
        anchor = anchorQuote(found.body, input.quote as string, { markdown: true, ...(input.section !== undefined ? { section: input.section as string } : {}) });
        if (!anchor) throw new CommandError("That passage is not in the source", "not_found");
        const section = anchor.headings?.[anchor.headings.length - 1];
        cited = { id: crypto.randomUUID(), kind: "document", agentId: target.agentId, documentId: target.documentId, title: found.title, quote: anchor.exact,
          ...(found.sourceUrl ? { url: found.sourceUrl } : {}), ...(section ? { section } : {}), anchor, annotationId: id };
      } else if (target.kind === "file") {
        let text: string;
        try { text = await readTextFile(target.path); } catch (cause) { throw new CommandError(`Could not read ${target.path}: ${cause instanceof Error ? cause.message : String(cause)}`, "not_found"); }
        const markdown = /\.(md|markdown|mdx)$/i.test(target.path);
        anchor = anchorQuote(text, input.quote as string, { markdown, ...(input.lines !== undefined ? { lines: lineSpan(input.lines as string) } : {}) });
        if (!anchor) throw new CommandError("That passage is not in the file", "not_found");
        cited = { id: crypto.randomUUID(), kind: "file", path: target.path, title: target.path.split(/[\\/]/).pop() || target.path, quote: anchor.exact,
          ...(anchor.lines ? { lines: anchor.lines } : {}), anchor, annotationId: id };
      } else throw new CommandError("PDF highlights are made in the reader", "usage");
      const now = Date.now();
      const saved = await upsertAnnotation({ id, documentId: "", target, anchor, source: cited, anchors: [],
        note: (input.note as string | undefined) ?? "", discussions: [], createdAt: now, updatedAt: now });
      return { ...(agentId ? { mentor: agentId } : {}), saved: true, annotation: shownMark(saved) };
    },
  },
  {
    name: "annotations.note",
    summary: "Write (or, with an empty note, clear) the note on a highlight.",
    fields: [field("id", "string", "The highlight's id", { required: true, positional: true, max: 128 }), field("note", "string", "The note", { max: 64 * 1024 })],
    callers: ["external"],
    run: async (_ctx, input) => {
      const found = await getAnnotation(input.id as string);
      if (!found) throw new CommandError(`No highlight ${String(input.id)}`, "not_found");
      const saved = await upsertAnnotation({ ...found, note: (input.note as string | undefined) ?? "", updatedAt: Date.now() });
      return { saved: true, annotation: shownMark(saved) };
    },
  },
  {
    name: "annotations.delete",
    summary: "Delete a highlight and its note. Questions asked about it keep their passage.",
    fields: [field("id", "string", "The highlight's id", { required: true, positional: true, max: 128 }), field("yes", "boolean", "Do not ask (Loci Dev and QA builds only)")],
    callers: ["external"],
    destructive: true,
    run: async (ctx, input) => {
      if (!await getAnnotation(input.id as string)) throw new CommandError(`No highlight ${String(input.id)}`, "not_found");
      if (!await confirmed(ctx, input)) throw new CommandError("Not deleted: the question was declined", "declined");
      await deleteAnnotation(input.id as string);
      return { deleted: true, id: input.id };
    },
  },
];
