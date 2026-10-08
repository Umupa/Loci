import { newElementWith } from "@excalidraw/excalidraw";
import { applyCheckpointPatch, type SceneViewport } from "../../canvas/checkpointScene";
import {
  GHOST_LIMIT, MISSION_ID, TITLE_ID, isRecord, labelsByOwner, learnData, live, parseScene,
  type ConceptData, type EdgeData, type El, type JudgmentData, type LearnSource, type RecallVerdict, type RecordVerdict,
} from "./learnMap";
import { connect, placeInRows, placeNear, type Box } from "./placement";
import { labelColumns } from "./quote";
import { afterRecall, scheduleFirst } from "./schedule";

const CONCEPT = { width: 180, height: 64 };
const JUDGMENT = { width: 220, height: 120 };
const adoptable = new Set(["rectangle", "ellipse", "diamond"]);

export type WriteContext = {
  now: number;
  sessionId: string;
  /** A fresh element id starting with `prefix`. */
  newId(prefix: string): string;
  /** The note that holds what the learner said about an element. */
  noteId(elementId: string): string;
};

export type NodeRecord = {
  kind: "concept" | "judgment";
  /** An existing node, or a shape the learner drew that is being recorded. */
  id?: string;
  /** A node by name: the existing one with this label, or a new one. */
  label?: string;
  /** The node a new one is placed beside. */
  near?: string;
  evidence: "said" | "prior" | "drew" | "did";
  verdict?: RecordVerdict;
  sources?: LearnSource[];
  /** Judgments: when to compare with what happened. */
  lookBackAt?: number;
};
export type EdgeRecord = { id?: string; from?: string; to?: string; label?: string };
export type WrittenNode = { id: string; label: string; kind: "concept" | "judgment"; state: string; created: boolean; noteId?: string; dueAt?: number };
export type MapWrite = { dataJson: string; nodes: WrittenNode[]; edges: string[]; viewport?: SceneViewport };

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
/** Excalidraw's own link badge on a node opens the note with the learner's words. */
const noteLink = (data: ConceptData | JudgmentData) => data.noteId && /^[A-Za-z0-9_-]+$/.test(data.noteId) ? `loci://note/${data.noteId}` : null;
const key = (label: string) => label.normalize("NFKC").trim().toLowerCase().replace(/\s+/g, " ");
const boxOf = ({ x, y, width, height }: El): Box => ({ x, y, width, height });

/** A node's look says its state: dashed until explained, heavy once it lasts, faint when a revisit is due. */
export function nodeStyle(data: ConceptData | JudgmentData, now: number) {
  const dashed = data.kind === "concept" && data.state === "ghost";
  const pending = data.kind === "concept" ? data.state !== "ghost" : data.state === "open";
  return {
    strokeStyle: dashed ? "dashed" : "solid",
    strokeWidth: data.state === "anchored" || data.state === "closed" ? 4 : dashed ? 1 : 2,
    opacity: pending && data.dueAt !== undefined && data.dueAt <= now ? 45 : 100,
  };
}

function patch(elements: El[], id: string, changes: Record<string, unknown>): boolean {
  const index = elements.findIndex((element) => element.id === id);
  if (index < 0 || Object.entries(changes).every(([name, value]) => same(elements[index][name], value))) return false;
  elements[index] = newElementWith(elements[index] as never, changes as never) as unknown as El;
  return true;
}

/** Store a node's state and redraw it to match; its label fades with it. */
function writeNode(elements: El[], id: string, data: ConceptData | JudgmentData, now: number): boolean {
  const element = elements.find((entry) => entry.id === id);
  if (!element) return false;
  const style = nodeStyle(data, now);
  let changed = patch(elements, id, { ...style, link: noteLink(data), customData: { ...(isRecord(element.customData) ? element.customData : {}), learn: data } });
  for (const label of elements)
    if (live(label) && label.type === "text" && label.containerId === id) changed = patch(elements, label.id, { opacity: style.opacity }) || changed;
  return changed;
}

