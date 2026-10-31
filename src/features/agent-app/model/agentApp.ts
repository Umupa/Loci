import { agentCanvasScope } from "../../agents/model/agent";
import { isHarnessAvailable } from "../../../integrations/harness/core/availability";
import { appResourceUrl } from "../../../shared/lib/appResourceLinks";
import { pathKey, projectName } from "../../../shared/lib/paths";
import {
  AgentFileConflict,
  memoryWithinBudget,
  type AgentFilePath,
  type AgentFiles,
} from "../../agents/model/agentFiles";
import {
  addMemoryEntry,
  archiveMemoryEntries,
  fitMemoryBudget,
  memoryDate,
  memoryEntry,
  removeMemoryEntry,
  searchMemory,
  sinceDate,
  supersedeMemoryEntry,
  topicName,
} from "../../agents/model/agentMemory";
import {
  checkHabitsNow,
  HABITS_MAX,
  habitRunningSince,
  habitSchedule,
  habitScheduleLabel,
  newHabit,
  nextHabitRunAt,
  type Habit,
} from "../../agents/model/agentHabits";
import { looksLikeProject, sameProjectPath } from "../../projects/model/recents";
import {
  createEmptyCanvas,
  deleteCanvas,
  getCanvas,
  loadCanvases,
  readCanvasScene,
  updateCanvas,
  upsertCanvas,
  writeCanvasScene,
  type Canvas,
} from "../../canvas/canvas";
import {
  mergeModelSettings,
  modelEffortSetting,
  modelsFor,
  preferredModelId,
  resolveModel,
} from "../../sessions/model/models";
import {
  HARNESSES,
  RUNTIME_MODE_HINT,
  RUNTIME_MODE_LABEL,
  RUNTIME_MODES,
  type HarnessId,
  type Session,
} from "../../sessions/model/session";
import {
  normalizeNoteTags,
  noteTitle,
  type Note,
  type NoteUpsert,
} from "../../notes";
export type SessionLaunch = {
  cwd: string;
  prompt: string;
  draft?: boolean;
  harness: HarnessId;
  model: string;
  modelSettings: Record<string, string>;
  runtimeMode: Session["runtimeMode"];
  reveal?: boolean;
};
import type { SplitDir } from "../../workspace/model/layout";
import { courseItems, parseCourseInput, type CourseSummary, type CourseWithProgress, type ParsedCourse } from "../../learning/model/course";
import { sessionConversationPage, type SessionReadOptions } from "./sessionConversation";

export type AppSessionListing = {
  id: string;
  title: string;
  harness: HarnessId;
  model: string;
  busy: boolean;
  hasDraft: boolean;
};

export type AppSessionPlacement = {
  direction: SplitDir;
  besideSessionId: string;
};

export type AgentAppHost = {
  /** `notify` reports the session's result to the calling agent once it stops. */
  start(
    launch: SessionLaunch,
    id: string,
    placement?: AppSessionPlacement,
    notify?: boolean,
  ): Promise<void>;
  sessions(cwd: string): Promise<AppSessionListing[]>;
  session(id: string): Promise<Session | null>;
  send(
    id: string,
    prompt: string,
    requestId: string,
    notify?: boolean,
  ): Promise<{ alreadySubmitted: boolean }>;
  stop?(id: string): Promise<void>;
  /** Deleting asks the user first; it rejects when they decline. */
  remove?(id: string, mode: "archive" | "delete"): Promise<void>;
  draft(
    id: string,
    prompt: string,
    requestId: string,
  ): Promise<{ alreadySaved: boolean; draft: boolean }>;
  notes(): Promise<Note[]>;
  note(id: string): Promise<Note | null>;
  saveNote(note: NoteUpsert): Promise<Note>;
  /**
   * The agent this session speaks for, when it is an agent's conversation.
   * Its projects are the ones it may name with "project".
   */
  agentOf?(sessionId: string):
    | {
        id: string;
        projects: readonly string[];
        /** Its own conversation, which it may read though it is in no project. */
        chatId?: string;
        /** A hidden run of one of its habits: it may remember, not schedule. */
        habitRun?: boolean;
      }
    | undefined;
  /** An agent's own chat, read through its archived pages when the request reaches that far. */
  readAgentChat?(
    chatId: string,
    options: SessionReadOptions,
  ): Promise<ReturnType<typeof sessionConversationPage>>;
  habits?: {
    load(agentId: string): Promise<Habit[]>;
    update<T>(
      agentId: string,
      change: (habits: Habit[]) => { habits: Habit[]; result: T },
    ): Promise<T>;
  };
  /** Gives the agent the name it and the user settled on. */
  renameAgent?(agentId: string, look: { name: string; role?: string }): void;
  /** The agents' own files: soul, memory and topic notes. */
  files?: AgentFileStore;
  /** What an agent has written for the user to read: its library. */
  documents?: {
    list(agentId: string): Promise<AgentLibraryEntry[]>;
    read(agentId: string, id: string): Promise<AgentLibraryEntry | undefined>;
    /** Takes the file at `path` in as a source. */
    importSource(agentId: string, source: AgentSourceImport): Promise<AgentLibraryEntry>;
  };
  /** Courses in an agent's library: chapters of lessons that point at its documents. */
  courses?: {
    list(agentId: string): Promise<CourseSummary[]>;
    read(agentId: string, id: string): Promise<CourseWithProgress | null>;
    write(agentId: string, course: ParsedCourse): Promise<void>;
    remove(agentId: string, id: string): Promise<void>;
  };
  /** The clock entries are dated by; tests pin it. */
  now?(): Date;
};

