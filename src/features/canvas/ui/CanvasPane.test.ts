// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ExcalidrawImperativeAPI, ExcalidrawProps } from "@excalidraw/excalidraw/types";
import { CANVAS_SCENE_ACCESS_EVENT, CANVAS_SCENE_REPLACED_EVENT, canvasElementsToText, updateCanvas, type Canvas } from "../canvas";
import { convertToExcalidrawElements } from "@excalidraw/excalidraw";
import { CanvasPane } from "./CanvasPane";
const scene = vi.hoisted(() => ({ props: null as ExcalidrawProps | null }));
vi.mock("@excalidraw/excalidraw", () => ({
  Excalidraw: (props: ExcalidrawProps) => { scene.props = props; return createElement("canvas", { onDoubleClick: () => normalDoubleClick() }); },
  convertToExcalidrawElements: vi.fn(),
  restore: (data: object) => data,
  CaptureUpdateAction: { IMMEDIATELY: "IMMEDIATELY", NEVER: "NEVER" },
  getSceneVersion: (elements: { version?: number }[]) => elements.reduce((sum, el) => sum + (el.version ?? 0), 0),
  hashElementsVersion: (elements: { versionNonce?: number }[]) => elements.reduce((hash, el) => ((hash << 5) + hash + (el.versionNonce ?? 0)) >>> 0, 5381),
}));
vi.mock("../canvas", () => ({ updateCanvas: vi.fn(), canvasSceneDrafts: new Map(), canvasElementsToText: vi.fn(), CANVAS_SCENE_ACCESS_EVENT: "loci-canvas-scene-access", CANVAS_SCENE_REPLACED_EVENT: "loci-canvas-scene-replaced" }));
let container: HTMLDivElement;
let root: Root;
const canvas: Canvas = { id: "pane-test", title: "Sketch", dataJson: '{"elements":[]}', tags: [], createdAt: 1, updatedAt: 1 };
const noop = vi.fn();
const normalDoubleClick = vi.fn();
const props: ComponentProps<typeof CanvasPane> = { canvas, focused: true, onFocus: noop, onClose: noop, onAddToChat: noop, onTitleChange: noop };
let testId = 0;
beforeEach(() => {
  canvas.id = `pane-test-${++testId}`;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers();
  vi.mocked(updateCanvas).mockImplementation(() => new Promise(() => {}));
  container = document.createElement("div"); document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount()); container.remove();
  vi.clearAllMocks(); vi.useRealTimers(); vi.unstubAllGlobals();
});
it("adds only the selected drawing elements using the agent action", () => {
  const onAddToChat = vi.fn();
  const elements = [{ id: "selected", type: "rectangle" }, { id: "other", type: "ellipse" }];
  vi.mocked(canvasElementsToText).mockReturnValue("Selected drawing context");
  act(() => root.render(createElement(CanvasPane, { ...props, chatTarget: "agent", onAddToChat })));
  act(() => scene.props!.excalidrawAPI!({
    getSceneElements: () => elements,
    getAppState: () => ({ selectedElementIds: { selected: true } }),
  } as unknown as ExcalidrawImperativeAPI));
  const button = container.querySelector<HTMLButtonElement>('button[aria-label="Add drawing to agent"]')!;
  expect(button.textContent).toBe("Add to agent");
  expect(button.title).toBe("Add selected elements or drawing to agent");
  act(() => button.click());
  expect(canvasElementsToText).toHaveBeenCalledWith(canvas.title, JSON.stringify([elements[0]], null, 2), canvas.id);
  expect(onAddToChat).toHaveBeenCalledExactlyOnceWith("Selected drawing context");
});
it("reads in the reader's own header, naming the mentor the drawing goes to", () => {
  act(() => root.render(createElement(CanvasPane, { ...props, reader: true, chatTarget: "agent", chatName: "Ada" })));
  expect(container.querySelector("[data-resource-header]")).not.toBeNull();
  expect(container.querySelectorAll('button[aria-label="Close"]')).toHaveLength(1);
  expect(container.querySelector('button[aria-label="Close pane"]')).toBeNull();
  const chat = container.querySelector<HTMLButtonElement>('button[aria-label="Add drawing to Ada"]')!;
  expect(chat.textContent).toBe("Add to Ada");
  expect(chat.title).toBe("Add selected elements or drawing to Ada");
});

