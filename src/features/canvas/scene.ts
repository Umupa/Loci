import { convertToExcalidrawElements, restoreElements } from "@excalidraw/excalidraw";

const elementTypes = new Set(["rectangle", "ellipse", "diamond", "arrow", "line", "text", "image", "freedraw", "frame", "magicframe", "iframe", "embeddable"]);
const skeletonTypes = new Set(["rectangle", "ellipse", "diamond", "arrow", "line", "text"]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Accept a native scene or basic programmatic shapes, never MCP stream commands. */
export function normalizeCanvasScene(dataJson: string): string {
  let scene: unknown;
  try { scene = JSON.parse(dataJson); }
  catch { throw new Error("dataJson must be valid JSON"); }
  if (!isRecord(scene) || !Array.isArray(scene.elements))
    throw new Error("dataJson must contain an elements array");
  if ((scene.appState !== undefined && !isRecord(scene.appState)) ||
    (scene.files !== undefined && !isRecord(scene.files)))
    throw new Error("appState and files must be objects");
  const ids = new Set<string>();
  for (const element of scene.elements) {
    if (!isRecord(element) || !elementTypes.has(element.type as string) ||
      !Number.isFinite(element.x) || !Number.isFinite(element.y))
      throw new Error("Each element must have a supported Excalidraw type and finite x/y; MCP stream commands are not scene elements");
    if (element.id !== undefined) {
      if (typeof element.id !== "string" || !element.id || ids.has(element.id))
        throw new Error("Element IDs must be non-empty and unique");
      ids.add(element.id);
    }
    for (const dimension of ["width", "height", "fontSize"]) {
      const linearDimension = (element.type === "arrow" || element.type === "line") && dimension !== "fontSize";
      if (element[dimension] !== undefined && (!Number.isFinite(element[dimension]) || (!linearDimension && (element[dimension] as number) < 0)))
        throw new Error(`Element ${dimension} must be finite, and non-negative for non-linear shapes`);
    }
    if (element.type === "text" && typeof element.text !== "string")
      throw new Error("Text elements must contain text");
    if (element.points !== undefined && (!Array.isArray(element.points) || element.points.length < (element.type === "freedraw" ? 1 : 2) ||
      element.points.some((point: unknown) => !Array.isArray(point) || point.length !== 2 || !point.every(Number.isFinite))))
      throw new Error("Element points must contain at least two finite coordinate pairs");
    if (element.label !== undefined && (!isRecord(element.label) || typeof element.label.text !== "string"))
      throw new Error("Element labels must contain text");
  }
  for (const [id, file] of Object.entries(scene.files ?? {})) {
    if (!isRecord(file) || file.id !== id || typeof file.dataURL !== "string" || typeof file.mimeType !== "string" || !Number.isFinite(file.created))
      throw new Error("Scene files must contain Excalidraw image records with matching id, dataURL, mimeType and created");
  }
  const native = scene.elements.every((element) => Number.isInteger(element.version) && element.version > 0 && typeof element.id === "string");
  if (!native && scene.elements.some((element) => Number.isInteger(element.version) && element.version > 0))
    throw new Error("Do not mix native scene elements and shorthand; normalize new elements before extending a native scene");
  if (!native && scene.elements.some((element) => !skeletonTypes.has(element.type)))
    throw new Error("Images, frames and freehand elements require a full Excalidraw scene; basic shapes may use the programmatic format");
  try {
    const elements = native
      ? restoreElements(scene.elements, null, { repairBindings: true })
      : restoreElements(convertToExcalidrawElements(scene.elements, { regenerateIds: false }), null, { repairBindings: true });
    // Persist document settings only; selection, collaborators and viewport stay local.
    const appState = scene.appState ?? {};
    return JSON.stringify({ elements, appState: {
      ...(typeof appState.viewBackgroundColor === "string" ? { viewBackgroundColor: appState.viewBackgroundColor } : {}),
      ...(Number.isInteger(appState.currentItemFontFamily) ? { currentItemFontFamily: appState.currentItemFontFamily } : {}),
    }, files: scene.files ?? {} });
  } catch (error) {
    throw new Error(`Could not restore Excalidraw scene elements: ${error instanceof Error ? error.message : "invalid scene"}`);
  }
}

/** Excalidraw keeps old file IDs for Undo; content-derived IDs prevent stale image reuse. */
export async function canonicalizeCanvasImages(dataJson: string): Promise<string> {
  const scene = JSON.parse(dataJson);
  const ids = new Map<string, string>();
  const files: Record<string, unknown> = {};
  for (const [id, file] of Object.entries(scene.files ?? {}) as Array<[string, Record<string, unknown>]>) {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(String(file.dataURL)));
    const nextId = `loci-${Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
    ids.set(id, nextId);
    files[nextId] = { ...file, id: nextId };
  }
  const elements = scene.elements.map((element: Record<string, unknown>) => {
    if (element.type !== "image") return element;
    const fileId = ids.get(String(element.fileId));
    if (!fileId && !element.isDeleted) throw new Error("Every image must reference a file in files");
    if (!fileId) return element;
    return { ...element, fileId };
  });
  return JSON.stringify({ ...scene, elements, files });
}
