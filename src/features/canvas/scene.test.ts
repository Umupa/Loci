// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";

beforeEach(() => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  // happy-dom has no text rasterizer; the actual Excalidraw conversion runs.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", measureText: (text: string) => ({ width: text.length * 10 }) } as never);
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

it("converts labeled programmatic shapes to editable, bound Excalidraw elements", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const data = JSON.parse(normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "input", x: 80, y: 160, width: 200, height: 80, label: { text: "Agent" } },
    { type: "rectangle", id: "output", x: 440, y: 160, width: 220, height: 80, label: { text: "Loci Canvas" } },
    { type: "arrow", id: "flow", x: 280, y: 200, width: 160, height: 0, points: [[0, 0], [160, 0]], start: { id: "input" }, end: { id: "output" } },
  ] })));
  expect(data.elements).toHaveLength(5);
  expect(data.elements.find((el: { id: string }) => el.id === "input")).toMatchObject({ type: "rectangle", version: expect.any(Number), boundElements: [{ type: "text", id: expect.any(String) }, { type: "arrow", id: "flow" }] });
  expect(data.elements.find((el: { text: string }) => el.text === "Agent")).toMatchObject({ containerId: "input", fontSize: expect.any(Number) });
  expect(data.elements.find((el: { id: string }) => el.id === "flow")).toMatchObject({ startBinding: { elementId: "input" }, endBinding: { elementId: "output" } });
  // An imported native scene can be written again without changing IDs/bindings.
  const second = JSON.parse(normalizeCanvasScene(JSON.stringify(data)));
  expect(second.elements.map((el: { id: string }) => el.id)).toEqual(data.elements.map((el: { id: string }) => el.id));
  expect(second.elements.find((el: { id: string }) => el.id === "flow").startBinding.elementId).toBe("input");
});

it("retains native image files and document settings without persisting viewport state", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const files = { photo: { id: "photo", dataURL: "data:image/png;base64,AAAA", mimeType: "image/png", created: 1 } };
  const result = JSON.parse(normalizeCanvasScene(JSON.stringify({
    elements: [{ id: "image", type: "image", version: 1, x: 10, y: 20, width: 100, height: 100, fileId: "photo" }],
    files, appState: { viewBackgroundColor: "#123456", currentItemFontFamily: 3, scrollX: 200, selectedElementIds: { image: true } },
  })));
  expect(result.files).toEqual(files);
  expect(result.elements[0]).toMatchObject({ id: "image", fileId: "photo", type: "image" });
  expect(result.appState).toEqual({ viewBackgroundColor: "#123456", currentItemFontFamily: 3 });
});

it("accepts reverse-direction arrow dimensions", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const result = JSON.parse(normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "arrow", id: "up", x: 200, y: 200, width: 0, height: -100, points: [[0, 0], [0, -100]] },
  ] })));
  expect(result.elements[0]).toMatchObject({ id: "up", type: "arrow" });
  expect(result.elements[0].points[1][1]).toBeLessThan(0);
});

it("rejects mixing a native scene with shorthand instead of rebuilding existing elements", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const base = JSON.parse(normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "old", x: 0, y: 0, width: 100, height: 50 },
    { type: "arrow", id: "bound", x: 100, y: 25, width: 100, height: 0, start: { id: "old" } },
  ] })));
  expect(() => normalizeCanvasScene(JSON.stringify({ elements: [...base.elements,
    { type: "rectangle", id: "new", x: 250, y: 0 },
  ] }))).toThrow("mix");
});

it("gives different image bytes different IDs while keeping repeated content stable", async () => {
  const { canonicalizeCanvasImages } = await import("./scene");
  const input = (dataURL: string) => JSON.stringify({ elements: [{ type: "image", id: "picture", fileId: "photo" }], files: { photo: { id: "photo", dataURL } } });
  const first = JSON.parse(await canonicalizeCanvasImages(input("data:image/png;base64,AAAA")));
  const second = JSON.parse(await canonicalizeCanvasImages(input("data:image/png;base64,BBBB")));
  expect(first.elements[0].fileId).not.toBe(second.elements[0].fileId);
  expect(second.files[second.elements[0].fileId].dataURL).toContain("BBBB");
  expect(JSON.parse(await canonicalizeCanvasImages(JSON.stringify(second)))).toEqual(second);
  await expect(canonicalizeCanvasImages('{"elements":[{"type":"image","fileId":"missing"}],"files":{}}')).rejects.toThrow("reference a file");
});

it.each([
  null, [], {}, { elements: {} }, { elements: [], files: [] }, { elements: [], appState: null },
  { elements: [], files: { bad: {} } },
  { elements: [{ type: "cameraUpdate", x: 0, y: 0 }] },
  { elements: [{ type: "delete", ids: "box" }] },
  { elements: [{ type: "restoreCheckpoint", id: "remote" }] },
  { elements: [{ type: "rectangle", x: "0", y: 0 }] },
  { elements: [{ type: "text", x: 0, y: 0, text: 42 }] },
  { elements: [{ type: "arrow", x: 0, y: 0, points: [[0, 0], [null, 0]] }] },
  { elements: [{ type: "rectangle", x: 0, y: 0, id: "same" }, { type: "ellipse", x: 0, y: 0, id: "same" }] },
])("rejects invalid scene %# instead of silently persisting it", async (scene) => {
  const { normalizeCanvasScene } = await import("./scene");
  expect(() => normalizeCanvasScene(JSON.stringify(scene))).toThrow();
});
