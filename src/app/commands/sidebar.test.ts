import { beforeEach, describe, expect, it, vi } from "vitest";
import { loadCourseSummaries } from "../../features/learning/model/course";
import { runCommand } from "./dispatch";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("../../features/learning/model/course", async (load) => ({
  ...await load<typeof import("../../features/learning/model/course")>(),
  loadCourse: vi.fn(async (id: string) => id === "k8s" ? { id, agentId: "a1", title: "K8s", updatedAt: 0, progress: new Map(), data: { engine: "reading", chapters: [] } } : null),
  loadCourseSummaries: vi.fn(async () => []),
}));

const external = { requestId: "r1", caller: "external" as const };
beforeEach(() => vi.clearAllMocks());

describe("library commands", () => {
  it("choose a segment, a course or a filter, and report them back", async () => {
    const { ctx } = testContext([agent("a1", "Kern"), agent("a2")]);
    expect(await runCommand(ctx, "library.show", { mentor: "a1" }, external)).toEqual({ mentor: "a1", visible: true, segment: "sources" });
    expect(await runCommand(ctx, "library.open", { mentor: "Kern", course: "k8s" }, external)).toEqual({ mentor: "a1", visible: true, segment: "courses", course: "k8s" });
    expect(ctx.library.open).toHaveBeenLastCalledWith("a1", { segment: "courses", course: "k8s" });
    expect(await runCommand(ctx, "library.open", { mentor: "a1", segment: "notes", filter: "pods" }, external)).toMatchObject({ segment: "notes", filter: "pods" });
    expect(await runCommand(ctx, "library.open", { mentor: "a1", filter: "" }, external)).not.toHaveProperty("filter");
    expect(ctx.switchAgent).not.toHaveBeenCalled();
    await runCommand(ctx, "library.open", { mentor: "a1", segment: "files", switch: true }, external);
    expect(ctx.switchAgent).toHaveBeenCalledWith("a1");
  });

  it("start on Courses when the mentor has one, and filter the segment shown", async () => {
    vi.mocked(loadCourseSummaries).mockResolvedValue([{ id: "k8s", agentId: "a1", engine: "reading", title: "K8s", updatedAt: 0, itemCount: 1, masteredCount: 0 }]);
    const { ctx } = testContext([agent("a1"), agent("a2")]);
    expect(await runCommand(ctx, "library.show", { mentor: "a1" }, external)).toMatchObject({ segment: "courses" });
    await expect(runCommand(ctx, "library.open", { mentor: "a1", filter: "x" }, external)).rejects.toMatchObject({ code: "usage" });
    expect(await runCommand(ctx, "library.open", { mentor: "a2", filter: "x" }, external)).toMatchObject({ segment: "sources", filter: "x" });
  });

  it("refuse what does not exist or does not fit", async () => {
    const { ctx } = testContext([agent("a1")]);
    await expect(runCommand(ctx, "library.open", { mentor: "a1", segment: "canvases" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "library.open", { mentor: "a1", course: "gone" }, external)).rejects.toMatchObject({ code: "not_found" });
    await expect(runCommand(ctx, "library.open", { mentor: "a1", course: "k8s", segment: "notes" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "library.open", { mentor: "a1", segment: "courses", filter: "x" }, external)).rejects.toMatchObject({ code: "usage" });
    expect(ctx.library.open).not.toHaveBeenCalled();
  });

  it("let a mentor's own turn use its own library only", async () => {
    const { ctx } = testContext([agent("a1"), agent("a2")]);
    const own = { requestId: "r2", caller: "agent" as const, agentId: "a1" };
    expect(await runCommand(ctx, "library.open", { segment: "notes" }, own)).toMatchObject({ mentor: "a1", segment: "notes" });
    await expect(runCommand(ctx, "library.open", { mentor: "a2", segment: "notes" }, own)).rejects.toMatchObject({ code: "failed" });
  });
});
