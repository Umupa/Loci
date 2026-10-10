import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { courseItems, loadCourse, parseCourse, parseCourseData, parseDiff } from "./course";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const step = { id: "s01", title: "Agent loop", summary: "Add the loop", file: "main.py", before: "", after: "  run()\n\n", explanation: "A **loop**", runCommand: "python main.py" };
const concept = (id: string) => ({ id, title: id.toUpperCase(), content: `Learn ${id}`, prerequisites: [], leadsTo: [] });
const courseSource = (engine: string, data: unknown, metadata = "") => `---\nid: sample\nengine: ${engine}\ntitle: Sample course\n${metadata}---\n${JSON.stringify(data)}\n---\n`;

beforeEach(() => vi.mocked(invoke).mockReset());
describe("generated course boundary", () => {
  it("keeps source code and removes inline progress from a valid build course", () => {
    const result = parseCourse(courseSource("build-your-own", { steps: [{ ...step, status: "mastered" }] }));
    expect(result.course?.data).toEqual({ engine: "build-your-own", steps: [step] });
    expect(result.course?.data.engine === "build-your-own" && result.course.data.steps[0].after).toBe("  run()\n\n");
  });

  it("persists the canvas scope and includes concepts outside a partial recommended path", () => {
    const result = parseCourse(courseSource("domain-navigation", { learningPath: ["pod"], concepts: [concept("container"), { ...concept("pod"), prerequisites: ["container"] }, concept("service")] }, "canvas-id: canvas-a\n"));
    expect(result.course?.data).toMatchObject({ canvasId: "canvas-a", learningPath: ["pod"] });
    expect(courseItems(result.course!.data).map((item) => item.id)).toEqual(["pod", "container", "service"]);
  });

  it.each([null, [], { steps: [] }, { steps: [null] }, { steps: [{ ...step, id: "../step" }] }, { steps: [{ ...step, before: null }] }, { steps: [{ ...step, file: "" }] }, { steps: [step, step] }])("rejects malformed build data without throwing from the parser: %j", (data) => {
    expect(parseCourse(courseSource("build-your-own", data)).error).toBeTruthy();
  });

  it.each([
    { concepts: [concept("pod")], learningPath: ["missing"] },
    { concepts: [concept("pod"), concept("pod")], learningPath: [] },
    { concepts: [concept("pod")], learningPath: ["pod", "pod"] },
    { concepts: [{ ...concept("pod"), prerequisites: ["missing"] }], learningPath: [] },
    { concepts: [{ ...concept("pod"), leadsTo: ["pod"] }], learningPath: [] },
    { concepts: [{ ...concept("pod"), prerequisites: null }], learningPath: [] },
    { concepts: [{ ...concept("pod"), simulationHtml: 123 }], learningPath: [] },
    { concepts: [], learningPath: [] },
  ])("rejects malformed concept structure or references: %j", (data) => {
    expect(parseCourse(courseSource("domain-navigation", data)).error).toBeTruthy();
  });

  it("rejects duplicate metadata, broken JSON, unknown engines and contradictory scopes", () => {
    expect(parseCourse(courseSource("build-your-own", { steps: [step] }, "id: duplicate\n")).error).toContain("duplicate metadata");
    expect(parseCourse("---\nid: sample\ntitle: Sample\nengine: build-your-own\n---\n{").error).toContain("valid JSON");
    expect(parseCourse(courseSource("other", {})).error).toContain("Unknown");
    expect(parseCourse(courseSource("domain-navigation", { concepts: [concept("pod")], learningPath: [], canvasId: "canvas-b" }, "canvas-id: canvas-a\n")).error).toContain("does not match");
    expect(() => parseCourseData("build-your-own", { engine: "domain-navigation", steps: [step] })).toThrow("engine does not match");
  });

  it("handles BOM, CRLF and quoted flat metadata", () => {
    const source = courseSource("build-your-own", { steps: [step] }).replace("id: sample", 'id: "sample"');
    expect(parseCourse("\uFEFF" + source.replace(/\n/g, "\r\n")).course?.id).toBe("sample");
  });
});

describe("diff sections", () => {
  const front = "---\nid: change\ntitle: Change\nfile: main.py\nrun: python main.py\n---\n";
  it("preserves leading whitespace, blank lines, and a missing final newline", () => {
    const result = parseDiff(front + "=== BEFORE ===\n  before()\n\n=== AFTER ===\n\n    after()\n\nend()");
    expect(result.diff).toMatchObject({ before: "  before()\n\n", after: "\n    after()\n\nend()", runCommand: "python main.py" });
  });
  it("supports an empty section and the documented empty-file marker", () => {
    expect(parseDiff(front + "=== BEFORE ===\n=== AFTER ===\nnew()\n").diff?.before).toBe("");
    expect(parseDiff(front + "=== BEFORE ===\n(empty file)\n=== AFTER ===\nnew()\n").diff?.before).toBe("");
  });
  it.each(["=== BEFORE ===\nold()", "=== AFTER ===\nnew()\n=== BEFORE ===\nold()", "=== BEFORE ===\n=== AFTER ===\n=== AFTER ===\n", "intro\n=== BEFORE ===\n=== AFTER ===\n"]) ("shows errors for missing, duplicate, unordered or unexpected sections", (body) => {
    expect(parseDiff(front + body).error).toBeTruthy();
  });
});

describe("stored course contract", () => {
  const raw = { id: "sample", agentId: "owner", title: "Stored", updatedAt: 42, engine: "build-your-own", dataJson: JSON.stringify({ steps: [step] }) };
  const mock = (course: unknown, progress: unknown) => vi.mocked(invoke).mockImplementation(async (command) => command === "course_get" ? course : progress);
  it("loads scoped camelCase data and progress through the real invoke arguments", async () => {
    mock(raw, [{ itemId: "s01", status: "mastered" }]);
    const loaded = await loadCourse("sample", "owner");
    expect(loaded?.progress.get("s01")).toBe("mastered");
    expect(invoke).toHaveBeenCalledWith("course_get", { id: "sample", agentId: "owner" });
    expect(invoke).toHaveBeenCalledWith("course_progress_get", { courseId: "sample", agentId: "owner" });
  });
  it("returns a missing course and exposes storage corruption or native errors", async () => {
    mock(null, []); expect(await loadCourse("sample", "owner")).toBeNull();
    mock({ ...raw, agentId: "other" }, []); await expect(loadCourse("sample", "owner")).rejects.toThrow("different conversation");
    mock({ ...raw, dataJson: "null" }, []); await expect(loadCourse("sample", "owner")).rejects.toThrow("must be an object");
    mock(raw, [{ itemId: "s01", status: "done" }]); await expect(loadCourse("sample", "owner")).rejects.toThrow("Invalid learning status");
    mock(raw, [{ itemId: "missing", status: "mastered" }]); await expect(loadCourse("sample", "owner")).rejects.toThrow("unknown or duplicate");
  });
  it("propagates native read failures", async () => {
    vi.mocked(invoke).mockImplementation(async (command) => { if (command === "course_get") throw new Error("database unavailable"); return []; });
    await expect(loadCourse("sample", "owner")).rejects.toThrow("database unavailable");
  });
});
