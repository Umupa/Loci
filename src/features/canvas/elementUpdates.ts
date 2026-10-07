import { convertToExcalidrawElements, newElementWith } from "@excalidraw/excalidraw";
import type { ExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import { validateElementUpdates } from "../../../src-tauri/resources/excalidraw-mcp/element-properties.mjs";

type Element = ExcalidrawElement;
type Point = [number, number];
const geometry = new Set(["x", "y", "width", "height", "angle"]);
const textMetrics = new Set(["text", "fontSize", "fontFamily", "lineHeight", "autoResize", "width"]);
const frame = (element: Element) => element.type === "frame" || element.type === "magicframe";
const linear = (element: Element): element is Extract<Element, { type: "arrow" | "line" | "freedraw" }> => element.type === "arrow" || element.type === "line" || element.type === "freedraw";
const changedGeometry = (before: Element, after: Element) => [...geometry].some(key => before[key as keyof Element] !== after[key as keyof Element]);
const withChanges = <T extends Element>(element: T, changes: Record<string, unknown>): T => newElementWith(element, changes as never);

/** Measure with Excalidraw's own font and wrapping logic, without persisting synthetic elements. */
function measureText(element: Element, container?: Element): { text: Element; container?: Element } {
  if (element.type !== "text") return { text: element };
  const content = element.originalText ?? element.text;
  if (container) {
    if (!element.autoResize)
      throw new Error(`Bound labels use the container width; set autoResize:true on label "${element.id}" before reflowing, or use the editor`);
    const elements = convertToExcalidrawElements([{ ...container, label: { ...element, text: content } }] as never, { regenerateIds: false });
    return { text: elements.find(el => el.type === "text")!, container: elements.find(el => el.id === container.id) };
  }
  if (!element.autoResize) {
    // A synthetic rectangle provides the same fixed-width wrapping as the editor.
    const elements = convertToExcalidrawElements([{ type: "rectangle", id: `loci-text-measure:${element.id}`, x: 0, y: 0,
      width: element.width + 10, height: 1, label: { ...element, text: content, textAlign: "left", verticalAlign: "top" } }] as never,
      { regenerateIds: false });
    return { text: elements.find(el => el.type === "text")! };
  }
  const elements = convertToExcalidrawElements([{ ...element, x: 0, y: 0, text: content, textAlign: "left", verticalAlign: "top" }] as never,
    { regenerateIds: false });
  return { text: elements[0] };
}

function rotated(point: Point, center: Point, angle: number): Point {
  const x = point[0] - center[0], y = point[1] - center[1];
  return [center[0] + x * Math.cos(angle) - y * Math.sin(angle), center[1] + x * Math.sin(angle) + y * Math.cos(angle)];
}
/** Keep a bound endpoint at its existing relative position as its shape moves/resizes/rotates. */
function movedEndpoint(point: Point, before: Element, after: Element): Point {
  const unrotated = rotated(point, [before.x + before.width / 2, before.y + before.height / 2], -before.angle);
  const coordinate = (value: number, origin: number, size: number, nextOrigin: number, nextSize: number) => {
    // Keep the existing pixel gap outside the shape; scale only the attachment position along it.
    if (value < origin) return nextOrigin + value - origin;
    if (value > origin + size) return nextOrigin + nextSize + value - origin - size;
    return nextOrigin + (value - origin) * (size ? nextSize / size : 1);
  };
  const x = coordinate(unrotated[0], before.x, before.width, after.x, after.width);
  const y = coordinate(unrotated[1], before.y, before.height, after.y, after.height);
  return rotated([x, y], [after.x + after.width / 2, after.y + after.height / 2], after.angle);
}

/** The native binding measurements must describe the final endpoints, not their old path. */
function refreshArrowBindings(element: Element, elements: Map<string, Element>): Element {
  if (element.type !== "arrow") return element;
  const targets = new Map<string, Record<string, unknown>>();
  for (const binding of [element.startBinding, element.endBinding]) {
    if (!binding) continue;
    const target = elements.get(binding.elementId);
    if (!target || target.isDeleted) throw new Error(`Cannot measure arrow binding to "${binding.elementId}"`);
    // Images, text and embedded content have rectangular binding outlines. Only
    // geometry crosses into the converter; the actual target records stay intact.
    targets.set(target.id, { id: target.id, type: target.type === "ellipse" || target.type === "diamond" ? target.type : "rectangle",
      x: target.x, y: target.y, width: target.width, height: target.height, angle: target.angle, roundness: target.roundness });
  }
  const measured = convertToExcalidrawElements([...targets.values(), { ...element,
    ...(element.startBinding ? { start: { id: element.startBinding.elementId } } : {}),
    ...(element.endBinding ? { end: { id: element.endBinding.elementId } } : {}),
  }] as never, { regenerateIds: false }).find(candidate => candidate.id === element.id);
  if (!measured || measured.type !== "arrow") throw new Error(`Cannot measure arrow "${element.id}"`);
  const changes: Record<string, unknown> = {};
  for (const end of ["startBinding", "endBinding"] as const) {
    const binding = element[end], next = measured[end];
    if (!binding) continue;
    if (!next || next.elementId !== binding.elementId) throw new Error(`Arrow "${element.id}" lost its binding target`);
    changes[end] = { ...binding, ...next, elementId: binding.elementId };
  }
  return withChanges(element, changes);
}

function followArrowTargets(original: Extract<Element, { type: "arrow" | "line" }>, current: Extract<Element, { type: "arrow" | "line" }>,
  before: Map<string, Element>, after: Map<string, Element>): Element {
  const ends = ["startBinding", "endBinding"] as const;
  const points = current.points.map(point => [current.x + point[0], current.y + point[1]] as Point);
  const positions = [points[0], points[points.length - 1]].map((point, index) => {
    const id = original[ends[index]]?.elementId;
    if (!id || !before.has(id) || !after.has(id)) return point;
    const oldPoint = original.points[index ? original.points.length - 1 : 0];
    return movedEndpoint([original.x + oldPoint[0], original.y + oldPoint[1]], before.get(id)!, after.get(id)!);
  });
  const delta = positions.map((point, index) => [point[0] - points[index ? points.length - 1 : 0][0], point[1] - points[index ? points.length - 1 : 0][1]]);
  const moved = points.map((point, index) => {
    const fraction = index / (points.length - 1);
    return [point[0] + delta[0][0] * (1 - fraction) + delta[1][0] * fraction,
      point[1] + delta[0][1] * (1 - fraction) + delta[1][1] * fraction] as Point;
  });
  const x = moved[0][0], y = moved[0][1];
  const local = moved.map(point => [point[0] - x, point[1] - y]);
  return refreshArrowBindings(withChanges(current, { x, y, points: local,
    width: Math.max(...local.map(point => point[0])) - Math.min(...local.map(point => point[0])),
    height: Math.max(...local.map(point => point[1])) - Math.min(...local.map(point => point[1])) }), after);
}

/** Recompute derived geometry when concurrent edits combine different native measurements. */
export function reconcileMergedScene(baseJson: string, editedJson: string, currentJson: string, mergedJson: string): string {
  const elementsOf = (json: string): Element[] => JSON.parse(json).elements ?? [];
  const byId = (elements: Element[]) => new Map(elements.map(element => [element.id, element]));
  const baseline = byId(elementsOf(baseJson)), local = byId(elementsOf(editedJson)), current = byId(elementsOf(currentJson));
  const scene = JSON.parse(mergedJson) as { elements: Element[] };
  const merged = byId(scene.elements);
  const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
  const inputs = (element: Extract<Element, { type: "text" }>) => [element.originalText ?? element.text, element.fontSize,
    element.fontFamily, element.lineHeight, element.autoResize, element.autoResize ? null : element.width];
  const reflowText = (element: Element): void => {
    if (element.type !== "text" || element.isDeleted) return;
    const before = baseline.get(element.id), edited = local.get(element.id), saved = current.get(element.id);
    if ((edited?.type !== "text" && saved?.type !== "text") ||
        ![element.x, element.y, element.width, element.height, element.fontSize, element.lineHeight].every(Number.isFinite)) return;
    // Native text edits regenerate these fields; a position-only draft leaves
    // them at its baseline and must keep the other actor's font measurement.
    const source = edited?.type === "text" && (before?.type !== "text" ||
      ["text", "width", "height", "x", "y"].some(key => !same(before[key as keyof typeof before], edited[key as keyof typeof edited]))) ? edited : saved;
    if (source?.type !== "text") return;
    const sourceElements = source === edited ? local : current;
    const container = element.containerId ? merged.get(element.containerId) : undefined;
    const sourceContainer = source.containerId ? sourceElements.get(source.containerId) : undefined;
    const needsMeasurement = !same(inputs(element), inputs(source)) ||
      (container && (!sourceContainer || changedGeometry(sourceContainer, container)));
    const measurement = needsMeasurement
      ? measureText(container && !element.autoResize ? { ...element, autoResize: true } : element, container)
      : { text: source };
    const measured = measurement.text;
    if (measured.type !== "text") return;
    const width = element.autoResize ? measured.width : element.width;
    const align = element.textAlign === "center" ? 0.5 : element.textAlign === "right" ? 1 : 0;
    merged.set(element.id, withChanges(element, { text: measured.text, width, height: measured.height,
      ...(container ? { x: measured.x + (measured.width - width) * align, y: measured.y, angle: container.angle } : {}) }));
    if (container && measurement.container && container.type !== "arrow")
      merged.set(container.id, withChanges(container, { width: measurement.container.width, height: measurement.container.height }));
  };
  for (const element of scene.elements) {
    const container = element.type === "text" && element.containerId ? merged.get(element.containerId) : undefined;
    if (container?.type !== "arrow") reflowText(element);
  }
  for (const element of scene.elements) {
    if (element.type !== "arrow" || element.isDeleted) continue;
    const before = baseline.get(element.id), edited = local.get(element.id), saved = current.get(element.id);
    const pathKeys = ["x", "y", "width", "height", "angle", "points", "startBinding", "endBinding"];
    const source = edited?.type === "arrow" && (before?.type !== "arrow" || pathKeys.some(key =>
      !same(before[key as keyof typeof before], edited[key as keyof typeof edited]))) ? edited : saved;
    if (source?.type !== "arrow") continue;
    const sourceElements = source === edited ? local : current;
    const affected = [source.startBinding, source.endBinding].some(binding => {
      const oldTarget = binding && sourceElements.get(binding.elementId), target = binding && merged.get(binding.elementId);
      return oldTarget && target && changedGeometry(oldTarget, target);
    });
    if (!affected) continue;
    if (("elbowed" in source && source.elbowed) || source.angle !== 0) throw new Error("Concurrent bound-arrow routing needs the editor; the manual draft remains unsaved");
    const path = withChanges(element, { x: source.x, y: source.y, width: source.width, height: source.height, points: source.points });
    merged.set(element.id, followArrowTargets(source, path, sourceElements, merged));
  }
  for (const element of scene.elements) {
    if (element.type === "text" && element.containerId && merged.get(element.containerId)?.type === "arrow") reflowText(element);
  }
  scene.elements = scene.elements.map(element => merged.get(element.id)!);
  return JSON.stringify(scene);
}

/** Edit native records in place by identity; unspecified fields and image resources never leave the server. */
export function applyElementUpdates(dataJson: string, rawUpdates: unknown): { dataJson: string; updatedIds: string[] } {
  const scene = JSON.parse(dataJson) as { elements: Element[]; appState: unknown; files: unknown };
  if (!Array.isArray(scene.elements)) throw new Error("Invalid canvas scene");
  const updates = validateElementUpdates(rawUpdates, scene.elements);
  const before = new Map(scene.elements.map(el => [el.id, el]));
  const after = new Map(before);
  const requested = new Map(updates.map(update => [update.id, update.changes]));
  for (const { id, changes } of updates) {
    const original = before.get(id)!;
    for (const key of ["strokeColor", "backgroundColor"]) if (changes[key] !== undefined) {
      const style = document.createElement("span").style;
      style.color = String(changes[key]);
      if (!style.color || String(changes[key]).includes("var(")) throw new Error(`Invalid ${key} for element "${id}"`);
    }
    if (original.type === "arrow" && (original.startBinding || original.endBinding) && Object.keys(changes).some(key => geometry.has(key)))
      throw new Error(`Move the shapes bound to arrow "${id}" instead of moving its bound endpoints independently`);
    if (original.type === "text" && original.containerId && Object.keys(changes).some(key => geometry.has(key)))
      throw new Error(`Move/resize the container of bound text "${id}"; change fontSize or alignment on the label`);
    if (frame(original) && changes.angle !== undefined && changes.angle !== 0)
      throw new Error("Frames cannot rotate; update their position or size");
    const change = { ...changes };
    if (original.type === "text") {
      if (change.text !== undefined) change.originalText = change.text;
      if (change.width !== undefined && (change.autoResize ?? original.autoResize) !== false)
        throw new Error("For a fixed text width, include autoResize:false explicitly");
    }
    if (linear(original)) {
      const width = typeof change.width === "number" ? change.width : original.width;
      const height = typeof change.height === "number" ? change.height : original.height;
      if ((!original.width && width !== original.width) || (!original.height && height !== original.height))
        throw new Error(`Cannot scale a zero-sized linear axis of "${id}"; move its endpoints/shapes in the editor`);
      if (width !== original.width || height !== original.height) change.points = original.points.map(point =>
        [point[0] * (original.width ? width / original.width : 1), point[1] * (original.height ? height / original.height : 1)]);
    }
    after.set(id, withChanges(original, change));
  }

  // Moving a frame carries its members, while explicit member coordinates win.
  for (const original of scene.elements) {
    if (original.isDeleted) continue;
    const deltaFromFrame = (axis: "x" | "y") => {
      let parent = original.frameId;
      const visited = new Set<string>();
      while (parent && !visited.has(parent)) {
        visited.add(parent);
        const owner = before.get(parent), change = requested.get(parent);
        if (!owner || !frame(owner)) break;
        if (typeof change?.[axis] === "number") return (change[axis] as number) - owner[axis];
        parent = owner.frameId;
      }
      return 0;
    };
    const dx = deltaFromFrame("x"), dy = deltaFromFrame("y");
    if (!dx && !dy) continue;
    const current = after.get(original.id)!, change = requested.get(original.id);
    after.set(original.id, withChanges(current, {
      ...(change?.x === undefined ? { x: current.x + dx } : {}),
      ...(change?.y === undefined ? { y: current.y + dy } : {}),
    }));
  }

  // Resize/reflow text using native metrics, and keep existing bound label IDs.
  for (const original of scene.elements) {
    if (original.isDeleted || original.type !== "text") continue;
    const current = after.get(original.id)!;
    if (current.type !== "text") continue;
    const change = requested.get(original.id);
    const container = current.containerId ? after.get(current.containerId) : undefined;
    const originalContainer = current.containerId ? before.get(current.containerId) : undefined;
    const containerMoved = !!container && !!originalContainer && changedGeometry(originalContainer, container);
    if (!containerMoved && !Object.keys(change ?? {}).some(key => textMetrics.has(key) || key === "textAlign" || key === "verticalAlign")) continue;
    const measured = measureText(current, container);
    if (!measured.text || measured.text.type !== "text") throw new Error(`Cannot measure text "${current.id}"`);
    after.set(current.id, withChanges(current, { text: measured.text.text, width: current.autoResize ? measured.text.width : current.width,
      height: measured.text.height, ...(container ? { x: measured.text.x, y: measured.text.y, angle: container.angle } : {}) }));
    if (container && measured.container && container.type !== "arrow" &&
        (measured.container.width !== container.width || measured.container.height !== container.height))
      after.set(container.id, withChanges(container, { width: measured.container.width, height: measured.container.height }));
  }

  // Bound arrows follow their shapes. Keep targets and interpolate bends, then
  // recompute native focus/gap so a later editor move does not snap the path.
  for (const original of scene.elements) {
    if (original.isDeleted || original.type !== "arrow") continue;
    let current = after.get(original.id)!;
    if (current.type !== "arrow") continue;
    const ends = ["startBinding", "endBinding"] as const;
    const affected = ends.some(end => {
      const id = original[end]?.elementId;
      return id && before.has(id) && after.has(id) && changedGeometry(before.get(id)!, after.get(id)!);
    });
    if (!affected) continue;
    if (("elbowed" in original && original.elbowed) || original.angle !== 0) throw new Error(`Moving a shape attached to elbowed/rotated arrow "${original.id}" needs the editor's routing; no changes were saved`);
    after.set(original.id, followArrowTargets(original, current, before, after));
  }
  // Arrow labels are positioned after endpoint movement, using the final path.
  for (const original of scene.elements) {
    if (original.isDeleted || original.type !== "text" || !original.containerId) continue;
    const oldContainer = before.get(original.containerId), container = after.get(original.containerId);
    if (!oldContainer || !container || container.type !== "arrow" || !changedGeometry(oldContainer, container)) continue;
    const current = after.get(original.id)!;
    const measured = measureText(current, container).text;
    if (!measured || measured.type !== "text") throw new Error(`Cannot measure bound text "${original.id}"`);
    after.set(original.id, withChanges(current, { text: measured.text, x: measured.x, y: measured.y, width: measured.width, height: measured.height }));
  }
  // No accidental element creation/deletion or changes to image file references.
  const elements = scene.elements.map(el => after.get(el.id)!);
  for (const [index, element] of elements.entries()) {
    const original = scene.elements[index];
    if (element.id !== original.id || element.type !== original.type || element.isDeleted !== original.isDeleted ||
        (element.type === "image" && original.type === "image" && element.fileId !== original.fileId)) throw new Error("Element identity changed unexpectedly");
    if (element !== original && !linear(element) && (element.width <= 0 || element.height <= 0)) throw new Error(`Update would make "${element.id}" invisible`);
    if (![element.x, element.y, element.width, element.height, element.angle].every(Number.isFinite)) throw new Error(`Invalid resulting geometry for "${element.id}"`);
  }
  return { dataJson: JSON.stringify({ ...scene, elements }), updatedIds: elements.filter(el => el !== before.get(el.id)).map(el => el.id) };
}
