import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { courseItems, lessonPlaces, loadCourse, parseCourse, parseCourseData, parseDiff } from "./course";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const step = { id: "s01", title: "Agent loop", summary: "Add the loop", file: "main.py", before: "", after: "  run()\n\n", explanation: "A **loop**", runCommand: "python main.py" };
const read = (id: string) => ({ id, title: id.toUpperCase(), document: `k8s-${id}` });
const chapters = (...lessons: unknown[]) => ({ chapters: [{ title: "Workloads", lessons }] });
const courseSource = (engine: string, data: unknown, metadata = "") => `---\nid: sample\nengine: ${engine}\ntitle: Sample course\n${metadata}---\n${JSON.stringify(data)}\n---\n`;

beforeEach(() => vi.mocked(invoke).mockReset());
describe("generated course boundary", () => {
  it("keeps source code and removes inline progress from a valid build course", () => {
    const result = parseCourse(courseSource("build-your-own", { steps: [{ ...step, status: "mastered" }] }));
    expect(result.course?.data).toEqual({ engine: "build-your-own", steps: [step] });
    expect(result.course?.data.engine === "build-your-own" && result.course.data.steps[0].after).toBe("  run()\n\n");
  });

  it("reads a course as chapters of lessons to read, in the order written, without naming an engine", () => {
    const data = { chapters: [
      { title: "Workloads", lessons: [read("pod"), { ...read("probe"), section: "Readiness probe", status: "mastered" }] },
      { title: "Papers", lessons: [{ id: "borg", title: "Borg", file: "/books/borg.pdf", pages: [3, 9] }, { id: "omega", title: "Omega", file: "C:\\books\\omega.pdf" }] },
    ] };
    const result = parseCourse(`---\nid: sample\ntitle: Sample course\ncanvas-id: canvas-a\n---\n${JSON.stringify(data)}\n`);
    expect(result.course).toMatchObject({ engine: "reading", canvasId: "canvas-a" });
    expect(result.course?.data).toMatchObject({ canvasId: "canvas-a", chapters: [{ lessons: [{ document: "k8s-pod" }, { document: "k8s-probe", section: "Readiness probe" }] }, { lessons: [{ file: "/books/borg.pdf", pages: [3, 9] }, { file: "C:\\books\\omega.pdf" }] }] });
    expect(JSON.stringify(result.course?.data)).not.toContain("status");
    expect(courseItems(result.course!.data).map((item) => item.id)).toEqual(["pod", "probe", "borg", "omega"]);
  });

  it("takes a file in the mentor's folder, and the pin shorthand with its lines", () => {
    expect(parseCourse(courseSource("reading", chapters({ id: "a", title: "A", file: "repos/e2b@3f2a9c1:envd/main.go#L4-9" }))).course?.data)
      .toMatchObject({ chapters: [{ lessons: [{ file: "repos/e2b/envd/main.go", commit: "3f2a9c1", lines: [4, 9] }] }] });
    expect(parseCourse(courseSource("reading", chapters({ id: "a", title: "A", file: "sources/paper.pdf", pages: [2, 3] }))).course?.data)
      .toMatchObject({ chapters: [{ lessons: [{ file: "sources/paper.pdf", pages: [2, 3] }] }] });
  });

  it("keeps a code lesson's pin and refuses one that is not a commit id", () => {
    const pinned = { id: "envd", title: "envd", file: "/m/repos/e2b/main.go", lines: [40, 88], commit: "3F2A9C1" };
    expect(parseCourse(courseSource("reading", chapters(pinned))).course?.data).toMatchObject({ chapters: [{ lessons: [{ ...pinned, commit: "3f2a9c1" }] }] });
    expect(parseCourse(courseSource("reading", chapters({ ...pinned, commit: "main" }))).error).toMatch(/commit/);
    expect(parseCourse(courseSource("reading", chapters({ ...read("pod"), commit: "3f2a9c1" }))).error).toMatch(/commit belongs to a file/);
  });

  it.each([null, [], { steps: [] }, { steps: [null] }, { steps: [{ ...step, id: "../step" }] }, { steps: [{ ...step, before: null }] }, { steps: [{ ...step, file: "" }] }, { steps: [step, step] }])("rejects malformed build data without throwing from the parser: %j", (data) => {
    expect(parseCourse(courseSource("build-your-own", data)).error).toBeTruthy();
  });

  it.each([
    { chapters: [] },
    { chapters: [{ title: "Empty", lessons: [] }] },
    { chapters: [{ title: "", lessons: [read("pod")] }] },
    chapters(read("pod"), read("pod")),
    chapters({ id: "pod", title: "Pod" }),
    chapters({ ...read("pod"), file: "/books/pod.pdf" }),
    chapters({ ...read("pod"), document: "../notes" }),
    chapters({ ...read("pod"), pages: [1, 2] }),
    chapters({ ...read("pod"), section: 42 }),
    chapters({ id: "borg", title: "Borg", file: "../borg.pdf" }),
    chapters({ id: "borg", title: "Borg", file: "repos//x.go" }),
    chapters({ id: "borg", title: "Borg", file: "/books/borg.pdf", section: "Intro" }),
    chapters({ id: "borg", title: "Borg", file: "/books/borg.pdf", pages: [9, 3] }),
    chapters({ id: "borg", title: "Borg", file: "/books/borg.pdf", pages: [0, 3] }),
    chapters({ id: "borg", title: "Borg", file: "/books/borg.pdf", pages: "3-9" }),
  ])("rejects malformed chapters or lessons: %j", (data) => {
    expect(parseCourse(courseSource("reading", data)).error).toBeTruthy();
  });

  it.each(["", "  ", undefined])("treats an empty section as a whole-document lesson: %j", (section) => {
    const result = parseCourse(courseSource("reading", chapters({ ...read("pod"), section })));
    expect(result.error).toBeUndefined();
    expect(courseItems(result.course!.data)[0]).not.toHaveProperty("section");
  });

  it("rejects duplicate metadata, broken JSON, unknown engines and contradictory scopes", () => {
    expect(parseCourse(courseSource("build-your-own", { steps: [step] }, "id: duplicate\n")).error).toContain("duplicate metadata");
    expect(parseCourse("---\nid: sample\ntitle: Sample\nengine: build-your-own\n---\n{").error).toContain("valid JSON");
    expect(parseCourse(courseSource("other", {})).error).toContain("Unknown");
    expect(parseCourse(courseSource("reading", { ...chapters(read("pod")), canvasId: "canvas-b" }, "canvas-id: canvas-a\n")).error).toContain("does not match");
    expect(() => parseCourseData("build-your-own", { engine: "reading", steps: [step] })).toThrow("engine does not match");
    expect(parseCourse(courseSource("domain-navigation", { concepts: [], learningPath: [] })).error).toContain("earlier format");
  });

  it("handles BOM, CRLF and quoted flat metadata", () => {
    const source = courseSource("build-your-own", { steps: [step] }).replace("id: sample", 'id: "sample"');
    expect(parseCourse("\uFEFF" + source.replace(/\n/g, "\r\n")).course?.id).toBe("sample");
  });
});

