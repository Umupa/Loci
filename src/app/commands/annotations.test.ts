import { beforeEach, describe, expect, it, vi } from "vitest";
import { runCommand } from "./dispatch";
import { anchorQuote } from "./annotations";
import { agent, testContext } from "./testContext";
import type { Annotation } from "../../features/learning/model/types";

const store = vi.hoisted(() => ({ marks: [] as Annotation[] }));
vi.mock("../../features/learning/model/learningStore", () => ({
  listAnnotations: vi.fn(async (target: unknown) => store.marks.filter((mark) => JSON.stringify(mark.target) === JSON.stringify(target))),
  queryAnnotations: vi.fn(async (targets: unknown[]) => store.marks.filter((mark) => targets.some((target) => JSON.stringify(target) === JSON.stringify(mark.target)))),
  getAnnotation: vi.fn(async (id: string) => store.marks.find((mark) => mark.id === id) ?? null),
  upsertAnnotation: vi.fn(async (mark: Annotation) => { store.marks = [...store.marks.filter((entry) => entry.id !== mark.id), mark]; return mark; }),
  deleteAnnotation: vi.fn(async (id: string) => { store.marks = store.marks.filter((entry) => entry.id !== id); }),
  getReadingDocumentByPath: vi.fn(async () => null),
}));
vi.mock("../../features/agents/model/agentDocuments", () => ({
  readAgentDocument: vi.fn(async (_agent: string, id: string) => id === "pods"
    ? { id, title: "Pods", body: "# Pods\n\n## Pod phase\n\nThe **Pending** phase means the Pod has been accepted.\n\n## Containers\n\nThe Pod has been accepted.\n" } : null),
}));
vi.mock("../../features/learning/model/course", () => ({
  loadCourse: vi.fn(async (id: string) => id === "k8s" ? { id, agentId: "a1", title: "K8s", data: { engine: "reading", chapters: [{ title: "C", lessons: [
    { id: "phase", title: "Phase", document: "pods", section: "Pod phase" }, { id: "containers", title: "Containers", document: "pods", section: "Containers" }] }] } } : null),
  courseItems: (data: { chapters: { lessons: unknown[] }[] }) => data.chapters.flatMap((chapter) => chapter.lessons),
}));
vi.mock("../../platform/tauri/fs", () => ({ readTextFile: vi.fn(async () => "fn main() {\n    run();\n}\n") }));

const external = { requestId: "r1", caller: "external" as const };
const mentorTurn = { requestId: "r2", caller: "agent" as const, agentId: "a1" };
beforeEach(() => { store.marks = []; });

describe("annotation commands", () => {
  it("highlight a passage of a source by its words, under the right heading, and count it on its lesson", async () => {
    const { ctx } = testContext([agent("a1", "Kern")]);
    const added = await runCommand(ctx, "annotations.add", { mentor: "Kern", source: "pods", quote: "the Pod has been accepted", section: "Containers", note: "why?" }, external) as { annotation: { id: string; section: string[] } };
    expect(added.annotation.section).toEqual(["Pods", "Containers"]);
    await runCommand(ctx, "annotations.add", { mentor: "a1", source: "pods", quote: "Pending phase" }, external);
    const counts = await runCommand(ctx, "annotations.counts", { course: "k8s" }, mentorTurn);
    expect(counts).toMatchObject({ lessons: { phase: { highlights: 1, notes: 0 }, containers: { highlights: 1, notes: 1 } }, total: { highlights: 2, notes: 1 } });
    const listed = await runCommand(ctx, "annotations.list", { course: "k8s", lesson: "containers" }, mentorTurn) as { annotations: { note: string }[] };
    expect(listed.annotations.map((mark) => mark.note)).toEqual(["why?"]);
  });

  it("refuse a passage that is not there, and keep writing to a terminal", async () => {
    const { ctx } = testContext([agent("a1", "Kern")]);
    await expect(runCommand(ctx, "annotations.add", { mentor: "a1", source: "pods", quote: "nowhere in it" }, external)).rejects.toMatchObject({ code: "not_found" });
    await expect(runCommand(ctx, "annotations.add", { source: "pods", quote: "Pending" }, mentorTurn)).rejects.toThrow();
  });

  it("note, list and delete a highlight on a file, with its lines", async () => {
    const { ctx } = testContext([agent("a1", "Kern")]);
    const added = await runCommand(ctx, "annotations.add", { file: "/src/main.rs", quote: "run();" }, external) as { annotation: { id: string; lines: number[] } };
    expect(added.annotation.lines).toEqual([2, 2]);
    await runCommand(ctx, "annotations.note", { id: added.annotation.id, note: "the call" }, external);
    const listed = await runCommand(ctx, "annotations.list", { file: "/src/main.rs" }, external) as { annotations: { note: string; place: string }[] };
    expect(listed.annotations).toMatchObject([{ note: "the call", place: "Line 2" }]);
    await runCommand(ctx, "annotations.delete", { id: added.annotation.id, yes: true }, external);
    expect(store.marks).toEqual([]);
  });
});

describe("quote anchoring", () => {
  it("finds rendered words in Markdown that marks them up", () => {
    expect(anchorQuote("Some **bold** and [a link](https://x) here.", "bold and a link", { markdown: true })?.exact).toBe("bold and a link");
  });
});
