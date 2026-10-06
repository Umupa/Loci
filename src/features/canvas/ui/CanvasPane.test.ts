// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ExcalidrawProps } from "@excalidraw/excalidraw/types";
import { updateCanvas, type Canvas } from "../canvas";
import { CanvasPane } from "./CanvasPane";
const scene = vi.hoisted(() => ({ props: null as ExcalidrawProps | null }));
vi.mock("@excalidraw/excalidraw", () => ({
  Excalidraw: (props: ExcalidrawProps) => { scene.props = props; return null; },
  convertToExcalidrawElements: vi.fn(),
}));
vi.mock("../canvas", () => ({ updateCanvas: vi.fn(), canvasElementsToText: vi.fn() }));
let container: HTMLDivElement;
let root: Root;
const canvas: Canvas = { id: "pane-test", title: "Sketch", dataJson: '{"elements":[]}', tags: [], createdAt: 1, updatedAt: 1 };
const noop = vi.fn();
const props: ComponentProps<typeof CanvasPane> = { canvas, focused: true, onFocus: noop, onClose: noop, onAddToChat: noop, onTitleChange: noop };
beforeEach(() => {
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
it("retains edits while moving to another pane before the save debounce fires", () => {
  act(() => root.render(createElement(CanvasPane, props)));
  const changed = [{ id: "rectangle", type: "rectangle", x: 12, y: 30 }];
  act(() => scene.props!.onChange!(changed as never, { viewBackgroundColor: "#fff" } as never, {}));
  expect(updateCanvas).not.toHaveBeenCalled();
  act(() => root.unmount());
  expect(updateCanvas).toHaveBeenCalledWith(canvas.id, { dataJson: expect.stringContaining('"rectangle"') });
  root = createRoot(container);
  act(() => root.render(createElement(CanvasPane, props)));
  expect(scene.props!.initialData).toMatchObject({ elements: changed });
});
