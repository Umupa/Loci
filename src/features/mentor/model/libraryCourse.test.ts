import { describe, expect, it } from "vitest";
import type { CourseData, LearningStatus } from "../../learning/model/course";
import { courseProgress, courseState, isLibrarySegment, lessonKind, nextLesson, withoutOrdinal } from "./libraryCourse";

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

describe("withoutOrdinal", () => {
  it("drops the number a title starts with, since the path shows the order", () => {
    expect(withoutOrdinal("一、KVM 第一性原理")).toBe("KVM 第一性原理");
    expect(withoutOrdinal("十二、收尾")).toBe("收尾");
    expect(withoutOrdinal("1. Pods")).toBe("Pods");
    expect(withoutOrdinal("2、调度")).toBe("调度");
    expect(withoutOrdinal("(3) Services")).toBe("Services");
  });
  it("keeps a number that is part of the title, and a title that is only a number", () => {
    expect(withoutOrdinal("1.5 seconds to boot")).toBe("1.5 seconds to boot");
    expect(withoutOrdinal("2+2 VMM")).toBe("2+2 VMM");
    expect(withoutOrdinal("一、")).toBe("一、");
    expect(withoutOrdinal("Kubernetes")).toBe("Kubernetes");
  });
});

describe("lessonKind", () => {
  it("tells a source from code shown in place and a comparison", () => {
    expect(lessonKind({})).toBe("source");
    expect(lessonKind({ file: "/papers/firecracker.pdf" })).toBe("source");
    expect(lessonKind({ file: "/papers/scan", pages: [1, 3] })).toBe("source");
    expect(lessonKind({ file: "/repo/src/vcpu.rs" })).toBe("code");
    expect(lessonKind({ compare: [{ label: "a" }, { label: "b" }] })).toBe("compare");
  });
});

it("draws a course as not started, begun or read", () => {
  expect(courseState(0, 0)).toBe("untouched");
  expect(courseState(0, 4)).toBe("untouched");
  expect(courseState(1, 4)).toBe("learning");
  expect(courseState(4, 4)).toBe("mastered");
});
