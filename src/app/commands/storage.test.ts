import { beforeEach, describe, expect, it, vi } from "vitest";
import { runCommand } from "./dispatch";
import { agent, testContext } from "./testContext";

const store = vi.hoisted(() => ({
  storageStatus: vi.fn(async () => ({ ready: true, root: "/L", mentors: [] })),
  migrateStorage: vi.fn(async () => ({ dryRun: true, done: true, mentors: [] })),
  reindexMentors: vi.fn(async () => []),
  checkLibrary: vi.fn(async () => [{ path: "/L/a/courses/c.yaml", kind: "course", id: "c", error: "Not valid YAML" }]),
  searchLibrary: vi.fn(async () => [{ agentId: "a1", kind: "source", id: "virtio", title: "Virtio", snippet: "[rings]" }]),
  exportMentor: vi.fn(async () => ({ path: "/tmp/a.zip", files: 3, bytes: 10, repos: [] })),
  importMentor: vi.fn(async () => ({ id: "a9", folder: "/L/a9", renamedId: false, files: 3, progress: 0, annotations: 0 })),
}));
vi.mock("../../features/agents/model/mentorStore", async (load) => ({ ...await load<object>(), ...store }));
const setAgentWorkdir = vi.hoisted(() => vi.fn(async (_id: string, path: string) => path));
vi.mock("../../features/agents/model/agentWorkdir", async (load) => ({ ...await load<object>(), setAgentWorkdir }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));

const external = { requestId: "r1", caller: "external" as const };
const own = (agentId: string) => ({ requestId: "r2", caller: "agent" as const, agentId });
beforeEach(() => vi.clearAllMocks());

describe("storage commands", () => {
  it("report, migrate and reindex mentors' folders", async () => {
    const { ctx } = testContext([agent("a1", "Kern")]);
    expect(await runCommand(ctx, "storage.status", {}, external)).toMatchObject({ ready: true, root: "/L" });
    await runCommand(ctx, "storage.migrate", { dryRun: true }, external);
    expect(store.migrateStorage).toHaveBeenCalledWith({ dryRun: true });
    await runCommand(ctx, "storage.reindex", { mentor: "Kern" }, external);
    expect(store.reindexMentors).toHaveBeenCalledWith("a1");
  });

  it("let a mentor check and search its own folder, and only its own", async () => {
    const { ctx } = testContext([agent("a1", "Kern"), agent("a2", "Wisp")]);
    expect(await runCommand(ctx, "library.check", {}, own("a1"))).toMatchObject({ mentor: "a1", problems: [{ id: "c" }] });
    await expect(runCommand(ctx, "library.check", { mentor: "Wisp" }, own("a1"))).rejects.toThrow("only act on itself");
    await runCommand(ctx, "library.search", { query: "rings" }, own("a1"));
    expect(store.searchLibrary).toHaveBeenLastCalledWith("rings", "a1", undefined);
    await runCommand(ctx, "library.search", { query: "rings", limit: 5 }, external);
    expect(store.searchLibrary).toHaveBeenLastCalledWith("rings", undefined, 5);
  });

  it("export, import and relocate from a terminal, with absolute paths", async () => {
    const { ctx } = testContext([{ ...agent("a1", "Kern"), folder: "/L/kern", workdir: "/Users/x/study" }]);
    await runCommand(ctx, "mentors.export", { mentor: "Kern", out: "/tmp/kern.zip" }, external);
    expect(store.exportMentor).toHaveBeenCalledWith("a1", "/tmp/kern.zip", false);
    await expect(runCommand(ctx, "mentors.export", { mentor: "Kern", out: "kern.zip" }, external)).rejects.toMatchObject({ code: "usage" });
    await runCommand(ctx, "mentors.import", { path: "/tmp/kern.zip" }, external);
    expect(store.importMentor).toHaveBeenCalledWith({ path: "/tmp/kern.zip" });
    await expect(runCommand(ctx, "mentors.import", {}, external)).rejects.toMatchObject({ code: "usage" });
    expect(await runCommand(ctx, "mentors.relocate", { mentor: "Kern" }, external)).toEqual({ mentor: "a1", workdir: "/L/kern", folder: "/L/kern" });
    await runCommand(ctx, "mentors.relocate", { mentor: "Kern", workdir: "/Users/x/other" }, external);
    expect(setAgentWorkdir).toHaveBeenLastCalledWith("a1", "/Users/x/other");
    await expect(runCommand(ctx, "mentors.export", { mentor: "Kern", out: "/tmp/k.zip" }, own("a1"))).rejects.toThrow();
  });
});
