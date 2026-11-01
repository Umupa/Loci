import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { runCommand } from "./dispatch";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const external = { requestId: "r1", caller: "external" as const };
let stored: unknown = null;
beforeEach(() => {
  stored = null;
  vi.mocked(invoke).mockReset().mockImplementation(async (command, args) => {
    if (command === "course_path_read") return { path: stored, file: "courses/_path.yaml" };
    if (command === "course_path_write") { stored = (args as { path: unknown }).path; return { path: stored, file: "courses/_path.yaml" }; }
    if (command === "course_list_all") return [
      { id: "basics", agentId: "a1", engine: "reading", title: "Basics", updatedAt: 0, itemCount: 8, masteredCount: 2 },
      { id: "theirs", agentId: "a2", engine: "reading", title: "Theirs", updatedAt: 0, itemCount: 1, masteredCount: 0 },
      { id: "extra", agentId: "a1", engine: "reading", title: "Extra", updatedAt: 0, itemCount: 3, masteredCount: 0 },
    ];
    throw new Error(`Unexpected ${command}`);
  });
});

describe("path commands", () => {
  it("write a path and read it back with progress, planned courses and the rest", async () => {
    const { ctx } = testContext([agent("a1", "Kern"), agent("a2")]);
    expect(await runCommand(ctx, "path.read", { mentor: "Kern" }, external)).toMatchObject({ path: null });
    expect(await runCommand(ctx, "path.write", { mentor: "Kern", title: "Sandboxes", courses: ["basics", { id: "cube", title: "Cube internals", after: ["basics"] }] }, external))
      .toEqual({ mentor: "a1", file: "courses/_path.yaml", courses: 2, saved: true });
    expect(await runCommand(ctx, "path.read", { mentor: "Kern" }, external)).toEqual({
      mentor: "a1", file: "courses/_path.yaml", title: "Sandboxes",
      courses: [{ id: "basics", title: "Basics", read: 2, lessons: 8 }, { id: "cube", title: "Cube internals", planned: true, after: ["basics"] }],
      otherCourses: [{ id: "extra", title: "Extra" }],
    });
  });

  it("refuse a path that is not one", async () => {
    const { ctx } = testContext([agent("a1", "Kern")]);
    await expect(runCommand(ctx, "path.write", { mentor: "Kern", courses: [] }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "path.write", { mentor: "Kern" }, external)).rejects.toMatchObject({ code: "usage" });
  });
});
