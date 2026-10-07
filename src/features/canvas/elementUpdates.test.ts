// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

type El = Record<string, any>;
beforeEach(() => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", font: "20px sans-serif",
    measureText(text: string) { return { width: text.length * (parseFloat(this.font) || 20) * 0.5 }; } } as never);
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });
const load = () => import("./elementUpdates");
const native = (props: El) => ({ version: 3, versionNonce: 7, seed: 11, updated: 5, isDeleted: false, groupIds: [], boundElements: null,
  locked: false, angle: 0, index: null, strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "solid", strokeWidth: 2,
  strokeStyle: "solid", roughness: 1, opacity: 100, roundness: null, frameId: null, ...props });
const scene = async (elements: El[], files: El = {}) => {
  const { normalizeCanvasScene } = await import("./scene");
  return normalizeCanvasScene(JSON.stringify({ elements: elements.map(native), appState: { viewBackgroundColor: "#ffe", currentItemFontFamily: 3 }, files }));
};
const byId = (data: string, id: string) => JSON.parse(data).elements.find((el: El) => el.id === id) as El;

describe("updating native canvas element properties", () => {
  it("preserves image flipping/cropping, resource identity and unknown metadata", async () => {
    const before = await scene([{ type: "image", id: "img", x: 1.125, y: 2.5, width: 64, height: 64, fileId: "photo", status: "saved",
      scale: [-1, 1], crop: { x: 10, y: 5, width: 30, height: 40, naturalWidth: 64, naturalHeight: 64 }, customData: { keep: true }, groupIds: ["group"] }],
      { photo: { id: "photo", dataURL: "data:image/png;base64,AAAA", mimeType: "image/png", created: 1 } });
    const { applyElementUpdates } = await load();
    const result = applyElementUpdates(before, [{ id: "img", changes: { x: 90.75, width: 100 } }]);
    const original = byId(before, "img");
    expect(byId(result.dataJson, "img")).toMatchObject({ ...original, x: 90.75, width: 100, version: original.version + 1, updated: expect.any(Number), versionNonce: expect.any(Number) });
    expect(JSON.parse(result.dataJson).files).toEqual(JSON.parse(before).files);
    expect(result.updatedIds).toEqual(["img"]);
  });

  it("remeasures typography while preserving the existing text identity, font and line height", async () => {
    const before = await scene([{ type: "text", id: "text", x: 10.5, y: 20.5, width: 100, height: 34, text: "Small", originalText: "Small",
      fontSize: 20, fontFamily: 3, textAlign: "left", verticalAlign: "top", containerId: null, lineHeight: 1.7, autoResize: true }]);
    const { applyElementUpdates } = await load();
    const after = applyElementUpdates(before, [{ id: "text", changes: { fontSize: 40, text: "Bigger\nSecond line" } }]);
    const text = byId(after.dataJson, "text");
    expect(text).toMatchObject({ id: "text", x: 10.5, y: 20.5, fontFamily: 3, fontSize: 40, lineHeight: 1.7, originalText: "Bigger\nSecond line" });
    expect(text.height).toBeCloseTo(40 * 1.7 * 2);
    expect(text.width).toBeGreaterThan(byId(before, "text").width);
    expect(JSON.parse(after.dataJson).elements).toHaveLength(1);
  });

  it("wraps fixed-width paragraphs without losing their original text", async () => {
    const before = await scene([{ type: "text", id: "text", x: 10, y: 20, width: 100, height: 25, text: "words words words words", originalText: "words words words words",
      fontSize: 20, fontFamily: 3, textAlign: "left", verticalAlign: "top", containerId: null, lineHeight: 1.5, autoResize: false }]);
    const { applyElementUpdates } = await load();
    const after = applyElementUpdates(before, [{ id: "text", changes: { width: 70 } }]);
    expect(byId(after.dataJson, "text")).toMatchObject({ width: 70, autoResize: false, originalText: "words words words words" });
    expect(byId(after.dataJson, "text").text).toContain("\n");
  });

  it("moves labels and bound straight-arrow endpoints with their shapes without creating IDs", async () => {
    const { normalizeCanvasScene } = await import("./scene");
    const before = normalizeCanvasScene(JSON.stringify({ elements: [
      { type: "rectangle", id: "box", x: 0, y: 0, width: 200, height: 100, label: { id: "label", text: "API" } },
      { type: "rectangle", id: "db", x: 400, y: 0, width: 100, height: 100 },
      { type: "arrow", id: "arrow", x: 200, y: 50, width: 200, height: 0, points: [[0, 0], [200, 0]], start: { id: "box" }, end: { id: "db" } },
    ] }));
    const { applyElementUpdates } = await load();
    const label = JSON.parse(before).elements.find((el: El) => el.containerId === "box");
    const arrow = byId(before, "arrow"), start = [arrow.x + arrow.points[0][0], arrow.y + arrow.points[0][1]];
    const result = applyElementUpdates(before, [{ id: "box", changes: { x: 100, y: 80 } }]);
    const moved = byId(result.dataJson, "arrow");
    expect([moved.x + moved.points[0][0], moved.y + moved.points[0][1]]).toEqual([start[0] + 100, start[1] + 80]);
    expect(moved.startBinding).toMatchObject({ elementId: arrow.startBinding.elementId });
    expect(moved.endBinding).toMatchObject({ elementId: arrow.endBinding.elementId });
    expect(byId(result.dataJson, label.id)).toMatchObject({ containerId: "box", x: label.x + 100, y: label.y + 80 });
    expect(JSON.parse(result.dataJson).elements.map((el: El) => el.id)).toEqual(JSON.parse(before).elements.map((el: El) => el.id));
  });

  it("moves frame members and lets explicitly positioned children override the frame translation", async () => {
    const before = await scene([
      { type: "frame", id: "frame", x: 0, y: 0, width: 500, height: 500, name: "Group" },
      { type: "rectangle", id: "child", x: 20, y: 40, width: 20, height: 20, frameId: "frame" },
      { type: "rectangle", id: "explicit", x: 70, y: 40, width: 20, height: 20, frameId: "frame" },
    ]);
    const { applyElementUpdates } = await load();
    const result = applyElementUpdates(before, [{ id: "frame", changes: { x: 100, y: 60 } }, { id: "explicit", changes: { x: 600 } }]);
    expect(byId(result.dataJson, "child")).toMatchObject({ x: 120, y: 100, frameId: "frame" });
    expect(byId(result.dataJson, "explicit")).toMatchObject({ x: 600, y: 100 });
  });

  it.each([
    [{ id: "missing", changes: { x: 1 } }],
    [{ id: "box", changes: { id: "new" } }],
    [{ id: "box", changes: { type: "ellipse" } }],
    [{ id: "box", changes: { fileId: "new" } }],
    [{ id: "box", changes: { isDeleted: true } }],
    [{ id: "box", changes: { x: Infinity } }],
    [{ id: "box", changes: { width: -1 } }],
    [{ id: "box", changes: { opacity: 101 } }],
    [{ id: "box", changes: { fontSize: 12 } }],
    [{ id: "box", changes: { strokeColor: "not-a-color" } }],
    [{ id: "box", changes: { x: 1 } }, { id: "box", changes: { y: 1 } }],
  ])("rejects invalid batches before saving: %j", async (updates) => {
    const before = await scene([{ type: "rectangle", id: "box", x: 0, y: 0, width: 100, height: 80 }]);
    const { applyElementUpdates } = await load();
    expect(() => applyElementUpdates(before, updates)).toThrow();
    expect(byId(before, "box").x).toBe(0);
  });
});


