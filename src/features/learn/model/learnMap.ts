/** A canvas with this tag is a learning map: agents change it only through `loci_learn`. */
export const LEARN_MAP_TAG = "learn-map";
/** What an agent is told when it tries to draw on a learning map with a general canvas tool. */
export const LEARN_MAP_WRITE_REFUSED =
  "This drawing is the learner's learning map. Change it with the loci_learn tools (map_sketch, map_record, revisit), and draw explanatory diagrams on another canvas.";
/** Unexplored nodes that may wait on a map at once, so it never turns into a syllabus. */
export const GHOST_LIMIT = 9;
/** Unexplored nodes one sketch may add. */
export const SKETCH_LIMIT = 3;
/** Nodes one record may hold: orientation records everything the learner already knows. */
export const RECORD_LIMIT = 12;
/** Revisits offered at the start of a sitting. */
export const REVISIT_LIMIT = 3;
/** Days before each revisit. A recall that holds moves one step along. */
export const LADDER_DAYS = [1, 3, 7, 21, 60, 150] as const;
export const DAY_MS = 86_400_000;
/** A recall that holds after this long anchors the node. */
export const ANCHOR_AFTER_MS = 7 * DAY_MS;

/** What a state change rests on. `did` is the agent's statement; the host checks the others. */
export type Evidence = "said" | "drew" | "prior" | "did" | "recall" | "reality";
export type RecordVerdict = "right" | "partly" | "wrong";
export type RecallVerdict = "solid" | "shaky" | "gone";
export type LearnSource = { path: string; page?: number; lines?: [number, number] } | { url: string; accessedAt: string };
export type LearnEvent = {
  at: number;
  type: Evidence;
  verdict?: RecordVerdict | RecallVerdict;
  sessionId: string;
  /** Revisits: where the node stood before, so the learner can overrule the verdict. */
  from?: { state: "ghost" | "solid" | "anchored"; step?: number };
};

/** `self` is the element's own id, so a pasted copy does not inherit the state. */
type Common = { v: 1; self: string };
export type ConceptData = Common & {
  kind: "concept";
  /** Not learned yet, explained once, or still explained after a week (or put to use). */
  state: "ghost" | "solid" | "anchored";
  noteId?: string;
  /** Position on the revisit ladder. */
  step?: number;
  dueAt?: number;
  sources?: LearnSource[];
  unsourced?: true;
  history: LearnEvent[];
};
export type JudgmentData = Common & {
  kind: "judgment";
  state: "open" | "closed";
  noteId?: string;
  /** The date the learner chose to compare the judgment with what happened. */
  dueAt?: number;
  history: LearnEvent[];
};
export type MissionData = Common & { kind: "mission" };
export type EdgeData = Common & { kind: "edge"; by: "learner" | "proposed" };
export type LearnData = ConceptData | JudgmentData | MissionData | EdgeData;

export type El = Record<string, unknown> & { id: string; type: string; x: number; y: number; width: number; height: number; isDeleted?: boolean };
export type Scene = { elements: El[]; appState: Record<string, unknown>; files: Record<string, unknown> };

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isLearnMap(canvas: { tags?: readonly string[] }): boolean {
  return !!canvas.tags?.includes(LEARN_MAP_TAG);
}

export function parseScene(dataJson: string): Scene {
  let scene: unknown;
  try { scene = JSON.parse(dataJson); } catch { scene = null; }
  const record = isRecord(scene) ? scene : {};
  return {
    elements: Array.isArray(record.elements) ? record.elements as El[] : [],
    appState: isRecord(record.appState) ? record.appState : {},
    files: isRecord(record.files) ? record.files : {},
  };
}

/** The element's learning state, unless it was copied from another element. */
export function learnData(element: El): LearnData | undefined {
  const data = isRecord(element.customData) ? element.customData.learn : undefined;
  if (!isRecord(data) || data.v !== 1 || data.self !== element.id) return undefined;
  if (data.kind === "concept" || data.kind === "judgment") return Array.isArray(data.history) ? data as LearnData : undefined;
  return data.kind === "mission" || data.kind === "edge" ? data as LearnData : undefined;
}

