import { invoke } from "@tauri-apps/api/core";

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
};

export const CANVASES_CHANGED_EVENT = "loci-canvases-changed";

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
export function updateCanvas(id: string, changes: Partial<Omit<CanvasUpsert, "id">>): Promise<Canvas> {
  const previous = pendingUpdates.get(id);
  const persist = async () => {
    const canvas = await getCanvas(id);
    if (!canvas) throw new Error("Drawing no longer exists.");
    return upsertCanvas({ ...canvas, ...changes });
  };
  const pending = (previous ?? Promise.resolve()).then(persist, persist).finally(() => {
    if (pendingUpdates.get(id) === pending) pendingUpdates.delete(id);
  });
  pendingUpdates.set(id, pending);
  return pending;
}

export async function deleteCanvas(id: string): Promise<void> {
  await invoke("canvas_delete", { id });
  if (cache) {
    cache = cache.filter((c) => c.id !== id);
  }
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

/** Serialize selected Excalidraw elements to a text block for injection into a chat. */
export function canvasElementsToText(
  canvasTitle: string,
  elementsJson: string,
): string {
  return `[Canvas: "${canvasTitle}"]\n<excalidraw-canvas>\n${elementsJson}\n</excalidraw-canvas>`;
}
