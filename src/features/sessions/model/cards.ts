/**
 * A card is a fenced block in an agent's reply that Loci draws as something
 * better than code: a form, a checklist, a tree, a document to open. Any
 * agent CLI can write one, since it is only text, and a client that does not
 * know the fence still shows readable source.
 *
 * Cards hold no state of their own. What the user does with one goes back to
 * the agent as their next message, and the agent keeps whatever is worth
 * keeping. Documents, retained explanations and opened courses can outlive
 * their messages; a course keeps its learning progress separately.
 */
export const CARD_FENCE = {
  /** A form: see `standingQuestion`. */
  question: "loci-question",
  /** A document the user opens beside the chat and finds again in the agent's library. */
  document: "loci-document",
  /** A checklist; ticking an item tells the agent it is done. */
  todo: "loci-todo",
  /** An outline drawn as a tree that folds. */
  mindmap: "loci-mindmap",
  /** A canvas that already exists, named so the user can open it. */
  canvas: "loci-canvas",
  /** A generated HTML/SVG/JS explanation, isolated from the application. */
  /** A persisted course with steps or connected concepts. */
  course: "loci-course",
  /** A code change, displayed as a line diff. */
  diff: "loci-diff",
} as const;

export type AgentDocument = {
  /** Stable name for revising it; the same id replaces the earlier text. */
  id: string;
  title: string;
  /** What it belongs to, for grouping a library: "Kubernetes". */
  subject?: string;
  /** Markdown. */
  body: string;
  /** Where a source was published. With one, the text is someone else's and is shown as saved. */
  sourceUrl?: string;
  sourceVersion?: string;
  fetchedAt?: number;
};

function slug(text: string): string {
  const base = text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
  return base || "document";
}

/**
 * A document block's source: optional front matter naming it, then Markdown.
 *
 * ```
 * ---
 * id: pods
 * title: Pods, explained
 * subject: Kubernetes
 * ---
 * # Pods
 * ```
 *
 * Without front matter the first heading is the title.
 */
