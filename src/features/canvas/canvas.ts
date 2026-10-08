import { invoke } from "@tauri-apps/api/core";
import type { ExcalidrawProps } from "@excalidraw/excalidraw/types";

type CanvasChange = NonNullable<ExcalidrawProps["onChange"]>;
export type CanvasScene = { elements: Parameters<CanvasChange>[0]; appState: Parameters<CanvasChange>[1]; files: Parameters<CanvasChange>[2]; baseDataJson?: string };
// Shared with persistence so replacements also retire drafts of closed panes.
export const canvasSceneDrafts = new Map<string, CanvasScene>();

export type Canvas = {
  id: string;
  title: string;
  dataJson: string;
  tags: string[];
  cwd?: string;
  createdAt: number;
  updatedAt: number;
};

export type CanvasUpsert = {
  id: string;
  title: string;
  dataJson: string;
  tags: string[];
  cwd?: string;
  /** Excalidraw MCP checkpoint saved with this scene, in one transaction. */
  checkpoint?: { id: string; baselineJson: string };
  /** Compare-and-swap revision for read/modify/write updates. */
  expectedUpdatedAt?: number;
};

/** A rectangle of the scene an agent asked viewers to look at. */
export type CanvasViewport = { x: number; y: number; width: number; height: number };
/** `CANVAS_SCENE_REPLACED_EVENT` detail: the saved canvas, where to look, and whether undo should skip it. */
export type CanvasSceneReplacement = Canvas & { viewport?: CanvasViewport; silent?: boolean };

export const CANVASES_CHANGED_EVENT = "loci-canvases-changed";
export const CANVAS_SCENE_ACCESS_EVENT = "loci-canvas-scene-access";
export const CANVAS_SCENE_REPLACED_EVENT = "loci-canvas-scene-replaced";
/** Ask the workspace to show the drawing behind an Excalidraw MCP checkpoint id. */
export const CANVAS_OPEN_CHECKPOINT_EVENT = "loci-canvas-open-checkpoint";

let cache: Canvas[] | null = null;

export function peekCanvases(): Canvas[] | null {
  return cache;
}

export function invalidateCanvases() {
  cache = null;
}

export async function loadCanvases(refresh = false): Promise<Canvas[]> {
  if (!refresh && cache) return cache;
  const list = await invoke<Canvas[]>("canvas_list");
  cache = list;
  return list;
}

export async function getCanvas(id: string): Promise<Canvas | null> {
  return invoke<Canvas | null>("canvas_get", { id });
}

/** The drawing an Excalidraw MCP checkpoint id (or a canvas id) refers to. */
export function checkpointCanvasId(checkpointId: string): Promise<string | null> {
  return invoke<string | null>("canvas_checkpoint_canvas", { checkpointId });
}

export async function upsertCanvas(canvas: CanvasUpsert): Promise<Canvas> {
  const result = await invoke<Canvas>("canvas_upsert", { canvas });
  if (cache) {
    const idx = cache.findIndex((c) => c.id === result.id);
    if (idx >= 0) {
      cache = cache.map((c, i) => (i === idx ? result : c));
    } else {
      cache = [result, ...cache];
    }
  }
  window.dispatchEvent(new Event(CANVASES_CHANGED_EVENT));
  return result;
}

// Preserve scene and title edits in order when a pane is moved or reopened.
const pendingUpdates = new Map<string, Promise<Canvas>>();
const deletingCanvases = new Set<string>();
type CanvasChanges = Partial<Omit<CanvasUpsert, "id">>;
/** Pass a function to derive the change from the canvas as saved at its turn in the queue. */
const CANVAS_CONFLICT = "Canvas changed since it was read; retry the update.";

