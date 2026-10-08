import { statFiles } from "../../platform/tauri/fs";
import { appResourceUrl, fileResourceUrl } from "../../shared/lib/appResourceLinks";
import { joinPath } from "../../shared/lib/paths";
import { createEmptyCanvas, loadCanvases, readCanvasScene, upsertCanvas, writeCanvasScene, type Canvas } from "../canvas/canvas";
import { getNote, normalizeNoteTags, NOTES_CHANGED_EVENT, upsertNote } from "../notes";
import { looksLikeProject, sameProjectPath } from "../projects/model/recents";
import { sessionDisplayTitle, type Session } from "../sessions/model/session";
import {
  GHOST_LIMIT, LEARN_MAP_TAG, RECORD_LIMIT, SKETCH_LIMIT, isLearnMap, isRecord, readMap,
  type LearnSource, type MapNode, type MapView, type RecallVerdict, type RecordVerdict,
} from "./model/learnMap";
import type { EdgeRecord, NodeRecord, WriteContext, WrittenNode } from "./model/mapScene";
import { EDGE_LABEL_COLUMNS, labelColumns, QUOTE_MIN, saidByLearner, wordedByLearner } from "./model/quote";
import { mapStats, pickRevisits } from "./model/schedule";

/** What the learning bridge needs from the window it runs in. */
export type LearnBridgeHost = {
  /** Show the map beside the session that works on it, without taking focus. */
  reveal(canvasId: string, sessionId: string): void;
};

/** Fired on `window` with the canvas id when a revisit from memory starts or ends. */
export const LEARN_RECALL_EVENT = "loci:learn-recall";

type Recall = { canvasId: string; nodeId: string; kind: "concept" | "judgment"; fromIndex: number; peeked: boolean };
// A revisit spans turns: the question goes out in one, the answer comes in the next.
const recalls = new Map<string, Recall>();
// What each session last saw of the learner's hand edits, to tell it when they change.
const seenEdits = new Map<string, string>();

const FIELDS: Record<string, readonly string[]> = {
  "map.read": ["nodeId", "stats"],
  "map.init": ["subject", "why", "success"],
  "map.sketch": ["near", "nodes", "edges"],
  "map.record": ["nodes", "edges"],
  "revisit.start": ["nodeId"],
  "revisit.finish": ["nodeId", "quote", "verdict", "principle"],
  "revisit.cancel": ["nodeId"],
};

/** Whether a revisit from memory is under way on this map, so its pane hides the answer. */
export function recallCovered(canvasId: string): boolean {
  return [...recalls.values()].some((recall) => recall.canvasId === canvasId && recall.kind === "concept" && !recall.peeked);
}

/** The learner lifted the cover: the revisit goes on, but can no longer count as held. */
export function liftRecallCover(canvasId: string): void {
  for (const recall of recalls.values()) if (recall.canvasId === canvasId) recall.peeked = true;
  window.dispatchEvent(new CustomEvent(LEARN_RECALL_EVENT, { detail: canvasId }));
}

function endRecall(sessionId: string) {
  const recall = recalls.get(sessionId);
  recalls.delete(sessionId);
  if (recall) window.dispatchEvent(new CustomEvent(LEARN_RECALL_EVENT, { detail: recall.canvasId }));
}

function projectOf(source: Session): string {
  if (!looksLikeProject(source.cwd)) throw new Error("Choose a project folder in this session first: a subject lives in its own folder");
  return source.cwd;
}

/** The subject's map: the oldest canvas of the project that carries the tag. */
export async function projectLearnMap(cwd: string): Promise<Canvas | null> {
  const maps = (await loadCanvases(true)).filter((canvas) => isLearnMap(canvas) && !!canvas.cwd && sameProjectPath(canvas.cwd, cwd));
  return maps.sort((a, b) => a.createdAt - b.createdAt)[0] ?? null;
}