export function parseDocument(source: string): AgentDocument | undefined {
  const text = source.replace(/^﻿/, "").replace(/\r\n/g, "\n");
  const fields: Record<string, string> = {};
  let body = text;
  const front = text.match(/^\s*---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/);
  if (front) {
    for (const line of front[1].split("\n")) {
      const field = line.match(/^\s*([A-Za-z]+)\s*:\s*(.*?)\s*$/);
      if (field) fields[field[1].toLowerCase()] = field[2].replace(/^(["'])(.*)\1$/, "$2");
    }
    body = text.slice(front[0].length);
  }
  body = body.replace(/^\n+/, "").trimEnd();
  const heading = body.match(/^#{1,3}[ \t]+(.+?)[ \t]*#*$/m)?.[1];
  const title = (fields.title || heading || "").trim().slice(0, 200);
  if (!title && !body) return undefined;
  const subject = fields.subject?.trim().slice(0, 80);
  return {
    id: slug(fields.id || title || "document"),
    title: title || "Untitled document",
    ...(subject ? { subject } : {}),
    body,
  };
}

/** The source of every closed block with this fence, in the order written. */
export function fencedBlocks(text: string, fence: string): string[] {
  if (!text.includes(fence)) return [];
  const blocks: string[] = [];
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  for (let i = 0; i < lines.length; i++) {
    const open = lines[i].match(/^[ \t]{0,3}(`{3,}|~{3,})[ \t]*([^\s`]*)/);
    if (!open) continue;
    const marker = open[1];
    // The closing fence uses the same character, at least as many times.
    const close = new RegExp(`^[ \\t]{0,3}${marker[0]}{${marker.length},}[ \\t]*$`);
    let end = i + 1;
    while (end < lines.length && !close.test(lines[end])) end++;
    if (end < lines.length && open[2] === fence)
      blocks.push(lines.slice(i + 1, end).join("\n"));
    // An unclosed fence runs to the end; nothing after it is a block either way.
    i = end;
  }
  return blocks;
}

/** The fences whose cards are worth keeping in view once the message around them is folded away. */
const KEPT_FENCES: readonly string[] = [
  CARD_FENCE.document,
  CARD_FENCE.todo,
  CARD_FENCE.mindmap,
  CARD_FENCE.canvas,
  CARD_FENCE.course,
  CARD_FENCE.diff,
];

/**
 * Only the cards of a message, as Markdown that draws them again. A message
 * the agent wrote while working is folded into the turn's work; what it made
 * for the user should not go with it.
 */
export function cardsOnly(text: string): string {
  if (!text.includes("loci-")) return "";
  const kept: { at: number; block: string }[] = [];
  for (const fence of KEPT_FENCES) {
    for (const source of fencedBlocks(text, fence)) {
      // Longer than any fence inside, so the source stays one block.
      const longest = Math.max(2, ...(source.match(/~+/g) ?? []).map((run) => run.length));
      const wrap = "~".repeat(longest + 1);
      kept.push({ at: text.indexOf(source), block: `${wrap}${fence}\n${source}\n${wrap}` });
    }
  }
  return kept.sort((a, b) => a.at - b.at).map((entry) => entry.block).join("\n\n");
}

/** The documents a reply wrote, each ready to save; a later one with the same id wins. */
export function documentsInText(text: string): AgentDocument[] {
  const byId = new Map<string, AgentDocument>();
  for (const source of fencedBlocks(text, CARD_FENCE.document)) {
    const document = parseDocument(source);
    if (document) byId.set(document.id, document);
  }
  return [...byId.values()];
}

export type TodoItem = { text: string; done: boolean };
export type TodoList = { title?: string; items: TodoItem[] };

/** A checklist written as Markdown task lines, with an optional heading for its title. */
export function parseTodo(source: string): TodoList | undefined {
  let title: string | undefined;
  const items: TodoItem[] = [];
  for (const raw of source.replace(/\r\n/g, "\n").split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    const task = line.match(/^(?:[-*+]|\d+[.)])\s+\[([ xX])\]\s+(.+)$/);
    if (task) {
      items.push({ text: task[2].trim(), done: task[1] !== " " });
      continue;
    }
    const heading = line.match(/^#{1,6}\s+(.+?)\s*#*$/);
    if (heading && !title && !items.length) title = heading[1];
    // A plain bullet is a task not yet done.
    else if (/^(?:[-*+]|\d+[.)])\s+\S/.test(line))
      items.push({ text: line.replace(/^(?:[-*+]|\d+[.)])\s+/, ""), done: false });
  }
  return items.length ? { ...(title ? { title } : {}), items } : undefined;
}

export type MindmapNode = { text: string; children: MindmapNode[] };

/**
 * An outline as a tree: headings and nested bullets, each level deeper than
 * the one it sits under. The first line is the root when it stands alone.
 */
export function parseMindmap(source: string): MindmapNode | undefined {
  const entries: { depth: number; text: string }[] = [];
  let headingDepth = 0;
  for (const raw of source.replace(/\r\n/g, "\n").replace(/\t/g, "  ").split("\n")) {
    if (!raw.trim()) continue;
    const heading = raw.match(/^\s*(#{1,6})\s+(.+?)\s*#*$/);
    if (heading) {
      headingDepth = heading[1].length;
      entries.push({ depth: headingDepth - 1, text: heading[2] });
      continue;
    }
    const bullet = raw.match(/^(\s*)(?:[-*+]|\d+[.)])\s+(.+?)\s*$/);
    // Bullets hang under the heading above them.
    if (bullet) entries.push({ depth: headingDepth + Math.floor(bullet[1].length / 2), text: bullet[2] });
    else entries.push({ depth: headingDepth, text: raw.trim() });
  }
  if (!entries.length) return undefined;
  const top = Math.min(...entries.map((entry) => entry.depth));
  const roots: MindmapNode[] = [];
  const stack: { depth: number; node: MindmapNode }[] = [];
  for (const entry of entries) {
    const node: MindmapNode = { text: entry.text, children: [] };
    const depth = entry.depth - top;
    while (stack.length && stack[stack.length - 1].depth >= depth) stack.pop();
    if (stack.length) stack[stack.length - 1].node.children.push(node);
    else roots.push(node);
    stack.push({ depth, node });
  }
  return roots.length === 1 ? roots[0] : { text: "", children: roots };
}

export type CanvasLink = { id: string; title?: string };

/** A canvas card's source: `id: <canvas id>` and, optionally, `title: ...`. A bare id works too. */
export function parseCanvasLink(source: string): CanvasLink | undefined {
  const fields: Record<string, string> = {};
  const lines = source.replace(/\r\n/g, "\n").split("\n").map((line) => line.trim()).filter(Boolean);
  for (const line of lines) {
    const field = line.match(/^([A-Za-z]+)\s*:\s*(.+)$/);
    if (field) fields[field[1].toLowerCase()] = field[2].replace(/^(["'])(.*)\1$/, "$2");
  }
  const id = fields.id ?? (lines.length === 1 && !/\s/.test(lines[0]) ? lines[0] : undefined);
  if (!id) return undefined;
  const title = fields.title?.slice(0, 200);
  return { id, ...(title ? { title } : {}) };
}

/** Bubbles from a card to the conversation it is in: send this as the user's message. */
export const CARD_REPLY_EVENT = "loci-card-reply";
/** Fired on `window`: open this document beside the chat. */
export const OPEN_DOCUMENT_EVENT = "loci:open-document";

export function sendCardReply(from: Element, text: string): void {
  from.dispatchEvent(new CustomEvent(CARD_REPLY_EVENT, { bubbles: true, detail: { text } }));
}

export type OpenDocumentDetail = AgentDocument & { agentId?: string };

export function openDocument(document: AgentDocument, agentId?: string): void {
  const detail: OpenDocumentDetail = agentId ? { ...document, agentId } : document;
  window.dispatchEvent(new CustomEvent(OPEN_DOCUMENT_EVENT, { detail }));
}