it("retains edits while moving to another pane before the save debounce fires", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const changed = [{ id: "rectangle", type: "rectangle", x: 12, y: 30 }];
  act(() => scene.props!.onChange!(changed as never, { viewBackgroundColor: "#fff" } as never, {}));
  expect(updateCanvas).not.toHaveBeenCalled();
  act(() => root.unmount());
  expect(updateCanvas).toHaveBeenCalledWith(canvas.id, { dataJson: expect.stringContaining('"rectangle"') }, { baseDataJson: canvas.dataJson });
  root = createRoot(container);
  act(() => root.render(createElement(CanvasPane, props)));
  expect(scene.props!.initialData).toMatchObject({ elements: changed });
});

const appState = { viewBackgroundColor: "#fff", currentItemFontFamily: 1 };
const change = (elements: unknown[], state: object = appState, files: object = {}) => {
  act(() => scene.props!.onChange!(elements as never, state as never, files as never));
};

it("does not save initial hydration, zoom, pan, selection or tool changes", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const files = {};
  change([], appState, files);
  for (let i = 0; i < 120; i++) {
    change([], { ...appState, zoom: { value: 0.2 + i / 100 }, scrollX: i, selectedElementIds: { rect: true }, activeTool: { type: "hand" } }, files);
  }
  act(() => vi.advanceTimersByTime(2000));
  expect(updateCanvas).not.toHaveBeenCalled();
});

it("saves an in-place element edit even when the array identity is unchanged", () => {
  const elements = [{ id: "rect", type: "rectangle", version: 1, x: 10 }];
  act(() => root.render(createElement(CanvasPane, { ...props, canvas: { ...canvas, dataJson: JSON.stringify({ elements }) } })));
  const files = {};
  change(elements, appState, files);
  elements[0].version += 1;
  elements[0].x = 20;
  change(elements, appState, files);
  act(() => vi.advanceTimersByTime(1500));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
  expect(JSON.parse(vi.mocked(updateCanvas).mock.calls[0][1].dataJson!)).toMatchObject({ elements: [{ x: 20 }] });
});

it("does not postpone a pending content save while panning", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const files = {};
  const elements = [{ id: "rect", version: 1 }];
  change([], appState, files);
  change(elements, appState, files);
  act(() => vi.advanceTimersByTime(1000));
  change(elements, { ...appState, scrollX: 100 }, files);
  act(() => vi.advanceTimersByTime(500));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
});

it("saves a changed stacking order even when the sum of element versions is unchanged", () => {
  const elements = [{ id: "a", version: 1, versionNonce: 123 }, { id: "b", version: 1, versionNonce: 456 }];
  act(() => root.render(createElement(CanvasPane, { ...props, canvas: { ...canvas, dataJson: JSON.stringify({ elements }) } })));
  const files = {};
  change(elements, appState, files);
  change([...elements].reverse(), appState, files);
  act(() => vi.advanceTimersByTime(1500));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
  expect(JSON.parse(vi.mocked(updateCanvas).mock.calls[0][1].dataJson!).elements[0].id).toBe("b");
});

it.each([
  ["background", { ...appState, viewBackgroundColor: "#123456" }, {}],
  ["font", { ...appState, currentItemFontFamily: 3 }, {}],
  ["files", appState, { image: { id: "image", dataURL: "data:image/png;base64,AAAA" } }],
])("persists a changed %s without an element edit", (_label, state, files) => {
  act(() => root.render(createElement(CanvasPane, props)));
  const originalFiles = {};
  change([], appState, originalFiles);
  change([], state, _label === "files" ? files : originalFiles);
  act(() => vi.advanceTimersByTime(1500));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
});

it("retains a failed save for retry even after viewport-only changes", async () => {
  vi.mocked(updateCanvas).mockRejectedValueOnce(new Error("disk full"));
  act(() => root.render(createElement(CanvasPane, props)));
  const files = {};
  const elements = [{ id: "rect", version: 1 }];
  change(elements, appState, files);
  await act(async () => vi.advanceTimersByTime(1500));
  change(elements, { ...appState, scrollX: 200 }, files);
  const retry = [...container.querySelectorAll("button")].find((button) => button.textContent === "Retry save")!;
  act(() => retry.click());
  expect(updateCanvas).toHaveBeenCalledTimes(2);
  expect(vi.mocked(updateCanvas).mock.calls[1][1]).toEqual(vi.mocked(updateCanvas).mock.calls[0][1]);
});

