// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { parsePathInput, pathSteps, saveCoursePath } from "./coursePath";
import type { CourseSummary } from "./course";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => ({ path: null })) }));
const course = (id: string, title: string, read: number, total: number): CourseSummary => ({ id, agentId: "m", engine: "reading", title, updatedAt: 0, itemCount: total, masteredCount: read });
beforeEach(() => vi.mocked(invoke).mockClear());

describe("a learning path", () => {
  it("shows its courses in order with progress, planned courses and unfinished prerequisites", () => {
    const { steps, others } = pathSteps({ title: "Sandboxes", courses: [
      { id: "basics" }, { id: "cube", after: ["basics"] }, { id: "compare", title: "Three ways", after: ["basics", "cube"] },
    ] }, [course("basics", "Basics", 8, 8), course("cube", "Cube internals", 3, 10), course("k8s", "Kubernetes", 0, 6)]);
    expect(steps.map((step) => [step.position, step.title, step.planned, step.read, step.total])).toEqual([
      [1, "Basics", false, 8, 8], [2, "Cube internals", false, 3, 10], [3, "Three ways", true, 0, 0],
    ]);
    expect(steps[1].pending).toEqual([]);
    expect(steps[2].pending).toEqual([{ id: "cube", title: "Cube internals" }]);
    expect(others.map((entry) => entry.id)).toEqual(["k8s"]);
  });

  it("takes ids or objects and refuses what is not a path", () => {
    expect(parsePathInput({ courses: ["a", { id: "b", after: "a", level: 2 }] })).toEqual({ courses: [{ id: "a" }, { id: "b", after: ["a"], level: 2 }] });
    expect(() => parsePathInput({ courses: [] })).toThrow(/needs courses/);
    expect(() => parsePathInput({ courses: ["_path"] })).toThrow(/course id/);
    expect(() => parsePathInput([])).toThrow();
  });

  it("tells every view when it is saved", async () => {
    const heard = vi.fn();
    window.addEventListener("loci:courses-changed", heard);
    await saveCoursePath("m", { courses: [{ id: "a" }] });
    expect(invoke).toHaveBeenCalledWith("course_path_write", { agentId: "m", path: { courses: [{ id: "a" }] } });
    expect((heard.mock.calls[0][0] as CustomEvent).detail).toEqual({ agentId: "m", courseId: "_path" });
    window.removeEventListener("loci:courses-changed", heard);
  });
});
