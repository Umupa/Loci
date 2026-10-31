import { beforeEach, describe, expect, it, vi } from "vitest";
import { createPath, listDir, writeTextFile } from "../../platform/tauri/fs";
import { runCommand } from "./dispatch";
import { mentorPath } from "./files";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("../../features/agents/model/agentWorkdir", async (load) => ({
  ...await load<typeof import("../../features/agents/model/agentWorkdir")>(),
  ensureAgentWorkdir: vi.fn(async () => "/home/me/Loci/kern"),
}));
vi.mock("../../platform/tauri/fs", async (load) => ({
  ...await load<typeof import("../../platform/tauri/fs")>(),
  listDir: vi.fn(async (path: string) => {
    if (path.includes("new")) throw new Error("missing");
    return [{ name: "a.md", path: `${path}/a.md`, isDir: false, hidden: false }];
  }),
  readTextFile: vi.fn(async () => "text"),
  writeTextFile: vi.fn(async () => undefined),
  createPath: vi.fn(async (parent: string, name: string) => `${parent}/${name}`),
}));

const external = { requestId: "r1", caller: "external" as const };
const kern = { ...agent("a1", "Kern"), projects: ["/code/repo"] };
beforeEach(() => vi.clearAllMocks());

describe("a mentor's files", () => {
  it("stay inside its working folder and the folders it was given", async () => {
    expect(await mentorPath(kern, undefined)).toBe("/home/me/Loci/kern");
    expect(await mentorPath(kern, "notes/a.md")).toBe("/home/me/Loci/kern/notes/a.md");
    expect(await mentorPath(kern, "/code/repo/src/main.rs")).toBe("/code/repo/src/main.rs");
    await expect(mentorPath(kern, "../other/secret")).rejects.toMatchObject({ code: "usage" });
    await expect(mentorPath(kern, "/home/me/Loci/kern/../../.ssh/id_rsa")).rejects.toMatchObject({ code: "usage" });
    await expect(mentorPath(kern, "/etc/passwd")).rejects.toMatchObject({ code: "usage" });
  });

  it("list, read and write, creating missing folders", async () => {
    const { ctx } = testContext([kern]);
    expect(await runCommand(ctx, "files.list", { mentor: "Kern" }, external)).toEqual({ path: "/home/me/Loci/kern", entries: [{ name: "a.md", path: "/home/me/Loci/kern/a.md", kind: "file" }] });
    expect(await runCommand(ctx, "files.read", { mentor: "Kern", path: "a.md" }, external)).toEqual({ path: "/home/me/Loci/kern/a.md", text: "text" });
    await runCommand(ctx, "files.write", { mentor: "Kern", path: "lab/new/x.md", text: "hi" }, external);
    expect(createPath).toHaveBeenCalledWith("/home/me/Loci/kern/lab", "new", true);
    expect(writeTextFile).toHaveBeenCalledWith("/home/me/Loci/kern/lab/new/x.md", "hi");
    expect(listDir).toHaveBeenCalled();
  });
});
