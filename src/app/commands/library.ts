import { appModels } from "../../features/agent-app/model/agentApp";
import { courseItems, loadCourse, setLessonStatus, type LearningStatus } from "../../features/learning/model/course";
import { deleteNote, getNote, NOTES_CHANGED_EVENT } from "../../features/notes";
import type { CommandContext } from "./context";
import { mentorField, resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition, type CommandField } from "./registry";

const id = (help = "Its id") => field("id", "string", help, { required: true, positional: true, max: 256 });
const project = field("project", "string", "One of the mentor's folders, by path or name");

/** What a terminal calls a lesson's status; Loci stores "read" as mastered, with no test behind it. */
const LESSON_STATUS: Record<string, LearningStatus> = { read: "mastered", reading: "learning", learning: "learning", untouched: "untouched", unread: "untouched" };
const STATUS_WORD: Record<LearningStatus, string> = { mastered: "read", learning: "reading", untouched: "untouched" };

/**
 * A command that runs one of the app CLI's agent actions for a mentor, as
 * that mentor's own conversation would: same handler, same rules.
 */
function forMentor(
  name: string,
  action: string,
  summary: string,
  fields: CommandField[],
  defaults: Record<string, unknown> = {},
): CommandDefinition<CommandContext> {
  return {
    name,
    summary,
    fields: [mentorField(), ...fields],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const { mentor, ...rest } = input;
      const agent = resolveMentor(ctx, mentor, meta);
      const chat = await ctx.agentChat(agent.id);
      return ctx.agentApp(chat, meta.requestId, action, { ...defaults, ...rest });
    },
  };
}