/** Reapply local edits, leaving elements and document settings the user did not change intact. */
async function rebaseCanvasScene(baseJson: string, editedJson: string, currentJson: string): Promise<string> {
  type Element = Record<string, unknown> & { id: string };
  type Scene = { elements?: Element[]; appState?: Record<string, unknown>; files?: Record<string, unknown> };
  const base = JSON.parse(baseJson) as Scene;
  const edited = JSON.parse(editedJson) as Scene;
  const current = JSON.parse(currentJson) as Scene;
  const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
  const before = new Map((base.elements ?? []).map((element) => [element.id, element]));
  const after = new Map((edited.elements ?? []).map((element) => [element.id, element]));
  const changed = new Map([...after].filter(([id, element]) => !same(before.get(id), element)));
  const mergeElement = (element: Element, local: Element): Element => {
    const baseline = before.get(element.id);
    if (!baseline) return local;
    const merged = { ...element };
    // A pane draft contains old values for properties the user did not edit.
    // Reapply only its property changes, excluding Excalidraw's revision bookkeeping.
    for (const key of new Set([...Object.keys(baseline), ...Object.keys(local)])) {
      if (["version", "versionNonce", "updated"].includes(key) || same(baseline[key], local[key])) continue;
      if (key in local) merged[key] = local[key];
      else delete merged[key];
    }
    if (same(element, merged)) return element;
    if (typeof element.version === "number" && typeof local.version === "number") {
      merged.version = Math.max(element.version, local.version) + 1;
      merged.versionNonce = Math.floor(Math.random() * 0x80000000);
      merged.updated = Date.now();
    }
    return merged;
  };
  const present = new Set((current.elements ?? []).map((element) => element.id));
  let elements = (current.elements ?? []).flatMap((element) =>
    before.has(element.id) && !after.has(element.id) ? [] : [changed.has(element.id) ? mergeElement(element, changed.get(element.id)!) : element]);
  // Reorder only when the user changed stacking; concurrent new elements keep their slots.
  const common = new Set([...before.keys()].filter((id) => after.has(id)));
  const originalOrder = [...before.keys()].filter((id) => common.has(id));
  const localOrder = [...after.keys()].filter((id) => common.has(id));
  if (!same(originalOrder, localOrder)) {
    const byId = new Map(elements.map((element) => [element.id, element]));
    const ordered = localOrder.flatMap((id) => byId.get(id) ?? []);
    let index = 0;
    elements = elements.map((element) => common.has(element.id) ? ordered[index++] : element);
  }
  // New local elements keep their position relative to the user's existing shapes.
  const localElements = edited.elements ?? [];
  for (let index = 0; index < localElements.length; index++) {
    const element = localElements[index];
    if (present.has(element.id) || !changed.has(element.id)) continue;
    const next = localElements.slice(index + 1).find((candidate) => elements.some((item) => item.id === candidate.id));
    const at = next ? elements.findIndex((candidate) => candidate.id === next.id) : elements.length;
    elements.splice(at, 0, element);
  }
  const appState = { ...current.appState };
  for (const key of new Set([...Object.keys(base.appState ?? {}), ...Object.keys(edited.appState ?? {})])) {
    if (same(base.appState?.[key], edited.appState?.[key])) continue;
    if (key in (edited.appState ?? {})) appState[key] = edited.appState![key];
    else delete appState[key];
  }
  const mergedJson = JSON.stringify({ ...current, elements, appState, files: { ...current.files, ...edited.files } });
  if (currentJson !== baseJson && elements.some(element => typeof element.version === "number" && (element.type === "text" || element.type === "arrow"))) {
    const { reconcileMergedScene } = await import("./elementUpdates");
    return reconcileMergedScene(baseJson, editedJson, currentJson, mergedJson);
  }
  return mergedJson;
}

export function updateCanvas(id: string, changes: CanvasChanges | ((canvas: Canvas) => CanvasChanges), options?: { baseDataJson: string }): Promise<Canvas> {
  if (deletingCanvases.has(id)) return Promise.reject(new Error("Drawing is being deleted."));
  const previous = pendingUpdates.get(id);
  const persist = async () => {
    for (let attempt = 0; attempt < 8; attempt++) {
      const canvas = await getCanvas(id);
      if (!canvas) throw new Error("Drawing no longer exists.");
      const update = typeof changes === "function" ? changes(canvas) : changes;
      const dataJson = options && update.dataJson !== undefined
        ? await rebaseCanvasScene(options.baseDataJson, update.dataJson, canvas.dataJson) : update.dataJson;
      try {
        return await upsertCanvas({ ...canvas, ...update, ...(dataJson === undefined ? {} : { dataJson }), expectedUpdatedAt: canvas.updatedAt });
      } catch (error) {
        if ((error instanceof Error ? error.message : error) !== CANVAS_CONFLICT) throw error;
      }
    }
    throw new Error(CANVAS_CONFLICT);
  };
  const pending = (previous ?? Promise.resolve()).then(persist, persist).finally(() => {
    if (pendingUpdates.get(id) === pending) pendingUpdates.delete(id);
  });
  pendingUpdates.set(id, pending);
  return pending;
}