export type AgentLibraryEntry = {
  id: string;
  title: string;
  subject?: string | null;
  body?: string;
  /** Where a source was published; absent on what the agent wrote. */
  sourceUrl?: string | null;
  sourceVersion?: string | null;
  fetchedAt?: number | null;
  updatedAt: number;
};

export type AgentSourceImport = {
  id: string;
  title: string;
  subject?: string;
  path: string;
  sourceUrl: string;
  version?: string;
};

export type AgentFileStore = {
  load(agentId: string): Promise<AgentFiles>;
  read(
    agentId: string,
    path: AgentFilePath,
  ): Promise<{ text: string | null; hash: string }>;
  /** Throws `AgentFileConflict` when the file moved past `hash`. */
  write(
    agentId: string,
    path: AgentFilePath,
    text: string,
    hash: string,
  ): Promise<string>;
};

const FIELDS = new Map<string, readonly string[]>([
  ["models.list", []],
  ["sessions.list", ["project"]],
  ["sessions.read", ["sessionId", "before", "limit", "maxChars", "project"]],
  ["sessions.send", ["sessionId", "prompt", "project", "notifyOnComplete"]],
  ["sessions.stop", ["sessionId", "project"]],
  ["sessions.archive", ["sessionId", "project"]],
  ["sessions.delete", ["sessionId", "project"]],
  ["sessions.draft", ["sessionId", "prompt", "project"]],
  [
    "sessions.start",
    [
      "prompt",
      "draft",
      "harness",
      "model",
      "modelSettings",
      "effort",
      "runtimeMode",
      "reveal",
      "placement",
      "besideSessionId",
      "project",
      "notifyOnComplete",
    ],
  ],
  ["notes.list", ["limit", "offset"]],
  ["notes.read", ["id"]],
  ["notes.write", ["id", "title", "body", "tags"]],
  ["agent.rename", ["name", "role"]],
  ["soul.read", []],
  ["soul.update", ["text", "expectedHash"]],
  ["memory.read", ["topic"]],
  ["memory.search", ["query", "since"]],
  ["memory.add", ["fact", "topic", "until"]],
  ["memory.replace", ["find", "fact", "topic", "until"]],
  ["memory.remove", ["find", "topic"]],
  ["documents.list", []],
  ["documents.read", ["id"]],
  ["documents.write", ["id", "title", "subject", "path", "sourceUrl", "version"]],
  ["courses.list", []],
  ["courses.read", ["id"]],
  ["courses.write", ["id", "title", "engine", "chapters", "canvasId", "steps"]],
  ["courses.delete", ["id"]],
  ["habits.list", []],
  ["habits.add", ["name", "instructions", "schedule", "access"]],
  ["habits.update", ["id", "name", "instructions", "schedule", "enabled", "access"]],
  ["habits.run", ["id"]],
  ["habits.remove", ["id"]],
  ["canvas.list", ["project"]],
  ["canvas.get", ["id", "project"]],
  ["canvas.create", ["title", "project"]],
  ["canvas.rename", ["id", "title", "project"]],
  ["canvas.delete", ["id", "project"]],
  ["canvas.read-data", ["id", "project"]],
  ["canvas.write-data", ["id", "dataJson", "project"]],
]);

function fields(action: string, input: Record<string, unknown>) {
  const allowed = FIELDS.get(action);
  if (!allowed) throw new Error(`Unknown app action: ${action}`);
  const unknown = Object.keys(input).filter((key) => !allowed.includes(key));
  if (unknown.length)
    throw new Error(`Unknown ${action} fields: ${unknown.join(", ")}`);
}

function requiredString(value: unknown, name: string, max = 30_000): string {
  if (typeof value !== "string" || !value.trim() || value.length > max)
    throw new Error(
      `${name} must be a non-empty string under ${max} characters`,
    );
  return value.trim();
}

function agentPrompt(value: unknown): string {
  return requiredString(value, "prompt", 240_000);
}

/**
 * Whether the calling agent is told when the session stops. Its own launches
 * report back unless it opts out; a follow-up reports only when asked.
 */
function notifiesOnComplete(
  source: Session,
  input: Record<string, unknown>,
  host: AgentAppHost,
  defaultForAgent = false,
): boolean {
  const requested = input.notifyOnComplete;
  if (requested !== undefined && typeof requested !== "boolean")
    throw new Error("notifyOnComplete must be a boolean");
  const agent = !!ownConversation(source, host);
  if (!(requested ?? (defaultForAgent && agent && !input.draft))) return false;
  if (!agent)
    throw new Error(
      "Completion notifications are only available in an agent's chat",
    );
  if (input.draft === true)
    throw new Error("An unsent draft cannot send a completion notification");
  return true;
}

function optionalString(
  value: unknown,
  name: string,
  max = 512,
): string | undefined {
  return value === undefined ? undefined : requiredString(value, name, max);
}

function noteBody(value: unknown): string {
  if (typeof value !== "string" || value.length > 240_000)
    throw new Error("body must be a string under 240000 characters");
  return value.replace(/\r\n?/g, "\n");
}

function noteTags(value: unknown): string[] {
  if (
    !Array.isArray(value) ||
    value.length > 20 ||
    value.some((tag) => typeof tag !== "string" || tag.length > 48)
  )
    throw new Error(
      "tags must be an array of at most 20 strings under 48 characters each",
    );
  return normalizeNoteTags(value as string[]);
}