/** Break mission text by hand: free-standing Excalidraw text does not wrap. */
function wrap(text: string, limit = 56): string {
  const lines: string[] = [];
  for (const paragraph of text.replace(/\r\n?/g, "\n").split("\n")) {
    let line = "";
    for (const char of paragraph) {
      if (labelColumns(line + char) > limit && line) {
        const cut = /\s/.test(char) ? -1 : line.lastIndexOf(" ");
        if (cut > 0 && labelColumns(line.slice(0, cut)) > limit / 3) { lines.push(line.slice(0, cut)); line = line.slice(cut + 1); }
        else { lines.push(line.trimEnd()); line = ""; }
        if (/\s/.test(char) && !line) continue;
      }
      line += char;
    }
    lines.push(line.trimEnd());
  }
  return lines.join("\n");
}

/** A new map: the subject as its title, then why the learner is here, in their words. */
export function initMapScene(subject: string, why: string, success: readonly string[]): string {
  const mission = [wrap(why), ...success.map((line) => wrap(`· ${line}`))].join("\n");
  const text = (id: string, y: number, content: string, fontSize: number) =>
    ({ type: "text", id, x: 0, y, text: content, fontSize, customData: { learn: { v: 1, self: id, kind: "mission" } } });
  return applyCheckpointPatch("", { elements: [text(TITLE_ID, 0, subject, 28), text(MISSION_ID, 52, mission, 16)] }).dataJson;
}

type Target = { id: string; box: Box; label: string };

/** Everything one write needs to know about the map as it stands. */
function workspace(dataJson: string, context: WriteContext) {
  const elements = parseScene(dataJson).elements;
  const ids = new Set(elements.map((element) => element.id));
  /** An id no element has, including ones tombstoned for undo. */
  const newId = (prefix: string) => {
    for (;;) {
      const id = context.newId(prefix);
      if (!ids.has(id)) { ids.add(id); return id; }
    }
  };
  const labels = labelsByOwner(elements);
  const nodes = new Map<string, Target>();
  const byLabel = new Map<string, Target[]>();
  const remember = (target: Target) => {
    if (nodes.has(target.id)) return;
    nodes.set(target.id, target);
    byLabel.set(key(target.label), [...(byLabel.get(key(target.label)) ?? []), target]);
  };
  for (const element of elements) {
    const data = live(element) ? learnData(element) : undefined;
    if (data?.kind === "concept" || data?.kind === "judgment") remember({ id: element.id, box: boxOf(element), label: labels.get(element.id) ?? "" });
  }
  const taken = elements.filter((element) => live(element) && element.type !== "arrow" && element.type !== "line" && !(element.type === "text" && element.containerId)).map(boxOf);
  const mission = elements.filter((element) => live(element) && learnData(element)?.kind === "mission");
  const top = mission.length ? Math.max(...mission.map((element) => element.y + element.height)) + 80 : 0;
  /** A node named by id or, when unambiguous, by label. */
  const find = (reference: string | undefined): Target | undefined => {
    if (!reference) return undefined;
    const named = byLabel.get(key(reference));
    return nodes.get(reference) ?? (named?.length === 1 ? named[0] : undefined);
  };
  const need = (reference: string | undefined, role: string): Target => {
    const target = find(reference);
    if (target) return target;
    throw new Error(reference && (byLabel.get(key(reference))?.length ?? 0) > 1
      ? `${role} "${reference}" names more than one node; use its id`
      : `${role} "${reference ?? ""}" is not a node on this map; call map_read for ids`);
  };
  const place = (near: Target | undefined, size: { width: number; height: number }): Box => {
    const box = { ...(near ? placeNear(taken, near.box, size) : placeInRows(taken, top, size)), ...size };
    taken.push(box);
    return box;
  };
  const named = (label: string) => byLabel.get(key(label)) ?? [];
  return { elements, labels, nodes, find, named, need, newId, place, remember };
}

function conceptShape(id: string, label: string, box: Box, data: ConceptData, now: number) {
  return { type: "rectangle", id, ...box, roundness: { type: 3 }, ...nodeStyle(data, now), link: noteLink(data), label: { text: label, fontSize: 18 }, customData: { learn: data } };
}

function arrow(id: string, from: Target, to: Target, label: string | undefined, by: EdgeData["by"]) {
  const line = connect(from.box, to.box);
  const [, [dx, dy]] = line.points;
  return {
    type: "arrow", id, ...line, width: Math.abs(dx), height: Math.abs(dy), endArrowhead: "arrow",
    start: { id: from.id }, end: { id: to.id }, strokeStyle: by === "proposed" ? "dashed" : "solid",
    ...(label ? { label: { text: label, fontSize: 16 } } : {}),
    customData: { learn: { v: 1, self: id, kind: "edge", by } satisfies EdgeData },
  };
}