export const libraryCommands: CommandDefinition<CommandContext>[] = [
  // Sources: what others published, taken into the mentor's library.
  forMentor("sources.list", "documents.list", "The sources and documents in the mentor's library, newest first.", []),
  forMentor("sources.read", "documents.read", "One source or document in full.", [id()]),
  forMentor("sources.write", "documents.write", "Take a UTF-8 Markdown file into the library as a source.", [
    field("id", "string", "A stable id, such as k8s-pod-lifecycle", { required: true, max: 80 }),
    field("title", "string", "Its title", { required: true, max: 200 }),
    field("path", "string", "Absolute path of the Markdown file (at most 1 MB)", { required: true, max: 4096 }),
    field("sourceUrl", "string", "Where it was published", { required: true, max: 2000 }),
    field("subject", "string", "Its subject, such as Kubernetes", { max: 80 }),
    field("version", "string", "The version it describes", { max: 80 }),
  ]),

  forMentor("courses.list", "courses.list", "The mentor's courses, with how many lessons have been read.", []),
  forMentor("courses.read", "courses.read", "One course in full, with progress per lesson.", [id()]),
  forMentor("courses.write", "courses.write", "Save a course (a loci-course block's fields; --input course.json works well). The same id replaces it and keeps progress.", [
    field("id", "string", "A stable course id", { required: true, max: 80 }),
    field("title", "string", "Its title", { required: true, max: 200 }),
    field("engine", "string", "reading (default) or another course engine"),
    field("chapters", "json", "Chapters of lessons, as JSON"),
    field("canvasId", "string", "The canvas a canvas course walks through"),
    field("steps", "json", "Steps of a canvas course, as JSON"),
  ]),
  forMentor("courses.delete", "courses.delete", "Remove a course and its progress.", [id()]),
  {
    name: "courses.lesson",
    summary: "Mark a lesson read, reading or untouched, as its check mark in the outline does.",
    fields: [
      mentorField(),
      field("course", "string", "The course id", { required: true, positional: true }),
      field("lesson", "string", "The lesson (or step) id", { required: true, positional: true }),
      field("status", "string", "read, reading or untouched", { required: true }),
    ],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const status = LESSON_STATUS[input.status as string];
      if (!status) throw new CommandError("status is read, reading or untouched", "usage");
      const course = await loadCourse(input.course as string, agent.id);
      if (!course) throw new CommandError(`No course ${String(input.course)} for this mentor`, "not_found");
      if (!courseItems(course.data).some((item) => item.id === input.lesson)) throw new CommandError(`No lesson ${String(input.lesson)} in this course`, "not_found");
      await setLessonStatus(course.id, agent.id, input.lesson as string, status);
      return { course: course.id, lesson: input.lesson, status: STATUS_WORD[status], saved: true };
    },
  },

  forMentor("notes.list", "notes.list", "Note titles and short previews.", [
    field("limit", "integer", "How many (1-100, default 30)"),
    field("offset", "integer", "How many to skip"),
  ]),
  forMentor("notes.read", "notes.read", "One note in full.", [id()]),
  forMentor("notes.write", "notes.write", "Create a note for the mentor, or edit one with --id.", [
    field("id", "string", "The note to edit", { max: 256 }),
    field("title", "string", "Its title; derived from the body when left out", { max: 200 }),
    field("body", "string", "Markdown (use --body-file)", { max: 200_000 }),
    field("tags", "json", "Tags, as a JSON array of strings"),
  ]),
  {
    name: "notes.delete",
    summary: "Delete one of the mentor's notes.",
    fields: [mentorField(), id()],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const note = await getNote(input.id as string);
      if (!note || note.agentId !== agent.id) throw new CommandError("No such note for this mentor", "not_found");
      await deleteNote(note.id);
      window.dispatchEvent(new Event(NOTES_CHANGED_EVENT));
      return { id: note.id, deleted: true };
    },
  },

  forMentor("canvases.list", "canvas.list", "The mentor's drawings, newest first; metadata only.", [project]),
  forMentor("canvases.get", "canvas.get", "Metadata of one drawing.", [id(), project]),
  forMentor("canvases.create", "canvas.create", "Create an empty drawing.", [field("title", "string", "Its title", { max: 200 }), project]),
  forMentor("canvases.rename", "canvas.rename", "Rename a drawing.", [id(), field("title", "string", "The new title", { required: true, max: 200 }), project]),
  forMentor("canvases.delete", "canvas.delete", "Delete a drawing.", [id(), project]),
  forMentor("canvases.read-data", "canvas.read-data", "The full Excalidraw scene of a drawing (dataJson).", [id(), project]),
  forMentor("canvases.write-data", "canvas.write-data", "Replace a drawing's scene with Excalidraw JSON.", [
    id(), field("dataJson", "string", "The scene as a JSON string (use --data-json-file)", { required: true, max: 250_000 }), project,
  ]),

  forMentor("soul.read", "soul.read", "The mentor's standing instructions (SOUL.md) and their hash.", []),
  forMentor("soul.update", "soul.update", "Replace the mentor's standing instructions.", [
    field("text", "string", "The complete Markdown (use --text-file)", { required: true, max: 100_000 }),
    field("expectedHash", "string", "The hash soul read returned", { required: true }),
  ]),

  forMentor("memory.read", "memory.read", "MEMORY.md, or one topic file.", [field("topic", "string", "A topic name")]),
  forMentor("memory.search", "memory.search", "Search memory, topic notes and the archive.", [
    field("query", "string", "What to look for", { required: true, positional: true }),
    field("since", "string", "A date or a span such as 7d"),
  ]),
  forMentor("memory.add", "memory.add", "Remember one dated fact.", [
    field("fact", "string", "The fact", { required: true, positional: true }),
    field("topic", "string", "A topic name"), field("until", "string", "YYYY-MM-DD it stops mattering"),
  ]),
  forMentor("memory.replace", "memory.replace", "Supersede an entry that changed.", [
    field("find", "string", "Text of the old entry", { required: true }), field("fact", "string", "The new fact", { required: true }),
    field("topic", "string", "A topic name"), field("until", "string", "YYYY-MM-DD"),
  ]),
  forMentor("memory.remove", "memory.remove", "Drop an entry that was wrong.", [
    field("find", "string", "Text of the entry", { required: true }), field("topic", "string", "A topic name"),
  ]),

  forMentor("habits.list", "habits.list", "What the mentor does on its own, with schedules.", []),
  forMentor("habits.add", "habits.add", "Add a habit.", [
    field("name", "string", "Its name", { required: true }), field("instructions", "string", "What to do", { required: true }),
    field("schedule", "json", "{\"kind\":\"daily\",\"time\":\"09:00\"} and the like", { required: true }),
    field("access", "string", "full (default) or auto"),
  ]),
  forMentor("habits.update", "habits.update", "Change a habit.", [
    id(), field("name", "string", "Its name"), field("instructions", "string", "What to do"),
    field("schedule", "json", "Its schedule"), field("enabled", "boolean", "On or off"), field("access", "string", "full or auto"),
  ]),
  forMentor("habits.run", "habits.run", "Run a habit now.", [id()]),
  forMentor("habits.remove", "habits.remove", "Remove a habit.", [id()]),

  forMentor("sessions.list", "sessions.list", "Sessions in one of the mentor's folders.", [project]),
  forMentor("sessions.read", "sessions.read", "Recent exchanges of a session (the mentor's own conversation too).", [
    field("sessionId", "string", "The session", { required: true, positional: true }),
    field("before", "string", "nextBefore from an earlier page"), field("limit", "integer", "Exchanges, up to 3"),
    field("maxChars", "integer", "Characters per message (200-6000)"), project,
  ]),
  forMentor("sessions.start", "sessions.start", "Start a session in one of the mentor's folders. It does not report back to the mentor unless --notify-on-complete.", [
    field("prompt", "string", "What to do", { required: true, positional: true, max: 240_000 }),
    field("harness", "string", "Provider: claude, codex, antigravity, ... (see models list)"),
    field("model", "string", "A model id from models list"), field("effort", "string", "The model's effort setting"),
    field("modelSettings", "json", "Other model settings, as a JSON object"),
    field("runtimeMode", "string", "supervised, auto-accept-edits, auto or full-access"),
    field("draft", "boolean", "Save the prompt unsent"), field("reveal", "boolean", "Show it in the mentor's reader"),
    field("notifyOnComplete", "boolean", "Report the result to the mentor's conversation"), project,
  ], { notifyOnComplete: false }),
  forMentor("sessions.send", "sessions.send", "Send a follow-up to an idle session.", [
    field("sessionId", "string", "The session", { required: true, positional: true }),
    field("prompt", "string", "The follow-up", { required: true, positional: true, max: 240_000 }),
    field("notifyOnComplete", "boolean", "Report the result to the mentor's conversation"), project,
  ], { notifyOnComplete: false }),
  forMentor("sessions.draft", "sessions.draft", "Save an unsent draft in an idle session.", [
    field("sessionId", "string", "The session", { required: true, positional: true }),
    field("prompt", "string", "The draft", { required: true, positional: true, max: 240_000 }), project,
  ]),
  forMentor("sessions.stop", "sessions.stop", "Cancel a session's current turn.", [field("sessionId", "string", "The session", { required: true, positional: true }), project]),
  forMentor("sessions.archive", "sessions.archive", "Stop a session and put it away.", [field("sessionId", "string", "The session", { required: true, positional: true }), project]),
  forMentor("sessions.delete", "sessions.delete", "Remove a session for good; Loci asks you first.", [field("sessionId", "string", "The session", { required: true, positional: true }), project]),

  {
    name: "models.list",
    summary: "Providers, their models and settings, and the permission modes.",
    fields: [],
    callers: ["external"],
    run: async () => appModels(),
  },
];
