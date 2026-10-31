// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { CourseWithProgress, LearningStatus } from "../../learning/model/course";
import { LibraryOutline } from "./LibraryOutline";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

let root: Root;
let host: HTMLDivElement;
const course = (progress: [string, LearningStatus][]): CourseWithProgress => ({
  id: "sds", agentId: "a", title: "SDS", updatedAt: 1, progress: new Map(progress),
  data: { engine: "reading", chapters: [
    { title: "Layout", lessons: [{ id: "bytes", title: "Bytes" }, { id: "flags", title: "Flags" }] },
    { title: "Growth", lessons: [{ id: "room", title: "Room" }] },
    { title: "Review", lessons: [{ id: "self", title: "Self check" }] },
  ] },
});
const scrolled: string[] = [];

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  scrolled.length = 0;
  vi.spyOn(HTMLElement.prototype, "scrollIntoView").mockImplementation(function (this: HTMLElement) { scrolled.push(this.dataset.libraryLesson ?? ""); });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

const chapters = () => [...host.querySelectorAll<HTMLButtonElement>(".library-chapter-title")];
const lessons = () => [...host.querySelectorAll<HTMLButtonElement>("[data-library-lesson]")].map((lesson) => lesson.dataset.libraryLesson);

it("marks read and begun lessons, folds a chapter wholly read, and follows the open lesson", async () => {
  const onSelect = vi.fn();
  const progress: [string, LearningStatus][] = [["self", "mastered"], ["bytes", "mastered"], ["flags", "learning"]];
  await act(async () => root.render(createElement(LibraryOutline, { course: course(progress), activeId: "flags", onSelect, badge: (id) => createElement("i", { "data-badge": id }) })));
  // Each lesson has room for a count, such as its highlights.
  expect(host.querySelector('[data-library-lesson="room"] [data-badge="room"]')).not.toBeNull();
  expect(chapters().map((chapter) => chapter.getAttribute("aria-expanded"))).toEqual(["true", "true", "false"]);
  expect(chapters()[2].textContent).toContain("1");
  expect(lessons()).toEqual(["bytes", "flags", "room"]);
  expect(host.querySelector('[data-library-lesson="bytes"]')!.className).toContain("library-lesson--mastered");
  expect(host.querySelector('[data-library-lesson="flags"] .library-mark--learning')).not.toBeNull();
  expect(host.querySelector('[data-library-lesson="flags"]')!.getAttribute("aria-current")).toBe("step");
  expect(scrolled).toContain("flags");

  // Opening a lesson in a folded chapter unfolds it and brings it into view.
  await act(async () => root.render(createElement(LibraryOutline, { course: course(progress), activeId: "self", onSelect })));
  expect(chapters()[2].getAttribute("aria-expanded")).toBe("true");
  expect(scrolled.at(-1)).toBe("self");

  // Chapters fold by hand, and with ← / →.
  await act(async () => chapters()[0].click());
  expect(lessons()).toEqual(["room", "self"]);
  await act(async () => chapters()[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })));
  expect(lessons()).toEqual(["bytes", "flags", "room", "self"]);

  // ↓ moves through chapters and lessons; Enter (a click) opens.
  chapters()[0].focus();
  await act(async () => chapters()[0].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
  expect((document.activeElement as HTMLElement).dataset.libraryLesson).toBe("bytes");
  await act(async () => (document.activeElement as HTMLElement).click());
  expect(onSelect).toHaveBeenCalledWith("bytes");
});