async function requireMap(cwd: string): Promise<Canvas> {
  const map = await projectLearnMap(cwd);
  const saved = map && await readCanvasScene(map.id);
  if (!saved) throw new Error("This project has no learning map yet. Ask the learner why they are learning this and what they already know, then call map_init.");
  return saved;
}

function text(value: unknown, name: string, max: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) throw new Error(`${name} must be a non-empty string of at most ${max} characters`);
  return value.trim();
}
const optionalText = (value: unknown, name: string, max: number) => value === undefined ? undefined : text(value, name, max);

function oneOf<T extends string>(value: unknown, name: string, allowed: readonly T[], fallback?: T): T {
  if (value === undefined && fallback !== undefined) return fallback;
  if (typeof value !== "string" || !allowed.includes(value as T)) throw new Error(`${name} must be one of: ${allowed.join(", ")}`);
  return value as T;
}

function list(value: unknown, name: string, max: number, min = 0): unknown[] {
  if (value === undefined && min === 0) return [];
  if (!Array.isArray(value) || value.length < min || value.length > max) throw new Error(`${name} must be a list of ${min} to ${max} items`);
  return value;
}

function fields(value: unknown, name: string, allowed: readonly string[]): Record<string, unknown> {
  if (!isRecord(value)) throw new Error(`${name} must be an object`);
  const unknown = Object.keys(value).filter((field) => !allowed.includes(field));
  if (unknown.length) throw new Error(`Unknown ${name} fields: ${unknown.join(", ")}`);
  return value;
}

/** The learner's own words, or the call is refused. This is what keeps the map theirs. */
function learnerQuote(source: Session, value: unknown, name: string, fromIndex = 0): string {
  const quote = text(value, name, 4000);
  if (saidByLearner(source.blocks, quote, fromIndex)) return quote;
  throw new Error(`${name} must be a passage the learner typed in this session${fromIndex ? " after the revisit began" : ""}, copied word for word (at least ${QUOTE_MIN} letters). ` +
    "Do not paraphrase, summarize or complete it. If the learner has not explained this in their own words yet, ask them to; the node stays unexplored until they do.");
}

