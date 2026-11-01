// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => invoke(...args) }));

import { getNote, upsertNote } from "./notes";

beforeEach(() => invoke.mockReset());

it("names the file version it read when saving a mentor's note", async () => {
  invoke.mockImplementation(async (command: string, args: { note?: Record<string, unknown> }) => {
    if (command === "notes_get") return { id: "n1", slug: "n1", title: "N", body: "", tags: [], slugPending: false, createdAt: 1, updatedAt: 1, agentId: "m", hash: "h1" };
    if (command === "notes_upsert") return { ...args.note, slug: "n1", slugPending: false, createdAt: 1, updatedAt: 2, hash: "h2" };
    return undefined;
  });
  await getNote("n1");
  await upsertNote({ id: "n1", title: "N", body: "x", tags: [] });
  expect(invoke).toHaveBeenLastCalledWith("notes_upsert", { note: { id: "n1", title: "N", body: "x", tags: [], expectedHash: "h1" } });
  await upsertNote({ id: "n1", title: "N", body: "y", tags: [] });
  expect(invoke).toHaveBeenLastCalledWith("notes_upsert", { note: { id: "n1", title: "N", body: "y", tags: [], expectedHash: "h2" } });
});

it("sends no hash for a note this window never read", async () => {
  invoke.mockResolvedValue({ id: "n9", slug: "n9", title: "N", body: "", tags: [], slugPending: false, createdAt: 1, updatedAt: 1 });
  await upsertNote({ id: "n9", title: "N", body: "", tags: [] });
  expect(invoke).toHaveBeenLastCalledWith("notes_upsert", { note: { id: "n9", title: "N", body: "", tags: [] } });
});