it("retries an unsaved draft after reopening without another content edit", async () => {
  vi.mocked(updateCanvas).mockRejectedValueOnce(new Error("database unavailable"));
  vi.mocked(updateCanvas).mockResolvedValueOnce(canvas);
  act(() => root.render(createElement(CanvasPane, props)));
  const elements = [{ id: "rect", version: 1, versionNonce: 123, x: 42 }];
  const files = {};
  change(elements, appState, files);
  await act(async () => root.unmount());
  expect(updateCanvas).toHaveBeenCalledTimes(1);

  root = createRoot(container);
  act(() => root.render(createElement(CanvasPane, props)));
  expect(scene.props!.initialData).toMatchObject({ elements });
  change(elements, appState, files);
  await act(async () => vi.advanceTimersByTime(1500));
  expect(updateCanvas).toHaveBeenCalledTimes(2);
  expect(vi.mocked(updateCanvas).mock.calls[1][1]).toEqual(vi.mocked(updateCanvas).mock.calls[0][1]);
});

it("flushes pending edits before an operator scene access", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  change([{ id: "local", version: 1 }]);
  act(() => window.dispatchEvent(new CustomEvent(CANVAS_SCENE_ACCESS_EVENT, { detail: "another-pane" })));
  expect(updateCanvas).not.toHaveBeenCalled();
  act(() => window.dispatchEvent(new CustomEvent(CANVAS_SCENE_ACCESS_EVENT, { detail: canvas.id })));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
  expect(updateCanvas).toHaveBeenCalledWith(canvas.id, { dataJson: expect.stringContaining('"local"') }, { baseDataJson: canvas.dataJson });
  act(() => vi.advanceTimersByTime(2000));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
});

it("opens with the whole drawing in view and follows an agent's camera without saving either", () => {
  const elements = [{ id: "rect", type: "rectangle", version: 1 }];
  act(() => root.render(createElement(CanvasPane, { ...props, canvas: { ...canvas, dataJson: JSON.stringify({ elements }) } })));
  const api = { addFiles: vi.fn(), getFiles: () => ({}), updateScene: vi.fn(), scrollToContent: vi.fn() };
  act(() => scene.props!.excalidrawAPI!(api as unknown as ExcalidrawImperativeAPI));
  change(elements);
  change(elements, { ...appState, scrollX: 50 });
  act(() => vi.advanceTimersByTime(100));
  // Fitting never zooms in, and happens once per opening.
  expect(api.scrollToContent).toHaveBeenCalledTimes(1);
  expect(api.scrollToContent).toHaveBeenCalledWith(undefined, { fitToViewport: true, viewportZoomFactor: 0.9, maxZoom: 1 });
  const frame = [{ id: "camera" }];
  vi.mocked(convertToExcalidrawElements).mockReturnValueOnce(frame as never);
  act(() => window.dispatchEvent(new CustomEvent(CANVAS_SCENE_REPLACED_EVENT, { detail: {
    ...canvas, dataJson: JSON.stringify({ elements, appState, files: {} }), viewport: { x: 40, y: 40, width: 800, height: 600 },
  } })));
  expect(convertToExcalidrawElements).toHaveBeenCalledWith([{ type: "rectangle", x: 40, y: 40, width: 800, height: 600 }]);
  expect(api.scrollToContent).toHaveBeenLastCalledWith(frame, { fitToViewport: true, viewportZoomFactor: 1, maxZoom: 1, animate: true, duration: 300 });
  // A replacement without a camera leaves the user's viewport alone.
  act(() => window.dispatchEvent(new CustomEvent(CANVAS_SCENE_REPLACED_EVENT, { detail: { ...canvas, dataJson: JSON.stringify({ elements, appState, files: {} }) } })));
  expect(api.scrollToContent).toHaveBeenCalledTimes(2);
  act(() => vi.advanceTimersByTime(2000));
  expect(updateCanvas).not.toHaveBeenCalled();
});

it("does not move the viewport of an empty drawing", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const api = { scrollToContent: vi.fn() };
  act(() => scene.props!.excalidrawAPI!(api as unknown as ExcalidrawImperativeAPI));
  change([]);
  change([{ id: "deleted", version: 1, isDeleted: true }]);
  act(() => vi.advanceTimersByTime(100));
  expect(api.scrollToContent).not.toHaveBeenCalled();
});

