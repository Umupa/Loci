import { describe, expect, it, vi } from "vitest";
import { HARNESSES } from "../../features/sessions/model/session";
import { runCommand } from "./dispatch";
import { resolveMentor } from "./mentor";
import { commandFailure } from "./registry";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("../../features/notes", async (load) => ({
  ...await load<typeof import("../../features/notes")>(),
  getNote: vi.fn(async (id: string) => ({ id, agentId: "a1", title: "Thoughts" })),
  deleteNote: vi.fn(async () => undefined),
}));

const external = { requestId: "r1", caller: "external" as const };

describe("mentor lookup", () => {
  const { ctx } = testContext([agent("a1", "Kern"), agent("a2", "Lens"), agent("a3", "lens")]);
  it("finds a mentor by id or unique name", () => {
    expect(resolveMentor(ctx, "a1", external).id).toBe("a1");
    expect(resolveMentor(ctx, "kern", external).id).toBe("a1");
  });
  it("refuses ambiguous and unknown mentors", () => {
    expect(() => resolveMentor(ctx, "Lens", external)).toThrow(/Several mentors/);
    expect(commandFailure((() => { try { resolveMentor(ctx, "Nobody", external); } catch (error) { return error; } })()).code).toBe("not_found");
  });
  it("keeps a mentor's own turn to itself", () => {
    expect(resolveMentor(ctx, undefined, { requestId: "r", caller: "agent", agentId: "a2" }).id).toBe("a2");
    expect(() => resolveMentor(ctx, "a1", { requestId: "r", caller: "agent", agentId: "a2" })).toThrow(/only act on itself/);
  });
});

describe("library commands", () => {
  it("run the agent action as the mentor's own conversation", async () => {
    const { ctx, chatOf } = testContext([agent("a1", "Kern")]);
    await runCommand(ctx, "sources.write", { mentor: "Kern", id: "doc", title: "Doc", path: "/tmp/doc.md", sourceUrl: "https://example.com" }, external);
    expect(ctx.agentApp).toHaveBeenCalledWith(chatOf("a1"), "r1", "documents.write", { id: "doc", title: "Doc", path: "/tmp/doc.md", sourceUrl: "https://example.com" });
    await runCommand(ctx, "guides.write", { mentor: "Kern", id: "guide", title: "Guide", body: "# Read this first" }, external);
    expect(ctx.agentApp).toHaveBeenLastCalledWith(chatOf("a1"), "r1", "guides.write", { id: "guide", title: "Guide", body: "# Read this first" });
    await runCommand(ctx, "canvases.read-data", { mentor: "a1", id: "c1" }, external);
    expect(ctx.agentApp).toHaveBeenLastCalledWith(chatOf("a1"), "r1", "canvas.read-data", { id: "c1" });
  });

  it("do not report sessions back to the mentor unless asked", async () => {
    const { ctx, chatOf } = testContext([agent("a1")]);
    await runCommand(ctx, "sessions.start", { mentor: "a1", prompt: "Build it" }, external);
    expect(ctx.agentApp).toHaveBeenLastCalledWith(chatOf("a1"), "r1", "sessions.start", { prompt: "Build it", notifyOnComplete: false });
    await runCommand(ctx, "sessions.start", { mentor: "a1", prompt: "Build it", notifyOnComplete: true }, external);
    expect(ctx.agentApp).toHaveBeenLastCalledWith(chatOf("a1"), "r1", "sessions.start", { prompt: "Build it", notifyOnComplete: true });
  });

  it("are refused to callers they are not for, and validate fields", async () => {
    const { ctx } = testContext([agent("a1")]);
    await expect(runCommand(ctx, "courses.list", { mentor: "a1" }, { requestId: "r", caller: "agent", agentId: "a1" })).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "courses.read", { mentor: "a1" }, external)).rejects.toMatchObject({ code: "usage", message: "id is required" });
    await expect(runCommand(ctx, "nothing.here", {}, external)).rejects.toMatchObject({ code: "usage" });
  });

  it("asks before deleting a note, and is marked destructive", async () => {
    const { deleteNote } = await import("../../features/notes");
    const { COMMANDS } = await import("./index");
    expect(COMMANDS.get("notes.delete")?.destructive).toBe(true);
    const confirm = vi.fn(() => false);
    const dispatch = vi.fn();
    vi.stubGlobal("window", { confirm, dispatchEvent: dispatch });
    const { ctx } = testContext([agent("a1")]);
    await expect(runCommand(ctx, "notes.delete", { mentor: "a1", id: "n1" }, external)).rejects.toMatchObject({ code: "declined" });
    expect(confirm).toHaveBeenCalledWith("Delete the note “Thoughts”?");
    expect(deleteNote).not.toHaveBeenCalled();
    confirm.mockReturnValueOnce(true);
    expect(await runCommand(ctx, "notes.delete", { mentor: "a1", id: "n1" }, external)).toEqual({ id: "n1", deleted: true });
    expect(deleteNote).toHaveBeenCalledWith("n1");
    expect(dispatch).toHaveBeenCalledOnce();
    vi.unstubAllGlobals();
  });

  it("list models without a mentor", async () => {
    const { ctx } = testContext();
    const models = await runCommand(ctx, "models.list", {}, external) as { harnesses: { id: string }[] };
    expect(models.harnesses.map((harness) => harness.id)).toContain("antigravity");
    // A fresh window has read no catalog yet; the CLI asks for them first.
    expect(ctx.refreshModels).toHaveBeenCalledWith(HARNESSES);
  });
});

vi.mock("../../features/learning/model/course", async (load) => ({
  ...await load<typeof import("../../features/learning/model/course")>(),
  loadCourse: vi.fn(async (id: string) => id === "k8s" ? { id, agentId: "a1", title: "K8s", updatedAt: 0, progress: new Map(),
    data: { engine: "reading", chapters: [{ title: "One", lessons: [{ id: "intro", title: "Intro", source: { kind: "document", id: "doc" } }] }] } } : null),
  setLessonStatus: vi.fn(async () => undefined),
}));

describe("lesson status", () => {
  it("marks a lesson read through the one setter the outline uses", async () => {
    const { setLessonStatus } = await import("../../features/learning/model/course");
    const { ctx } = testContext([agent("a1")]);
    expect(await runCommand(ctx, "courses.lesson", { mentor: "a1", course: "k8s", lesson: "intro", status: "read" }, external)).toEqual({ course: "k8s", lesson: "intro", status: "read", saved: true });
    expect(setLessonStatus).toHaveBeenCalledWith("k8s", "a1", "intro", "mastered");
    await expect(runCommand(ctx, "courses.lesson", { mentor: "a1", course: "k8s", lesson: "nope", status: "read" }, external)).rejects.toMatchObject({ code: "not_found" });
    await expect(runCommand(ctx, "courses.lesson", { mentor: "a1", course: "k8s", lesson: "intro", status: "mastered" }, external)).rejects.toMatchObject({ code: "usage" });
  });
});
