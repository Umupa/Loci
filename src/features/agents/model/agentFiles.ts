import { invoke } from "@tauri-apps/api/core";
import { updateAgent, type AgentLook } from "./agent";

/**
 * The agent's SOUL.md and MEMORY.md, kept in the app's data folder
 * rather than the repo (see `src-tauri/src/agent.rs`).
 */
export type AgentFiles = {
  id: string;
  dir: string;
  soul: string;
  soulHash: string;
  memory: string;
  memoryHash: string;
  memoryPath: string;
  /** Topic notes under memory/, by name; listed in the memory block. */
  topics: string[];
  /** The same topic notes with their text; they load with MEMORY.md. */
  topicNotes?: TopicNote[];
};

export type TopicNote = { name: string; text: string; hash: string };

type LoadedFiles = Omit<AgentFiles, "soul"> & { soul: string | null };

export type AgentFile = "soul" | "memory";

/** An agent file by its path in the agent's folder. */
export type AgentFilePath =
  "SOUL.md" | "MEMORY.md" | "habits.json" | `memory/${string}.md`;

const FILE_PATH: Record<AgentFile, AgentFilePath> = {
  soul: "SOUL.md",
  memory: "MEMORY.md",
};

/** A save refused because the file changed since it was opened. */
export class AgentFileConflict extends Error {
  constructor() {
    super("The file changed while you were editing");
  }
}

/** Only this much of MEMORY.md loads into a turn, whichever cuts first. */
export const MEMORY_MAX_LINES = 200;
export const MEMORY_MAX_BYTES = 24 * 1024;

const FILES_CHANGED = "loci:agent-files-changed";

/**
 * What a new agent starts with; the user shapes it from there. What they
 * said it is for when making it becomes its first standing instructions.
 */
export function defaultSoul(purpose?: string): string {
  const own = purpose?.trim();
  return `# Soul

## Standing instructions
${own || "- (Add anything it should always keep in mind.)"}
`;
}

/**
 * Loads the agent's files, writing SOUL.md the first time. */
export function loadAgentFiles(agentId: string): Promise<AgentFiles> {
  // The panel and a send can both find SOUL.md missing; seed it once.
  const pending = loading.get(agentId);
  if (pending) return pending;
  const load = readAgentFiles(agentId).finally(() => loading.delete(agentId));
  loading.set(agentId, load);
  return load;
}

const loading = new Map<string, Promise<AgentFiles>>();

async function readAgentFiles(agentId: string): Promise<AgentFiles> {
  const loaded = await invoke<LoadedFiles>("agent_load", { agent: agentId });
  if (loaded.soul != null) return { ...loaded, soul: loaded.soul };
  const soul = defaultSoul();
  try {
    // Over the missing file only, so another window's seed is never replaced.
    const soulHash = await invoke<string>("agent_save", {
      agent: agentId,
      path: FILE_PATH.soul,
      text: soul,
      expectedHash: loaded.soulHash,
    });
    return { ...loaded, soul, soulHash };
  } catch (error) {
    if (error !== "conflict") throw error;
    const seeded = await invoke<LoadedFiles>("agent_load", { agent: agentId });
    return { ...seeded, soul: seeded.soul ?? "" };
  }
}

/** Back to the default soul and name; conversation, memory and habits stay. */
export async function resetAgentDefaults(agentId: string): Promise<void> {
  const files = await loadAgentFiles(agentId);
  await saveAgentFile(agentId, "soul", defaultSoul(), files.soulHash);
  updateAgent(agentId, (agent) => ({ ...agent, name: "" }));
}

/** Saves over `expectedHash`; throws `AgentFileConflict` if it moved. */
export function saveAgentFile(
  agentId: string,
  file: AgentFile,
  text: string,
  expectedHash?: string,
): Promise<string> {
  return writeAgentFile(agentId, FILE_PATH[file], text, expectedHash);
}

/** Reapply a small edit to the latest file, including after a concurrent save. */
export async function editAgentFile(
  agentId: string,
  file: AgentFile | AgentFilePath,
  edit: (text: string) => string,
): Promise<string> {
  const path = file === "soul" || file === "memory" ? FILE_PATH[file] : file;
  for (let attempt = 0; ; attempt++) {
    const current = await readAgentFile(agentId, path);
    const text = edit(current.text ?? "");
    if (text === (current.text ?? "")) return current.hash;
    try {
      return await writeAgentFile(agentId, path, text, current.hash);
    } catch (error) {
      if (!(error instanceof AgentFileConflict) || attempt >= 2) throw error;
    }
  }
}

