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