describe("comparison lessons", () => {
  const sha = "3f2a9c1e3f2a9c1e3f2a9c1e3f2a9c1e3f2a9c1e";
  const compare = (parts: unknown[], extra: Record<string, unknown> = {}) => chapters({ id: "restore", title: "Restoring", compare: parts, ...extra });
  const parts = [
    { label: "E2B", file: `repos/e2b-dev/runtime@${sha.slice(0, 7)}:restore.go#L40-88`, note: "Starts from the snapshot." },
    { label: "Cube", file: "/m/repos/cube/restore.rs", lines: [3, 9] },
    { label: "Spec", document: "virtio", section: "Virtqueues" },
  ];

  it("reads its parts as lessons of their own, with labels and guide notes", () => {
    const result = parseCourse(courseSource("reading", compare(parts)));
    expect(result.error).toBeUndefined();
    const lesson = courseItems(result.course!.data)[0] as Parameters<typeof lessonPlaces>[0];
    expect(lesson).toEqual({ id: "restore", title: "Restoring", compare: [
      { label: "E2B", file: "repos/e2b-dev/runtime/restore.go", lines: [40, 88], commit: sha.slice(0, 7), note: "Starts from the snapshot." },
      { label: "Cube", file: "/m/repos/cube/restore.rs", lines: [3, 9] },
      { label: "Spec", document: "virtio", section: "Virtqueues" },
    ] });
    expect(lessonPlaces(lesson)).toHaveLength(3);
    expect(lessonPlaces({ id: "a", title: "A", document: "d" })).toEqual([{ id: "a", title: "A", document: "d" }]);
  });

  it.each([
    ["one part", compare(parts.slice(0, 1))],
    ["five parts", compare([...parts, { label: "D", document: "d" }, { label: "E", document: "e" }])],
    ["a lesson file too", compare(parts, { file: "/m/x.go" })],
    ["a part with no place", compare([parts[0], { label: "X" }])],
    ["a part with both", compare([parts[0], { label: "X", document: "d", file: "/x.go" }])],
    ["an empty label", compare([parts[0], { ...parts[1], label: " " }])],
    ["a repeated label", compare([parts[0], { ...parts[1], label: "e2b" }])],
    ["a long label", compare([parts[0], { ...parts[1], label: "x".repeat(61) }])],
    ["an empty note", compare([parts[0], { ...parts[1], note: "" }])],
    ["a bad commit", compare([parts[0], { ...parts[1], commit: "xyz" }])],
    ["pages in a part", compare([parts[0], { ...parts[1], lines: undefined, pages: [1, 2] }])],
    ["lines on a document", compare([parts[0], { ...parts[2], lines: [1, 2] }])],
    ["not a list", compare({ label: "A" } as unknown as unknown[])],
  ])("refuses %s", (_case, data) => {
    expect(parseCourse(courseSource("reading", data)).error).toBeTruthy();
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
