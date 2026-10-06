// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { updateCanvas, type Canvas } from "./canvas";
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const original: Canvas = { id: "drawing", title: "Before", dataJson: "old scene", tags: [], cwd: "/project", createdAt: 1, updatedAt: 1 };

beforeEach(() => vi.clearAllMocks());
describe("canvas edits", () => {
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