it("keeps the binding gap while a rectangle is resized", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const before = normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "box", x: 0, y: 0, width: 200, height: 100 },
    { type: "rectangle", id: "other", x: 500, y: 0, width: 100, height: 100 },
    { type: "arrow", id: "arrow", x: 200, y: 50, width: 300, height: 0, points: [[0, 0], [300, 0]], start: { id: "box" }, end: { id: "other" } },
  ] }));
  const { applyElementUpdates } = await load();
  const arrow = byId(before, "arrow");
  const gap = arrow.x + arrow.points[0][0] - 200;
  const after = applyElementUpdates(before, [{ id: "box", changes: { width: 300 } }]);
  const moved = byId(after.dataJson, "arrow");
  expect(moved.x + moved.points[0][0] - 300).toBeCloseTo(gap);
  expect(moved.startBinding).toEqual(arrow.startBinding);
});


it("requires an explicit switch to fixed-width text layout", async () => {
  const before = await scene([{ type: "text", id: "loci-text-measure", x: 10, y: 20, width: 100, height: 25, text: "words words words", originalText: "words words words",
    fontSize: 20, fontFamily: 3, textAlign: "left", verticalAlign: "top", containerId: null, lineHeight: 1.5, autoResize: true }]);
  const { applyElementUpdates } = await load();
  expect(() => applyElementUpdates(before, [{ id: "loci-text-measure", changes: { width: 70 } }])).toThrow("autoResize:false");
  const result = applyElementUpdates(before, [{ id: "loci-text-measure", changes: { width: 70, autoResize: false } }]);
  expect(byId(result.dataJson, "loci-text-measure")).toMatchObject({ width: 70, autoResize: false, originalText: "words words words" });
});

it("rejects a fixed-width bound label instead of mixing two different measured widths", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const before = normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "box", x: 0, y: 0, width: 200, height: 100,
      label: { id: "label", text: "API", fontFamily: 3 } },
  ] }));
  const label = JSON.parse(before).elements.find((element: El) => element.type === "text");
  expect(label).toMatchObject({ width: 30, x: 85, autoResize: true });
  const { applyElementUpdates } = await load();
  expect(() => applyElementUpdates(before, [{ id: label.id, changes: { autoResize: false, fontSize: 40 } }]))
    .toThrow("container width");
  expect(byId(before, label.id)).toEqual(label);
});