/** One agent file and the hash a save over it must name. */
export async function readAgentFile(
  agentId: string,
  path: AgentFilePath,
): Promise<{ text: string | null; hash: string }> {
  return invoke("agent_read", { agent: agentId, path });
}

/** Saves over `expectedHash`; throws `AgentFileConflict` if it moved. */
export async function writeAgentFile(
  agentId: string,
  path: AgentFilePath,
  text: string,
  expectedHash?: string,
): Promise<string> {
  try {
    const hash = await invoke<string>("agent_save", {
      agent: agentId,
      path,
      text,
      expectedHash: expectedHash ?? null,
    });
    window.dispatchEvent(new CustomEvent(FILES_CHANGED));
    return hash;
  } catch (error) {
    if (error === "conflict") throw new AgentFileConflict();
    throw error;
  }
}

export function subscribeAgentFiles(onChange: () => void): () => void {
  window.addEventListener(FILES_CHANGED, onChange);
  return () => window.removeEventListener(FILES_CHANGED, onChange);
}

export type MemoryBudget = {
  /** What loads into a turn. */
  text: string;
  lines: number;
  bytes: number;
  /** Lines past the budget, which do not load. */
  droppedLines: number;
};

/**
 * MEMORY.md followed by each topic note under its own heading, which is what
 * loads into a turn. Topics are for keeping facts apart, not for hiding them:
 * an agent that files everything under topics still remembers it.
 */
