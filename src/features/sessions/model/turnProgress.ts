import {
  isAgentTool,
  isEditTool,
  isExecuteTool,
  isReadTool,
  isSearchTool,
  isWeakToolTitle,
} from "../../../integrations/harness/core/preview";
import { unwrapShellCommand } from "../../../integrations/harness/core/shellIntent";
import { leafName } from "../../../shared/lib/fileName";
import type { Block } from "./session";
import { shellWords } from "./shellWords";
import {
  isHiddenTool,
  subagentName,
  toolCallLabel,
  toolCallState,
} from "./transcriptActivity";

/**
 * What a mentor is doing in its running turn, in words a learner reads while
 * waiting. One entry per tool call; the transcript's own rows stay the detailed
 * record.
 */
export type ActivityEntryKind =
  | "source"
  | "guide"
  | "course"
  | "note"
  | "fetch"
  | "clone"
  | "read"
  | "write"
  | "search"
  | "run"
  | "agent"
  | "library"
  | "memory"
  | "other";

export type ActivityEntryStatus = "running" | "done" | "failed";

/** A library item a call saved, when its result or command names one. */
export type SavedActivityItem = {
  kind: "source" | "guide" | "course" | "note";
  id: string;
  title: string;
};

export type ActivityEntry = {
  /** Stable across the updates of one call, so a stream can say what is new. */
  id: string;
  kind: ActivityEntryKind;
  text: string;
  status: ActivityEntryStatus;
  saved?: SavedActivityItem;
};

/** How many entries the chat shows before offering to expand. */
export const VISIBLE_ACTIVITY = 3;

/** The activity of the turn being produced, newest first. */
export function turnActivity(blocks: readonly Block[]): ActivityEntry[] {
  const start = lastUserIndex(blocks) + 1;
  const entries = new Map<string, ActivityEntry>();
  for (let index = blocks.length - 1; index >= start; index -= 1) {
    const block = blocks[index];
    if (block.role !== "tool" && block.role !== "approval") continue;
    if (isHiddenTool(block)) continue;
    const entry = activityEntry(block);
    if (!entry) continue;
    // A provider may publish a call more than once as it updates. The newest
    // row wins, and older copies of the same call stay out of the line.
    if (!entries.has(entry.id)) entries.set(entry.id, entry);
  }
  return [...entries.values()];
}

/** One tool call as a progress line, or undefined for chrome that is not work. */
export function activityEntry(block: Block): ActivityEntry | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  if (block.tool?.kind?.toLowerCase() === "tasks") return undefined;
  const status = entryStatus(block);
  const id = block.tool?.callId || block.id;
  const call = appCall(block);
  if (call) {
    const entry = appActivity(id, call, status, block);
    if (entry) return entry;
  }
  const clone = cloneActivity(block, id, status);
  if (clone) return clone;
  const fetch = fetchActivity(block, id, status);
  if (fetch) return fetch;
  return fileActivity(block, id, status);
}

function entryStatus(block: Block): ActivityEntryStatus {
  if (toolCallState(block) === "rejected") return "failed";
  if (toolCallState(block) === "pending") return "running";
  return "done";
}

function lastUserIndex(blocks: readonly Block[]): number {
  for (let index = blocks.length - 1; index >= 0; index -= 1) {
    if (blocks[index].role === "user") return index;
  }
  return -1;
}

type AppCall = { action: string; options: Map<string, string> };

const APP_WORDING: Record<
  string,
  [running: string, done: string, failed: string, kind: ActivityEntryKind]
