import { beforeEach, describe, expect, it, vi } from "vitest";
import { codeDefinition, codePinStatus, readCode, resolveCommit } from "../../platform/tauri/code";
import { codeFile } from "./code";
import { runCommand } from "./dispatch";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("../../features/agents/model/agentWorkdir", async (load) => ({
  ...await load<typeof import("../../features/agents/model/agentWorkdir")>(),
  ensureAgentWorkdir: vi.fn(async () => "/home/me/Loci/kern"),
}));
vi.mock("../../platform/tauri/fs", async (load) => ({
  ...await load<typeof import("../../platform/tauri/fs")>(),
  statFiles: vi.fn(async (paths: string[]) => paths.map((path) => ({ path, mtimeMs: path.startsWith("/home/me/Loci/kern/") ? 1 : null }))),
}));
vi.mock("../../features/learning/model/course", async (load) => ({
  ...await load<typeof import("../../features/learning/model/course")>(),
  loadCourseSummaries: vi.fn(async () => [{ id: "tour", agentId: "a1" }, { id: "other", agentId: "zz" }]),
  loadCourse: vi.fn(async (id: string) => id !== "tour" ? undefined : ({
    id, agentId: "a1", title: "Tour", updatedAt: 0, progress: new Map(),
    data: { engine: "reading", chapters: [{ title: "C", lessons: [
      { id: "envd", title: "envd", file: "/home/me/Loci/kern/repos/e2b/envd/main.go", lines: [40, 88], commit: "a".repeat(40) },
      { id: "doc", title: "Doc", document: "readme" },
    ] }] },
  })),
}));
vi.mock("../../platform/tauri/code", () => ({
  readCode: vi.fn(async (_file: string, commit?: string) => ({ text: "l1\nl2\nl3\nl4\n", ...(commit ? { commit: "b".repeat(40) } : {}) })),
  resolveCommit: vi.fn(async () => ({ commit: "c".repeat(40), repoRoot: "/home/me/Loci/kern/repos/e2b", pathInRepo: "envd/main.go" })),
  codeSymbols: vi.fn(async () => ({ language: "go", symbols: [] })),
  codeDefinition: vi.fn(async () => ({ name: "Start", definitions: [] })),
  codeReferences: vi.fn(async () => ({ name: "Start", match: "name", total: 0, truncated: false, references: [] })),
  codePinStatus: vi.fn(async () => ({ state: "changed", currentLines: [41, 89], exact: true })),
}));

const external = { requestId: "r1", caller: "external" as const };
const kern = { ...agent("a1", "Kern"), folder: "/home/me/Loci/kern", workdir: "/home/me/Loci/kern", projects: ["/code/repo"] };
beforeEach(() => vi.clearAllMocks());

describe("code commands", () => {
  it("name files in the mentor's folders, pinned or not, and nothing outside", async () => {
    expect(await codeFile(kern, "repos/e2b@abcdef0:envd/main.go#L3-4"))
      .toEqual({ file: "/home/me/Loci/kern/repos/e2b/envd/main.go", commit: "abcdef0", lines: [3, 4] });
    expect(await codeFile(kern, "/code/repo/a.rs")).toEqual({ file: "/code/repo/a.rs" });
    await expect(codeFile(kern, "/etc/passwd")).rejects.toMatchObject({ code: "usage" });
    await expect(codeFile(kern, "repos/../../../etc/passwd")).rejects.toMatchObject({ code: "usage" });
  });

  it("pin lines to HEAD as the string a lesson takes, with the excerpt", async () => {
    const { ctx } = testContext([kern]);
    expect(await runCommand(ctx, "code.pin", { mentor: "Kern", file: "repos/e2b/envd/main.go", lines: "2-3" }, external)).toEqual({
      ref: `repos/e2b@${"c".repeat(40)}:envd/main.go#L2-3`, file: "/home/me/Loci/kern/repos/e2b/envd/main.go",
      commit: "c".repeat(40), lines: [2, 3], excerpt: "2\tl2\n3\tl3",
    });
    expect(resolveCommit).toHaveBeenCalledWith("/home/me/Loci/kern/repos/e2b/envd/main.go", undefined);
    await expect(runCommand(ctx, "code.pin", { mentor: "Kern", file: "repos/e2b/envd/main.go", lines: "9-12" }, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("read numbered lines at the pin in the file name", async () => {
    const { ctx } = testContext([kern]);
    expect(await runCommand(ctx, "code.read", { mentor: "Kern", file: "repos/e2b@abcdef0:envd/main.go#L2-3" }, external))
      .toMatchObject({ commit: "b".repeat(40), lines: [2, 3], totalLines: 4, text: "2\tl2\n3\tl3" });
    expect(readCode).toHaveBeenCalledWith("/home/me/Loci/kern/repos/e2b/envd/main.go", "abcdef0");
  });

  it("look up a definition from a place or a name, and want one of them", async () => {
    const { ctx } = testContext([kern]);
    await runCommand(ctx, "code.definition", { mentor: "Kern", file: "repos/e2b/envd/main.go", line: 3, column: 5 }, external);
    expect(codeDefinition).toHaveBeenCalledWith({ file: "/home/me/Loci/kern/repos/e2b/envd/main.go", line: 3, column: 5 });
    await expect(runCommand(ctx, "code.definition", { mentor: "Kern", file: "repos/e2b/envd/main.go" }, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("list pinned lessons and how they stand", async () => {
    const { ctx } = testContext([kern]);
    expect(await runCommand(ctx, "code.pins", { mentor: "Kern" }, external)).toEqual({
      stale: 1,
      pins: [{ course: "tour", lesson: "envd", title: "envd", file: "repos/e2b/envd/main.go", pin: "a".repeat(40), lines: [40, 88], state: "changed", currentLines: [41, 89], exact: true }],
    });
    expect(codePinStatus).toHaveBeenCalledTimes(1);
    await expect(runCommand(ctx, "code.pins", { mentor: "Kern", course: "nope" }, external)).rejects.toMatchObject({ code: "not_found" });
  });
});