const pad = (value: number) => String(value).padStart(2, "0");
const day = (ms: number) => { const date = new Date(ms); return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`; };

function futureDay(value: unknown, name: string, now: number): number {
  const match = typeof value === "string" ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(value) : null;
  const at = match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])).getTime() : NaN;
  if (!Number.isFinite(at) || at <= now) throw new Error(`${name} must be a future date as YYYY-MM-DD`);
  return at;
}

async function sourcesOf(value: unknown, cwd: string): Promise<LearnSource[]> {
  const sources: LearnSource[] = [];
  for (const entry of list(value, "sources", 12)) {
    const source = fields(entry, "source", ["path", "page", "lines", "url", "accessedAt"]);
    if (source.url !== undefined) {
      const url = text(source.url, "source url", 2000);
      if (!/^https?:\/\/\S+$/i.test(url)) throw new Error("source url must be an http(s) address");
      if (typeof source.accessedAt !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(source.accessedAt)) throw new Error("source accessedAt must be the date you read the page, as YYYY-MM-DD");
      sources.push({ url, accessedAt: source.accessedAt });
      continue;
    }
    const path = text(source.path, "source path", 1000);
    const parts = path.split("/");
    if (path.startsWith("/") || path.includes("\\") || parts.some((part) => !part || part === "." || part === ".."))
      throw new Error(`source path "${path}" must be a path inside the project, such as sources/notes.md`);
    const [found] = await statFiles([joinPath(cwd, path)]);
    if (found?.mtimeMs == null) throw new Error(`source path "${path}" does not exist in this project. Save the source under sources/ first, or cite the file you actually read.`);
    const page = source.page;
    const lines = source.lines;
    if (page !== undefined && (!Number.isInteger(page) || (page as number) < 1)) throw new Error("source page must be a positive integer");
    if (lines !== undefined && (!Array.isArray(lines) || lines.length !== 2 || !lines.every((line) => Number.isInteger(line) && line >= 1) || lines[0] > lines[1]))
      throw new Error("source lines must be [first, last]");
    sources.push({ path, ...(page === undefined ? {} : { page: page as number }), ...(lines === undefined ? {} : { lines: lines as [number, number] }) });
  }
  return sources;
}

function sourceLine(source: LearnSource): string {
  if ("url" in source) return `${source.url} (read ${source.accessedAt})`;
  const place = source.page !== undefined ? { page: source.page } : source.lines ? { lines: source.lines } : undefined;
  const where = source.page !== undefined ? `, p. ${source.page}` : source.lines ? `, lines ${source.lines[0]}–${source.lines[1]}` : "";
  return `[${source.path.replace(/[\\[\]]/g, "\\$&")}${where}](${fileResourceUrl(source.path, place)})`;
}

const quoted = (words: string) => words.replace(/\r\n?/g, "\n").split("\n").map((line) => line ? `> ${line}` : ">").join("\n");

function sessionLink(source: Session): string {
  const title = sessionDisplayTitle(source.title, source.harness).replace(/\r?\n/g, " ").replace(/[\\[\]]/g, "\\$&") || "session";
  return /^[A-Za-z0-9_-]+$/.test(source.id) ? `[${title}](${appResourceUrl("session", source.id)})` : title;
}

/** Add to the note behind a node. The host only ever appends: the note is the learner's to edit. */
async function appendNote(source: Session, cwd: string, subject: string, noteId: string, label: string, section: string): Promise<boolean> {
  try {
    const existing = await getNote(noteId);
    await upsertNote(existing
      ? { id: noteId, title: existing.title, body: `${existing.body.trimEnd()}\n\n${section}`, tags: existing.tags }
      : { id: noteId, title: label.slice(0, 200), body: section, tags: normalizeNoteTags([subject, "learn"]), sourceSessionId: source.id, sourceCwd: cwd });
    window.dispatchEvent(new Event(NOTES_CHANGED_EVENT));
    return true;
  } catch { return false; }
}

function writeContext(source: Session, canvasId: string, now: number): WriteContext {
  return {
    now, sessionId: source.id,
    newId: (prefix) => `${prefix}${crypto.randomUUID().replace(/-/g, "").slice(0, 10)}`,
    noteId: (elementId) => `learn-${canvasId}-${elementId}`,
  };
}

const nodeLine = (node: MapNode) => ({
  id: node.id, label: node.label, ...(node.kind === "judgment" ? { kind: node.kind } : {}), state: node.state,
  ...(node.due ? { due: true } : {}), ...(node.links ? { links: node.links } : {}), ...(node.unsourced ? { unsourced: true } : {}),
});

const editSignature = (view: MapView) => JSON.stringify(view.untracked);

/** Fade the nodes that have come due. Not an edit the learner made, so it stays out of undo. */
async function showDue(canvas: Canvas, now: number): Promise<Canvas> {
  const { refreshDue } = await import("./model/mapScene");
  if (!refreshDue(canvas.dataJson, now)) return canvas;
  return writeCanvasScene(canvas.id, (current) => ({ dataJson: refreshDue(current.dataJson, now) ?? current.dataJson, silent: true }));
}

/** The learner disagrees with the verdict of a node's latest revisit and judges it again. */
export async function overruleLearnRecall(canvasId: string, nodeId: string, verdict: RecallVerdict): Promise<void> {
  const { overruleRecall } = await import("./model/mapScene");
  const now = Date.now();
  let noteId: string | undefined;
  await writeCanvasScene(canvasId, (current) => {
    if (!isLearnMap(current)) throw new Error("This drawing is not a learning map");
    const result = overruleRecall(current.dataJson, nodeId, verdict, { now, sessionId: "", newId: (prefix) => `${prefix}${crypto.randomUUID().slice(0, 10)}`, noteId: (id) => `learn-${canvasId}-${id}` });
    noteId = result.data.noteId;
    return { dataJson: result.dataJson };
  });
  const note = noteId ? await getNote(noteId) : null;
  if (!note) return;
  await upsertNote({ id: note.id, title: note.title, body: `${note.body.trimEnd()}\n\n### ${day(now)} · verdict changed by the learner · ${verdict}`, tags: note.tags });
  window.dispatchEvent(new Event(NOTES_CHANGED_EVENT));
}