> = {
  "documents.list": ["Reading its library", "Read its library", "Couldn't read its library", "library"],
  "documents.read": ["Reading a source", "Read a source", "Couldn't read a source", "source"],
  "courses.list": ["Checking its courses", "Checked its courses", "Couldn't check its courses", "library"],
  "courses.read": ["Reading a course", "Read a course", "Couldn't read a course", "course"],
  "notes.list": ["Reading its notes", "Read its notes", "Couldn't read its notes", "library"],
  "notes.read": ["Reading a note", "Read a note", "Couldn't read a note", "note"],
  "memory.read": ["Checking its memory", "Checked its memory", "Couldn't check its memory", "memory"],
  "memory.search": ["Searching its memory", "Searched its memory", "Couldn't search its memory", "memory"],
  "memory.add": ["Remembering that", "Remembered that", "Couldn't remember that", "memory"],
  "memory.replace": ["Updating its memory", "Updated its memory", "Couldn't update its memory", "memory"],
  "memory.remove": ["Forgetting something", "Forgot something", "Couldn't forget that", "memory"],
  "soul.read": ["Reading its soul", "Read its soul", "Couldn't read its soul", "memory"],
  "soul.update": ["Updating its soul", "Updated its soul", "Couldn't update its soul", "memory"],
  "habits.list": ["Checking its habits", "Checked its habits", "Couldn't check its habits", "library"],
  "habits.add": ["Adding a habit", "Added a habit", "Couldn't add a habit", "library"],
  "habits.update": ["Updating a habit", "Updated a habit", "Couldn't update a habit", "library"],
  "habits.run": ["Running a habit", "Ran a habit", "Couldn't run a habit", "library"],
  "habits.remove": ["Removing a habit", "Removed a habit", "Couldn't remove a habit", "library"],
  "canvas.create": ["Creating a drawing", "Created a drawing", "Couldn't create a drawing", "write"],
  "canvas.write-data": ["Drawing on the canvas", "Drew on the canvas", "Couldn't draw on the canvas", "write"],
  "canvas.read-data": ["Reading the canvas", "Read the canvas", "Couldn't read the canvas", "read"],
  "agent.rename": ["Renaming itself", "Renamed itself", "Couldn't rename itself", "other"],
};

function appCall(block: Block): AppCall | undefined {
  const command = toolCommand(block);
  if (!command) return undefined;
  // A call often sits after `cd <workdir> &&`; take the stage that is the CLI
  // itself, not the whole chain, and keep quoted JSON in one piece.
  const segment = commandSegments(unwrapShellCommand(command)).find((part) => {
    const words = shellWords(part);
    return (
      !!words &&
      /^(?:.*[/\\])?loci(?:\.exe)?$/i.test(words[0] ?? "") &&
      words[1] === "app"
    );
  });
  if (!segment) return undefined;
  const words = shellWords(segment);
  if (!words || !words[2]) return undefined;
  const options = new Map<string, string>();
  for (let index = 3; index < words.length; index += 1) {
    const token = words[index];
    if (!token.startsWith("--")) continue;
    const equals = token.indexOf("=");
    if (equals > 2) {
      options.set(optionKey(token.slice(2, equals)), token.slice(equals + 1));
      continue;
    }
    const next = words[index + 1];
    if (next !== undefined && !next.startsWith("--")) {
      options.set(optionKey(token.slice(2)), next);
      index += 1;
    }
  }
  // The CLI takes one JSON object as well as separate flags.
  const json = options.get("json");
  if (json) {
    try {
      const values: unknown = JSON.parse(json);
      if (values && typeof values === "object" && !Array.isArray(values)) {
        for (const [key, value] of Object.entries(values)) {
          if (value === null || value === undefined) continue;
          options.set(
            optionKey(key),
            typeof value === "string" ? value : JSON.stringify(value),
          );
        }
      }
    } catch {
      // A malformed object makes the CLI fail; the row still names its action.
    }
  }
  return { action: words[2], options };
}

function optionKey(name: string): string {
  return name.replace(/-/g, "").toLowerCase();
}

