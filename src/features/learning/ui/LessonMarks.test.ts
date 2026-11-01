// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { LessonMarks } from "./LessonMarks";

const counts = vi.hoisted(() => ({ value: new Map([["phase", { highlights: 3, notes: 1 }], ["empty", { highlights: 0, notes: 0 }]]) }));
vi.mock("../model/course", () => ({ loadCourse: vi.fn(async () => ({ id: "k8s" })), COURSES_CHANGED_EVENT: "loci:courses-changed" }));
vi.mock("../model/annotationCounts", () => ({ lessonMarkCounts: vi.fn(async () => counts.value) }));
vi.mock("../model/learningStore", () => ({ LEARNING_CHANGED_EVENT: "loci:learning-changed" }));

it("shows a lesson's highlights with a note dot, the course total, nothing at zero, and follows changes", async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const host = document.createElement("div");
  document.body.append(host);
  const root = createRoot(host);
  const render = () => act(async () => {
    root.render(createElement("div", null,
      createElement(LessonMarks, { agentId: "a", courseId: "k8s", lessonId: "phase" }),
      createElement(LessonMarks, { agentId: "a", courseId: "k8s", lessonId: "empty" }),
      createElement(LessonMarks, { agentId: "a", courseId: "k8s" })));
    await new Promise((resolve) => setTimeout(resolve, 10));
  });
  await render();
  const marks = [...host.querySelectorAll<HTMLElement>("[data-lesson-marks]")];
  expect(marks.map((mark) => mark.title)).toEqual(["3 highlights · 1 note", "3 highlights · 1 note"]);
  expect(marks[0].querySelector(".sr-only")?.textContent).toBe("3 highlights · 1 note");
  counts.value = new Map([["phase", { highlights: 1, notes: 0 }]]);
  await act(async () => { window.dispatchEvent(new Event("loci:learning-changed")); await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(host.querySelector<HTMLElement>("[data-lesson-marks]")!.title).toBe("1 highlight");
  await act(async () => root.unmount());
  vi.unstubAllGlobals();
});
