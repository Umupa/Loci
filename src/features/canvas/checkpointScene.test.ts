// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

type El = Record<string, any>;

beforeEach(() => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  // happy-dom has no text rasterizer; the actual Excalidraw conversion runs.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", measureText: (text: string) => ({ width: text.length * 10 }) } as never);
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

const load = () => import("./checkpointScene");
const parse = (dataJson: string) => JSON.parse(dataJson) as { elements: El[]; appState: El; files: El };
const byId = (elements: El[], id: string) => elements.find((element) => element.id === id)!;
const liveIds = (elements: El[]) => elements.filter((element) => !element.isDeleted).map((element) => element.id);

const photo = { id: "photo", dataURL: "data:image/png;base64,AAAA", mimeType: "image/png", created: 1 };

/** A drawing as a person leaves it: an image, a frame, restyled text and a bound arrow. */
async function handDrawnScene(): Promise<string> {
  const { normalizeCanvasScene } = await import("./scene");
  const shapes = parse(normalizeCanvasScene(JSON.stringify({ elements: [
    { type: "rectangle", id: "api", x: 100, y: 100, width: 200, height: 80, label: { text: "API" } },
    { type: "rectangle", id: "db", x: 500, y: 100, width: 200, height: 80, label: { text: "Database" } },
    { type: "arrow", id: "api-db", x: 300, y: 140, width: 200, height: 0, points: [[0, 0], [200, 0]], start: { id: "api" }, end: { id: "db" } },
  ] }))).elements;
  const native = (element: El) => ({ version: 3, versionNonce: 7, seed: 11, updated: 5, isDeleted: false, groupIds: [], boundElements: null, link: null, locked: false, angle: 0,
    strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "solid", strokeWidth: 2, strokeStyle: "solid", roughness: 1, opacity: 100, roundness: null, frameId: null, ...element });
  return normalizeCanvasScene(JSON.stringify({
    elements: [
      native({ id: "zone", type: "frame", x: 60, y: 40, width: 700, height: 420, name: "Backend" }),
      ...shapes.map((element) => ({ ...element, frameId: "zone" })),
      native({ id: "logo", type: "image", x: 120, y: 260, width: 64, height: 64, fileId: "photo", status: "saved", scale: [1, 1], crop: null, frameId: "zone" }),
      native({ id: "note", type: "text", x: 320, y: 300, width: 160, height: 25, text: "typed by hand", originalText: "typed by hand", fontSize: 20, fontFamily: 3,
        textAlign: "left", verticalAlign: "top", containerId: null, lineHeight: 1.2, autoResize: true, strokeColor: "#e03131" }),
    ],
    appState: { viewBackgroundColor: "#fdf6e3", currentItemFontFamily: 3 },
    files: { photo },
  }));
}

describe("drawing through the official Excalidraw MCP format", () => {
  it("turns a first create_view call into an editable, bound scene and keeps only real elements", async () => {
    const { applyCheckpointPatch } = await load();
    const result = applyCheckpointPatch("", { elements: [
      { type: "cameraUpdate", width: 800, height: 600, x: 50, y: 50 },
      { type: "rectangle", id: "b1", x: 100, y: 100, width: 200, height: 100, backgroundColor: "#a5d8ff", label: { text: "Start", fontSize: 20 } },
      { type: "rectangle", id: "b2", x: 450, y: 100, width: 200, height: 100, label: { text: "End", fontSize: 20 } },
      { type: "arrow", id: "a1", x: 300, y: 150, width: 150, height: 0, points: [[0, 0], [150, 0]], endArrowhead: "arrow",
        startBinding: { elementId: "b1", fixedPoint: [1, 0.5] }, endBinding: { elementId: "b2", fixedPoint: [0, 0.5] } },
      { type: "cameraUpdate", width: 400, height: 300, x: 80, y: 60 },
    ] });
    const { elements } = parse(result.dataJson);
    expect(result.viewport).toEqual({ x: 80, y: 60, width: 400, height: 300 });
    expect(elements.map((element) => element.type).sort()).toEqual(["arrow", "rectangle", "rectangle", "text", "text"]);
    // The reference's binding syntax becomes a real two-way binding.
    expect(byId(elements, "a1")).toMatchObject({ startBinding: { elementId: "b1" }, endBinding: { elementId: "b2" } });
    expect(byId(elements, "b1").boundElements).toEqual(expect.arrayContaining([{ id: "a1", type: "arrow" }, { type: "text", id: expect.any(String) }]));
    expect(byId(elements, "b2").boundElements).toEqual(expect.arrayContaining([{ id: "a1", type: "arrow" }]));
    const label = elements.find((element) => element.text === "Start")!;
    expect(label).toMatchObject({ containerId: "b1", textAlign: "center", verticalAlign: "middle", fontFamily: 5 });
    expect(elements.every((element) => Number.isInteger(element.version) && typeof element.index === "string")).toBe(true);
  });

  it("applies a later call as a patch: images, frames, fonts and bindings it does not touch are unchanged", async () => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    const base = parse(before);
    const result = applyCheckpointPatch(before, {
      deletedIds: ["note"],
      elements: [
        { type: "rectangle", id: "cache", x: 300, y: 320, width: 200, height: 80, label: { text: "Cache" } },
        { type: "arrow", id: "api-cache", x: 200, y: 180, width: 100, height: 140, points: [[0, 0], [100, 140]],
          startBinding: { elementId: "api", fixedPoint: [0.5, 1] }, endBinding: { elementId: "cache", fixedPoint: [0, 0.5] } },
      ],
    });
    const after = parse(result.dataJson);
    // Nothing about these was rewritten, including versions and order keys.
    for (const id of ["zone", "db", "api-db", "logo"]) expect(byId(after.elements, id)).toEqual(byId(base.elements, id));
    expect(after.files).toEqual({ photo });
    expect(after.appState).toEqual({ viewBackgroundColor: "#fdf6e3", currentItemFontFamily: 3 });
    expect(byId(after.elements, "logo")).toMatchObject({ type: "image", fileId: "photo", frameId: "zone" });
    expect(byId(after.elements, "api-db")).toMatchObject({ startBinding: { elementId: "api" }, endBinding: { elementId: "db" } });
    // The existing shape gained the new arrow and kept its label, style and frame.
    const api = byId(after.elements, "api");
    expect(api).toMatchObject({ ...byId(base.elements, "api"), version: expect.any(Number), versionNonce: expect.any(Number), updated: expect.any(Number),
      boundElements: [...byId(base.elements, "api").boundElements, { id: "api-cache", type: "arrow" }] });
    expect(api.version).toBeGreaterThan(byId(base.elements, "api").version);
    expect(byId(after.elements, "api-cache")).toMatchObject({ startBinding: { elementId: "api", focus: expect.any(Number), gap: expect.any(Number) }, endBinding: { elementId: "cache" } });
    // A deletion is an Excalidraw tombstone, so the pane can undo it.
    expect(byId(after.elements, "note")).toMatchObject({ isDeleted: true, text: "typed by hand", fontFamily: 3 });
    expect(liveIds(after.elements)).not.toContain("note");
    expect(liveIds(after.elements)).toEqual(expect.arrayContaining(["zone", "api", "db", "api-db", "logo", "cache", "api-cache"]));
  });

  it("keeps a hand-styled text exactly when the agent only adds to the drawing", async () => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    const after = parse(applyCheckpointPatch(before, { elements: [{ type: "text", id: "t", x: 10, y: 10, text: "Title", fontSize: 28 }] }).dataJson);
    expect(byId(after.elements, "note")).toEqual(byId(parse(before).elements, "note"));
    expect(byId(after.elements, "t")).toMatchObject({ fontFamily: 5, fontSize: 28, text: "Title" });
  });

  it("removes a shape with its label and releases arrows and frame members that pointed at it", async () => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    const label = parse(before).elements.find((element) => element.containerId === "db")!;
    const after = parse(applyCheckpointPatch(before, { deletedIds: ["db", "zone"], elements: [] }).dataJson);
    expect(byId(after.elements, "db").isDeleted).toBe(true);
    expect(byId(after.elements, label.id).isDeleted).toBe(true);
    expect(byId(after.elements, "api-db")).toMatchObject({ isDeleted: false, startBinding: { elementId: "api" }, endBinding: null });
    expect(byId(after.elements, "logo")).toMatchObject({ isDeleted: false, frameId: null, fileId: "photo" });
    expect(byId(after.elements, "api").boundElements).toEqual(expect.arrayContaining([{ id: "api-db", type: "arrow" }]));
  });

  it("replaces an element that is drawn again under the same id, with a single label", async () => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    const after = parse(applyCheckpointPatch(before, { elements: [
      { type: "rectangle", id: "api", x: 100, y: 100, width: 240, height: 80, backgroundColor: "#b2f2bb", label: { text: "Gateway" } },
    ] }).dataJson);
    const api = after.elements.filter((element) => element.id === "api");
    expect(api).toHaveLength(1);
    expect(api[0]).toMatchObject({ width: 240, backgroundColor: "#b2f2bb" });
    // It keeps its place in the stack instead of jumping above later elements.
    const order = (elements: El[]) => elements.filter((element) => ["zone", "api", "db", "logo"].includes(element.id)).map((element) => element.id);
    expect(order(after.elements)).toEqual(order(parse(before).elements));
    expect(after.elements.filter((element) => element.containerId === "api" && !element.isDeleted).map((element) => element.text)).toEqual(["Gateway"]);
    // The arrow that was bound to it still is, in both directions.
    expect(byId(after.elements, "api-db").startBinding.elementId).toBe("api");
    expect(api[0].boundElements).toEqual(expect.arrayContaining([{ id: "api-db", type: "arrow" }]));
  });

  it("places frames itself: empty ones keep their geometry and members may be old or new", async () => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    const after = parse(applyCheckpointPatch(before, { elements: [
      { type: "frame", id: "empty", x: 0, y: 0, width: 320, height: 200, name: "Empty" },
      { type: "rectangle", id: "queue", x: 900, y: 100, width: 120, height: 60 },
      { type: "frame", id: "async", x: 880, y: 60, name: "Async", children: ["queue", "note", "missing"] },
    ] }).dataJson);
    expect(byId(after.elements, "empty")).toMatchObject({ type: "frame", x: 0, y: 0, width: 320, height: 200, name: "Empty" });
    expect(byId(after.elements, "queue").frameId).toBe("async");
    expect(byId(after.elements, "note")).toMatchObject({ frameId: "async", fontFamily: 3 });
    // Without a size, the frame is drawn around its members.
    const frame = byId(after.elements, "async");
    expect([frame.x, frame.y, frame.x + frame.width, frame.y + frame.height]).toEqual([310, 90, 1030, 335]);
  });

  it("stores a widget's whole edited scene without rebuilding elements that did not change", async () => {
    const { applyCheckpointPatch, checkpointElements } = await load();
    const before = await handDrawnScene();
    const edited = checkpointElements(before).filter((element) => element.id !== "note")
      .map((element) => element.id === "db" ? { ...element, x: 640, version: element.version + 1 } : element);
    const after = parse(applyCheckpointPatch(before, { replace: true, elements: edited }).dataJson);
    expect(byId(after.elements, "db").x).toBe(640);
    expect(byId(after.elements, "note").isDeleted).toBe(true);
    expect(byId(after.elements, "logo")).toEqual(byId(parse(before).elements, "logo"));
    expect(after.files).toEqual({ photo });
  });

  it.each([
    [[{ type: "image", id: "new", x: 0, y: 0, width: 10, height: 10, fileId: "absent" }], "image"],
    [[{ type: "rectangle", id: "a", x: "0", y: 0 }], "supported Excalidraw type"],
    [[{ type: "sticker", id: "a", x: 0, y: 0 }], "supported Excalidraw type"],
    [[{ type: "rectangle", id: "same", x: 0, y: 0 }, { type: "ellipse", id: "same", x: 0, y: 0 }], "unique"],
    [[{ type: "arrow", id: "a", x: 0, y: 0, points: [[0, 0]] }], "points"],
  ])("rejects call %# instead of saving a broken scene", async (elements, message) => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    expect(() => applyCheckpointPatch(before, { elements })).toThrow(message);
  });

  it("ignores a binding to something that cannot be bound instead of failing the call", async () => {
    const { applyCheckpointPatch } = await load();
    const before = await handDrawnScene();
    const after = parse(applyCheckpointPatch(before, { elements: [
      { type: "arrow", id: "loose", x: 0, y: 0, width: 50, height: 0, points: [[0, 0], [50, 0]], startBinding: { elementId: "gone" }, endBinding: { elementId: "api-db" } },
    ] }).dataJson);
    expect(byId(after.elements, "loose")).toMatchObject({ startBinding: null, endBinding: null });
  });
});