/** One shell line's stages, split on `&&`, `||`, `;` and `|` outside quotes. */
function commandSegments(command: string): string[] {
  const parts: string[] = [];
  let current = "";
  let quote: '"' | "'" | null = null;
  for (let index = 0; index < command.length; index += 1) {
    const char = command[index];
    if (char === "\\" && quote !== "'") {
      current += char;
      if (index + 1 < command.length) current += command[++index];
      continue;
    }
    if (quote) {
      current += char;
      if (char === quote) quote = null;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      current += char;
      continue;
    }
    if ((char === "&" && command[index + 1] === "&") || (char === "|" && command[index + 1] === "|")) {
      parts.push(current);
      current = "";
      index += 1;
      continue;
    }
    if (char === "|" || char === ";") {
      parts.push(current);
      current = "";
      continue;
    }
    current += char;
  }
  parts.push(current);
  return parts.map((part) => part.trim()).filter(Boolean);
}

function appActivity(
  id: string,
  call: AppCall,
  status: ActivityEntryStatus,
  block: Block,
): ActivityEntry | undefined {
  const result = resultObject(block);
  if (call.action === "documents.write") {
    return savedActivity(id, "source", "Saving source", "Saved source", "Couldn't save source", call, result, status);
  }
  if (call.action === "guides.write") {
    return savedActivity(id, "guide", "Writing guide", "Saved guide", "Couldn't save guide", call, result, status);
  }
  if (call.action === "notes.write") {
    return savedActivity(id, "note", "Writing note", "Saved note", "Couldn't save note", call, result, status);
  }
  if (call.action === "courses.write") {
    const lessons =
      resultNumber(result, "items") ?? lessonCount(call.options.get("chapters"));
    return savedActivity(
      id,
      "course",
      "Writing course",
      "Wrote course",
      "Couldn't write course",
      call,
      result,
      status,
      status === "running"
        ? lessons
          ? ` (${countPhrase(lessons)} so far)`
          : ""
        : lessons
          ? ` (${countPhrase(lessons)})`
          : "",
    );
  }
  const wording = APP_WORDING[call.action];
  if (wording) {
    const [running, done, failed, kind] = wording;
    return {
      id,
      kind,
      status,
      text: status === "failed" ? failed : status === "running" ? running : done,
    };
  }
  return {
    id,
    kind: "other",
    status,
    text:
      status === "failed"
        ? "A Loci action failed"
        : status === "running"
          ? "Using Loci"
          : "Used Loci",
  };
}

function savedActivity(
  id: string,
  kind: SavedActivityItem["kind"],
  running: string,
  done: string,
  failed: string,
  call: AppCall,
  result: Record<string, unknown> | undefined,
  status: ActivityEntryStatus,
  suffix = "",
): ActivityEntry {
  const title =
    stringField(result, "title")?.trim() ||
    call.options.get("title")?.trim() ||
    stringField(result, "id")?.trim() ||
    call.options.get("id")?.trim() ||
    (call.action === "courses.write" ? "a course" : `a ${kind}`);
  const savedId =
    stringField(result, "id")?.trim() || call.options.get("id")?.trim();
  const verb = status === "failed" ? failed : status === "running" ? running : done;
  const line = `${verb}: ${title}${suffix}`;
  return {
    id,
    kind,
    status,
    text: line,
    ...(status === "done" && savedId ? { saved: { kind, id: savedId, title } } : {}),
  };
}

function resultObject(block: Block): Record<string, unknown> | undefined {
  const detail = block.tool?.detail?.trim();
  if (!detail) return undefined;
  const candidates = [detail, detail.match(/\{[\s\S]*\}/)?.[0]].filter(
    (value): value is string => !!value,
  );
  for (const candidate of candidates) {
    try {
      const parsed: unknown = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // A provider may wrap the JSON in prose; the next candidate tries the object itself.
    }
  }
  return undefined;
}

function stringField(value: unknown, key: string): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const found = (value as Record<string, unknown>)[key];
  return typeof found === "string" ? found : undefined;
}

function resultNumber(
  value: Record<string, unknown> | undefined,
  key: string,
): number | undefined {
  const found = value?.[key];
  return typeof found === "number" && Number.isFinite(found) ? found : undefined;
}