export const live = (element: El) => !element.isDeleted;
const containerOf = (element: El) => typeof element.containerId === "string" ? element.containerId : null;
const boundTo = (element: El, end: "startBinding" | "endBinding") => {
  const binding = element[end];
  return isRecord(binding) && typeof binding.elementId === "string" ? binding.elementId : null;
};

/** The text a person reads on each shape or arrow, by the id of what carries it. */
export function labelsByOwner(elements: readonly El[]): Map<string, string> {
  const labels = new Map<string, string>();
  for (const element of elements) {
    if (!live(element) || element.type !== "text" || typeof element.text !== "string") continue;
    // A label inside a shape is wrapped to fit; `originalText` is the name as it was given.
    const written = containerOf(element) && typeof element.originalText === "string" ? element.originalText : element.text;
    labels.set(containerOf(element) ?? element.id, written.replace(/\s*\n\s*/g, " ").trim());
  }
  return labels;
}

export type MapNode = {
  id: string;
  label: string;
  kind: "concept" | "judgment";
  state: ConceptData["state"] | JudgmentData["state"];
  due: boolean;
  dueAt?: number;
  step?: number;
  noteId?: string;
  unsourced?: true;
  sources?: LearnSource[];
  history: LearnEvent[];
  /** Arrows touching the node. */
  links: number;
};
export type MapEdge = { id: string; from: string | null; to: string | null; label: string; by: EdgeData["by"] };
export type MapView = {
  title: string;
  mission: string;
  nodes: MapNode[];
  edges: MapEdge[];
  /** What the learner drew by hand and nobody has recorded yet. */
  untracked: {
    shapes: Array<{ id: string; type: string; text: string }>;
    edges: Array<{ id: string; from: string | null; to: string | null; label: string }>;
  };
};

const shapeTypes = new Set(["rectangle", "ellipse", "diamond"]);

/** The map as an agent and the inspector read it: meaning, not drawing instructions. */
export function readMap(dataJson: string, now: number): MapView {
  return viewOf(parseScene(dataJson).elements, now);
}

/** `readMap` for a scene that is already in memory, such as the one a pane is showing. */
export function viewOf(scene: readonly El[], now: number): MapView {
  const elements = scene.filter(live);
  const labels = labelsByOwner(elements);
  const view: MapView = { title: "", mission: "", nodes: [], edges: [], untracked: { shapes: [], edges: [] } };
  const degree = new Map<string, number>();
  for (const element of elements) {
    if (element.type !== "arrow") continue;
    for (const end of [boundTo(element, "startBinding"), boundTo(element, "endBinding")])
      if (end) degree.set(end, (degree.get(end) ?? 0) + 1);
  }
  for (const element of elements) {
    const data = learnData(element);
    const label = labels.get(element.id) ?? "";
    if (data?.kind === "mission") {
      if (element.id === TITLE_ID) view.title = label;
      else view.mission = typeof element.text === "string" ? element.text : label;
    } else if (data?.kind === "concept" || data?.kind === "judgment") {
      const pending = data.kind === "concept" ? data.state !== "ghost" : data.state === "open";
      view.nodes.push({
        id: element.id, label, kind: data.kind, state: data.state,
        due: pending && data.dueAt !== undefined && data.dueAt <= now,
        ...(data.dueAt === undefined ? {} : { dueAt: data.dueAt }),
        ...(data.kind === "concept" && data.step !== undefined ? { step: data.step } : {}),
        ...(data.noteId ? { noteId: data.noteId } : {}),
        ...(data.kind === "concept" && data.unsourced ? { unsourced: true as const } : {}),
        ...(data.kind === "concept" && data.sources?.length ? { sources: data.sources } : {}),
        history: data.history, links: degree.get(element.id) ?? 0,
      });
    } else if (element.type === "arrow") {
      const edge = { id: element.id, from: boundTo(element, "startBinding"), to: boundTo(element, "endBinding"), label };
      if (data?.kind === "edge") view.edges.push({ ...edge, by: data.by });
      else view.untracked.edges.push(edge);
    } else if (shapeTypes.has(element.type) || (element.type === "text" && !containerOf(element))) {
      view.untracked.shapes.push({ id: element.id, type: element.type, text: label });
    }
  }
  return view;
}

export const TITLE_ID = "learn-title";
export const MISSION_ID = "learn-mission";