it("applies an operator replacement and files without saving the old draft over it", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const files = { image: { id: "image", dataURL: "data:image/png;base64,AAAA" } };
  const elements = [{ id: "agent", type: "rectangle", version: 2, versionNonce: 100 }];
  const api = {
    addFiles: vi.fn(), getFiles: () => files, scrollToContent: vi.fn(),
    updateScene: vi.fn(() => scene.props!.onChange!(elements as never, appState as never, files as never)),
  };
  act(() => scene.props!.excalidrawAPI!(api as unknown as ExcalidrawImperativeAPI));
  change([{ id: "old-draft", version: 1 }]);
  act(() => window.dispatchEvent(new CustomEvent(CANVAS_SCENE_REPLACED_EVENT, { detail: {
    ...canvas, dataJson: JSON.stringify({ elements, appState, files }),
  } })));
  expect(api.addFiles).toHaveBeenCalledWith(Object.values(files));
  expect(api.updateScene).toHaveBeenCalledWith({ elements, appState, captureUpdate: "IMMEDIATELY" });
  change(elements, { ...appState, scrollX: 200 }, files);
  act(() => vi.advanceTimersByTime(2000));
  expect(updateCanvas).not.toHaveBeenCalled();
  // Subsequent manual edits still save normally.
  change([{ ...elements[0], version: 3 }], appState, files);
  act(() => vi.advanceTimersByTime(1500));
  expect(updateCanvas).toHaveBeenCalledTimes(1);
});

it("follows a scene changed on disk when it has no local change", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const api = { addFiles: vi.fn(), getFiles: () => ({}), updateScene: vi.fn(), scrollToContent: vi.fn() };
  act(() => scene.props!.excalidrawAPI!(api as unknown as ExcalidrawImperativeAPI));
  const elements = [{ id: "from-disk", type: "rectangle", version: 1, versionNonce: 7 }];
  const changed = { ...canvas, dataJson: JSON.stringify({ elements, appState, files: {} }) };
  act(() => root.render(createElement(CanvasPane, { ...props, canvas: changed })));
  expect(api.updateScene).toHaveBeenCalledWith({ elements, appState, captureUpdate: "NEVER" });
  // The reload is not an edit: nothing is saved.
  act(() => vi.advanceTimersByTime(2000));
  expect(updateCanvas).not.toHaveBeenCalled();
});

it("keeps a local edit when the scene changes on disk", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const api = { addFiles: vi.fn(), getFiles: () => ({}), updateScene: vi.fn(), scrollToContent: vi.fn() };
  act(() => scene.props!.excalidrawAPI!(api as unknown as ExcalidrawImperativeAPI));
  const local = [{ id: "local", type: "rectangle", version: 2, versionNonce: 11 }];
  change(local);
  const changed = { ...canvas, dataJson: JSON.stringify({ elements: [{ id: "from-disk", version: 1 }], appState, files: {} }) };
  act(() => root.render(createElement(CanvasPane, { ...props, canvas: changed })));
  expect(api.updateScene).not.toHaveBeenCalled();
  act(() => vi.advanceTimersByTime(1500));
  expect(JSON.parse(vi.mocked(updateCanvas).mock.calls[0][1].dataJson!).elements[0].id).toBe("local");
});

type PointerState = Parameters<NonNullable<ExcalidrawProps["onPointerUp"]>>[1];
const concept = { id: "pod-node", type: "rectangle", x: -500, y: 700, width: 200, height: 100, angle: Math.PI / 4,
  customData: { type: "concept", courseId: "kubernetes", conceptId: "pod" } };
function doubleClickDrawing(elements: unknown[], hit: unknown, options: { tool?: string; state?: object; target?: HTMLElement } = {}) {
  const surface = container.querySelector("canvas")!;
  act(() => scene.props!.excalidrawAPI!({ getSceneElements: () => elements } as unknown as ExcalidrawImperativeAPI));
  act(() => surface.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })));
  const state = { hit: { element: hit, allHitElements: elements }, drag: { hasOccurred: false }, resize: { isResizing: false },
    boxSelection: { hasOccurred: false }, scrollbars: { isOverEither: false }, ...options.state };
  act(() => scene.props!.onPointerUp!({ type: options.tool ?? "selection" } as never, state as PointerState));
  const doubleClick = new MouseEvent("dblclick", { bubbles: true, cancelable: true, clientX: 110, clientY: 40, detail: 2 });
  act(() => (options.target ?? surface).dispatchEvent(doubleClick));
  return doubleClick;
}

