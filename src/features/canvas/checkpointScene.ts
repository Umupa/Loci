import { convertToExcalidrawElements, newElementWith, restoreElements } from "@excalidraw/excalidraw";
import { isNativeElement, isRecord, validateSceneElements, type SceneElement } from "./scene";

type ExcalidrawElements = Parameters<typeof restoreElements>[0];
type NativeElement = NonNullable<ExcalidrawElements>[number];
type Skeletons = NonNullable<Parameters<typeof convertToExcalidrawElements>[0]>;

/** What one Excalidraw MCP call changes on a canvas. */
export type CheckpointPatch = {
  /** MCP-format elements: shorthand shapes, complete elements and camera commands. */
  elements: unknown[];
  /** Ids the call removed from the scene it loaded. */
  deletedIds?: string[];
  /** `elements` is the whole scene rather than additions to it. */
  replace?: boolean;
};

export type SceneViewport = { x: number; y: number; width: number; height: number };

export type PatchedScene = {
  dataJson: string;
  /** The last camera command, so an open pane can show what was drawn. */
  viewport?: SceneViewport;
};

// Commands the official server leaves in a checkpoint or strips before saving.
const pseudoTypes = new Set(["cameraUpdate", "delete", "restoreCheckpoint"]);
const bindableTypes = new Set(["rectangle", "diamond", "ellipse", "image", "iframe", "embeddable", "frame", "magicframe", "text"]);

const live = (element: NativeElement) => !element.isDeleted;
const containerOf = (element: NativeElement) => (element as { containerId?: string | null }).containerId ?? null;
const bindingTarget = (element: NativeElement, end: "startBinding" | "endBinding") =>
  (element as unknown as Record<string, { elementId?: string } | null | undefined>)[end]?.elementId;

function parseScene(dataJson: string): { elements: NativeElement[]; appState: Record<string, unknown>; files: Record<string, unknown> } {
  let scene: unknown;
  try { scene = JSON.parse(dataJson); } catch { scene = null; }
  const record = isRecord(scene) ? scene : {};
  return {
    elements: Array.isArray(record.elements) ? record.elements as NativeElement[] : [],
    appState: isRecord(record.appState) ? record.appState : {},
    files: isRecord(record.files) ? record.files : {},
  };
}

/** The camera the agent ended on; other commands are already resolved by the server. */
function splitCommands(elements: unknown[]): { drawn: unknown[]; viewport?: SceneViewport } {
  let viewport: SceneViewport | undefined;
  const drawn = elements.filter((element) => {
    if (!isRecord(element) || !pseudoTypes.has(element.type as string)) return true;
    if (element.type === "cameraUpdate" && [element.x, element.y, element.width, element.height].every(Number.isFinite) &&
      (element.width as number) > 0 && (element.height as number) > 0)
      viewport = { x: element.x as number, y: element.y as number, width: element.width as number, height: element.height as number };
    return false;
  });
  return { drawn, viewport };
}

const frameTypes = new Set(["frame", "magicframe"]);

/**
 * Shorthand the official reference teaches: labels on shapes, and arrows that
 * name their ends with `startBinding.elementId`. Excalidraw's converter binds
 * through `start`/`end` and only to elements in the same call, so an arrow to
 * an existing shape gets a geometry-only stand-in that is dropped afterwards.
 * The real element is never rebuilt, which keeps its style, text and image.
 */
