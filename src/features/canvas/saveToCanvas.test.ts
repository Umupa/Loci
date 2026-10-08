// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { appendCanvasText } from "./saveToCanvas";
import { CANVAS_SCENE_ACCESS_EVENT, CANVAS_SCENE_REPLACED_EVENT, updateCanvas, type Canvas } from "./canvas";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
let stored: Canvas | null;
beforeEach(() => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", measureText: (text: string) => ({ width: text.length * 10 }) } as never);
  stored = { id: "drawing", cwd: "/project", title: "Sketch", tags: ["kept"], createdAt: 1, updatedAt: 1,
    dataJson: JSON.stringify({ elements: [{ id: "shape", type: "rectangle", x: 5, y: 20, width: 100, height: 60, version: 1 }],
      appState: { viewBackgroundColor: "#123456" }, files: { photo: { id: "photo", dataURL: "data:image/png;base64,AAAA" } } }) };
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_get") return stored && { ...stored };
    if (command === "canvas_upsert") {
      stored = { ...(args as { canvas: Canvas }).canvas, updatedAt: stored!.updatedAt + 1 };
      return { ...stored };
    }
    throw new Error(`Unexpected command ${command}`);
  });
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.clearAllMocks(); });
it("persists native text in an unopened canvas while preserving the scene", async () => {
  const before = JSON.parse(stored!.dataJson);
  const changed = vi.fn();
  window.addEventListener(CANVAS_SCENE_REPLACED_EVENT, changed);
  try {
    await appendCanvasText("drawing", "Saved reply");
    const scene = JSON.parse(stored!.dataJson);
    expect(scene.elements).toHaveLength(2);
    expect(scene.elements[0]).toEqual(before.elements[0]);
    expect(scene.elements[1]).toMatchObject({ type: "text", text: "Saved reply", x: 40, y: 120, fontSize: 16, version: expect.any(Number) });
    expect(scene.appState).toEqual(before.appState);
    expect(scene.files).toEqual(before.files);
    expect(stored).toMatchObject({ title: "Sketch", tags: ["kept"] });
    expect(changed).toHaveBeenCalledTimes(1);
    expect((changed.mock.calls[0][0] as CustomEvent<Canvas>).detail.dataJson).toBe(stored!.dataJson);
  } finally { window.removeEventListener(CANVAS_SCENE_REPLACED_EVENT, changed); }
});
it("flushes a mounted editor's latest edit before appending", async () => {
  const before = JSON.parse(stored!.dataJson);
  const manual = { ...before.elements[0], id: "manual", y: 200 };
  const flush = () => { void updateCanvas("drawing", { dataJson: JSON.stringify({ ...before, elements: [...before.elements, manual] }) }); };
  window.addEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
  try {
    await appendCanvasText("drawing", "Reply after draft");
    const elements = JSON.parse(stored!.dataJson).elements;
    expect(elements).toHaveLength(3);
    expect(elements[1]).toEqual(manual);
    expect(elements[2]).toMatchObject({ text: "Reply after draft", y: 300 });
  } finally { window.removeEventListener(CANVAS_SCENE_ACCESS_EVENT, flush); }
});
it("rejects a deleted canvas instead of reporting a successful save", async () => {
  stored = null;
  await expect(appendCanvasText("drawing", "reply")).rejects.toThrow("no longer exists");
});