it("retains an explicit concept owner in navigation events", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const owned = { ...concept, customData: { ...concept.customData, agentId: "agent-a" } };
  const navigate = vi.fn();
  window.addEventListener("loci:navigate-concept", navigate);
  try {
    doubleClickDrawing([owned], owned);
    expect((navigate.mock.calls[0][0] as CustomEvent).detail).toEqual({
      courseId: "kubernetes", conceptId: "pod", canvasId: canvas.id, agentId: "agent-a",
    });
  } finally { window.removeEventListener("loci:navigate-concept", navigate); }
});

it("navigates the native hit concept on double-click without starting text editing", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const navigate = vi.fn();
  window.addEventListener("loci:navigate-concept", navigate);
  try {
    const event = doubleClickDrawing([concept], concept);
    expect(navigate).toHaveBeenCalledOnce();
    expect((navigate.mock.calls[0][0] as CustomEvent).detail).toEqual({ courseId: "kubernetes", conceptId: "pod", canvasId: canvas.id });
    expect(event.defaultPrevented).toBe(true);
    expect(normalDoubleClick).not.toHaveBeenCalled();
    // The concept's scene coordinates/rotation are deliberately different from
    // the viewport click. Only Excalidraw knows which element was actually hit.
    expect(updateCanvas).not.toHaveBeenCalled();
  } finally { window.removeEventListener("loci:navigate-concept", navigate); }
});

it("routes bound text to its concept container", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const label = { id: "pod-label", type: "text", containerId: concept.id };
  const navigate = vi.fn();
  window.addEventListener("loci:navigate-concept", navigate);
  try {
    doubleClickDrawing([concept, label], label);
    expect((navigate.mock.calls[0][0] as CustomEvent).detail.conceptId).toBe("pod");
  } finally { window.removeEventListener("loci:navigate-concept", navigate); }
});

it.each([
  { label: "a covering shape", hit: { id: "cover", type: "rectangle" } },
  { label: "empty space", hit: null },
  { label: "another customData type", hit: { ...concept, customData: { type: "note", courseId: "kubernetes", conceptId: "pod" } } },
  { label: "an incomplete concept link", hit: { ...concept, customData: { type: "concept", conceptId: "pod" } } },
])("keeps normal Excalidraw double-click behavior for $label", ({ hit }) => {
  act(() => root.render(createElement(CanvasPane, props)));
  const navigate = vi.fn();
  window.addEventListener("loci:navigate-concept", navigate);
  try {
    const elements = hit?.id === concept.id ? [hit] : [concept, ...(hit ? [hit] : [])];
    const event = doubleClickDrawing(elements, hit);
    expect(navigate).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
    expect(normalDoubleClick).toHaveBeenCalledOnce();
  } finally { window.removeEventListener("loci:navigate-concept", navigate); }
});

it.each([
  { tool: "hand" },
  { state: { drag: { hasOccurred: true } } },
  { state: { resize: { isResizing: true } } },
  { state: { boxSelection: { hasOccurred: true } } },
  { state: { scrollbars: { isOverEither: true } } },
])("does not navigate after an editor gesture %#", (options) => {
  act(() => root.render(createElement(CanvasPane, props)));
  const navigate = vi.fn();
  window.addEventListener("loci:navigate-concept", navigate);
  try {
    doubleClickDrawing([concept], concept, options);
    expect(navigate).not.toHaveBeenCalled();
  } finally { window.removeEventListener("loci:navigate-concept", navigate); }
});

it("clears the previous hit before another pointer gesture and ignores editor controls", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const navigate = vi.fn();
  window.addEventListener("loci:navigate-concept", navigate);
  try {
    doubleClickDrawing([concept], concept, { target: container.querySelector("button")! });
    expect(navigate).not.toHaveBeenCalled();
    const surface = container.querySelector("canvas")!;
    act(() => surface.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })));
    act(() => surface.dispatchEvent(new MouseEvent("dblclick", { bubbles: true, cancelable: true })));
    expect(navigate).not.toHaveBeenCalled();
  } finally { window.removeEventListener("loci:navigate-concept", navigate); }
});
