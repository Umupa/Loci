import { readAgentDocument } from "../../features/agents/model/agentDocuments";
import { requestDocumentPlace } from "../../features/agents/model/documentPlace";
import { getCanvas } from "../../features/canvas/canvas";
import { requestFilePlace } from "../../features/files/model/filePlace";
import { courseItems, isCommit, loadCourse } from "../../features/learning/model/course";
import { samePage, type MentorPage } from "../../features/mentor/model/mentorPage";
import { compareView } from "../../features/learning/model/compareView";
import { getNote } from "../../features/notes";
import type { FilePlace } from "../../shared/lib/appResourceLinks";
import type { CommandContext } from "./context";
import { readingView } from "./mentors";
import { resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition } from "./registry";

export type ReaderFocus = { section?: string; quote?: string; lines?: [number, number]; page?: number };

/** The place each reader was last asked to show, while it still shows that page. */
const focuses = new Map<string, { page: MentorPage; focus: ReaderFocus }>();

const mentor = field("mentor", "string", "The mentor whose reader to use, by id or name (a mentor's own turn: itself)", { max: 200 });

/** `12` or `12-40`, 1-based and inclusive. */
export function lineSpan(value: string): [number, number] {
  const match = /^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$/.exec(value);
  const first = match ? Number(match[1]) : NaN;
  const last = match?.[2] ? Number(match[2]) : first;
  if (!match || first < 1 || last < first) throw new CommandError("lines is a line or a range such as 10-40", "usage");
  return [first, last];
}

function isAbsolute(path: string): boolean {
  return path.startsWith("/") || /^[A-Za-z]:[\\/]/.test(path) || path.startsWith("\\\\");
}

