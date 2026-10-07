// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ExcalidrawProps } from "@excalidraw/excalidraw/types";
import { invoke } from "@tauri-apps/api/core";
import { canvasSceneDrafts, writeCanvasScene, type Canvas } from "../canvas";
import { CanvasPane } from "./CanvasPane";
const scene = vi.hoisted(() => ({ props: null as ExcalidrawProps | null }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@excalidraw/excalidraw", () => ({
  Excalidraw: (props: ExcalidrawProps) => { scene.props = props; return null; },
  convertToExcalidrawElements: vi.fn(), restore: (data: object) => data,
  CaptureUpdateAction: { IMMEDIATELY: "IMMEDIATELY" },
  getSceneVersion: (elements: { version?: number }[]) => elements.reduce((sum, el) => sum + (el.version ?? 0), 0),
  hashElementsVersion: (elements: { versionNonce?: number }[]) => elements.reduce((sum, el) => sum + (el.versionNonce ?? 0), 0),
}));
let root: Root;
let container: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers();
  container = document.createElement("div"); document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.clearAllMocks();
});

it.each([false, true])("preserves manual edits made during an agent upsert (debounce already fired: %s)", async (queued) => {
  const base = { id: "base", type: "rectangle", x: 0, y: 0, version: 1, versionNonce: 1 };
  const manual = { ...base, id: "manual", x: 100, versionNonce: 2 };
  const appState = { viewBackgroundColor: "#fff", currentItemFontFamily: 1 };
  const files = {};
  let saved: Canvas = { id: `race-${queued}`, title: "Drawing", tags: [], cwd: "/project", createdAt: 1, updatedAt: 1,
    dataJson: JSON.stringify({ elements: [base], appState, files }) };
  let release!: () => void;
  let started!: () => void;
  const held = new Promise<void>((resolve) => { release = resolve; });
  const starting = new Promise<void>((resolve) => { started = resolve; });
  let first = true;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_get") return { ...saved };
    if (command === "canvas_upsert") {
      if (first) { first = false; started(); await held; }
      const { checkpoint: _checkpoint, expectedUpdatedAt: expected, ...canvas } = (args as { canvas: Canvas & { expectedUpdatedAt?: number; checkpoint?: unknown } }).canvas;
      if (expected !== undefined && expected !== saved.updatedAt) throw "Canvas changed since it was read; retry the update.";
      saved = { ...canvas, updatedAt: saved.updatedAt + 1 };
      return { ...saved };
    }
    throw new Error(`Unexpected command ${command}`);
  });
  const updateScene = vi.fn();
  await act(async () => root.render(createElement(CanvasPane, { canvas: saved, focused: true, onFocus: vi.fn(), onClose: vi.fn() })));
  act(() => {
    scene.props!.excalidrawAPI!({ addFiles: vi.fn(), updateScene, getFiles: () => files, scrollToContent: vi.fn() } as never);
    scene.props!.onChange!([base] as never, appState as never, files);
  });
  let writing!: Promise<Canvas>;
  await act(async () => {
    writing = writeCanvasScene(saved.id, (current) => ({ dataJson: JSON.stringify({ ...JSON.parse(current.dataJson),
      elements: [...JSON.parse(current.dataJson).elements, { ...base, id: "agent", x: 200, versionNonce: 3 }] }) }));
    await starting;
  });
  act(() => scene.props!.onChange!([base, manual] as never, appState as never, files));
  if (queued) await act(async () => vi.advanceTimersByTimeAsync(1500));
  await act(async () => { release(); await writing; });
  expect(JSON.parse(saved.dataJson).elements.map((element: { id: string }) => element.id).sort()).toEqual(["agent", "base", "manual"]);
  expect(updateScene).toHaveBeenCalledTimes(1);
  expect(updateScene.mock.calls[0][0].elements.map((element: { id: string }) => element.id).sort()).toEqual(["agent", "base", "manual"]);
  expect(updateScene.mock.calls[0][0].captureUpdate).toBe("IMMEDIATELY");
  expect(canvasSceneDrafts.has(saved.id)).toBe(false);
  await act(async () => vi.advanceTimersByTimeAsync(2000));
  expect(JSON.parse(saved.dataJson).elements.map((element: { id: string }) => element.id).sort()).toEqual(["agent", "base", "manual"]);
});