function convertShorthand(shorthand: SceneElement[], kept: NativeElement[]): NativeElement[] {
  if (!shorthand.length) return [];
  const drawnIds = new Set(shorthand.map((element) => element.id));
  const existing = new Map(kept.filter(live).map((element) => [element.id, element]));
  const standIns = new Map<string, Record<string, unknown>>();
  const endOf = (element: SceneElement, binding: "startBinding" | "endBinding", end: "start" | "end") => {
    const declared = isRecord(element[binding]) ? element[binding].elementId : isRecord(element[end]) ? element[end].id : undefined;
    if (typeof declared !== "string") return undefined;
    const drawn = shorthand.find((other) => other.id === declared);
    if (drawn) return frameTypes.has(drawn.type) ? undefined : { id: declared };
    const target = existing.get(declared);
    if (!target || !bindableTypes.has(target.type) || (target.type === "text" && containerOf(target))) return undefined;
    if (!standIns.has(declared)) standIns.set(declared, {
      type: target.type === "ellipse" || target.type === "diamond" ? target.type : "rectangle",
      id: declared, x: target.x, y: target.y, width: target.width, height: target.height, angle: target.angle,
    });
    return { id: declared };
  };
  const skeletons = shorthand.filter((element) => !frameTypes.has(element.type)).map((element) => {
    const skeleton: Record<string, unknown> = { ...element };
    if (isRecord(element.label)) skeleton.label = { textAlign: "center", verticalAlign: "middle", ...element.label };
    if (element.type === "arrow") {
      const start = endOf(element, "startBinding", "start");
      const end = endOf(element, "endBinding", "end");
      for (const key of ["startBinding", "endBinding", "start", "end"]) delete skeleton[key];
      if (start) skeleton.start = start;
      if (end) skeleton.end = end;
    }
    return skeleton;
  });
  const converted = convertToExcalidrawElements([...standIns.values(), ...skeletons] as unknown as Skeletons, { regenerateIds: false })
    .filter((element) => !standIns.has(element.id)) as NativeElement[];

  // The converter sizes frames from children of the same call and breaks on
  // empty ones, so frames are placed here and may also adopt existing elements.
  const framed = new Map<string, string>();
  const frames = shorthand.filter((element) => frameTypes.has(element.type)).map((frame) => {
    const { children, ...rest } = frame;
    const members = (Array.isArray(children) ? children : []).filter((id): id is string =>
      typeof id === "string" && (drawnIds.has(id) || existing.has(id)));
    if (frame.id) for (const id of members) framed.set(id, frame.id);
    const boxes = [...converted, ...kept].filter((element) => members.includes(element.id));
    const span = (from: (box: NativeElement) => number, to: (box: NativeElement) => number, origin: unknown, size: unknown) => {
      if (Number.isFinite(size) && (size as number) > 0) return [origin as number, size as number];
      if (!boxes.length) return [origin as number, 300];
      const low = Math.min(...boxes.map(from)) - 10;
      return [low, Math.max(...boxes.map(to)) + 10 - low];
    };
    const [x, width] = span((box) => Math.min(box.x, box.x + box.width), (box) => Math.max(box.x, box.x + box.width), frame.x, frame.width);
    const [y, height] = span((box) => Math.min(box.y, box.y + box.height), (box) => Math.max(box.y, box.y + box.height), frame.y, frame.height);
    return { ...rest, x, y, width, height } as unknown as NativeElement;
  });
  const frameOf = (element: NativeElement) => framed.get(element.id) ?? framed.get(containerOf(element) ?? "");
  kept.forEach((element, index) => {
    const frameId = live(element) ? frameOf(element) : undefined;
    if (frameId && element.frameId !== frameId) kept[index] = newElementWith(element, { frameId });
  });
  return [...frames, ...converted.map((element) => frameOf(element) ? { ...element, frameId: frameOf(element)! } : element)];
}

/** Arrows and labels name their shape; make every shape name them back. */
function syncBoundElements(elements: NativeElement[]): NativeElement[] {
  const bound = new Map<string, Array<{ id: string; type: "arrow" | "text" }>>();
  const add = (target: string | null | undefined, id: string, type: "arrow" | "text") => {
    if (!target) return;
    const list = bound.get(target) ?? [];
    if (!list.some((entry) => entry.id === id)) list.push({ id, type });
    bound.set(target, list);
  };
  for (const element of elements) {
    if (!live(element)) continue;
    if (element.type === "text") add(containerOf(element), element.id, "text");
    if (element.type === "arrow") {
      add(bindingTarget(element, "startBinding"), element.id, "arrow");
      add(bindingTarget(element, "endBinding"), element.id, "arrow");
    }
  }
  return elements.map((element) => {
    if (!live(element)) return element;
    const wanted = bound.get(element.id) ?? [];
    const current = element.boundElements ?? [];
    const retained = current.filter((entry) => wanted.some((other) => other.id === entry.id));
    const next = [...retained, ...wanted.filter((entry) => !current.some((other) => other.id === entry.id))];
    if (next.length === current.length && retained.length === current.length) return element;
    return newElementWith(element, { boundElements: next.length ? next : null });
  });
}