/**
 * The project an action works in. A session works in its own; an agent works
 * on several, so it names one with "project" (its path or name), and may leave
 * it out when it has one project or is in one of its own.
 */
function requireProject(
  source: Session,
  input: Record<string, unknown>,
  host: AgentAppHost,
): string {
  const agent = host.agentOf?.(source.id);
  const named = optionalString(input.project, "project", 4096);
  if (!agent) {
    if (named) throw new Error("project is only for an agent");
    if (!looksLikeProject(source.cwd))
      throw new Error("Choose a project folder in this session first");
    return source.cwd;
  }
  const choices = () =>
    agent.projects.length
      ? agent.projects
          .map((path) => `${projectName(path)} (${path})`)
          .join(", ")
      : "none yet; the user adds them from your details panel";
  if (named) {
    const byPath = agent.projects.find(
      (path) => pathKey(path) === pathKey(named),
    );
    const byName = agent.projects.filter(
      (path) => projectName(path) === named,
    );
    const match = byPath ?? (byName.length === 1 ? byName[0] : undefined);
    if (!match) throw new Error(`Not one of your projects. Yours: ${choices()}`);
    return match;
  }
  const own = agent.projects.find(
    (path) => pathKey(path) === pathKey(source.cwd),
  );
  if (own) return own;
  if (agent.projects.length === 1) return agent.projects[0];
  throw new Error(`Pass "project" to choose one. Yours: ${choices()}`);
}

/**
 * Where a canvas action works. An agent's canvases are in its library, in
 * no project, and that is where it draws unless it names one of its projects.
 */
function canvasPlace(
  source: Session,
  input: Record<string, unknown>,
  host: AgentAppHost,
): string {
  const agent = host.agentOf?.(source.id);
  if (agent && input.project === undefined) return agentCanvasScope(agent.id);
  return requireProject(source, input, host);
}

/** An agent's chat lives outside its projects; project access follows its roster. */
export function canAccessAgentAppProject(
  source: Session,
  cwd: string,
  agentProjects?: readonly string[],
): boolean {
  return (agentProjects ?? [source.cwd]).some(
    (project) => pathKey(project) === pathKey(cwd),
  );
}

function canvasMetadata({ id, title, cwd, createdAt, updatedAt }: Canvas) {
  return { id, title, cwd, createdAt, updatedAt, url: appResourceUrl("canvas", id) };
}

function savedNote(note: Note) {
  return { ...note, url: appResourceUrl("note", note.id), saved: true };
}