function frame(boxes: readonly Box[]): SceneViewport | undefined {
  if (!boxes.length) return undefined;
  const left = Math.min(...boxes.map((box) => box.x)) - 120;
  const top = Math.min(...boxes.map((box) => box.y)) - 120;
  return { x: left, y: top, width: Math.max(...boxes.map((box) => box.x + box.width)) + 120 - left, height: Math.max(...boxes.map((box) => box.y + box.height)) + 120 - top };
}

/**
 * Add unexplored nodes beside what the learner knows. The cap is the point:
 * a map filled in by the agent would show the agent's understanding.
 */
export function sketchOnMap(dataJson: string, input: { near?: string; labels: readonly string[]; edges?: readonly EdgeRecord[] }, context: WriteContext): MapWrite {
  const map = workspace(dataJson, context);
  const waiting = [...map.nodes.keys()].filter((id) => {
    const data = learnData(map.elements.find((element) => element.id === id)!);
    return data?.kind === "concept" && data.state === "ghost";
  }).length;
  if (waiting + input.labels.length > GHOST_LIMIT)
    throw new Error(`The map already has ${waiting} unexplored nodes and may hold ${GHOST_LIMIT}. Explore some with the learner, or let the learner delete some, before adding more.`);
  const near = input.near ? map.need(input.near, "near") : undefined;
  const added: unknown[] = [];
  const nodes: WrittenNode[] = [];
  const boxes: Box[] = near ? [near.box] : [];
  for (const label of input.labels) {
    if (map.named(label).length) throw new Error(`"${label}" is already on the map (id ${map.named(label)[0].id})`);
    const id = map.newId("n");
    const box = map.place(near, CONCEPT);
    const data: ConceptData = { v: 1, self: id, kind: "concept", state: "ghost", history: [] };
    added.push(conceptShape(id, label, box, data, context.now));
    map.remember({ id, box, label });
    nodes.push({ id, label, kind: "concept", state: "ghost", created: true });
    boxes.push(box);
  }
  const edges: string[] = [];
  for (const edge of input.edges ?? []) {
    const id = map.newId("e");
    added.push(arrow(id, map.need(edge.from, "edge from"), map.need(edge.to, "edge to"), edge.label, "proposed"));
    edges.push(id);
  }
  return { dataJson: applyCheckpointPatch(dataJson, { elements: added }).dataJson, nodes, edges, viewport: frame(boxes) };
}

function recordedConcept(base: ConceptData, record: NodeRecord, context: WriteContext): ConceptData {
  const history = [...base.history, { at: context.now, type: record.evidence, ...(record.verdict ? { verdict: record.verdict } : {}), sessionId: context.sessionId }];
  const sources = [...(base.sources ?? []), ...(record.sources ?? [])].filter((source, index, all) => all.findIndex((other) => same(other, source)) === index);
  const { unsourced: _unsourced, sources: _sources, ...rest } = base;
  const next: ConceptData = {
    ...rest, history, noteId: context.noteId(base.self),
    ...(sources.length ? { sources } : record.evidence === "said" || base.unsourced ? { unsourced: true as const } : {}),
  };
  if (record.evidence === "did") return { ...next, state: "anchored", ...(next.dueAt === undefined ? scheduleFirst(context.now) : {}) };
  // A wrong explanation is kept as history; only one that holds makes the node solid.
  if (record.verdict === "wrong" || base.state !== "ghost") return next;
  return { ...next, state: "solid", ...scheduleFirst(context.now) };
}

/**
 * Record what the learner said, drew or did. New nodes are placed by the host;
 * nothing that exists is moved. An agent cannot reach this without evidence:
 * the caller has already checked the learner's words.
 */