/** Refresh which nodes look due on a map that is being opened. */
export async function refreshLearnMap(canvasId: string): Promise<void> {
  const canvas = await readCanvasScene(canvasId);
  if (canvas && isLearnMap(canvas)) await showDue(canvas, Date.now());
}

/**
 * A line for the learner's next message when they have drawn on the map since
 * the session last read it: their drawing is a claim the agent should look at.
 */
export async function learnEditHint(source: Session): Promise<string> {
  if (!looksLikeProject(source.cwd)) return "";
  const map = await projectLearnMap(source.cwd);
  const saved = map && await readCanvasScene(map.id);
  if (!saved) return "";
  const view = readMap(saved.dataJson, Date.now());
  const signature = editSignature(view);
  const count = view.untracked.shapes.length + view.untracked.edges.length;
  if (!count || seenEdits.get(source.id) === signature) return "";
  seenEdits.set(source.id, signature);
  return `\n\n<loci_learn_hint>The learner has drawn on the learning map by hand since you last read it (${count} unrecorded shape(s) or arrow(s)). Call map_read before answering: what they drew is a claim to ask about, never to correct or delete.</loci_learn_hint>`;
}

/**
 * Loci's side of the `loci_learn` MCP server. Every write is checked here, so
 * the rules of a learning map hold whichever model is on the other end.
 */