export function memoryForContext(files: Pick<AgentFiles, "memory" | "topicNotes">): string {
  const parts = [files.memory.replace(/\s+$/, "")];
  for (const note of files.topicNotes ?? []) {
    const body = note.text.trim().replace(/^# .*\n?/, "").trim();
    if (body) parts.push(`## ${note.name}\n${body}`);
  }
  return parts.filter(Boolean).join("\n\n");
}

/** What decides whether a session has seen this memory: MEMORY.md and every topic note. */
export function memoryKey(files: Pick<AgentFiles, "memoryHash" | "topicNotes">): string {
  const topics = (files.topicNotes ?? []).map((note) => `${note.name}:${note.hash}`);
  return topics.length ? `${files.memoryHash}|${topics.join(",")}` : files.memoryHash;
}

/** The part of MEMORY.md that fits the budget: whole lines only. */
export function memoryWithinBudget(memory: string): MemoryBudget {
  const all = memory.replace(/\s+$/, "").split("\n");
  const lines = memory.trim() ? all : [];
  const encoder = new TextEncoder();
  const kept: string[] = [];
  let bytes = 0;
  for (const line of lines) {
    const size = encoder.encode(line).length + 1;
    if (kept.length >= MEMORY_MAX_LINES || bytes + size > MEMORY_MAX_BYTES)
      break;
    kept.push(line);
    bytes += size;
  }
  return {
    text: kept.join("\n"),
    lines: lines.length,
    bytes: encoder.encode(memory).length,
    droppedLines: lines.length - kept.length,
  };
}

/** What one native session has already been given by the app. */
type Handed = {
  /** The provider session it was given to; absent before the first reply. */
  provider?: string;
  soulHash: string;
  memoryHash: string;
};

const HANDED_KEY = "loci:agent-handed";

function readHanded(): Record<string, Handed> {
  try {
    const parsed = JSON.parse(localStorage.getItem(HANDED_KEY) ?? "{}");
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

/**
 * Bump when the context format changes,
 * so sessions already running are handed the new version once.
 */
const CONTEXT_VERSION = 9;

function handedSoul(soulHash: string): string {
  return `${soulHash}:v${CONTEXT_VERSION}`;
}

export type AgentContextPlan = {
  /** Identity, soul and how to keep memory: a new native session. */
  soul: boolean;
  /** The memory block, when the session has not seen this version of it. */
  memory: boolean;
};

/**
 * What this turn has to carry. A native session that already holds the soul
 * and this memory gets neither again, so nothing piles up in its context; a
 * fresh one (first turn, model switch, a rotated session) gets everything.
 */
export function planAgentContext(
  sessionId: string,
  providerSessionId: string | undefined,
  files: Pick<AgentFiles, "soulHash" | "memoryHash" | "topicNotes">,
): AgentContextPlan {
  const handed = readHanded()[sessionId];
  // The provider id arrives with the first reply, so a record made before it
  // belongs to whatever session that reply started.
  const sameSession =
    !!handed &&
    !!providerSessionId &&
    (handed.provider == null || handed.provider === providerSessionId);
  if (!sameSession) return { soul: true, memory: true };
  const soul = handed.soulHash !== handedSoul(files.soulHash);
  return { soul, memory: soul || handed.memoryHash !== memoryKey(files) };
}

/** A native conversation carrying old or unknown app policies needs a fresh context. */
export function needsAppContextReset(sessionId: string, providerSessionId: string | undefined): boolean {
  if (!providerSessionId) return false;
  const handed = readHanded()[sessionId];
  return typeof handed?.soulHash !== "string" ||
    !handed.soulHash.endsWith(`:v${CONTEXT_VERSION}`) ||
    (!!handed.provider && handed.provider !== providerSessionId);
}

/** Record what a turn the provider accepted carried. */
export function recordAgentContext(
  sessionId: string,
  providerSessionId: string | undefined,
  files: Pick<AgentFiles, "soulHash" | "memoryHash" | "topicNotes">,
): void {
  const next = {
    ...readHanded(),
    [sessionId]: {
      ...(providerSessionId ? { provider: providerSessionId } : {}),
      soulHash: handedSoul(files.soulHash),
      memoryHash: memoryKey(files),
    },
  };
  try {
    localStorage.setItem(HANDED_KEY, JSON.stringify(next));
  } catch {
    // Without the record the next turn resends everything, which is safe.
  }
}

/** A plain chat carries the current app context version without agent files. */
export function recordAppContext(
  sessionId: string,
  providerSessionId: string | undefined,
): void {
  recordAgentContext(sessionId, providerSessionId, { soulHash: "", memoryHash: "" });
}

/** Drop the context receipt when its conversation is deleted. */
export function forgetAgentContext(sessionId: string): void {
  const handed = readHanded();
  delete handed[sessionId];
  try {
    localStorage.setItem(HANDED_KEY, JSON.stringify(handed));
  } catch {
    // A deleted conversation id is never reused.
  }
}

/** Version of the app data carried by an agent turn. */
export const AGENT_PROMPT_VERSION = 6;

/** Discoverable app capabilities; teaching style and standing behavior belong to the Soul. */
const AGENT_TOOLS = `<tools>
The local app CLI is available in this conversation; its command and help entry point are in <loci_app>. Run its --help for arguments and reply formats.
- Courses: courses.list/read/write/delete manage this agent's courses. A reading course arranges chapters and lessons referencing saved document IDs (optionally a heading) or absolute file paths (optionally PDF pages). Keep lesson IDs stable when revising so reading progress survives. Save with courses.write, then show a loci-course fence containing only id and title front matter. The course appears in the overview and opens beside this chat; discuss it in this conversation.
- Documents: documents.list/read find saved material. documents.write imports an existing local source file with its sourceUrl, preserving the original text. For a document you write yourself, use a loci-document fence with id, title, optional subject, and Markdown. Reuse its ID to revise it. These are separate from the user's notes.
- Notes: notes.list/read/write manage editable personal notes. Notes created here belong to this agent and also appear in Notes. Link a saved note with its returned loci:// URL.
- Drawings: use the available canvas tools to create or revise diagrams; canvas.list/get locate existing drawings. A course can reference its canvasId.
- Memory: memory.read/search find facts and topic notes; memory.add/replace/remove update long-term facts through the CLI. Soul: soul.read/update read or edit standing instructions using the returned hash.
- Habits: habits.list/add/update/run/remove manage recurring tasks and their schedules. Habits run only while Loci is open, and their reports appear here.
- Reading: <reading_now> names the course lesson, document or note open beside this chat, when there is one. "This", "here" and "the passage" usually mean it.
- Reply formats: loci-question presents choices, loci-todo a checklist, and loci-mindmap or mermaid a diagram. The help includes the exact formats.
</tools>`;

/** Wrap app data separately from the user's message, without extra instructions. */
export function agentTurn(message: string, context: readonly string[]): string {
  if (!context.length) return message;
  return `<loci_context>\n${context.join("\n\n")}\n</loci_context>\n\n${message}`;
}

/** Soul and factual app state, with no platform-wide behavior policies. */
export function agentContext(
  look: AgentLook,
  files: AgentFiles,
  plan: AgentContextPlan,
): string {
  const parts: string[] = [];
  if (plan.soul) {
    parts.push(
      `<agent>\n${JSON.stringify({ id: files.id, name: look.name, role: look.role ?? null, projects: look.projects }, null, 2)}\n</agent>`,
      `<soul>\n${files.soul.trim()}\n</soul>`,
      AGENT_TOOLS,
    );
  }
  if (plan.memory) {
    const budget = memoryWithinBudget(memoryForContext(files));
    parts.push(
      `<memory>\n${budget.text}\n</memory>`,
      `<memory_files>\n${JSON.stringify({ path: files.memoryPath, topics: files.topics, omittedLines: budget.droppedLines }, null, 2)}\n</memory_files>`,
    );
  }
  return parts.join("\n\n");
}