export const readerCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "reader.open",
    summary: "Open a lesson, source, note, canvas or file in a mentor's reader, in place of what it showed.",
    fields: [
      mentor,
      field("course", "string", "A course id"),
      field("lesson", "string", "A lesson id in that course"),
      field("source", "string", "A source or document id from the library"),
      field("note", "string", "A note id"),
      field("canvas", "string", "A canvas id"),
      field("file", "string", "An absolute file path", { max: 4096 }),
      field("section", "string", "A heading to scroll to, in a source", { max: 300 }),
      field("quote", "string", "A passage to show and flash, verbatim from the text (with --source, or --file and --lines)", { max: 500 }),
      field("lines", "string", "Lines to show in a text file: 12 or 12-40"),
      field("page", "integer", "A page to show in a PDF"),
      field("at", "string", "With --file: show source code as it was at this commit (read-only)", { max: 64 }),
      field("switch", "boolean", "Also bring the mentor on screen"),
    ],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const chosen = (["course", "source", "note", "canvas", "file"] as const).filter((kind) => input[kind] !== undefined);
      if (chosen.length !== 1) throw new CommandError("Name exactly one of --course, --source, --note, --canvas or --file", "usage");
      const kind = chosen[0];
      const value = input[kind] as string;
      if (input.lesson !== undefined && kind !== "course") throw new CommandError("--lesson goes with --course", "usage");
      if (input.section !== undefined && kind !== "source") throw new CommandError("--section goes with --source", "usage");
      if (input.quote !== undefined && kind !== "source" && !(kind === "file" && input.lines !== undefined))
        throw new CommandError("--quote goes with --source, or with --file and --lines", "usage");
      if (input.lines !== undefined && kind !== "file") throw new CommandError("--lines goes with --file", "usage");
      if (input.page !== undefined && kind !== "file" && kind !== "source")
        throw new CommandError("--page goes with --file, or with a PDF --source", "usage");
      if (input.lines !== undefined && input.page !== undefined) throw new CommandError("Choose --lines or --page", "usage");
      if (input.at !== undefined && (kind !== "file" || !isCommit(input.at as string))) throw new CommandError("--at is a commit id (7 to 40 hex digits) and goes with --file", "usage");
      const focus: ReaderFocus = {};
      let page: MentorPage;
      if (kind === "course") {
        const course = await loadCourse(value, agent.id);
        if (!course) throw new CommandError(`No course ${value} for this mentor`, "not_found");
        const lesson = input.lesson as string | undefined;
        if (lesson && !courseItems(course.data).some((item) => item.id === lesson))
          throw new CommandError(`No lesson ${lesson} in ${value}`, "not_found");
        page = { kind: "course", course: { courseId: course.id, agentId: agent.id, title: course.title, ...(lesson ? { itemId: lesson } : {}) } };
      } else if (kind === "source") {
        const found = await readAgentDocument(agent.id, value);
        if (found?.pdf) {
          if (input.section !== undefined || input.quote !== undefined)
            throw new CommandError("A PDF source opens at --page; section and quote belong to text sources", "usage");
          const at = typeof input.page === "number" ? input.page : 1;
          if (at < 1) throw new CommandError("page starts at 1", "usage");
          page = { kind: "file", path: found.pdf.path };
          focus.page = at;
          requestFilePlace(found.pdf.path, { page: at });
        } else {
          if (found?.body == null) throw new CommandError(`No source ${value} in this mentor's library`, "not_found");
          if (input.page !== undefined) throw new CommandError(`${value} is not a PDF; --page needs a PDF source`, "usage");
          page = { kind: "document", document: { id: found.id, title: found.title, body: found.body, ...(found.subject ? { subject: found.subject } : {}) } };
          if (input.section !== undefined) focus.section = input.section as string;
          if (input.quote !== undefined) focus.quote = input.quote as string;
          if (focus.section || focus.quote) requestDocumentPlace(agent.id, found.id, { ...(focus.section ? { section: focus.section } : {}), ...(focus.quote ? { quote: focus.quote } : {}) });
        }
      } else if (kind === "note") {
        if (!await getNote(value)) throw new CommandError(`No note ${value}`, "not_found");
        page = { kind: "note", id: value };
      } else if (kind === "canvas") {
        if (!await getCanvas(value)) throw new CommandError(`No canvas ${value}`, "not_found");
        page = { kind: "canvas", id: value };
      } else {
        if (!isAbsolute(value)) throw new CommandError("--file takes an absolute path", "usage");
        page = { kind: "file", path: value, ...(input.at !== undefined ? { commit: (input.at as string).toLowerCase() } : {}) };
        let place: FilePlace | undefined;
        if (input.lines !== undefined) {
          place = { lines: focus.lines = lineSpan(input.lines as string) };
          if (input.quote !== undefined) place.quote = focus.quote = input.quote as string;
        }
        if (input.page !== undefined) {
          if ((input.page as number) < 1) throw new CommandError("page starts at 1", "usage");
          place = { page: focus.page = input.page as number };
        }
        if (place) requestFilePlace(value, place);
      }
      await ctx.reader.show(agent.id, page, meta.caller === "external" && input.switch === true);
      if (Object.keys(focus).length) focuses.set(agent.id, { page, focus });
      else focuses.delete(agent.id);
      return { mentor: agent.id, opened: true, ...readingView({ page }), ...(Object.keys(focus).length ? { focus } : {}) };
    },
  },
  {
    name: "reader.show",
    summary: "What a mentor's reader shows now: the kind, the id or path, the lesson (a comparison's parts as compare: label, file and commit read or document, pin state, folded), and the place it was asked to show.",
    fields: [mentor],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const current = ctx.reader.current(agent.id);
      const remembered = focuses.get(agent.id);
      const focus = remembered && samePage(remembered.page, current.page) ? { focus: remembered.focus } : {};
      // A comparison on screen says what each part shows: the commit read, the pin's state, folded or not.
      const view = compareView(agent.id);
      const shown = view && current.page?.kind === "course" && current.page.course.courseId === view.courseId && current.lesson?.id === view.lessonId ? { compare: view.parts } : {};
      return { mentor: agent.id, active: ctx.activeAgentId() === agent.id, ...readingView(current), ...shown, ...focus };
    },
  },
  {
    name: "reader.close",
    summary: "Empty a mentor's reader.",
    fields: [mentor],
    callers: ["external", "agent"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      if (!await ctx.reader.close(agent.id)) throw new CommandError("The reader kept its page: unsaved edits could not be saved");
      focuses.delete(agent.id);
      return { mentor: agent.id, closed: true };
    },
  },
];
