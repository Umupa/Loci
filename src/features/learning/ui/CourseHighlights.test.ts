// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { lessonAnnotations } from "../model/annotationCounts";
import { loadCourse } from "../model/course";
import type { Annotation } from "../model/types";
import { CourseHighlights } from "./CourseHighlights";

vi.mock("../model/course", async (importOriginal) => ({ ...await importOriginal<typeof import("../model/course")>(), loadCourse: vi.fn() }));
vi.mock("../model/annotationCounts", () => ({ lessonAnnotations: vi.fn() }));

const mark = (id: string, quote: string, start: number, note = ""): Annotation => ({
  id, documentId: "", target: { kind: "document", agentId: "kern", documentId: "d" }, anchor: { exact: quote, prefix: "", suffix: "", start, end: start + quote.length },
  source: { id, kind: "document", agentId: "kern", documentId: "d", title: "Doc", quote }, anchors: [], note, discussions: [], createdAt: 1, updatedAt: 1,
});
const course = { id: "kvm", agentId: "kern", title: "KVM", updatedAt: 1, progress: new Map(), data: { engine: "reading" as const, chapters: [
  { title: "API", lessons: [{ id: "fd", title: "File descriptors", document: "d" }, { id: "run", title: "KVM_RUN", document: "d" }, { id: "mem", title: "Memory", document: "d" }] },
] } };

let host: HTMLDivElement; let root: Root;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.mocked(loadCourse).mockResolvedValue(course);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.unstubAllGlobals(); });

const render = async (onOpenLesson = vi.fn()) => {
  await act(async () => root.render(createElement(CourseHighlights, { agentId: "kern", courseId: "kvm", title: "KVM", onOpenLesson, onClose: vi.fn() })));
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
  return onOpenLesson;
};

it("lists the course's highlights by lesson in reading order, with the note on each, and opens the lesson", async () => {
  vi.mocked(lessonAnnotations).mockResolvedValue(new Map([
    ["fd", [mark("b", "later passage", 40), mark("a", "earlier passage", 2, "My thought")]],
    ["run", []],
    ["mem", [mark("c", "guest memory", 5)]],
  ]));
  const open = await render();
  const lessons = [...host.querySelectorAll("section")];
  expect(lessons.map((section) => section.getAttribute("aria-label"))).toEqual(["File descriptors", "Memory"]);
  const entries = [...lessons[0].querySelectorAll<HTMLButtonElement>(".course-highlights__entry")];
  expect(entries.map((entry) => entry.querySelector(".course-highlights__quote")?.textContent)).toEqual(["earlier passage", "later passage"]);
  expect(entries[0].querySelector(".course-highlights__note")?.textContent).toBe("My thought");
  await act(async () => entries[1].click());
  expect(open).toHaveBeenCalledWith("fd");
});

it("says how to keep a passage when there is none", async () => {
  vi.mocked(lessonAnnotations).mockResolvedValue(new Map());
  await render();
  expect(host.textContent).toContain("Select text in a lesson and press H.");
});