/**
 * Apply one MCP call to a saved scene. Everything the call does not delete or
 * redraw is carried over untouched, with the scene's images and settings.
 */
export function applyCheckpointPatch(dataJson: string, patch: CheckpointPatch): PatchedScene {
  const scene = parseScene(dataJson);
  const { drawn, viewport } = splitCommands(patch.elements);
  const incoming = validateSceneElements(drawn);
  const incomingIds = new Set(incoming.map((element) => element.id).filter((id): id is string => typeof id === "string"));
  const removed = new Set(patch.replace
    ? scene.elements.filter((element) => live(element) && !incomingIds.has(element.id)).map((element) => element.id)
    : patch.deletedIds ?? []);
  for (const element of incoming)
    if (element.type === "image" && !element.isDeleted && !(typeof element.fileId === "string" && scene.files[element.fileId]))
      throw new Error("Images can only be kept from the existing drawing; this Excalidraw MCP cannot attach new image files");

  const relabeled = new Set(incoming.filter((element) => isRecord(element.label)).map((element) => element.id));
  const kept: NativeElement[] = [];
  for (const element of scene.elements) {
    // A redrawn id replaces the old element; its new label replaces the old one.
    if (incomingIds.has(element.id)) continue;
    const container = containerOf(element);
    if (container && relabeled.has(container)) continue;
    if (!live(element)) { kept.push(element); continue; }
    if (removed.has(element.id) || (container && removed.has(container))) {
      kept.push(newElementWith(element, { isDeleted: true }));
      continue;
    }
    // Deleting a frame or a bound shape releases what pointed at it.
    const released: Record<string, null> = {};
    if (element.frameId && removed.has(element.frameId)) released.frameId = null;
    for (const end of ["startBinding", "endBinding"] as const) {
      const target = bindingTarget(element, end);
      if (target && removed.has(target)) released[end] = null;
    }
    kept.push(Object.keys(released).length ? newElementWith(element, released as never) : element);
  }

  const added = [
    ...convertShorthand(incoming.filter((element) => !isNativeElement(element)), kept),
    ...incoming.filter(isNativeElement) as unknown as NativeElement[],
  ];
  // A redrawn element stays where it was in the stack; new ones go on top.
  const redrawn = new Map(added.filter((element) => scene.elements.some((old) => old.id === element.id)).map((element) => [element.id, element]));
  const keptById = new Map(kept.map((element) => [element.id, element]));
  const ordered = [
    ...scene.elements.flatMap((old) => redrawn.get(old.id) ?? keptById.get(old.id) ?? []),
    ...added.filter((element) => !redrawn.has(element.id)),
  ];
  let elements: NativeElement[];
  try {
    elements = restoreElements(syncBoundElements(ordered), null, { repairBindings: true }) as NativeElement[];
  } catch (error) {
    throw new Error(`Could not restore Excalidraw scene elements: ${error instanceof Error ? error.message : "invalid scene"}`);
  }
  return { dataJson: JSON.stringify({ elements, appState: scene.appState, files: scene.files }), viewport };
}

/** Elements as the official fullscreen editor would save them. */
export function checkpointElements(dataJson: string): NativeElement[] {
  return parseScene(dataJson).elements.filter(live);
}

type Baseline = Record<string, [number, number, number, number, string?]>;

/** What the agent left behind, kept small enough to store with each checkpoint. */
export function checkpointBaseline(dataJson: string): string {
  const baseline: Baseline = {};
  for (const element of checkpointElements(dataJson)) {
    const text = (element as { text?: string }).text;
    const box: Baseline[string] = [Math.round(element.x), Math.round(element.y), Math.round(element.width), Math.round(element.height)];
    if (typeof text === "string") box.push(text);
    baseline[element.id] = box;
  }
  return JSON.stringify(baseline);
}