describe("what an agent is told about a drawing", () => {
  it("reports the user's manual edits in the official widget's wording", async () => {
    const { applyCheckpointPatch, checkpointBaseline, describeUserEdits } = await load();
    const agent = await handDrawnScene();
    const baseline = checkpointBaseline(agent);
    expect(describeUserEdits(baseline, agent, "cp1")).toBe("");
    const scene = parse(agent);
    const label = scene.elements.find((element) => element.containerId === "api")!;
    const edited = JSON.stringify({ ...scene, elements: [
      ...scene.elements.filter((element) => element.id !== "logo").map((element) =>
        element.id === "db" ? { ...element, x: 560, y: 220 } : element.id === label.id ? { ...element, text: "Gateway", x: 999 } : element),
      { ...byId(scene.elements, "note"), id: "mine", text: "my box", x: 40, y: 500 },
    ] });
    const text = describeUserEdits(baseline, edited, "cp1");
    expect(text).toContain("User edited diagram (checkpoint: cp1).");
    expect(text).toContain('Added: text "my box" at (40,500) id mine');
    expect(text).toContain("Removed: logo");
    expect(text).toContain("Moved/resized: db → (560,220) 200x80");
    expect(text).toContain(`Text changed: ${label.id} "Gateway"`);
    // A label moves with its shape; that is not a second edit.
    expect(text).not.toContain(`${label.id} →`);
    // After the agent's next call the edits are the new baseline.
    const next = applyCheckpointPatch(edited, { elements: [] }).dataJson;
    expect(describeUserEdits(checkpointBaseline(next), next, "cp2")).toBe("");
    expect(describeUserEdits("not json", edited, "cp1")).toBe("");
  });

  it("lists elements compactly, with the ids and links needed to edit them", async () => {
    const { compactElements } = await load();
    const elements = compactElements(await handDrawnScene());
    expect(byId(elements, "note")).toEqual({ type: "text", id: "note", x: 320, y: 300, width: 160, height: 25, strokeColor: "#e03131", text: "typed by hand", fontSize: 20, fontFamily: 3 });
    expect(byId(elements, "api-db")).toMatchObject({ type: "arrow", startBinding: { elementId: "api" }, endBinding: { elementId: "db" }, points: [[expect.any(Number), 0], [expect.any(Number), 0]] });
    expect(byId(elements, "logo")).toMatchObject({ type: "image", fileId: "photo" });
    expect(byId(elements, "zone")).toMatchObject({ type: "frame", name: "Backend" });
    expect(elements.some((element) => "seed" in element || "versionNonce" in element || "index" in element)).toBe(false);
    expect(JSON.stringify(elements)).not.toContain("base64");
  });

  it("names a new drawing after its heading", async () => {
    const { applyCheckpointPatch, suggestedTitle } = await load();
    const scene = applyCheckpointPatch("", { elements: [
      { type: "text", id: "sub", x: 0, y: 40, text: "6CO2 + 6H2O", fontSize: 16 },
      { type: "text", id: "title", x: 0, y: 0, text: "Photosynthesis\nexplained", fontSize: 28 },
      { type: "rectangle", id: "box", x: 0, y: 80, width: 200, height: 80, label: { text: "A much larger label", fontSize: 40 } },
    ] }).dataJson;
    expect(suggestedTitle(scene)).toBe("Photosynthesis");
    expect(suggestedTitle(applyCheckpointPatch("", { elements: [{ type: "rectangle", id: "box", x: 0, y: 0, width: 10, height: 10 }] }).dataJson)).toBeUndefined();
    const long = suggestedTitle(applyCheckpointPatch("", { elements: [{ type: "text", id: "t", x: 0, y: 0, text: "x".repeat(200), fontSize: 20 }] }).dataJson)!;
    expect(long).toHaveLength(78);
    expect(long.endsWith("…")).toBe(true);
  });
});
