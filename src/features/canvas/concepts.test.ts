// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { CANVAS_SCENE_REPLACED_EVENT, canvasSceneDrafts, type Canvas, type CanvasUpsert } from "./canvas";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
type Element = Record<string, any>;
const link = { type: "concept", courseId: "kubernetes", conceptId: "pod" };
const node = (id: string, customData: object = link): Element => ({ id, type: "rectangle", x: 10, y: 20, width: 160, height: 80,
  angle: 0, backgroundColor: "#f4f4f5", strokeColor: "#1971c2", groupIds: ["concept-group"], customData });
let saved: Canvas;
const elements = () => JSON.parse(saved.dataJson).elements as Element[];
const byId = (id: string) => elements().find((element) => element.id === id)!;
const load = () => import("./concepts");

beforeEach(async () => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", measureText: (text: string) => ({ width: text.length * 10 }) } as never);
  const { normalizeCanvasScene } = await import("./scene");
  saved = { id: "concept-map", title: "Map", tags: [], createdAt: 1, updatedAt: 1,
    dataJson: normalizeCanvasScene(JSON.stringify({ elements: [node("pod")], appState: {}, files: {} })) };
  canvasSceneDrafts.clear();
  vi.mocked(invoke).mockReset();
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_get") return { ...saved };
    if (command === "canvas_upsert") {
      const { expectedUpdatedAt, ...canvas } = (args as { canvas: CanvasUpsert }).canvas;
      if (expectedUpdatedAt !== saved.updatedAt) throw new Error("Canvas changed since it was read; retry the update.");
      saved = { ...saved, ...canvas, updatedAt: saved.updatedAt + 1 };
      return { ...saved };
    }
    throw new Error(`Unexpected command ${command}`);
  });
});
afterEach(() => { canvasSceneDrafts.clear(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("persists each progress color on a closed canvas and publishes a silent pane replacement", async () => {
  const { setConceptStatus } = await load();
  const original = byId("pod");
  const replaced = vi.fn();
  window.addEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced);
  try {
    for (const [status, color] of [["learning", "#fef3c7"], ["mastered", "#dcfce7"], ["untouched", "#f4f4f5"]] as const) {
      await setConceptStatus(saved.id, "kubernetes", "pod", status, "teacher");
      expect(byId("pod")).toMatchObject({ ...original, backgroundColor: color,
        version: expect.any(Number), versionNonce: expect.any(Number), updated: expect.any(Number) });
      expect(replaced.mock.lastCall![0].detail).toMatchObject({ id: saved.id, dataJson: saved.dataJson, silent: true });
    }
    expect(byId("pod").version).toBeGreaterThan(original.version);
  } finally { window.removeEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced); }
});

it("changes only this course's concept nodes and respects explicit agent ownership", async () => {
  const { normalizeCanvasScene } = await import("./scene");
  const { setConceptStatus } = await load();
  saved.dataJson = normalizeCanvasScene(JSON.stringify({ elements: [
    node("pod"), node("owned-pod", { ...link, agentId: "teacher" }),
    node("foreign-owner", { ...link, agentId: "other-teacher" }),
    node("foreign-course", { ...link, courseId: "other-course" }),
    node("other-concept", { ...link, conceptId: "service" }), node("ordinary", { type: "note" }),
  ], appState: { viewBackgroundColor: "#fff" }, files: { keep: { id: "keep", dataURL: "data:image/png;base64,AAAA", mimeType: "image/png", created: 1 } } }));
  const before = JSON.parse(saved.dataJson);
  await setConceptStatus(saved.id, "kubernetes", "pod", "mastered", "teacher");
  for (const id of ["pod", "owned-pod"]) expect(byId(id).backgroundColor).toBe("#dcfce7");
  for (const id of ["foreign-owner", "foreign-course", "other-concept", "ordinary"])
    expect(byId(id)).toEqual(before.elements.find((element: Element) => element.id === id));
  expect(JSON.parse(saved.dataJson).appState).toEqual(before.appState);
  expect(JSON.parse(saved.dataJson).files).toEqual(before.files);
});

it("recomputes the color update after a CAS conflict without dropping another window's edits", async () => {
  const { setConceptStatus } = await load();
  const persist = vi.mocked(invoke).getMockImplementation()!;
  let collided = false;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_upsert" && !collided) {
      collided = true;
      const data = JSON.parse(saved.dataJson);
      data.elements[0] = { ...data.elements[0], x: 99, version: 5 };
      data.elements.push({ ...data.elements[0], id: "other", customData: undefined });
      saved = { ...saved, dataJson: JSON.stringify(data), updatedAt: 2 };
    }
    return persist(command, args);
  });
  await setConceptStatus(saved.id, "kubernetes", "pod", "mastered");
  expect(byId("pod")).toMatchObject({ x: 99, backgroundColor: "#dcfce7", version: 6 });
  expect(byId("other")).toMatchObject({ x: 99, backgroundColor: "#f4f4f5" });
  expect(vi.mocked(invoke).mock.calls.filter(([command]) => command === "canvas_upsert")).toHaveLength(2);
});

it("rebases a manual draft created while the progress color is being saved", async () => {
  const { setConceptStatus } = await load();
  const original = saved;
  const persist = vi.mocked(invoke).getMockImplementation()!;
  let started!: () => void, release!: () => void;
  const starting = new Promise<void>((resolve) => { started = resolve; });
  const waiting = new Promise<void>((resolve) => { release = resolve; });
  let first = true;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_upsert" && first) { first = false; started(); await waiting; }
    return persist(command, args);
  });
  const syncing = setConceptStatus(saved.id, "kubernetes", "pod", "mastered");
  await starting;
  const draft = JSON.parse(original.dataJson);
  draft.elements[0] = { ...draft.elements[0], x: 80, version: 4, versionNonce: 9 };
  canvasSceneDrafts.set(saved.id, { ...draft, baseDataJson: original.dataJson });
  release();
  await syncing;
  expect(byId("pod")).toMatchObject({ x: 80, backgroundColor: "#dcfce7" });
  expect(byId("pod").version).toBeGreaterThan(4);
  expect(canvasSceneDrafts.has(saved.id)).toBe(false);
});

it("reports a drawing failure and permits retry without claiming the color was saved", async () => {
  const { setConceptStatus } = await load();
  const persist = vi.mocked(invoke).getMockImplementation()!;
  const before = saved.dataJson;
  const replaced = vi.fn();
  window.addEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced);
  try {
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_upsert") throw new Error("disk full");
      return persist(command, args);
    });
    await expect(setConceptStatus(saved.id, "kubernetes", "pod", "mastered")).rejects.toThrow("disk full");
    expect(saved.dataJson).toBe(before);
    expect(replaced).not.toHaveBeenCalled();
    vi.mocked(invoke).mockImplementation(persist);
    await setConceptStatus(saved.id, "kubernetes", "pod", "mastered");
    expect(byId("pod").backgroundColor).toBe("#dcfce7");
    expect(replaced).toHaveBeenCalledOnce();
  } finally { window.removeEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced); }
});

it("reports a missing scoped concept without saving unrelated nodes", async () => {
  const { setConceptStatus } = await load();
  const before = saved.dataJson;
  await expect(setConceptStatus(saved.id, "other-course", "pod", "mastered")).rejects.toThrow("no matching concept");
  expect(saved.dataJson).toBe(before);
  expect(vi.mocked(invoke).mock.calls.filter(([command]) => command === "canvas_upsert")).toHaveLength(0);
});
