// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { CourseWithProgress, LearningStatus } from "../../learning/model/course";
import { LibraryOutline } from "./LibraryOutline";
import { listKeyDown } from "./listKeys";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

let root: Root;
let host: HTMLDivElement;
const course = (progress: [string, LearningStatus][]): CourseWithProgress => ({
  id: "sds", agentId: "a", title: "SDS", updatedAt: 1, progress: new Map(progress),
  data: { engine: "reading", chapters: [
    { title: "Layout", lessons: [{ id: "bytes", title: "Bytes" }, { id: "flags", title: "Flags" }] },
    { title: "Growth", lessons: [{ id: "room", title: "Room", file: "/repo/sds.c", lines: [1, 9] }] },
    { title: "Review", lessons: [{ id: "self", title: "Self check", compare: [{ label: "a", document: "x" }, { label: "b", document: "y" }] }] },
  ] },
});
const build = (progress: [string, LearningStatus][]): CourseWithProgress => ({
  id: "own", agentId: "a", title: "Own", updatedAt: 1, progress: new Map(progress),
  data: { engine: "build-your-own", steps: [
    { id: "one", title: "One", summary: "", file: "", before: "", after: "", explanation: "" },
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

it("names build-your-own statuses in product words and describes a lesson's marks", async () => {
  await act(async () => root.render(createElement(LibraryOutline, {
    course: build([["one", "learning"]]), activeId: null, onSelect: vi.fn(),
    badge: () => createElement("span", { "data-badge": true }, "3 highlights"),
  })));
  const row = host.querySelector<HTMLButtonElement>('[data-library-lesson="one"]')!;
  expect(row.getAttribute("aria-label")).toBe("One, Working");
  const marks = document.getElementById(row.getAttribute("aria-describedby")!);
  expect(marks?.textContent).toBe("3 highlights");
  expect(row.querySelector(".library-mark--learning")).not.toBeNull();
  // Build-your-own steps are all code: no kind to tell apart.
  expect(row.querySelector("[data-lesson-kind]")).toBeNull();
});

it("marks read and begun lessons, folds a chapter wholly read, and follows the open lesson", async () => {
  const onSelect = vi.fn();
  const progress: [string, LearningStatus][] = [["self", "mastered"], ["bytes", "mastered"], ["flags", "learning"]];
  const outline = (activeId: string) => createElement("div", { onKeyDown: listKeyDown },
    createElement(LibraryOutline, { course: course(progress), activeId, onSelect, badge: (id) => createElement("i", { "data-badge": id }) }));
  await act(async () => root.render(outline("flags")));
  // Each lesson has room for a count, such as its highlights.
  expect(host.querySelector('[data-library-lesson="room"] [data-badge="room"]')).not.toBeNull();
  expect(chapters().map((chapter) => chapter.getAttribute("aria-expanded"))).toEqual(["true", "true", "false"]);
  // Chapters and lessons carry no numbers; lessons say only what kind of reading they are.
  expect(chapters().map((chapter) => chapter.textContent)).toEqual(["Layout", "Growth", "Review"]);
  expect(host.querySelector('[data-library-lesson="flags"]')!.textContent).toBe("Flags");
  expect([...host.querySelectorAll<HTMLElement>("[data-lesson-kind]")].map((kind) => [kind.dataset.lessonKind, kind.title]))
    .toEqual([["source", "Source"], ["source", "Source"], ["code", "Code tour"]]);
  expect(lessons()).toEqual(["bytes", "flags", "room"]);
  expect(host.querySelector('[data-library-lesson="bytes"]')!.className).toContain("library-lesson--mastered");
  expect(host.querySelector('[data-library-lesson="flags"] .library-mark--learning')).not.toBeNull();
  expect(host.querySelector('[data-library-lesson="flags"]')!.getAttribute("aria-current")).toBe("step");
  expect(scrolled).toContain("flags");

  // Opening a lesson in a folded chapter unfolds it and brings it into view.
  await act(async () => root.render(outline("self")));
  expect(chapters()[2].getAttribute("aria-expanded")).toBe("true");
  expect(scrolled.at(-1)).toBe("self");
  expect(host.querySelector('[data-library-lesson="self"] [data-lesson-kind]')?.getAttribute("title")).toBe("Comparison");

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
