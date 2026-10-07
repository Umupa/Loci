// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { CANVASES_CHANGED_EVENT, CANVAS_SCENE_ACCESS_EVENT, CANVAS_SCENE_REPLACED_EVENT, canvasElementsToText, canvasSceneDrafts, deleteCanvas, readCanvasScene, writeCanvasScene, updateCanvas, type Canvas, type CanvasSceneReplacement } from "./canvas";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const original: Canvas = { id: "drawing", title: "Before", dataJson: "old scene", tags: [], cwd: "/project", createdAt: 1, updatedAt: 1 };

beforeEach(() => vi.clearAllMocks());
describe("canvas edits", () => {
  it("finishes pending saves before deleting and announces the deletion", async () => {
    let stored: Canvas | null = { ...original };
    let release!: () => void;
    const saving = new Promise<void>((resolve) => { release = resolve; });
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return stored;
      if (command === "canvas_upsert") { await saving; stored = (args as { canvas: Canvas }).canvas; return stored; }
      if (command === "canvas_delete") { stored = null; return; }
      throw new Error("Unexpected command");
    });
    const changed = vi.fn();
    window.addEventListener(CANVASES_CHANGED_EVENT, changed);
    try {
      const edit = updateCanvas(original.id, { title: "Edited" });
      await Promise.resolve();
      await Promise.resolve();
      const deletion = deleteCanvas(original.id);
      release();
      await Promise.all([edit, deletion]);
      expect(stored).toBeNull();
      expect(changed).toHaveBeenCalledTimes(2);
    } finally { window.removeEventListener(CANVASES_CHANGED_EVENT, changed); }
  });
  it("reads the pane's flushed draft and orders a replacement after queued edits", async () => {
    let saved = { ...original };
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") {
        saved = { ...saved, ...(args as { canvas: Canvas }).canvas };
        return { ...saved };
      }
      throw new Error("Unexpected command");
    });
    const flush = () => { void updateCanvas(original.id, { dataJson: "local draft" }); };
    const replaced = vi.fn();
    window.addEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
    window.addEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced);
    try {
      expect(await readCanvasScene(original.id)).toMatchObject({ dataJson: "local draft" });
      canvasSceneDrafts.set(original.id, { elements: [], appState: {}, files: {} } as never);
      await writeCanvasScene(original.id, "agent scene");
      expect(saved.dataJson).toBe("agent scene");
      expect(canvasSceneDrafts.has(original.id)).toBe(false);
      expect(replaced).toHaveBeenCalledTimes(1);
      expect((replaced.mock.calls[0][0] as CustomEvent<Canvas>).detail.dataJson).toBe("agent scene");
    } finally {
      window.removeEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
      window.removeEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced);
    }
  });
  it("derives an agent's change from the scene the pane just saved, and stores its checkpoint with it", async () => {
    let saved = { ...original };
    const upserts: unknown[] = [];
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") {
        const { checkpoint, ...canvas } = (args as { canvas: Canvas & { checkpoint?: unknown } }).canvas;
        upserts.push(checkpoint);
        saved = { ...saved, ...canvas };
        return { ...saved };
      }
      throw new Error("Unexpected command");
    });
    // The open pane holds one edit that is not saved yet.
    let pending: string | null = "user edit";
    const flush = () => { if (pending) void updateCanvas(original.id, { dataJson: pending }); pending = null; };
    const replaced = vi.fn();
    window.addEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
    window.addEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced);
    try {
      const viewport = { x: 0, y: 0, width: 800, height: 600 };
      const result = await writeCanvasScene(original.id, (current) =>
        ({ dataJson: `${current.dataJson} + agent`, checkpoint: { id: "cp1", baselineJson: "{}" }, viewport }));
      expect(result.dataJson).toBe("user edit + agent");
      expect(upserts).toEqual([undefined, { id: "cp1", baselineJson: "{}" }]);
      const detail = (replaced.mock.calls[0][0] as CustomEvent<CanvasSceneReplacement>).detail;
      expect(detail).toMatchObject({ id: original.id, dataJson: "user edit + agent", viewport });
      // The checkpoint is not part of the canvas record panes receive.
      expect(detail).not.toHaveProperty("checkpoint");
      // A change that cannot be computed saves nothing and replaces nothing.
      await expect(writeCanvasScene(original.id, () => { throw new Error("Each element must have a supported Excalidraw type"); })).rejects.toThrow("supported Excalidraw type");
      expect(saved.dataJson).toBe("user edit + agent");
      expect(replaced).toHaveBeenCalledTimes(1);
    } finally {
      window.removeEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
      window.removeEventListener(CANVAS_SCENE_REPLACED_EVENT, replaced);
    }
  });

  it("does not overwrite a pane edit that failed to save", async () => {
    vi.mocked(invoke).mockImplementation(async (command) => {
      if (command === "canvas_get") return { ...original };
      throw new Error("disk full");
    });
    const flush = () => { void updateCanvas(original.id, { dataJson: "unsaved edit" }).catch(() => undefined); };
    const compute = vi.fn(() => ({ dataJson: "agent scene" }));
    window.addEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
    try {
      await expect(writeCanvasScene(original.id, compute)).rejects.toThrow("disk full");
      expect(compute).not.toHaveBeenCalled();
    } finally { window.removeEventListener(CANVAS_SCENE_ACCESS_EVENT, flush); }
  });

  it.each(["patch", "rename", "manual"] as const)("retries a %s against a concurrent window's revision", async (kind) => {
    const baseJson = JSON.stringify({ elements: [{ id: "base", x: 0 }], appState: {}, files: {} });
    let saved = { ...original, dataJson: baseJson };
    let collided = false;
    const versions: (number | undefined)[] = [];
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") {
        const { expectedUpdatedAt, ...canvas } = (args as { canvas: Canvas & { expectedUpdatedAt?: number } }).canvas;
        versions.push(expectedUpdatedAt);
        if (!collided) {
          collided = true;
          saved = { ...saved, updatedAt: 2, dataJson: JSON.stringify({ elements: [{ id: "base", x: 0 }, { id: "remote", x: 10 }], appState: {}, files: {} }) };
        }
        if (expectedUpdatedAt !== undefined && expectedUpdatedAt !== saved.updatedAt)
          throw "Canvas changed since it was read; retry the update.";
        saved = { ...canvas, updatedAt: saved.updatedAt + 1 };
        return { ...saved };
      }
      throw new Error("Unexpected command");
    });
    if (kind === "patch") await writeCanvasScene(original.id, (current) => ({ dataJson: JSON.stringify({ ...JSON.parse(current.dataJson),
      elements: [...JSON.parse(current.dataJson).elements, { id: "agent", x: 20 }] }) }));
    if (kind === "rename") await updateCanvas(original.id, { title: "Renamed" });
    if (kind === "manual") await updateCanvas(original.id, { dataJson: JSON.stringify({ elements: [{ id: "base", x: 40 }], appState: {}, files: {} }) }, { baseDataJson: baseJson });
    expect(versions).toEqual([1, 2]);
    const elements = JSON.parse(saved.dataJson).elements;
    expect(elements.some((element: { id: string }) => element.id === "remote")).toBe(true);
    if (kind === "patch") expect(elements.some((element: { id: string }) => element.id === "agent")).toBe(true);
    if (kind === "rename") expect(saved.title).toBe("Renamed");
    if (kind === "manual") expect(elements.find((element: { id: string }) => element.id === "base").x).toBe(40);
  });

  it("rebases manual stacking, deletion and document edits without dropping a remote addition", async () => {
    const base = { elements: [{ id: "a" }, { id: "b" }, { id: "deleted" }], appState: { viewBackgroundColor: "white", currentItemFontFamily: 1 }, files: {} };
    let saved = { ...original, dataJson: JSON.stringify({ ...base,
      elements: [...base.elements, { id: "remote" }], appState: { ...base.appState, currentItemFontFamily: 3 }, files: { image: { id: "image" } } }) };
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") { saved = (args as { canvas: Canvas }).canvas; return saved; }
      throw new Error("Unexpected command");
    });
    await updateCanvas(original.id, { dataJson: JSON.stringify({ ...base, elements: [{ id: "new-underneath" }, { id: "b" }, { id: "a" }],
      appState: { ...base.appState, viewBackgroundColor: "blue" } }) }, { baseDataJson: JSON.stringify(base) });
    expect(JSON.parse(saved.dataJson)).toEqual({ elements: [{ id: "new-underneath" }, { id: "b" }, { id: "a" }, { id: "remote" }],
      appState: { viewBackgroundColor: "blue", currentItemFontFamily: 3 }, files: { image: { id: "image" } } });
  });

  it("merges edited properties of one element and advances its native revision", async () => {
    const baseElement = { id: "text", x: 0, fontSize: 20, strokeColor: "black", version: 1, versionNonce: 2, updated: 1, obsolete: true };
    const base = { elements: [baseElement], appState: {}, files: {} };
    let saved = { ...original, dataJson: JSON.stringify({ ...base, elements: [{ ...baseElement, x: 10, fontSize: 40, version: 6, versionNonce: 3, updated: 2 }] }) };
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") { saved = (args as { canvas: Canvas }).canvas; return saved; }
      throw new Error("Unexpected command");
    });
    const local = { id: "text", x: 80, fontSize: 20, strokeColor: "blue", version: 4, versionNonce: 9, updated: 3 };
    await updateCanvas(original.id, { dataJson: JSON.stringify({ ...base, elements: [local] }) }, { baseDataJson: JSON.stringify(base) });
    const merged = JSON.parse(saved.dataJson).elements[0];
    expect(merged).toMatchObject({ id: "text", x: 80, fontSize: 40, strokeColor: "blue", version: 7 });
    expect(merged).not.toHaveProperty("obsolete");
    expect(merged.versionNonce).toEqual(expect.any(Number));
    expect(merged.updated).toBeGreaterThan(3);
  });

  it("keeps the current native revision when a stale draft changes only bookkeeping", async () => {
    const baseline = { id: "text", x: 0, version: 1, versionNonce: 2, updated: 1 };
    const base = { elements: [baseline], appState: {}, files: {} };
    const current = { ...baseline, x: 80, version: 6, versionNonce: 3, updated: 2 };
    let saved = { ...original, dataJson: JSON.stringify({ ...base, elements: [current] }) };
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") { saved = (args as { canvas: Canvas }).canvas; return saved; }
      throw new Error("Unexpected command");
    });
    await updateCanvas(original.id, { dataJson: JSON.stringify({ ...base, elements: [{ ...baseline, version: 4, versionNonce: 9, updated: 3 }] }) }, { baseDataJson: JSON.stringify(base) });
    expect(JSON.parse(saved.dataJson).elements).toEqual([current]);
  });

  it("does not recreate a canvas deleted during a conditional update", async () => {
    let deleted = false;
    vi.mocked(invoke).mockImplementation(async (command) => {
      if (command === "canvas_get") return deleted ? null : original;
      deleted = true;
      throw "Canvas changed since it was read; retry the update.";
    });
    await expect(updateCanvas(original.id, { title: "Changed" })).rejects.toThrow("no longer exists");
    expect(vi.mocked(invoke).mock.calls.filter(([command]) => command === "canvas_upsert")).toHaveLength(1);
  });

  it("hands a drawing to a chat with the id an agent needs to continue it", () => {
    const text = canvasElementsToText("Plan", '[{"id":"a"}]', "drawing-1");
    expect(text).toContain('[Canvas: "Plan"]');
    expect(text).toContain('Excalidraw checkpoint id: "drawing-1"');
    expect(text).toContain('{"type":"restoreCheckpoint","id":"drawing-1"}');
    expect(text).toContain('<excalidraw-canvas>\n[{"id":"a"}]\n</excalidraw-canvas>');
    expect(canvasElementsToText("Plan", "[]")).toBe('[Canvas: "Plan"]\n<excalidraw-canvas>\n[]\n</excalidraw-canvas>');
  });

  it("orders scene and title writes, retaining both changes", async () => {
    let saved = { ...original };
    let release!: () => void;
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    let first = true;
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_get") return { ...saved };
      if (command === "canvas_upsert") {
        if (first) { first = false; await blocked; }
        saved = { ...saved, ...(args as { canvas: Canvas }).canvas };
        return { ...saved };
      }
      throw new Error("Unexpected command");
    });
    const scene = updateCanvas("drawing", { dataJson: "new scene" });
    const title = updateCanvas("drawing", { title: "After" });
    release();
    await Promise.all([scene, title]);
    expect(saved).toMatchObject({ title: "After", dataJson: "new scene", cwd: "/project" });
  });

  it("continues saving after a failed write instead of poisoning the queue", async () => {
    vi.mocked(invoke).mockResolvedValueOnce(original).mockRejectedValueOnce(new Error("disk full"));
    await expect(updateCanvas("drawing", { dataJson: "new scene" })).rejects.toThrow("disk full");
    vi.mocked(invoke).mockResolvedValueOnce(original).mockResolvedValueOnce({ ...original, title: "Recovered" });
    await expect(updateCanvas("drawing", { title: "Recovered" })).resolves.toMatchObject({ title: "Recovered" });
  });
});