export async function readCanvasScene(id: string): Promise<Canvas | null> {
  window.dispatchEvent(new CustomEvent(CANVAS_SCENE_ACCESS_EVENT, { detail: id }));
  // Pane listeners enqueue their current draft synchronously before this lookup.
  await pendingUpdates.get(id);
  return getCanvas(id);
}

/** `silent` marks a change the app derives by itself, which is not a step for the user to undo. */
export type CanvasSceneWrite = { dataJson: string; checkpoint?: CanvasUpsert["checkpoint"]; viewport?: CanvasViewport; silent?: boolean };

/**
 * Replace a scene and update open panes. A function receives the scene after
 * the pane's pending edits were saved, so an agent's change is applied to what
 * the user currently sees rather than to an older read.
 */
export async function writeCanvasScene(id: string, scene: string | ((current: Canvas) => CanvasSceneWrite)): Promise<Canvas> {
  const initialDraft = canvasSceneDrafts.get(id);
  window.dispatchEvent(new CustomEvent(CANVAS_SCENE_ACCESS_EVENT, { detail: id }));
  // A pane edit that failed to save must not be overwritten by the replacement.
  await pendingUpdates.get(id);
  let viewport: CanvasViewport | undefined;
  let silent = false;
  let saved = await updateCanvas(id, (current) => {
    if (typeof scene === "string") return { dataJson: scene };
    const write = scene(current);
    viewport = write.viewport;
    silent = write.silent === true;
    return { dataJson: write.dataJson, ...(write.checkpoint ? { checkpoint: write.checkpoint } : {}) };
  });
  // A user can keep drawing during the asynchronous write. Drain queued saves,
  // then rebase any still-debounced draft before publishing a single undo step.
  let appliedDraft = initialDraft;
  for (;;) {
    const pending = pendingUpdates.get(id);
    if (pending) { saved = await pending; continue; }
    const draft = canvasSceneDrafts.get(id);
    if (!draft || draft === appliedDraft) break;
    if (!draft.baseDataJson) throw new Error("The drawing has an unsaved edit; save it before retrying the update.");
    const dataJson = JSON.stringify({ elements: draft.elements, appState: {
      viewBackgroundColor: draft.appState.viewBackgroundColor,
      currentItemFontFamily: draft.appState.currentItemFontFamily,
    }, files: draft.files });
    saved = await updateCanvas(id, { dataJson }, { baseDataJson: draft.baseDataJson });
    appliedDraft = draft;
  }
  canvasSceneDrafts.delete(id);
  const detail: CanvasSceneReplacement = viewport || silent ? { ...saved, ...(viewport ? { viewport } : {}), ...(silent ? { silent } : {}) } : saved;
  window.dispatchEvent(new CustomEvent(CANVAS_SCENE_REPLACED_EVENT, { detail }));
  return saved;
}

export async function deleteCanvas(id: string): Promise<void> {
  if (deletingCanvases.has(id)) throw new Error("Drawing is being deleted.");
  deletingCanvases.add(id);
  try {
    await pendingUpdates.get(id)?.catch(() => undefined);
    await invoke("canvas_delete", { id });
    canvasSceneDrafts.delete(id);
    if (cache) cache = cache.filter((c) => c.id !== id);
    window.dispatchEvent(new Event(CANVASES_CHANGED_EVENT));
  } finally { deletingCanvases.delete(id); }
}

export function createEmptyCanvas(cwd?: string): CanvasUpsert {
  return {
    id: crypto.randomUUID(),
    title: "Untitled drawing",
    dataJson: JSON.stringify({ elements: [], appState: {}, files: {} }),
    tags: [],
    cwd,
  };
}

/**
 * Serialize selected Excalidraw elements to a text block for injection into a chat.
 * The canvas id doubles as an Excalidraw MCP checkpoint, so the agent can edit it.
 */
export function canvasElementsToText(
  canvasTitle: string,
  elementsJson: string,
  canvasId?: string,
): string {
  const checkpoint = canvasId
    ? `\nExcalidraw checkpoint id: "${canvasId}". To modify existing elements, use loci_excalidraw get_elements for this checkpoint and update_elements with its revision, keeping element IDs and image resources. For additions/removals, start create_view with {"type":"restoreCheckpoint","id":"${canvasId}"}.`
    : "";
  return `[Canvas: "${canvasTitle}"]${checkpoint}\n<excalidraw-canvas>\n${elementsJson}\n</excalidraw-canvas>`;
}