export async function handleLearnBridge(source: Session, action: string, input: Record<string, unknown>, host: LearnBridgeHost): Promise<unknown> {
  const allowed = FIELDS[action];
  if (!allowed) throw new Error(`Unknown learn action: ${action}`);
  fields(input, action, allowed);
  const cwd = projectOf(source);
  const now = Date.now();

  switch (action) {
    case "map.read": {
      const found = await projectLearnMap(cwd);
      const saved = found && await readCanvasScene(found.id);
      if (!saved) return { exists: false, next: "No learning map in this project yet. Ask the learner two things in one message: why they are learning this (what they want to be able to do), and what they already know, told freely. Then call map_init with their words, and map_record for what they said they know." };
      const canvas = await showDue(saved, now);
      const view = readMap(canvas.dataJson, now);
      seenEdits.set(source.id, editSignature(view));
      host.reveal(canvas.id, source.id);
      const url = appResourceUrl("canvas", canvas.id);
      if (input.nodeId !== undefined) {
        const node = view.nodes.find((entry) => entry.id === input.nodeId);
        if (!node) throw new Error(`"${String(input.nodeId)}" is not a node on this map`);
        // The learner's earlier words are the answer to a revisit; they stay hidden until it is done.
        const pending = node.kind === "concept" && (node.due || recalls.get(source.id)?.nodeId === node.id);
        const note = node.noteId ? await getNote(node.noteId) : null;
        return {
          ...nodeLine(node), kind: node.kind, ...(node.dueAt === undefined ? {} : { dueOn: day(node.dueAt) }), ...(node.step === undefined ? {} : { step: node.step }),
          sources: node.sources ?? [], history: node.history.map((event) => ({ on: day(event.at), type: event.type, ...(event.verdict ? { verdict: event.verdict } : {}) })),
          ...(node.noteId ? { noteUrl: appResourceUrl("note", node.noteId) } : {}),
          ...(pending ? { note: "Withheld: a revisit is due. Call revisit with phase start; the learner's earlier words come back when it finishes." } : { note: note?.body ?? "" }),
        };
      }
      const ghosts = view.nodes.filter((node) => node.state === "ghost").length;
      // What a connection says is what the learner said about its ends, so it is withheld like the note
      // while either end is due or being revisited. It comes back when the revisit finishes.
      const hidden = new Set(view.nodes.filter((node) => node.kind === "concept" && (node.due || recalls.get(source.id)?.nodeId === node.id)).map((node) => node.id));
      const withheld = (edge: { from: string | null; to: string | null }) => (!!edge.from && hidden.has(edge.from)) || (!!edge.to && hidden.has(edge.to));
      return {
        exists: true, canvasId: canvas.id, url, title: view.title, mission: view.mission,
        nodes: view.nodes.map(nodeLine),
        edges: view.edges.map((edge) => ({
          id: edge.id, from: edge.from, to: edge.to,
          ...(edge.label ? withheld(edge) ? { labelWithheld: true } : { label: edge.label } : {}),
          ...(edge.by === "proposed" ? { proposed: true } : {}),
        })),
        ...(view.untracked.shapes.length || view.untracked.edges.length ? { drawnByLearner: view.untracked } : {}),
        revisit: pickRevisits(view.nodes).map(({ id, label, kind }) => ({ id, label, kind })),
        unexplored: `${ghosts} of at most ${GHOST_LIMIT}`,
        ...(input.stats === true ? { stats: mapStats(view, now) } : {}),
        rules: "Solid nodes are what the learner has explained in their own words; dashed ones are not learned yet. Only map_record with the learner's words makes a node solid. Never present a dashed node, or anything you explained, as something the learner knows.",
      };
    }

    case "map.init": {
      const subject = text(input.subject, "subject", 80);
      const why = learnerQuote(source, input.why, "why");
      const success = list(input.success, "success", 5).map((entry) => learnerQuote(source, entry, "success"));
      const existing = await projectLearnMap(cwd);
      if (existing) {
        host.reveal(existing.id, source.id);
        return { canvasId: existing.id, title: existing.title, url: appResourceUrl("canvas", existing.id), saved: true, created: false, text: "This project already has a learning map; nothing was changed. Call map_read." };
      }
      const { initMapScene } = await import("./model/mapScene");
      const canvas = await upsertCanvas({ ...createEmptyCanvas(cwd), title: subject, dataJson: initMapScene(subject, why, success), tags: [LEARN_MAP_TAG] });
      host.reveal(canvas.id, source.id);
      return { canvasId: canvas.id, title: canvas.title, url: appResourceUrl("canvas", canvas.id), saved: true, created: true };
    }

    case "map.sketch": {
      const map = await requireMap(cwd);
      const labels = list(input.nodes, "nodes", SKETCH_LIMIT, 1).map((entry) => text(entry, "node label", 60));
      const edges = list(input.edges, "edges", 6).map((entry): EdgeRecord => {
        const edge = fields(entry, "edge", ["from", "to", "label"]);
        return { from: text(edge.from, "edge from", 256), to: text(edge.to, "edge to", 256), label: optionalText(edge.label, "edge label", 40) };
      });
      const near = optionalText(input.near, "near", 256);
      const { sketchOnMap } = await import("./model/mapScene");
      let written: { nodes: WrittenNode[]; edges: string[] } = { nodes: [], edges: [] };
      const saved = await writeCanvasScene(map.id, (current) => {
        const result = sketchOnMap(current.dataJson, { near, labels, edges }, writeContext(source, map.id, now));
        written = result;
        return { dataJson: result.dataJson, viewport: result.viewport };
      });
      host.reveal(saved.id, source.id);
      return { canvasId: saved.id, title: saved.title, url: appResourceUrl("canvas", saved.id), saved: true,
        nodes: written.nodes.map(({ id, label }) => ({ id, label, state: "ghost" })), edges: written.edges };
    }

    case "map.record": {
      const map = await requireMap(cwd);
      const known = readMap(map.dataJson, now);
      const subject = known.title || map.title;
      const records: NodeRecord[] = [];
      const sections: string[][] = [];
      for (const entry of list(input.nodes, "nodes", RECORD_LIMIT)) {
        const node = fields(entry, "node", ["kind", "id", "label", "near", "evidence", "quote", "verdict", "sources", "correction", "wrongIf", "lookBackAt", "detail"]);
        const kind = oneOf(node.kind, "kind", ["concept", "judgment"] as const, "concept");
        const evidence = oneOf(node.evidence, "evidence", ["said", "prior", "drew", "did"] as const, "said");
        const id = optionalText(node.id, "id", 256);
        const label = optionalText(node.label, "label", 60);
        if (!id && !label) throw new Error("Each node needs an id (an existing node or a shape the learner drew) or a label");
        const correction = optionalText(node.correction, "correction", 2000);
        const today = day(now);
        const lines: string[] = [];
        let verdict: RecordVerdict | undefined;
        let lookBackAt: number | undefined;
        if (kind === "judgment") {
          if (evidence !== "said") throw new Error("A judgment is recorded with evidence \"said\"");
          const thesis = learnerQuote(source, node.quote, "quote");
          const wrongIf = learnerQuote(source, node.wrongIf, "wrongIf");
          lookBackAt = futureDay(node.lookBackAt, "lookBackAt", now);
          lines.push(`### ${today} · judgment`, quoted(thesis), "", "Wrong if:", quoted(wrongIf), "", `Look back on: ${day(lookBackAt)}`);
        } else if (evidence === "did") {
          // Doing follows explaining: use never creates a node the learner has not put into words.
          if (!known.nodes.some((entry) => entry.id === id || (label !== undefined && entry.label.trim().toLowerCase() === label.toLowerCase())))
            throw new Error("Evidence \"did\" is for a node already on the map. Record what the learner said about it first.");
          const detail = text(node.detail, "detail", 2000);
          lines.push(`### ${today} · did`, `Agent's statement: ${detail}`);
        } else if (evidence === "drew") {
          if (!id) throw new Error("Evidence \"drew\" records a shape the learner drew: pass its id from map_read");
          lines.push(`### ${today} · drew`, "The learner drew this on the map.");
        } else {
          verdict = oneOf(node.verdict, "verdict", ["right", "partly", "wrong"] as const);
          lines.push(`### ${today} · ${evidence === "prior" ? "already knew" : "said"} · ${verdict}`, quoted(learnerQuote(source, node.quote, "quote")));
        }
        const sources = await sourcesOf(node.sources, cwd);
        if (correction) lines.push("", `Correction (agent): ${correction}`);
        if (sources.length) lines.push("", `Sources: ${sources.map(sourceLine).join("; ")}`);
        lines.push("", `Session: ${sessionLink(source)}`);
        records.push({ kind, evidence, ...(id ? { id } : {}), ...(label ? { label } : {}), ...(verdict ? { verdict } : {}), ...(sources.length ? { sources } : {}),
          ...(lookBackAt === undefined ? {} : { lookBackAt }), ...(typeof node.near === "string" ? { near: text(node.near, "near", 256) } : {}) });
        sections.push(lines);
      }
      const edges = list(input.edges, "edges", 24).map((entry): EdgeRecord => {
        const edge = fields(entry, "edge", ["id", "from", "to", "label"]);
        if (edge.id !== undefined) return { id: text(edge.id, "edge id", 256) };
        const label = optionalText(edge.label, "edge label", 40);
        if (label && labelColumns(label) > EDGE_LABEL_COLUMNS)
          throw new Error(`edge label "${label}" is too long to sit on an arrow. Use a few words of the learner's wording (at most ${EDGE_LABEL_COLUMNS / 2} CJK characters or ${EDGE_LABEL_COLUMNS} letters).`);
        if (label && !wordedByLearner(source.blocks, label))
          throw new Error(`edge label "${label}" must be lifted from the learner's own wording in this session. Use their words for how the two connect, or leave the label out.`);
        return { from: text(edge.from, "edge from", 256), to: text(edge.to, "edge to", 256), ...(label ? { label } : {}) };
      });
      if (!records.length && !edges.length) throw new Error("Nothing to record: pass nodes, edges or both");
      const { recordOnMap } = await import("./model/mapScene");
      let written: { nodes: WrittenNode[]; edges: string[] } = { nodes: [], edges: [] };
      const saved = await writeCanvasScene(map.id, (current) => {
        const result = recordOnMap(current.dataJson, records, edges, writeContext(source, map.id, now));
        written = result;
        return { dataJson: result.dataJson, viewport: result.viewport };
      });
      host.reveal(saved.id, source.id);
      // Records on one node add to the same note, so the writes go one after another:
      // each reads what the one before it left, and none of the learner's words is lost.
      const noted = new Map<string, boolean>();
      for (const [index, node] of written.nodes.entries()) {
        if (!node.noteId) continue;
        const done = await appendNote(source, cwd, subject, node.noteId, node.label, sections[index].join("\n"));
        noted.set(node.noteId, (noted.get(node.noteId) ?? true) && done);
      }
      // A node recorded twice in one call is reported once, as it stands after both.
      const final = new Map(written.nodes.map((node) => [node.id, node]));
      return {
        canvasId: saved.id, title: saved.title, url: appResourceUrl("canvas", saved.id), saved: true,
        nodes: [...final.values()].map((node) => ({
          id: node.id, label: node.label, state: node.state, ...(written.nodes.find((entry) => entry.id === node.id && entry.created) ? { created: true } : {}),
          ...(node.dueAt === undefined ? {} : { [node.kind === "judgment" ? "lookBackOn" : "revisitOn"]: day(node.dueAt) }),
          ...(node.noteId && noted.get(node.noteId) ? { noteUrl: appResourceUrl("note", node.noteId) } : node.noteId ? { noteSaved: false } : {}),
        })),
        edges: written.edges,
      };
    }

    case "revisit.start": {
      const map = await requireMap(cwd);
      const node = readMap(map.dataJson, now).nodes.find((entry) => entry.id === input.nodeId);
      if (!node) throw new Error(`"${String(input.nodeId)}" is not a node on this map; call map_read for ids`);
      if (node.kind === "concept" && node.state === "ghost") throw new Error("This node has not been explained yet, so there is nothing to revisit. Explore it with the learner instead.");
      if (node.kind === "judgment" && node.state === "closed") throw new Error("This judgment has already been looked back on.");
      endRecall(source.id);
      recalls.set(source.id, { canvasId: map.id, nodeId: node.id, kind: node.kind, fromIndex: source.blocks.length, peeked: false });
      host.reveal(map.id, source.id);
      window.dispatchEvent(new CustomEvent(LEARN_RECALL_EVENT, { detail: map.id }));
      if (node.kind === "judgment") {
        const note = node.noteId ? await getNote(node.noteId) : null;
        return { id: node.id, label: node.label, kind: node.kind, written: note?.body ?? "",
          next: "Show the learner what they wrote then. Ask what actually happened, and what they take from it. Then call revisit with phase finish and their words." };
      }
      return { id: node.id, label: node.label, kind: node.kind,
        next: "The map is covered. Name only this node and ask the learner to explain from memory what it is and what it connects to. Give no hints and do not restate their earlier words. When they answer, call revisit with phase finish, a passage of their answer and your verdict. If they would rather not, call revisit with phase cancel." };
    }

    case "revisit.cancel": {
      endRecall(source.id);
      return { cancelled: true, text: "No change: the node stays due. Do not bring it up again in this session." };
    }

    case "revisit.finish": {
      const recall = recalls.get(source.id);
      if (!recall || recall.nodeId !== input.nodeId) throw new Error("No revisit of this node is under way in this session. Call revisit with phase start first, then ask the learner.");
      const map = await requireMap(cwd);
      const view = readMap(map.dataJson, now);
      const node = view.nodes.find((entry) => entry.id === recall.nodeId);
      if (!node) { endRecall(source.id); throw new Error("The node was removed from the map during the revisit."); }
      const quote = learnerQuote(source, input.quote, "quote", recall.fromIndex);
      const context = writeContext(source, map.id, now);
      const scenes = await import("./model/mapScene");
      const before = node.noteId ? (await getNote(node.noteId))?.body ?? "" : "";
      const labelOf = new Map(view.nodes.map((entry) => [entry.id, entry.label]));
      const connections = view.edges.filter((edge) => edge.label && (edge.from === node.id || edge.to === node.id))
        .map((edge) => ({ with: labelOf.get(edge.from === node.id ? edge.to ?? "" : edge.from ?? "") ?? "", said: edge.label }));
      const today = day(now);
      if (recall.kind === "judgment") {
        const principle = input.principle === undefined ? undefined : fields(input.principle, "principle", ["label", "quote"]);
        const lesson = principle ? { label: text(principle.label, "principle label", 60), quote: learnerQuote(source, principle.quote, "principle quote", recall.fromIndex) } : undefined;
        let added: WrittenNode[] = [];
        const saved = await writeCanvasScene(map.id, (current) => {
          const closed = scenes.closeJudgment(current.dataJson, node.id, context);
          if (!lesson) return { dataJson: closed.dataJson };
          const result = scenes.recordOnMap(closed.dataJson, [{ kind: "concept", label: lesson.label, near: node.id, evidence: "said", verdict: "right" }], [{ from: lesson.label, to: node.id }], context);
          added = result.nodes;
          return { dataJson: result.dataJson, viewport: result.viewport };
        });
        endRecall(source.id);
        if (node.noteId) await appendNote(source, cwd, view.title || map.title, node.noteId, node.label, [`### ${today} · looked back`, quoted(quote), "", `Session: ${sessionLink(source)}`].join("\n"));
        for (const principleNode of added)
          if (principleNode.noteId && lesson) await appendNote(source, cwd, view.title || map.title, principleNode.noteId, principleNode.label,
            [`### ${today} · said · right`, quoted(lesson.quote), "", `From looking back on: ${node.label}`, "", `Session: ${sessionLink(source)}`].join("\n"));
        return { canvasId: saved.id, title: saved.title, url: appResourceUrl("canvas", saved.id), saved: true, id: node.id, state: "closed",
          ...(added.length ? { principle: { id: added[0].id, label: added[0].label } } : {}) };
      }
      const given = oneOf(input.verdict, "verdict", ["solid", "shaky", "gone"] as const) as RecallVerdict;
      // Looking at the map during the revisit is allowed, but then the recall was not from memory.
      const verdict: RecallVerdict = recall.peeked && given === "solid" ? "shaky" : given;
      let data: { state: string; dueAt?: number } = { state: node.state };
      const saved = await writeCanvasScene(map.id, (current) => {
        const result = scenes.finishRecall(current.dataJson, node.id, verdict, context);
        data = result.data;
        return { dataJson: result.dataJson };
      });
      endRecall(source.id);
      if (node.noteId) await appendNote(source, cwd, view.title || map.title, node.noteId, node.label, [`### ${today} · revisit · ${verdict}`, quoted(quote), "", `Session: ${sessionLink(source)}`].join("\n"));
      return {
        canvasId: saved.id, title: saved.title, url: appResourceUrl("canvas", saved.id), saved: true, id: node.id, label: node.label, verdict, state: data.state,
        ...(data.dueAt === undefined ? {} : { revisitOn: day(data.dueAt) }),
        ...(verdict !== given ? { adjusted: "The learner uncovered the map during the revisit, so it counts as shaky, not solid." } : {}),
        earlier: before, connections,
        next: "Show the learner their earlier words above, and what they connected it to, next to what they just said, and name exactly what was missing or wrong, if anything. If they disagree with the verdict, they can change it in the map's inspector.",
      };
    }
  }
}
