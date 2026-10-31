import { describe, expect, it } from "vitest";
import type { CourseData, LearningStatus } from "../../learning/model/course";
import { courseProgress, isLibrarySegment, nextLesson } from "./libraryCourse";

const data: CourseData = { engine: "reading", chapters: [
  { title: "One", lessons: [{ id: "a", title: "A" }, { id: "b", title: "B" }] },
  { title: "Two", lessons: [{ id: "c", title: "C" }, { id: "d", title: "D" }] },
] };
const course = (entries: [string, LearningStatus][]) => ({ data, progress: new Map(entries) });

describe("nextLesson", () => {
  it("starts at the first lesson of a new course", () => {
    expect(nextLesson(course([]))?.id).toBe("a");
  });
  it("keeps the open lesson while it is unread", () => {
    expect(nextLesson(course([["a", "mastered"]]), "c")?.id).toBe("c");
  });
  it("moves past an open lesson that is read", () => {
    expect(nextLesson(course([["a", "mastered"]]), "a")?.id).toBe("b");
  });
  it("prefers a lesson already begun", () => {
    expect(nextLesson(course([["a", "mastered"], ["c", "learning"]]))?.id).toBe("c");
  });
  it("continues after the last read lesson, then wraps to an earlier unread one", () => {
    expect(nextLesson(course([["c", "mastered"]]))?.id).toBe("d");
    expect(nextLesson(course([["c", "mastered"], ["d", "mastered"]]))?.id).toBe("a");
  });
  it("has nothing left when every lesson is read", () => {
    expect(nextLesson(course(["a", "b", "c", "d"].map((id) => [id, "mastered"])))).toBeUndefined();
  });
  it("follows a build-your-own course's steps", () => {
    const steps = { engine: "build-your-own", steps: [{ id: "s1", title: "S1" }, { id: "s2", title: "S2" }] } as unknown as CourseData;
    expect(nextLesson({ data: steps, progress: new Map([["s1", "mastered"]]) })?.id).toBe("s2");
  });
});

it("counts read lessons", () => {
  expect(courseProgress(course([["a", "mastered"], ["b", "learning"]]))).toEqual({ read: 1, total: 4 });
});

it("knows the four segments", () => {
  expect(["courses", "sources", "notes", "files"].every(isLibrarySegment)).toBe(true);
  expect(isLibrarySegment("canvases")).toBe(false);
});
