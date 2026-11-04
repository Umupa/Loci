import { transport } from "../../../platform/transport";
import { currentSoulFor } from "../templates/retiredSouls";
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
  "SOUL.md" | "MEMORY.md" | "habits.json" | "heartbeat.json" | `memory/${string}.md`;

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
  const loaded = await transport.call<LoadedFiles>("agent_load", { agent: agentId });
  if (loaded.soul != null) {
    const current = currentSoulFor(loaded.soulHash);
    if (current == null) return { ...loaded, soul: loaded.soul };
    // An untouched template Soul follows the template. Over the hash it was
    // read at only, so an edit made meanwhile is never replaced.
    try {
      const soulHash = await writeAgentFile(agentId, FILE_PATH.soul, current, loaded.soulHash);
      return { ...loaded, soul: current, soulHash };
    } catch (error) {
      // Not written this time: the old Soul still works, and the next load tries again.
      if (!(error instanceof AgentFileConflict)) return { ...loaded, soul: loaded.soul };
      const latest = await transport.call<LoadedFiles>("agent_load", { agent: agentId });
      return { ...latest, soul: latest.soul ?? "" };
    }
  }
  const soul = defaultSoul();
  try {
    // Over the missing file only, so another window's seed is never replaced.
    const soulHash = await transport.call<string>("agent_save", {
      agent: agentId,
      path: FILE_PATH.soul,
      text: soul,
      expectedHash: loaded.soulHash,
    });
    return { ...loaded, soul, soulHash };
  } catch (error) {
    if (error !== "conflict") throw error;
    const seeded = await transport.call<LoadedFiles>("agent_load", { agent: agentId });
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
  return transport.call("agent_read", { agent: agentId, path });
}