/** Lessons in a course body, for the count a progress line can name. */
function lessonCount(value: unknown): number | undefined {
  if (typeof value === "string") {
    try {
      return lessonCount(JSON.parse(value));
    } catch {
      return undefined;
    }
  }
  const chapters = Array.isArray(value)
    ? value
    : value && typeof value === "object"
      ? (value as Record<string, unknown>).chapters
      : undefined;
  if (Array.isArray(chapters)) {
    return chapters.reduce<number>((total, chapter) => {
      const lessons =
        chapter && typeof chapter === "object"
          ? (chapter as Record<string, unknown>).lessons
          : undefined;
      return total + (Array.isArray(lessons) ? lessons.length : 0);
    }, 0);
  }
  const steps =
    value && typeof value === "object"
      ? (value as Record<string, unknown>).steps
      : undefined;
  return Array.isArray(steps) ? steps.length : undefined;
}

function countPhrase(count: number): string {
  return `${count} ${count === 1 ? "lesson" : "lessons"}`;
}

function cloneActivity(
  block: Block,
  id: string,
  status: ActivityEntryStatus,
): ActivityEntry | undefined {
  const kind = block.tool?.kind?.toLowerCase() ?? "";
  const title = block.tool?.title ?? block.text;
  if (!isExecuteTool(kind, title)) return undefined;
  const command = toolCommand(block);
  const script = command ? unwrapShellCommand(command) : "";
  const match = script.match(/\bgit\s+clone\b([^;&|]*)/i);
  if (!match) return undefined;
  // A command chain may end the clone with `2>&1` or a pipe, which is not
  // shellWords input; the repository URL still names what is being cloned.
  const segment = match[0];
  const url = segment.match(/(?:https?:\/\/|git@)[^\s"'`]+/i)?.[0];
  const words = shellWords(`git clone${match[1]}`) ?? [];
  const target = (url ? repositoryName(url) : undefined) ?? cloneTarget(words.slice(2));
  return {
    id,
    kind: "clone",
    status,
    text:
      status === "failed"
        ? `Couldn't clone ${target ?? "the repository"}`
        : status === "running"
          ? `Cloning ${target ?? "a repository"}`
          : `Cloned ${target ?? "a repository"}`,
  };
}

const CLONE_VALUE_FLAGS = new Set([
  "--depth",
  "--branch",
  "-b",
  "--origin",
  "-o",
  "--config",
  "-c",
  "--reference",
  "--reference-if-able",
  "--separate-git-dir",
  "--jobs",
  "-j",
  "--template",
  "--shallow-since",
  "--shallow-exclude",
  "--filter",
]);

function cloneTarget(words: readonly string[]): string | undefined {
  for (let index = 0; index < words.length; index += 1) {
    const word = words[index];
    if (word.startsWith("-")) {
      if (CLONE_VALUE_FLAGS.has(word)) index += 1;
      continue;
    }
    return repositoryName(word);
  }
  return undefined;
}

function repositoryName(value: string): string | undefined {
  const cleaned = value.trim().replace(/\.git$/i, "");
  if (!cleaned) return undefined;
  const scp = cleaned.match(/^[^@]+@[^:]+:(.+)$/);
  const path = scp?.[1] ?? cleaned.replace(/^[a-z]+:\/\/[^/]+\//i, "");
  const parts = path.split(/[/\\]/).filter(Boolean);
  if (parts.length >= 2) return `${parts[parts.length - 2]}/${parts[parts.length - 1]}`;
  return parts[0];
}

function fetchActivity(
  block: Block,
  id: string,
  status: ActivityEntryStatus,
): ActivityEntry | undefined {
  const kind = block.tool?.kind?.toLowerCase() ?? "";
  const title = block.tool?.title ?? block.text ?? "";
  const label = toolCallLabel(block);
  const webSearch =
    /^(?:websearch|web_search|web-search)$/i.test(kind) ||
    /^web\s*search\b/i.test(title);
  if (webSearch) {
    const query =
      block.tool?.preview?.query?.trim() ||
      title.replace(/^web\s*search\b[:\s-]*/i, "").trim() ||
      "a source";
    return {
      id,
      kind: "search",
      status,
      text:
        status === "failed"
          ? "Web search failed"
          : status === "running"
            ? `Searching the web for ${query || "a source"}`
            : `Searched the web for ${query || "a source"}`,
    };
  }
  const fetch =
    /^(?:fetch|webfetch|web_fetch)$/i.test(kind) ||
    /^(?:web\s*fetch|fetch)\b/i.test(label) ||
    /^(?:web\s*fetch|fetch)\b/i.test(title);
  if (!fetch) return undefined;
  const target =
    webTarget(block.tool?.preview?.path) ??
    webTarget(title) ??
    webTarget(label) ??
    webTarget(block.tool?.detail);
  return {
    id,
    kind: "fetch",
    status,
    text:
      status === "failed"
        ? `Couldn't fetch ${target ?? "that page"}`
        : status === "running"
          ? `Fetching ${target ?? "a page"}`
          : `Fetched ${target ?? "a page"}`,
  };
}

function webTarget(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const match = value.match(/https?:\/\/[^\s"'<>)]+/i);
  const raw =
    match?.[0] ??
    value.match(/(?:^|\s)([a-z0-9-]+(?:\.[a-z0-9-]+)+\/[^\s"'<>)]*)/i)?.[1];
  if (!raw) return undefined;
  try {
    const url = new URL(/^https?:/i.test(raw) ? raw : `https://${raw}`);
    if (!url.hostname.includes(".")) return undefined;
    const path = url.pathname === "/" ? "" : url.pathname.replace(/\/+$/, "");
    return shortenWebTarget(`${url.hostname}${path}`);
  } catch {
    return undefined;
  }
}

function shortenWebTarget(value: string): string {
  const limit = 52;
  if (value.length <= limit) return value;
  const slash = value.indexOf("/");
  const host = slash > 0 ? value.slice(0, slash) : value;
  if (!slash) return `${value.slice(0, limit - 1)}…`;
  const room = Math.max(1, limit - host.length - 1);
  const path = value.slice(slash, slash + room);
  const lastSlash = path.lastIndexOf("/");
  const cut = lastSlash > 0 ? path.slice(0, lastSlash + 1) : path;
  return `${host}${cut}…`;
}

function fileActivity(
  block: Block,
  id: string,
  status: ActivityEntryStatus,
): ActivityEntry | undefined {
  const kind = block.tool?.kind;
  const title = block.text || block.tool?.title;
  const preview = block.tool?.preview;
  if (isAgentTool(kind, title)) {
    const name = subagentName(block);
    return {
      id,
      kind: "agent",
      status,
      text:
        status === "failed"
          ? `A subagent failed${name && name !== "Subagent" ? `: ${name}` : ""}`
          : status === "running"
            ? `Running a subagent${name && name !== "Subagent" ? `: ${name}` : ""}`
            : `Ran a subagent${name && name !== "Subagent" ? `: ${name}` : ""}`,
    };
  }
  const label = toolCallLabel(block);
  // A provider may shape an execute call's preview like a read; the call is
  // still a command, and its own words say so.
  if (isExecuteTool(kind, title)) {
    const command = toolCommand(block);
    const script = command ? unwrapShellCommand(command) : label;
    const target = downloadTarget(script);
    if (target) {
      return {
        id,
        kind: "fetch",
        status,
        text:
          status === "failed"
            ? `Couldn't fetch ${target}`
            : status === "running"
              ? `Fetching ${target}`
              : `Fetched ${target}`,
      };
    }
    const short = shorten(script, 80);
    return {
      id,
      kind: "run",
      status,
      text:
        status === "failed"
          ? `Command failed${short ? `: ${short}` : ""}`
          : status === "running"
            ? `Running ${short || "a command"}`
            : `Ran ${short || "a command"}`,
    };
  }
  const parts = label.match(/^(Read|List|Find|Edit|Write|Create|Delete|Move)\s+(.+)$/i);
  const verb = parts?.[1]?.toLowerCase();
  const target = parts?.[2]?.trim();
  const fileTarget = target ? leafName(target) || target : undefined;
  if (isSearchTool(kind, title, preview) || verb === "find") {
    const query = preview?.query ?? target;
    return {
      id,
      kind: "search",
      status,
      text:
        status === "failed"
          ? "Search failed"
          : status === "running"
            ? `Searching for ${query ?? "something"}`
            : `Searched for ${query ?? "something"}`,
    };
  }
  if (isEditTool(kind, title, preview) || ["edit", "write", "create", "delete", "move"].includes(verb ?? "")) {
    const action = verb === "delete" ? "Deleting" : verb === "move" ? "Moving" : "Writing";
    const past = verb === "delete" ? "Deleted" : verb === "move" ? "Moved" : "Wrote";
    return {
      id,
      kind: "write",
      status,
      text:
        status === "failed"
          ? `Couldn't write ${fileTarget ?? "a file"}`
          : status === "running"
            ? `${action} ${fileTarget ?? "a file"}`
            : `${past} ${fileTarget ?? "a file"}`,
    };
  }
  if (isReadTool(kind, title, preview) || verb === "read" || verb === "list") {
    return {
      id,
      kind: "read",
      status,
      text:
        status === "failed"
          ? `Couldn't read ${fileTarget ?? "that"}`
          : status === "running"
            ? `Reading ${fileTarget ?? "a file"}`
            : `Read ${fileTarget ?? "a file"}`,
    };
  }
  if (!label || label === "Working") return undefined;
  return {
    id,
    kind: "other",
    status,
    text: status === "failed" ? `${label} failed` : label,
  };
}

/** A shell call that downloads a URL with curl or wget, named the way a fetch is. */
function downloadTarget(script: string): string | undefined {
  if (!/\b(?:curl|wget)\b/i.test(script)) return undefined;
  return webTarget(script.match(/https?:\/\/[^\s"'`]+/i)?.[0]);
}

const COMMAND_PROGRAM =
  /^(?:loci|git|curl|wget|cd|ls|cat|bat|rg|grep|egrep|fgrep|find|sed|awk|python3?|node|npm|npx|pnpm|yarn|cargo|rustc|make|mkdir|rmdir|rm|cp|mv|ln|touch|echo|printf|pwd|head|tail|nl|wc|sort|uniq|cut|tr|xargs|tar|unzip|zip|bash|sh|zsh|fish|env|which|test|chmod|chown|open|git|gh|jq|tee|time|true|false)$/i;

/**
 * The command a provider ran, however that adapter shaped the row. Grok labels
 * a shell call "Run Terminal Command" and keeps the command in a read-shaped
 * preview's path; Claude and Codex put it in the title.
 */
function toolCommand(block: Block): string | undefined {
  if (block.role !== "tool" && block.role !== "approval") return undefined;
  const preview = block.tool?.preview;
  const candidates = [
    preview?.kind === "shell" ? preview.title : undefined,
    preview?.path,
    block.tool?.title,
    block.text,
  ];
  for (const candidate of candidates) {
    const command = candidate?.trim().replace(/^Run(?:ning)?\s+command:\s*/i, "");
    if (command && looksLikeCommand(command)) return command;
  }
  return undefined;
}

function looksLikeCommand(value: string): boolean {
  if (isWeakToolTitle(value)) return false;
  if (/^(?:run\s+)?terminal(?:\s+command)?$/i.test(value)) return false;
  // A command chain is a command even before its first stage is recognized.
  if (/\s(?:&&|\|\||;|\|)\s/.test(value)) return true;
  const inner = unwrapShellCommand(value);
  if (inner !== value) return looksLikeCommand(inner);
  const words = shellWords(value);
  if (!words || words.length < 2) return false;
  const program = words[0].split(/[/\\]/).pop() ?? words[0];
  return COMMAND_PROGRAM.test(program);
}

function firstLine(value: string): string {
  return value.split(/\r?\n/)[0]?.trim() ?? "";
}

function shorten(value: string, limit: number): string {
  const line = firstLine(value);
  return line.length > limit ? `${line.slice(0, limit - 1)}…` : line;
}