export function recordOnMap(dataJson: string, records: readonly NodeRecord[], edgeRecords: readonly EdgeRecord[], context: WriteContext): MapWrite {
  const map = workspace(dataJson, context);
  const added: unknown[] = [];
  const updates = new Map<string, ConceptData | JudgmentData>();
  const fresh = new Set<string>();
  const nodes: WrittenNode[] = [];
  const boxes: Box[] = [];
  for (const record of records) {
    const element = record.id ? map.elements.find((entry) => entry.id === record.id && live(entry)) : undefined;
    if (record.id && !element) throw new Error(`Element "${record.id}" is not on this map; call map_read for ids`);
    const existing = element ? learnData(element) : undefined;
    if (element && !existing && !adoptable.has(element.type))
      throw new Error(`Element "${record.id}" is a ${element.type}; only a box, ellipse or diamond the learner drew can become a node`);
    if (existing && existing.kind !== record.kind) throw new Error(`Element "${record.id}" is not a ${record.kind} node`);
    let target = element ? map.find(element.id) ?? { id: element.id, box: boxOf(element), label: map.labels.get(element.id) ?? "" } : map.find(record.label);
    if (target && fresh.has(target.id)) throw new Error(`"${target.label}" appears twice in this call`);
    const current = target ? updates.get(target.id) ?? learnData(map.elements.find((entry) => entry.id === target!.id)!) : undefined;
    if (target && current && current.kind !== record.kind) throw new Error(`"${target.label}" is already on the map as a ${current.kind}`);
    const created = !target;
    if (!target) {
      if (!record.label?.trim()) throw new Error("A new node needs a label");
      const size = record.kind === "judgment" ? JUDGMENT : CONCEPT;
      target = { id: map.newId(record.kind === "judgment" ? "j" : "n"), box: map.place(record.near ? map.need(record.near, "near") : undefined, size), label: record.label.trim() };
    }
    let data: ConceptData | JudgmentData;
    if (record.kind === "judgment") {
      const base = (current as JudgmentData | undefined) ?? { v: 1 as const, self: target.id, kind: "judgment" as const, state: "open" as const, history: [] };
      if (record.lookBackAt === undefined && base.dueAt === undefined) throw new Error("A judgment needs lookBackAt, the date to compare it with what happened");
      data = { ...base, noteId: context.noteId(target.id), dueAt: record.lookBackAt ?? base.dueAt, history: [...base.history, { at: context.now, type: record.evidence, sessionId: context.sessionId }] };
    } else {
      data = recordedConcept((current as ConceptData | undefined) ?? { v: 1, self: target.id, kind: "concept", state: "ghost", history: [] }, record, context);
    }
    if (created) {
      fresh.add(target.id);
      added.push(record.kind === "judgment"
        ? { type: "diamond", id: target.id, ...target.box, ...nodeStyle(data, context.now), link: noteLink(data), label: { text: target.label, fontSize: 16 }, customData: { learn: data } }
        : conceptShape(target.id, target.label, target.box, data as ConceptData, context.now));
    } else updates.set(target.id, data);
    map.remember(target);
    boxes.push(target.box);
    nodes.push({ id: target.id, label: target.label, kind: record.kind, state: data.state, created, noteId: data.noteId, ...(data.dueAt === undefined ? {} : { dueAt: data.dueAt }) });
  }

  const edges: string[] = [];
  const deletedIds: string[] = [];
  const confirmed: string[] = [];
  const arrows = map.elements.filter((element) => live(element) && element.type === "arrow");
  const ends = (element: El) => [isRecord(element.startBinding) ? element.startBinding.elementId : null, isRecord(element.endBinding) ? element.endBinding.elementId : null];
  for (const edge of edgeRecords) {
    if (edge.id) {
      // An arrow the learner drew, or one the agent proposed and the learner accepts.
      const drawn = arrows.find((element) => element.id === edge.id);
      if (!drawn) throw new Error(`Arrow "${edge.id}" is not on this map; call map_read for ids`);
      if (!ends(drawn).every((end) => typeof end === "string" && map.nodes.has(end)))
        throw new Error(`Arrow "${edge.id}" does not join two nodes. Record the shapes it touches first, or ask the learner to attach both ends`);
      confirmed.push(drawn.id);
      edges.push(drawn.id);
      continue;
    }
    const from = map.need(edge.from, "edge from");
    const to = map.need(edge.to, "edge to");
    const between = arrows.filter((element) => learnData(element)?.kind === "edge" && same(ends(element), [from.id, to.id]));
    const identical = between.find((element) => key(map.labels.get(element.id) ?? "") === key(edge.label ?? ""));
    if (identical) { confirmed.push(identical.id); edges.push(identical.id); continue; }
    // The learner worded it differently from the agent's proposal: theirs replaces it.
    for (const proposal of between) if ((learnData(proposal) as EdgeData).by === "proposed") deletedIds.push(proposal.id);
    const id = map.newId("e");
    added.push(arrow(id, from, to, edge.label, "learner"));
    edges.push(id);
  }

  const patched = added.length || deletedIds.length ? applyCheckpointPatch(dataJson, { elements: added, deletedIds }).dataJson : dataJson;
  const scene = parseScene(patched);
  for (const [id, data] of updates) writeNode(scene.elements, id, data, context.now);
  for (const id of confirmed) {
    const element = scene.elements.find((entry) => entry.id === id);
    if (element) patch(scene.elements, id, { strokeStyle: "solid", customData: { ...(isRecord(element.customData) ? element.customData : {}), learn: { v: 1, self: id, kind: "edge", by: "learner" } satisfies EdgeData } });
  }
  return { dataJson: JSON.stringify(scene), nodes, edges, viewport: frame(boxes) };
}