it("preserves imported fixed-width bound labels and refuses their reflow until explicitly re-enabled", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const parsed = JSON.parse(normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "box", x: 0, y: 0, width: 200, height: 100,
      label: { id: "label", text: "API", fontFamily: 3 } },
  ] })));
  const label = parsed.elements.find((element: El) => element.type === "text");
  label.autoResize = false;
  const before = JSON.stringify(parsed);
  const { applyElementUpdates } = await load();
  const restyled = applyElementUpdates(before, [{ id: label.id, changes: { strokeColor: "#1971c2" } }]);
  expect(byId(restyled.dataJson, label.id)).toMatchObject({ width: 30, x: 85, autoResize: false });
  expect(() => applyElementUpdates(before, [{ id: "box", changes: { x: 100 } }])).toThrow("container width");
  const resized = applyElementUpdates(before, [{ id: label.id, changes: { autoResize: true, fontSize: 40 } }]);
  expect(byId(resized.dataJson, label.id)).toMatchObject({ width: 60, x: 70, autoResize: true });
});

it("recomputes straight-arrow attachment focus after the path changes while preserving both targets", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const before = normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "box", x: 0, y: 0, width: 200, height: 100 },
    { type: "rectangle", id: "other", x: 400, y: 0, width: 100, height: 100 },
    { type: "arrow", id: "arrow", x: 200, y: 50, width: 200, height: 0, points: [[0, 0], [200, 0]],
      start: { id: "box" }, end: { id: "other" } },
  ] }));
  const original = byId(before, "arrow");
  expect(original.startBinding.focus).toBe(0);
  expect(original.endBinding.focus).toBe(0);
  const { applyElementUpdates } = await load();
  const result = applyElementUpdates(before, [{ id: "box", changes: { y: 100 } }]);
  const arrow = byId(result.dataJson, "arrow");
  expect(arrow.startBinding).toMatchObject({ elementId: "box", focus: expect.any(Number), gap: expect.any(Number) });
  expect(arrow.endBinding).toMatchObject({ elementId: "other", focus: expect.any(Number), gap: expect.any(Number) });
  expect(Math.abs(arrow.startBinding.focus)).toBeGreaterThan(0.1);
  expect(Math.abs(arrow.endBinding.focus)).toBeGreaterThan(0.1);
  expect([arrow.x + arrow.points[0][0], arrow.y + arrow.points[0][1]]).toEqual([200.5, 150]);
  expect(JSON.parse(result.dataJson).elements.map((element: El) => element.id))
    .toEqual(JSON.parse(before).elements.map((element: El) => element.id));
});

it("rewraps the rendered arrow-label text after the final path becomes narrower", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const originalText = "a rather long arrow label words words words words";
  const before = normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "box", x: 0, y: 0, width: 100, height: 100 },
    { type: "rectangle", id: "other", x: 600, y: 0, width: 100, height: 100 },
    { type: "arrow", id: "arrow", x: 100, y: 50, width: 500, height: 0, points: [[0, 0], [500, 0]],
      start: { id: "box" }, end: { id: "other" }, label: { id: "label", text: originalText, fontFamily: 3, fontSize: 20 } },
  ] }));
  const label = JSON.parse(before).elements.find((element: El) => element.containerId === "arrow");
  const { applyElementUpdates } = await load();
  const result = applyElementUpdates(before, [{ id: "other", changes: { x: 250 } }]);
  const final = byId(result.dataJson, label.id);
  expect(final).toMatchObject({ id: label.id, containerId: "arrow", originalText });
  expect(final.text.split("\n").length).toBeGreaterThan(label.text.split("\n").length);
  expect(final.height).toBeCloseTo(final.fontSize * final.lineHeight * final.text.split("\n").length);
  expect(final.width).toBeLessThanOrEqual(220);
});

it("measures combined manual content and agent typography without moving text or changing scene metadata", async () => {
  const before = await scene([{ type: "text", id: "text", x: 0, y: 0, width: 50, height: 24,
    text: "hello", originalText: "hello", fontSize: 20, fontFamily: 3, lineHeight: 1.2,
    textAlign: "left", verticalAlign: "top", autoResize: true, containerId: null, customData: { keep: true } }]);
  const { applyElementUpdates, reconcileMergedScene } = await load();
  const current = applyElementUpdates(before, [{ id: "text", changes: { fontSize: 40 } }]).dataJson;
  const edited = applyElementUpdates(before, [{ id: "text", changes: { text: "hello\nsecond line", x: 80 } }]).dataJson;
  const merged = JSON.parse(current);
  Object.assign(merged.elements[0], { x: 80, text: "hello\nsecond line", originalText: "hello\nsecond line", width: 110, height: 48 });
  merged.customMetadata = { keep: "scene" };
  const result = JSON.parse(reconcileMergedScene(before, edited, current, JSON.stringify(merged)));
  expect(result.elements[0]).toMatchObject({ id: "text", x: 80, y: 0, fontSize: 40, width: 220, height: 96,
    originalText: "hello\nsecond line", customData: { keep: true } });
  expect(result.elements[0].version).toBeGreaterThan(merged.elements[0].version);
  expect(result.appState).toEqual(merged.appState);
  expect(result.files).toEqual(merged.files);
  expect(result.customMetadata).toEqual({ keep: "scene" });
});
