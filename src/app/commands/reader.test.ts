import { beforeEach, describe, expect, it, vi } from "vitest";
import { requestDocumentPlace } from "../../features/agents/model/documentPlace";
import { requestFilePlace } from "../../features/files/model/filePlace";
import { runCommand } from "./dispatch";
import { lineSpan } from "./reader";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("../../features/learning/model/course", async (load) => ({
  ...await load<typeof import("../../features/learning/model/course")>(),
  loadCourse: vi.fn(async (id: string) => id === "k8s" ? { id, agentId: "a1", title: "K8s", updatedAt: 0, progress: new Map(),
    data: { engine: "reading", chapters: [{ title: "One", lessons: [{ id: "intro", title: "Intro", source: { kind: "document", id: "doc" } }] }] } } : null),
}));
vi.mock("../../features/agents/model/agentDocuments", () => ({
  readAgentDocument: vi.fn(async (_agent: string, id: string) => id === "doc" ? { id, title: "Doc", body: "# A\n## B", updatedAt: 0 } : undefined),
}));
vi.mock("../../features/notes", () => ({ getNote: vi.fn(async (id: string) => id === "n1" ? { id } : null) }));
vi.mock("../../features/canvas/canvas", () => ({ getCanvas: vi.fn(async () => null) }));
vi.mock("../../features/agents/model/documentPlace", () => ({ requestDocumentPlace: vi.fn() }));
vi.mock("../../features/files/model/filePlace", () => ({ requestFilePlace: vi.fn() }));

const external = { requestId: "r1", caller: "external" as const };
beforeEach(() => vi.clearAllMocks());

describe("reader commands", () => {
  it("open a lesson and report it back", async () => {
    const { ctx } = testContext([agent("a1", "Kern"), agent("a2")]);
    const opened = await runCommand(ctx, "reader.open", { mentor: "Kern", course: "k8s", lesson: "intro" }, external);
    expect(ctx.reader.show).toHaveBeenCalledWith("a1", { kind: "course", course: { courseId: "k8s", agentId: "a1", title: "K8s", itemId: "intro" } }, false);
    expect(opened).toMatchObject({ mentor: "a1", opened: true, kind: "course", id: "k8s", lesson: { id: "intro" } });
    expect(await runCommand(ctx, "reader.show", { mentor: "a1" }, external)).toMatchObject({ kind: "course", id: "k8s", lesson: { id: "intro" }, active: true });
  });

  it("ask the source and file readers for a section, lines or a page", async () => {
    const { ctx } = testContext([agent("a1")]);
    await runCommand(ctx, "reader.open", { mentor: "a1", source: "doc", section: "B", switch: true }, external);
    expect(requestDocumentPlace).toHaveBeenCalledWith("a1", "doc", { section: "B" });
    expect(ctx.reader.show).toHaveBeenLastCalledWith("a1", expect.objectContaining({ kind: "document" }), true);
    expect(await runCommand(ctx, "reader.show", { mentor: "a1" }, external)).toMatchObject({ kind: "source", id: "doc", focus: { section: "B" } });
    await runCommand(ctx, "reader.open", { mentor: "a1", file: "/src/main.rs", lines: "10-20" }, external);
    expect(requestFilePlace).toHaveBeenCalledWith("/src/main.rs", { lines: [10, 20] });
    await runCommand(ctx, "reader.open", { mentor: "a1", file: "/papers/x.pdf", page: 3 }, external);
    expect(requestFilePlace).toHaveBeenLastCalledWith("/papers/x.pdf", { page: 3 });
    expect(await runCommand(ctx, "reader.show", { mentor: "a1" }, external)).toMatchObject({ kind: "file", path: "/papers/x.pdf", focus: { page: 3 } });
    await runCommand(ctx, "reader.open", { mentor: "a1", file: "/m/repos/x/main.go", at: "ABCDEF0", lines: "3-9" }, external);
    expect(ctx.reader.show).toHaveBeenLastCalledWith("a1", { kind: "file", path: "/m/repos/x/main.go", commit: "abcdef0" }, false);
    expect(await runCommand(ctx, "reader.show", { mentor: "a1" }, external)).toMatchObject({ kind: "file", path: "/m/repos/x/main.go", commit: "abcdef0" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", file: "/m/x.go", at: "main" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", note: "n1", at: "abcdef0" }, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("refuse what is missing or ambiguous", async () => {
    const { ctx } = testContext([agent("a1")]);
    await expect(runCommand(ctx, "reader.open", { mentor: "a1" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", note: "n1", canvas: "c" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", course: "k8s", lesson: "nope" }, external)).rejects.toMatchObject({ code: "not_found" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", canvas: "c" }, external)).rejects.toMatchObject({ code: "not_found" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", file: "relative.md" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", note: "n1", section: "x" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "reader.open", { note: "n1" }, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("serve a mentor's own turn, only for itself", async () => {
    const { ctx } = testContext([agent("a1"), agent("a2")]);
    const own = { requestId: "r", caller: "agent" as const, agentId: "a2" };
    await runCommand(ctx, "reader.open", { note: "n1" }, own);
    expect(ctx.reader.show).toHaveBeenCalledWith("a2", { kind: "note", id: "n1" }, false);
    await expect(runCommand(ctx, "reader.open", { mentor: "a1", note: "n1" }, own)).rejects.toThrow(/only act on itself/);
    await runCommand(ctx, "reader.close", {}, own);
    expect(ctx.reader.close).toHaveBeenCalledWith("a2");
  });

  it("read line spans", () => {
    expect(lineSpan("12")).toEqual([12, 12]);
    expect(lineSpan(" 3 - 9 ")).toEqual([3, 9]);
    expect(() => lineSpan("9-3")).toThrow();
    expect(() => lineSpan("0")).toThrow();
  });
});