function nodeElement(elements: El[], id: string, kind: "concept" | "judgment") {
  const element = elements.find((entry) => entry.id === id && live(entry));
  const data = element ? learnData(element) : undefined;
  if (!element || data?.kind !== kind) throw new Error(`"${id}" is not a ${kind} node on this map`);
  return { element, data };
}

/** Apply the outcome of a revisit from memory. */
export function finishRecall(dataJson: string, id: string, verdict: RecallVerdict, context: WriteContext): { dataJson: string; data: ConceptData } {
  const scene = parseScene(dataJson);
  const data = afterRecall(nodeElement(scene.elements, id, "concept").data as ConceptData, verdict, context.now, context.sessionId);
  writeNode(scene.elements, id, data, context.now);
  return { dataJson: JSON.stringify(scene), data };
}

/** Close a judgment once the learner has compared it with what happened. */
export function closeJudgment(dataJson: string, id: string, context: WriteContext): { dataJson: string; data: JudgmentData } {
  const scene = parseScene(dataJson);
  const { dueAt: _dueAt, ...open } = nodeElement(scene.elements, id, "judgment").data as JudgmentData;
  const data: JudgmentData = { ...open, state: "closed", history: [...open.history, { at: context.now, type: "reality", sessionId: context.sessionId }] };
  writeNode(scene.elements, id, data, context.now);
  return { dataJson: JSON.stringify(scene), data };
}

/** Let the learner overrule a revisit verdict: the last recall is judged again. */
export function overruleRecall(dataJson: string, id: string, verdict: RecallVerdict, context: WriteContext): { dataJson: string; data: ConceptData } {
  const scene = parseScene(dataJson);
  const current = nodeElement(scene.elements, id, "concept").data as ConceptData;
  const last = current.history[current.history.length - 1];
  if (last?.type !== "recall") throw new Error("This node's latest evidence is not a revisit");
  if (!last.from) throw new Error("This revisit cannot be judged again");
  // Replay from where the node stood going into that revisit.
  const { step: _step, ...rest } = current;
  const previous: ConceptData = { ...rest, state: last.from.state, ...(last.from.step === undefined ? {} : { step: last.from.step }), history: current.history.slice(0, -1) };
  const data = afterRecall(previous, verdict, last.at, last.sessionId);
  writeNode(scene.elements, id, data, context.now);
  return { dataJson: JSON.stringify(scene), data };
}

/** Fade nodes whose revisit is due and restore the rest. Null when nothing changes. */
export function refreshDue(dataJson: string, now: number): string | null {
  const scene = parseScene(dataJson);
  let changed = false;
  for (const element of [...scene.elements]) {
    const data = live(element) ? learnData(element) : undefined;
    if (data?.kind !== "concept" && data?.kind !== "judgment") continue;
    const { opacity } = nodeStyle(data, now);
    changed = patch(scene.elements, element.id, { opacity }) || changed;
    for (const label of scene.elements)
      if (live(label) && label.type === "text" && label.containerId === element.id) changed = patch(scene.elements, label.id, { opacity }) || changed;
  }
  return changed ? JSON.stringify(scene) : null;
}