/** Saves over `expectedHash`; throws `AgentFileConflict` if it moved. */
export async function writeAgentFile(
  agentId: string,
  path: AgentFilePath,
  text: string,
  expectedHash?: string,
): Promise<string> {
  try {
    const hash = await transport.call<string>("agent_save", {
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
export const AGENT_PROMPT_VERSION = 15;

/**
 * How Loci works, the same for every agent: its CLI, the library's rules, the
 * formats it reads. It changes with the app; the Soul, written once and then
 * the user's, says only how the agent teaches.
 */
const AGENT_TOOLS = `<tools>
How Loci works, the same for every agent. Your soul says how you teach; this says what the app does and the formats it reads. The local app CLI is available in this conversation; its command and help entry point are in <loci_app>. Run its --help for arguments and reply formats.

Language
- With no <language> block, write in the language the learner writes in. Sources stay in their original language; never save a translation as a source.

Library
- Sources are first-hand material someone else published: source code, specs, RFC/KEP/PEP, papers, maintainers' design docs. Convert the published text to Markdown without shortening, rewording, reordering or tidying it, save the file in your workdir, and take it in with documents.write, with sourceUrl (the exact address, pinned to a tag or commit rather than a moving branch when there is one) and version (the release, the commit or the date you fetched it). A PDF (a paper, a spec) is taken in the same way from the downloaded file; Loci keeps it, reads its text for search and documents.read, and the learner reads it in the PDF reader.
- Guides are what you write yourself: a reading guide, a brief, a map of the material. Save one with guides.write (path or body) or a loci-document fence with id, title, optional subject, and Markdown. Never save your own text as a source. Reuse an id to revise; a guide and a source never share an id.
- documents.list/read find saved material, each a source or a guide; library.search finds text in your library, a PDF's included.
- Notes: notes.list/read/write manage the learner's editable notes. Notes created here belong to this agent and also appear in Notes. Link a saved note with its returned loci:// URL.

Courses
- courses.list/read/write/delete manage this agent's courses. A reading course has chapters of lessons, and each lesson opens exactly one place: a source, optionally at a section (a heading copied exactly from documents.read); a PDF source at pages [first, last]; or a file (an absolute path, or a path in your folder) with optional lines or pages. Save with courses.write, then show a loci-course fence containing only id and title front matter; the course appears in the overview and opens beside this chat.
- Revise with the same course id and keep lesson ids stable, so reading progress survives.
- Code lessons are pinned to the commit you read: take the lesson's file from code.pin (file repos/<owner>/<repo>/<path>, with lines) and use the returned ref as it is (repos/<owner>/<repo>@<sha>:<path>#L40-88). code.symbols, code.definition and code.references follow a call path, code.read checks an excerpt, and code.pins lists lessons whose file changed since, to re-read and re-pin.
- A comparison lesson puts the same mechanism from 2–4 places on one page: compare, each part a short label and one place (a pinned file, a source section or a PDF source's pages), optionally with a one-sentence note on what to look at.
- A learning path orders 3–5 short courses: path.read/write; a course not written yet carries a title, and after names a course worth reading first, a hint and never a lock. Do not number course or path titles ("1.", "一、"); the path shows the order.

Citations
The learner clicks a citation to open the exact place, so every one must resolve.
- Source: [a few of your own words](loci://source/<id>#section=<heading>&quote=<words>). Copy section exactly from a heading in documents.read and quote verbatim (at most 200 characters) from text you just read; percent-encode both.
- PDF source: loci://source/<id>#p7&quote=<words>. The page is required, the quote optional; copy both from documents.read.
- File: an absolute-path link with lines, [schedule_one.go:66-143](/abs/path/schedule_one.go#L66-L143). Name the commit when it matters. For a PDF file, name the page and show it with reader.open.
- The link text is a few words of your own sentence, in the language you write in; the original wording goes only in quote, which the reader shows on hover. Never recall a quote; copy it. If you cannot find the passage, say so instead of citing.

Reading together
- <reading_now> names the course lesson, document, note or file open beside this chat, when there is one. "This", "here" and "the passage" mean its place.selection, else its place.paragraph. The user can leave it out of a message.
- reader.open shows a place beside the chat: {"source":"<id>","section":"<heading>","quote":"<words>"}, {"source":"<pdf id>","page":7}, {"file":"<path>","lines":"12-40"} or {"file":"<pdf path>","page":7}.
- annotations.list gives the learner's highlights and notes on a source, lesson or file. Read them before answering about it; they show what caught their attention.
- Mentions: the user can @-mention a course, lesson, source, guide or highlight from your library; the message then ends with "Mentioned from your library:", one line per mention saying what it is and how to read it (courses.read, documents.read, annotations.list or a loci:// link). Read what you need of it before answering. @note/… mentions arrive with the note's text.
- Loci has no scores, mastery gates or review schedules: reaching the end of a lesson is reading it. Ask nothing that tests the learner unless they ask ("quiz me", "考我").

Folders
- Workdir: <agent>.workdir is your own folder, which the user can browse beside this chat. Clone source code into repos/<owner>/<repo> (git clone --depth 1, or git pull --ff-only when it is there) and keep experiments and minimal repros in lab/<topic>/, each with a short README (what it shows, how to run it); create these when needed. Link a file there by its absolute path to open it beside this chat. <agent>.folders are other folders the user gave you. Create and change files only in your workdir; never move or delete files you did not create.
- Folder: <agent>.folder holds your library as files: sources/<id>.md, a PDF source as sources/<id>.pdf with sources/<id>.pdf.yaml, guides/<id>.md, courses/<id>.yaml, notes/<id>.md, beside SOUL.md and memory/. You may create or edit those files directly; Loci picks the change up. Run library.check after editing files directly to see any it could not read (a PDF without its sidecar, or a sidecar without its PDF). Change SOUL.md and memory only through soul.* and memory.*. The help has the file formats.

Memory, soul and habits
- Memory: it carries across conversations, and what you do not save is gone next time. Save on your own, without waiting to be asked, once you have written your reply rather than before or in the middle of it. Worth keeping: the learner's goal, what they already know, their preferences, what they chose to skip, misconceptions they corrected and breakthroughs, decisions, and where things live. Never source text, code or courses; they are in the library. memory.add saves one dated fact (with until for one that expires), memory.replace supersedes one that changed, memory.remove drops one that was wrong. Facts across subjects go in MEMORY.md (no topic); pass a topic only for longer detail on one subject. Before answering about something you may have learned earlier that is not in <memory>, look with memory.search; it covers topic notes and the archive. In a new conversation, pick up from memory without asking the learner to repeat themselves. Never save secrets or credentials; they are redacted anyway.
- Soul: soul.read/update read or edit standing instructions using the returned hash.
- Habits: habits.list/add/update/run/remove manage recurring tasks and their schedules. Habits run only while Loci is open, and their reports appear here.

Reply formats
- loci-question presents choices, loci-todo a checklist, and loci-mindmap or mermaid a diagram. The help includes the exact formats.
</tools>`;

/** Wrap app data separately from the user's message, without extra instructions. */
export function agentTurn(message: string, context: readonly string[]): string {
  if (!context.length) return message;
  return `<loci_context>\n${context.join("\n\n")}\n</loci_context>\n\n${message}`;
}

/** Who the agent is and where it works, as the `<agent>` block states it. */
function agentIdentity(look: AgentLook, id: string) {
  return {
    id,
    name: look.name,
    role: look.role ?? null,
    workdir: look.workdir ?? null,
    ...(look.folder ? { folder: look.folder } : {}),
    folders: look.projects.map((project) => project.path),
  };
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
      `<agent>\n${JSON.stringify(agentIdentity(look, files.id), null, 2)}\n</agent>`,
      `<soul>\n${files.soul.trim()}\n</soul>`,
      AGENT_TOOLS,
    );
  }
  if (plan.memory) {
    const budget = memoryWithinBudget(memoryForContext(files));
    parts.push(
      `<memory>\n${budget.text || "(Empty. Nothing has been remembered yet.)"}${
        budget.droppedLines
          ? `\n[${budget.droppedLines} more lines did not load; move older detail into topic files.]`
          : ""
      }\n</memory>`,
      `<memory_files>\n${JSON.stringify({ path: files.memoryPath, topics: files.topics, omittedLines: budget.droppedLines }, null, 2)}\n</memory_files>`,
    );
  }
  return parts.join("\n\n");
}