async function projectCanvas(
  source: Session,
  id: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<Canvas> {
  const cwd = canvasPlace(source, input, host);
  const canvas = await getCanvas(id);
  if (!canvas) throw new Error("Canvas was not found");
  if (!canvas.cwd || !sameProjectPath(canvas.cwd, cwd)) throw new Error("Canvas was not found in this project");
  return canvas;
}

async function projectSession(
  source: Session,
  id: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<Session> {
  const cwd = requireProject(source, input, host);
  if (!(await host.sessions(cwd)).some((session) => session.id === id))
    throw new Error("Session was not found in this project");
  const target = await host.session(id);
  if (!target || pathKey(target.cwd) !== pathKey(cwd))
    throw new Error("Session was not found in this project");
  return target;
}

/** The agent, when this is its chat rather than one of its habits' runs. */
function ownConversation(source: Session, host: AgentAppHost) {
  const agent = host.agentOf?.(source.id);
  return agent && !agent.habitRun ? agent : undefined;
}

function memoryPath(topic: unknown): AgentFilePath {
  return topic === undefined
    ? "MEMORY.md"
    : `memory/${topicName(requiredString(topic, "topic", 80))}.md`;
}

async function handleDocuments(
  source: Session,
  action: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<unknown> {
  const agentId = ownConversation(source, host)?.id;
  if (!agentId || !host.documents)
    throw new Error("Only an agent's own conversation can use its library");
  const named = (entry: AgentLibraryEntry) => ({
    id: entry.id,
    title: entry.title,
    ...(entry.subject ? { subject: entry.subject } : {}),
    ...(entry.sourceUrl ? { sourceUrl: entry.sourceUrl } : {}),
    ...(entry.sourceVersion ? { version: entry.sourceVersion } : {}),
    updatedAt: new Date(entry.updatedAt).toISOString(),
  });
  if (action === "documents.list") {
    const documents = await host.documents.list(agentId);
    return { documents: documents.map(named) };
  }
  if (action === "documents.write") {
    const saved = await host.documents.importSource(agentId, {
      id: requiredString(input.id, "id", 80),
      title: requiredString(input.title, "title", 200),
      ...(input.subject === undefined
        ? {}
        : { subject: requiredString(input.subject, "subject", 80) }),
      path: requiredString(input.path, "path", 4096),
      sourceUrl: requiredString(input.sourceUrl, "sourceUrl", 2000),
      ...(input.version === undefined
        ? {}
        : { version: requiredString(input.version, "version", 80) }),
    });
    return { ...named(saved), saved: true };
  }
  const found = await host.documents.read(
    agentId,
    requiredString(input.id, "id", 80),
  );
  if (found?.body == null) throw new Error("No such document");
  return { ...named(found), text: found.body };
}

async function handleCourses(
  source: Session,
  action: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<unknown> {
  const agentId = ownConversation(source, host)?.id;
  if (!agentId || !host.courses)
    throw new Error("Only an agent's own conversation can use its courses");
  if (action === "courses.list") {
    const courses = await host.courses.list(agentId);
    return {
      courses: courses.map((course) => ({
        id: course.id,
        title: course.title,
        engine: course.engine,
        items: course.itemCount,
        read: course.masteredCount,
        updatedAt: new Date(course.updatedAt).toISOString(),
      })),
    };
  }
  if (action === "courses.write") {
    let course: ParsedCourse;
    try {
      course = parseCourseInput(input);
    } catch (error) {
      throw new Error(`Invalid course: ${error instanceof Error ? error.message : String(error)}`);
    }
    await host.courses.write(agentId, course);
    return { id: course.id, title: course.title, engine: course.engine, items: courseItems(course.data).length, saved: true };
  }
  const id = requiredString(input.id, "id", 80);
  if (action === "courses.delete") {
    await host.courses.remove(agentId, id);
    return { id, deleted: true };
  }
  const found = await host.courses.read(agentId, id);
  if (!found) throw new Error("No such course");
  const { engine, ...body } = found.data;
  return {
    id: found.id,
    title: found.title,
    engine,
    ...body,
    // What the user has read so far, per lesson or step id.
    progress: Object.fromEntries(found.progress),
    updatedAt: new Date(found.updatedAt).toISOString(),
  };
}

async function handleSoul(
  source: Session,
  action: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<unknown> {
  const agentId = ownConversation(source, host)?.id;
  if (!agentId || !host.files)
    throw new Error("Only an agent's own conversation can manage its soul");
  const files = host.files;
  if (action === "soul.read") {
    const loaded = await files.load(agentId);
    return { file: "SOUL.md", text: loaded.soul, hash: loaded.soulHash };
  }
  if (typeof input.text !== "string" || input.text.length > 240_000)
    throw new Error("text must be a string under 240000 characters");
  const expectedHash = requiredString(input.expectedHash, "expectedHash", 128);
  try {
    const hash = await files.write(
      agentId,
      "SOUL.md",
      input.text,
      expectedHash,
    );
    return { file: "SOUL.md", updated: true, hash };
  } catch (error) {
    if (error instanceof AgentFileConflict)
      throw new Error(
        "SOUL.md changed since you read it. Run soul.read and reapply the user's requested changes to the current text before calling soul.update again.",
      );
    throw error;
  }
}

/**
 * Read, change and write one memory file over the version it read, again
 * from the top when the user saved the same file in between.
 */
async function editAgentFile<T>(
  files: AgentFileStore,
  agentId: string,
  path: AgentFilePath,
  edit: (text: string) => { text: string; result: T },
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const current = await files.read(agentId, path);
    const fallback =
      current.text == null && path !== "MEMORY.md"
        ? `# ${path.slice("memory/".length, -".md".length)}\n\n`
        : "";
    const next = edit(current.text ?? fallback);
    try {
      if (next.text !== (current.text ?? ""))
        await files.write(agentId, path, next.text, current.hash);
      return next.result;
    } catch (error) {
      if (!(error instanceof AgentFileConflict) || attempt >= 2)
        throw error;
    }
  }
}

/**
 * Keeps MEMORY.md within what loads. The archive is written first, so a line
 * is never out of one file without already being in the other. If the user
 * saved MEMORY.md in between, the trim waits for the next write.
 */
async function keepMemoryInBudget(
  files: AgentFileStore,
  agentId: string,
  keep: string,
  date: string,
): Promise<string[]> {
  const memory = await files.read(agentId, "MEMORY.md");
  const fitted = fitMemoryBudget(memory.text ?? "", keep, date);
  if (!fitted.moved.length) return [];
  await editAgentFile(files, agentId, "memory/archive.md", (archive) => ({
    text: archiveMemoryEntries(archive, fitted.moved, date),
    result: undefined,
  }));
  try {
    await files.write(agentId, "MEMORY.md", fitted.text, memory.hash);
  } catch (error) {
    if (!(error instanceof AgentFileConflict)) throw error;
    return [];
  }
  return fitted.moved;
}

async function handleMemory(
  source: Session,
  action: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<unknown> {
  const agentId = host.agentOf?.(source.id)?.id;
  if (!agentId || !host.files)
    throw new Error("Memory belongs to an agent's conversation");
  const store = host.files;
  const path = memoryPath(input.topic);
  const date = memoryDate(host.now?.() ?? new Date());
  const until = optionalString(input.until, "until", 10);
  const report = async (result: Record<string, unknown>, keep?: string) => {
    const moved =
      path === "MEMORY.md" && keep
        ? await keepMemoryInBudget(store, agentId, keep, date)
        : [];
    return {
      file: path,
      ...result,
      ...(moved.length
        ? { movedToArchive: moved.length, moved: moved.slice(0, 5) }
        : {}),
    };
  };
  switch (action) {
    case "memory.search": {
      const query =
        input.query === undefined
          ? ""
          : requiredString(input.query, "query", 500);
      const since =
        input.since === undefined
          ? undefined
          : sinceDate(
              requiredString(input.since, "since", 20),
              host.now?.() ?? new Date(),
            );
      const loaded = await store.load(agentId);
      const paths: AgentFilePath[] = [
        "MEMORY.md",
        ...loaded.topics.map((topic) => `memory/${topic}.md` as const),
        "memory/archive.md",
      ];
      const texts = await Promise.all(
        paths.map(async (file) => ({
          file,
          text:
            file === "MEMORY.md"
              ? loaded.memory
              : ((await store.read(agentId, file)).text ?? ""),
        })),
      );
      const hits = searchMemory(texts, query, { since });
      return hits.length
        ? { hits }
        : { hits, note: "Nothing in memory matches. It may never have been saved." };
    }
    case "memory.read": {
      if (path !== "MEMORY.md") {
        const topic = await store.read(agentId, path);
        if (topic.text == null) throw new Error("No such memory topic");
        return { file: path, text: topic.text };
      }
      const loaded = await store.load(agentId);
      const budget = memoryWithinBudget(loaded.memory);
      return {
        file: path,
        text: loaded.memory,
        lines: budget.lines,
        notLoaded: budget.droppedLines,
        topics: loaded.topics,
      };
    }
    case "memory.add": {
      const entry = memoryEntry(requiredString(input.fact, "fact"), date, until);
      const added = await editAgentFile(store, agentId, path, (text) => {
        const next = addMemoryEntry(text, entry);
        return { text: next.text, result: next.added };
      });
      return added
        ? report({ added: entry }, entry)
        : { file: path, alreadyRemembered: true };
    }
    case "memory.replace": {
      const find = requiredString(input.find, "find", 2000);
      const entry = memoryEntry(requiredString(input.fact, "fact"), date, until);
      await editAgentFile(store, agentId, path, (text) => ({
        text: supersedeMemoryEntry(text, find, entry, date),
        result: undefined,
      }));
      return report({ superseded: find, added: entry }, entry);
    }
    case "memory.remove": {
      const find = requiredString(input.find, "find", 2000);
      const removed = await editAgentFile(store, agentId, path, (text) => {
        const next = removeMemoryEntry(text, find);
        return { text: next.text, result: next.removed };
      });
      return { file: path, removed };
    }
  }
  throw new Error(`Unknown app action: ${action}`);
}

/** "auto" asks before risky steps; "full", the default, runs unattended. */
function habitAccess(value: unknown): "auto" | undefined {
  if (value === undefined || value === "full") return undefined;
  if (value === "auto") return "auto";
  throw new Error('access must be "full" or "auto"');
}

function habitView(habit: Habit) {
  return {
    id: habit.id,
    name: habit.name,
    instructions: habit.instructions,
    schedule: habitScheduleLabel(habit.schedule),
    access: habit.access ?? "full",
    enabled: habit.enabled,
    nextRun: habit.enabled ? new Date(habit.nextRunAt).toLocaleString() : null,
    ...(habitRunningSince(habit.id) != null ? { running: true } : {}),
    ...(habit.lastRunAt
      ? {
          lastRun: new Date(habit.lastRunAt).toLocaleString(),
          lastOutcome: habit.lastOutcome,
          ...(habit.lastError ? { lastError: habit.lastError } : {}),
        }
      : {}),
  };
}

async function handleHabits(
  source: Session,
  action: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<unknown> {
  const habits = host.habits;
  // A habit's own run cannot schedule more runs.
  const agentId = ownConversation(source, host)?.id;
  if (!habits || !agentId)
    throw new Error("Only an agent's own conversation can manage its habits");
  const now = host.now?.() ?? new Date();
  const find = (list: Habit[]) => {
    const id = requiredString(input.id, "id", 128);
    const habit = list.find((entry) => entry.id === id);
    if (!habit) throw new Error("No habit with that id; run habits.list");
    return habit;
  };
  switch (action) {
    case "habits.list":
      return { habits: (await habits.load(agentId)).map(habitView) };
    case "habits.add": {
      const name = requiredString(input.name, "name", 80);
      const instructions = requiredString(input.instructions, "instructions", 4_000);
      const schedule = habitSchedule(input.schedule);
      const access = habitAccess(input.access);
      const habit = await habits.update(agentId, (list) => {
        if (list.length >= HABITS_MAX)
          throw new Error(`An agent can have at most ${HABITS_MAX} habits`);
        const created = newHabit(
          { name, instructions, schedule, ...(access ? { access } : {}) },
          now.getTime(),
        );
        return { habits: [...list, created], result: created };
      });
      return { habit: habitView(habit) };
    }
    case "habits.update": {
      const patch = {
        ...(input.name === undefined
          ? {}
          : { name: requiredString(input.name, "name", 80) }),
        ...(input.instructions === undefined
          ? {}
          : {
              instructions: requiredString(
                input.instructions,
                "instructions",
                4_000,
              ),
            }),
        ...(input.schedule === undefined
          ? {}
          : { schedule: habitSchedule(input.schedule) }),
      };
      if (input.enabled !== undefined && typeof input.enabled !== "boolean")
        throw new Error("enabled must be true or false");
      const access = input.access === undefined ? undefined : habitAccess(input.access) ?? "full";
      const habit = await habits.update(agentId, (list) => {
        const current = find(list);
        const next: Habit = {
          ...current,
          ...patch,
          ...(input.enabled === undefined
            ? {}
            : { enabled: input.enabled as boolean }),
        };
        if (access === "auto") next.access = "auto";
        else if (access === "full") delete next.access;
        // A new schedule, or turning it back on, counts from now.
        if (patch.schedule || (next.enabled && !current.enabled))
          next.nextRunAt = nextHabitRunAt(next.schedule, now.getTime());
        return {
          habits: list.map((entry) => (entry.id === next.id ? next : entry)),
          result: next,
        };
      });
      return { habit: habitView(habit) };
    }
    case "habits.run": {
      const running = habitRunningSince(requiredString(input.id, "id", 128));
      if (running != null)
        throw new Error(
          `That habit is already running (started ${new Date(running).toLocaleTimeString()}); its result will be posted here when it ends`,
        );
      const habit = await habits.update(agentId, (list) => {
        const next = { ...find(list), runRequested: true };
        return {
          habits: list.map((entry) => (entry.id === next.id ? next : entry)),
          result: next,
        };
      });
      checkHabitsNow();
      return {
        habit: habitView(habit),
        note: "It starts now, on its own. Whatever it finds is posted to this chat, or nothing if there is nothing to say.",
      };
    }
    case "habits.remove": {
      const removed = await habits.update(agentId, (list) => {
        const habit = find(list);
        return {
          habits: list.filter((entry) => entry.id !== habit.id),
          result: habit,
        };
      });
      return { removed: removed.name };
    }
  }
  throw new Error(`Unknown app action: ${action}`);
}

/** Two short body paragraphs, with a hard cap independent of Markdown length. */
export function notePreview(body: string): string {
  return body
    .trim()
    .split(/\n\s*\n/)
    .map((paragraph) => paragraph.replace(/\s+/g, " ").trim())
    .filter(Boolean)
    .slice(0, 2)
    .join("\n\n")
    .slice(0, 400);
}

function startLaunch(
  source: Session,
  input: Record<string, unknown>,
  host: AgentAppHost,
): SessionLaunch {
  const cwd = requireProject(source, input, host);
  const prompt = agentPrompt(input.prompt);
  const draft = input.draft ?? false;
  if (typeof draft !== "boolean") throw new Error("draft must be a boolean");
  const harness = input.harness ?? source.harness;
  if (!HARNESSES.includes(harness as HarnessId))
    throw new Error("Unknown harness; run models.list for available providers");
  const chosenHarness = harness as HarnessId;
  if (!isHarnessAvailable(chosenHarness))
    throw new Error(`${chosenHarness} is not available in Loci`);
  const requestedModel = optionalString(input.model, "model");
  const model = requestedModel
    ? modelsFor(chosenHarness).find((entry) => entry.id === requestedModel)
    : resolveModel(
        chosenHarness,
        chosenHarness === source.harness
          ? source.model
          : preferredModelId(chosenHarness),
      );
  if (!model || model.harness !== chosenHarness)
    throw new Error("Unknown model; run models.list for exact model IDs");
  const rawSettings = input.modelSettings;
  if (
    rawSettings !== undefined &&
    (!rawSettings ||
      typeof rawSettings !== "object" ||
      Array.isArray(rawSettings))
  )
    throw new Error(
      "modelSettings must be an object of setting IDs and values",
    );
  const requestedSettings = {
    ...((rawSettings ?? {}) as Record<string, unknown>),
  };
  if (input.effort !== undefined) {
    const effort = modelEffortSetting(model);
    if (!effort)
      throw new Error(`${model.id} does not expose an effort setting`);
    requestedSettings[effort.id] = requiredString(input.effort, "effort", 128);
  }
  for (const [key, value] of Object.entries(requestedSettings)) {
    const setting = model.settings?.find((entry) => entry.id === key);
    if (
      !setting ||
      typeof value !== "string" ||
      !setting.options.some((option) => option.value === value)
    )
      throw new Error(
        `Invalid model setting ${key}; run models.list for allowed values`,
      );
  }
  const runtimeMode = input.runtimeMode ?? source.runtimeMode;
  if (!RUNTIME_MODES.includes(runtimeMode as Session["runtimeMode"]))
    throw new Error(`runtimeMode must be one of: ${RUNTIME_MODES.join(", ")}`);
  const reveal = input.reveal ?? false;
  if (typeof reveal !== "boolean") throw new Error("reveal must be a boolean");
  return {
    cwd,
    prompt,
    ...(draft ? { draft: true } : {}),
    harness: chosenHarness,
    model: model.id,
    modelSettings: mergeModelSettings(model, {
      ...(chosenHarness === source.harness && model.id === source.model
        ? source.modelSettings
        : {}),
      ...(requestedSettings as Record<string, string>),
    }),
    runtimeMode: runtimeMode as Session["runtimeMode"],
    reveal,
  };
}

export async function handleAgentApp(
  source: Session,
  requestId: string,
  action: string,
  input: Record<string, unknown>,
  host: AgentAppHost,
): Promise<unknown> {
  fields(action, input);
  if (action === "agent.rename") {
    const agent = ownConversation(source, host);
    if (!agent || !host.renameAgent)
      throw new Error("Only an agent's own conversation can rename it");
    const name = requiredString(input.name, "name", 40)
      .replace(/\s+/g, " ")
      .trim();
    if (!name) throw new Error("name must not be empty");
    const role =
      input.role === undefined
        ? undefined
        : requiredString(input.role, "role", 60).replace(/\s+/g, " ").trim();
    host.renameAgent(agent.id, { name, ...(role ? { role } : {}) });
    return { name, ...(role ? { role } : {}) };
  }
  if (action.startsWith("soul."))
    return handleSoul(source, action, input, host);
  if (action.startsWith("memory."))
    return handleMemory(source, action, input, host);
  if (action.startsWith("documents."))
    return handleDocuments(source, action, input, host);
  if (action.startsWith("habits."))
    return handleHabits(source, action, input, host);
  if (action.startsWith("courses."))
    return handleCourses(source, action, input, host);
  switch (action) {
    case "models.list":
      return {
        runtimeModes: RUNTIME_MODES.map((id) => ({
          id,
          label: RUNTIME_MODE_LABEL[id],
          description: RUNTIME_MODE_HINT[id],
        })),
        harnesses: HARNESSES.map((harness) => ({
          id: harness,
          available: isHarnessAvailable(harness),
          models: modelsFor(harness).map((model) => ({
            id: model.id,
            name: model.name,
            settings: model.settings ?? [],
          })),
        })),
      };
    case "sessions.list": {
      const cwd = requireProject(source, input, host);
      return { cwd, sessions: await host.sessions(cwd) };
    }
    case "sessions.read": {
      const id = requiredString(input.sessionId, "sessionId", 256);
      const options = {
        before: optionalString(input.before, "before", 256),
        limit: input.limit as number | undefined,
        maxChars: input.maxChars as number | undefined,
      };
      // An agent's own chat is in none of its projects, and reaches back
      // into pages the live conversation no longer holds.
      if (host.readAgentChat && host.agentOf?.(source.id)?.chatId === id)
        return host.readAgentChat(id, options);
      const target = await projectSession(source, id, input, host);
      return sessionConversationPage(target, options);
    }
    case "sessions.send": {
      const id = requiredString(input.sessionId, "sessionId", 256);
      const prompt = agentPrompt(input.prompt);
      const notify = notifiesOnComplete(source, input, host);
      if (id === source.id)
        throw new Error(
          "Use the current conversation to continue this session",
        );
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId))
        throw new Error("Invalid request ID");
      await projectSession(source, id, input, host);
      const result = await host.send(
        id,
        prompt,
        `app-${source.id}-${requestId}`,
        ...(notify ? [true] : []),
      );
      return {
        sessionId: id,
        submitted: true,
        ...result,
        ...(notify ? { notifyOnComplete: true } : {}),
      };
    }
    case "sessions.stop":
    case "sessions.archive":
    case "sessions.delete": {
      const id = requiredString(input.sessionId, "sessionId", 256);
      if (id === source.id)
        throw new Error("Cannot stop, archive or delete the calling session");
      if (!host.stop || !host.remove)
        throw new Error("Sessions cannot be managed from here");
      const target = await projectSession(source, id, input, host);
      if (target.ephemeral || host.agentOf?.(id))
        throw new Error("Only regular project sessions can be managed here");
      if (action === "sessions.stop") {
        await host.stop(id);
        return { sessionId: id, stopped: true };
      }
      const mode = action === "sessions.archive" ? "archive" : "delete";
      await host.remove(id, mode);
      return {
        sessionId: id,
        [mode === "archive" ? "archived" : "deleted"]: true,
      };
    }
    case "sessions.draft": {
      const id = requiredString(input.sessionId, "sessionId", 256);
      const prompt = agentPrompt(input.prompt);
      if (id === source.id)
        throw new Error("Use the composer to save a draft in this session");
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId))
        throw new Error("Invalid request ID");
      await projectSession(source, id, input, host);
      const result = await host.draft(
        id,
        prompt,
        `app-${source.id}-${requestId}`,
      );
      return { sessionId: id, saved: true, ...result };
    }
    case "sessions.start": {
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId))
        throw new Error(
          "request ID must use letters, digits, underscores or hyphens",
        );
      const notify = notifiesOnComplete(source, input, host, true);
      const launch = startLaunch(source, input, host);
      const placement = input.placement ?? "tab";
      if (placement !== "tab" && placement !== "right" && placement !== "down")
        throw new Error("placement must be tab, right or down");
      if (input.besideSessionId !== undefined && placement === "tab")
        throw new Error("besideSessionId requires placement right or down");
      const besideSessionId =
        placement === "tab"
          ? undefined
          : (optionalString(input.besideSessionId, "besideSessionId", 256) ??
            source.id);
      const id = `app-${source.id}-${requestId}`;
      const beside = besideSessionId
        ? { direction: placement as SplitDir, besideSessionId }
        : undefined;
      if (notify) await host.start(launch, id, beside, true);
      else if (beside) await host.start(launch, id, beside);
      else await host.start(launch, id);
      return {
        id,
        cwd: launch.cwd,
        harness: launch.harness,
        model: launch.model,
        submitted: !launch.draft,
        draft: !!launch.draft,
        ...(notify ? { notifyOnComplete: true } : {}),
      };
    }
    case "canvas.list": {
      const cwd = canvasPlace(source, input, host);
      const canvases = await loadCanvases(true);
      return {
        cwd,
        canvases: canvases
          .filter((canvas) => !!canvas.cwd && sameProjectPath(canvas.cwd, cwd))
          .sort((a, b) => b.updatedAt - a.updatedAt)
          .map(canvasMetadata),
      };
    }
    case "canvas.get": {
      const id = requiredString(input.id, "id", 256);
      const canvas = await projectCanvas(source, id, input, host);
      return canvasMetadata(canvas);
    }
    case "canvas.create": {
      const cwd = canvasPlace(source, input, host);
      const title = optionalString(input.title, "title", 200);
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId)) throw new Error("Invalid request ID");
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify([source.id, requestId])));
      const id = `app-${Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
      const existing = await getCanvas(id);
      if (existing) {
        if (!existing.cwd || !sameProjectPath(existing.cwd, cwd) || existing.title !== (title ?? "Untitled drawing"))
          throw new Error("Request ID was already used for another drawing");
        return { id: existing.id, title: existing.title, url: appResourceUrl("canvas", existing.id), saved: true };
      }
      const canvas = await upsertCanvas({
        ...createEmptyCanvas(cwd),
        id,
        ...(title === undefined ? {} : { title }),
      });
      return { id: canvas.id, title: canvas.title, url: appResourceUrl("canvas", canvas.id), saved: true };
    }
    case "canvas.rename": {
      const id = requiredString(input.id, "id", 256);
      const title = requiredString(input.title, "title", 200);
      await projectCanvas(source, id, input, host);
      const canvas = await updateCanvas(id, { title });
      return { title: canvas.title, url: appResourceUrl("canvas", canvas.id), saved: true };
    }
    case "canvas.delete": {
      const id = requiredString(input.id, "id", 256);
      await projectCanvas(source, id, input, host);
      await deleteCanvas(id);
      return { deleted: true };
    }
    case "canvas.read-data": {
      const cwd = canvasPlace(source, input, host);
      const id = requiredString(input.id, "id", 256);
      const canvas = await getCanvas(id);
      if (!canvas) throw new Error("Canvas was not found");
      if (!canvas.cwd || !sameProjectPath(canvas.cwd, cwd)) throw new Error("Canvas was not found in this project");
      const saved = await readCanvasScene(id);
      if (!saved) throw new Error("Canvas was not found");
      return { id: saved.id, title: saved.title, dataJson: saved.dataJson, url: appResourceUrl("canvas", saved.id) };
    }
    case "canvas.write-data": {
      const cwd = canvasPlace(source, input, host);
      const id = requiredString(input.id, "id", 256);
      const dataJson = requiredString(input.dataJson, "dataJson", 250_000);
      if (new TextEncoder().encode(dataJson).length > 250_000) throw new Error("dataJson must be under 250000 UTF-8 bytes");
      const { normalizeCanvasScene, canonicalizeCanvasImages } = await import("../../canvas/scene");
      const scene = await canonicalizeCanvasImages(normalizeCanvasScene(dataJson));
      const existing = await getCanvas(id);
      if (!existing) throw new Error("Canvas was not found");
      if (!existing.cwd || !sameProjectPath(existing.cwd, cwd)) throw new Error("Canvas was not found in this project");
      await writeCanvasScene(id, scene);
      return { updated: true, url: appResourceUrl("canvas", id), saved: true };
    }
    case "notes.list": {
      const limit = input.limit ?? 30;
      const offset = input.offset ?? 0;
      if (
        !Number.isInteger(limit) ||
        (limit as number) < 1 ||
        (limit as number) > 100
      )
        throw new Error("limit must be an integer from 1 to 100");
      if (!Number.isInteger(offset) || (offset as number) < 0)
        throw new Error("offset must be a non-negative integer");
      const notes = await host.notes();
      return {
        total: notes.length,
        offset,
        notes: notes
          .slice(offset as number, (offset as number) + (limit as number))
          .map((note) => ({
            id: note.id,
            title: note.title,
            preview: notePreview(note.body),
            tags: note.tags,
            sourceCwd: note.sourceCwd,
            url: appResourceUrl("note", note.id),
          })),
      };
    }
    case "notes.read": {
      const id = requiredString(input.id, "id", 256);
      const note = await host.note(id);
      if (!note) throw new Error("Note was not found");
      return { ...note, url: appResourceUrl("note", note.id) };
    }
    case "notes.write": {
      const id = optionalString(input.id, "id", 256);
      if (id && !/^[A-Za-z0-9_-]+$/.test(id))
        throw new Error("Invalid note ID");
      const title =
        input.title === undefined
          ? undefined
          : requiredString(input.title, "title", 200);
      const body = input.body === undefined ? undefined : noteBody(input.body);
      const tags = input.tags === undefined ? undefined : noteTags(input.tags);
      if (id) {
        if (title === undefined && body === undefined && tags === undefined)
          throw new Error("Supply title, body or tags to update a note");
        const current = await host.note(id);
        if (!current) throw new Error("Note was not found");
        return savedNote(await host.saveNote({
          id,
          title: title ?? current.title,
          body: body ?? current.body,
          tags: tags ?? current.tags,
        }));
      }
      if (body === undefined)
        throw new Error("body is required to create a note");
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(requestId))
        throw new Error("Invalid request ID");
      const createdId = `app-${source.id}-${requestId}`;
      const existing = await host.note(createdId);
      if (existing) {
        if (
          existing.title !== (title ?? noteTitle(body)) ||
          existing.body !== body ||
          JSON.stringify(existing.tags) !== JSON.stringify(tags ?? [])
        )
          throw new Error("Request ID was already used for another note");
        return savedNote(existing);
      }
      return savedNote(await host.saveNote({
        id: createdId,
        title: title ?? noteTitle(body),
        body,
        tags: tags ?? [],
        sourceSessionId: source.id,
        ...(host.agentOf?.(source.id) ? { agentId: host.agentOf(source.id)!.id } : {}),
        // An agent's note belongs to the agent, not to the folder its chat runs in.
        ...(!host.agentOf?.(source.id) && looksLikeProject(source.cwd) ? { sourceCwd: source.cwd } : {}),
      }));
    }
  }
}