/** The user's edits since the agent last drew, in the official widget's wording. */
export function describeUserEdits(baselineJson: string, dataJson: string, checkpointId: string): string {
  let baseline: Baseline;
  try { baseline = JSON.parse(baselineJson); } catch { return ""; }
  if (!isRecord(baseline)) return "";
  const added: string[] = [];
  const moved: string[] = [];
  const retexted: string[] = [];
  const present = new Set<string>();
  for (const element of checkpointElements(dataJson)) {
    present.add(element.id);
    const before = baseline[element.id];
    const text = (element as { text?: string }).text;
    const [x, y, width, height] = [element.x, element.y, element.width, element.height].map(Math.round);
    if (!before) {
      // A label is reported with its shape.
      if (!containerOf(element) || baseline[containerOf(element)!]) added.push(`${element.type} "${text ?? ""}" at (${x},${y}) id ${element.id}`);
      continue;
    }
    if (typeof text === "string" && typeof before[4] === "string" && text !== before[4]) retexted.push(`${element.id} "${text}"`);
    // Bound text follows its container; free text is re-measured when fonts load.
    if (containerOf(element)) continue;
    const far = (a: number, b: number) => Math.abs(a - b) > 1;
    if (far(x, before[0]) || far(y, before[1]) || (element.type !== "text" && (far(width, before[2]) || far(height, before[3]))))
      moved.push(`${element.id} → (${x},${y}) ${width}x${height}`);
  }
  const removed = Object.keys(baseline).filter((id) => !present.has(id));
  const parts: string[] = [];
  if (added.length) parts.push(`Added: ${added.join("; ")}`);
  if (removed.length) parts.push(`Removed: ${removed.join(", ")}`);
  if (moved.length) parts.push(`Moved/resized: ${moved.join("; ")}`);
  if (retexted.length) parts.push(`Text changed: ${retexted.join("; ")}`);
  return parts.length ? `User edited diagram (checkpoint: ${checkpointId}). ${parts.join(". ")}` : "";
}

const compactDefaults: Record<string, unknown> = {
  strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "solid", strokeWidth: 2, strokeStyle: "solid",
  roughness: 1, opacity: 100, angle: 0, fontFamily: 5, textAlign: "left", verticalAlign: "top",
};
const compactKeys = ["strokeColor", "backgroundColor", "fillStyle", "strokeWidth", "strokeStyle", "roughness", "opacity", "angle",
  "text", "fontSize", "fontFamily", "textAlign", "verticalAlign", "containerId", "frameId", "name", "fileId",
  "startArrowhead", "endArrowhead", "elbowed", "link", "locked"];

/** The scene for a model to read: ids and geometry without render bookkeeping. */
export function compactElements(dataJson: string): Array<Record<string, unknown>> {
  return checkpointElements(dataJson).map((element) => {
    const source = element as unknown as Record<string, unknown>;
    const out: Record<string, unknown> = { type: element.type, id: element.id,
      x: Math.round(element.x), y: Math.round(element.y), width: Math.round(element.width), height: Math.round(element.height) };
    for (const key of compactKeys) {
      const value = source[key];
      if (value === undefined || value === null || value === false || value === compactDefaults[key]) continue;
      if (key === "endArrowhead" && value === "arrow") continue;
      out[key] = value;
    }
    if (Array.isArray(source.points) && (element.type === "arrow" || element.type === "line"))
      out.points = source.points.map((point) => (point as number[]).map(Math.round));
    if (Array.isArray(source.groupIds) && source.groupIds.length) out.groupIds = source.groupIds;
    if (element.roundness) out.roundness = { type: element.roundness.type };
    for (const end of ["startBinding", "endBinding"] as const) {
      const target = bindingTarget(element, end);
      if (target) out[end] = { elementId: target };
    }
    return out;
  });
}

/** Name a new drawing after its heading: the largest free-standing text. */
export function suggestedTitle(dataJson: string): string | undefined {
  let best: { size: number; text: string } | undefined;
  for (const element of checkpointElements(dataJson)) {
    if (element.type !== "text" || containerOf(element)) continue;
    const { fontSize, text } = element as unknown as { fontSize: number; text: string };
    const line = text.split("\n")[0].trim();
    if (line && (!best || fontSize > best.size)) best = { size: fontSize, text: line };
  }
  return best && best.text.length <= 80 ? best.text : best?.text.slice(0, 77).trimEnd().concat("…");
}
