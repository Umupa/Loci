// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { CANVASES_CHANGED_EVENT, deleteCanvas, updateCanvas, type Canvas } from "./canvas";
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
