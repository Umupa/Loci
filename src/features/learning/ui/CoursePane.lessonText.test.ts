// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { LearningStatus } from "../model/course";
import { ADD_TO_CHAT_EVENT } from "../../sessions/model/quoteDraft";
import { CoursePane } from "./CoursePane";
import { CourseOutline } from "./CourseOutline";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agent", () => ({ findAgent: () => ({ id: "owner", name: "Kern", sessionId: "chat" }), listAgents: () => [] }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", { "data-markdown": "" }, text) }));
vi.mock("../../../shared/hooks/useCodePlugin", () => {
  const plugin = { highlight: () => null, getThemes: () => ["github-light", "github-dark"] };
  return { useCodePlugin: () => plugin };
});
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));

const course = {
  id: "virtio", agentId: "owner", title: "Virtio", updatedAt: 1, engine: "reading", bodies: ["map", "queue"],
  dataJson: JSON.stringify({ chapters: [{ title: "Rings", lessons: [
    { id: "map", title: "The map" },
    { id: "queue", title: "A queue is two rings", document: "virtio-spec", section: "Virtqueues" },
    { id: "later", title: "Interrupts" },
  ] }, { title: "Devices", lessons: [{ id: "net", title: "virtio-net" }] }] }),
};
let progress: Map<string, LearningStatus>;
let container: HTMLDivElement, root: Root;
const command = async (name: string, args: any): Promise<any> => {
  if (name === "course_get") return course;
  if (name === "course_progress_get") return [...progress].map(([itemId, status]) => ({ itemId, status }));
  if (name === "course_progress_set") { progress.set(args.itemId, args.status); return; }
  if (name === "course_lesson_get") return { courseId: args.courseId, lessonId: args.lessonId, body: `${args.lessonId === "map" ? "" : "# Two rings\n\n"}Text of ${args.lessonId}`, path: `/m/courses/virtio/${args.lessonId}.md`, updatedAt: 1 };
  if (name === "lesson_questions_list") return args.lessonId === "map" ? [
    { courseId: "virtio", lessonId: "map", sessionId: "chat", messageId: "m2", text: "Why two rings?", askedAt: 2 },
    { courseId: "virtio", lessonId: "map", sessionId: "chat", messageId: "m1", text: "What is a descriptor?", askedAt: 1 },
  ] : [];
  if (name === "agent_documents_get") return { id: args.id, title: args.id, body: `Spec ${args.id}`, sourceUrl: "https://docs.oasis-open.org", createdAt: 1, updatedAt: 1 };
  if (name === "learning_annotations_list" || name.startsWith("learning_")) return [];
  return null;
};
const settle = async () => { for (let i = 0; i < 6; i++) await act(async () => { await Promise.resolve(); }); };
const button = (label: string) => [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent === label || item.title === label)!;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  progress = new Map();
  vi.mocked(invoke).mockReset().mockImplementation(command);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

const pane = (itemId: string, openRequest = 1) => createElement(CoursePane, { courseId: "virtio", agentId: "owner", itemId, openRequest, focused: true, onFocus: vi.fn(), onClose: vi.fn(), reader: true });

it("shows a lesson's own text with the course's title, and its source behind Original", async () => {
  await act(async () => root.render(pane("map")));
  await settle();
  expect(container.querySelector("[data-lesson-text] h2")?.textContent).toBe("The map");
  expect(container.textContent).toContain("Text of map");
  // No source, no Original; the mentor's text carries no guide label.
  expect(button("Original")).toBeUndefined();
  expect(container.querySelector("[data-document-guide]")).toBeNull();

  await act(async () => root.render(pane("queue", 2)));
  await settle();
  // The mentor's own heading stands as the title.
  expect(container.querySelector("[data-lesson-text] > h2")).toBeNull();
  expect(container.textContent).toContain("Text of queue");
  await act(async () => button("Original").click());
  await settle();
  expect(container.textContent).toContain("Spec virtio-spec");
  expect(container.textContent).not.toContain("Text of queue");
  await act(async () => button("Back to the lesson").click());
  expect(container.textContent).toContain("Text of queue");
});

it("shows a planned lesson as its title and asks for its chapter, without marking it read or begun", async () => {
  const drafts: string[] = [];
  const listen = (event: Event) => drafts.push((event as CustomEvent<{ text: string }>).detail.text);
  window.addEventListener(ADD_TO_CHAT_EVENT, listen);
  try {
    await act(async () => root.render(pane("later")));
    await settle();
    expect(container.querySelector("[data-planned-lesson] h2")?.textContent).toBe("Interrupts");
    expect(invoke).not.toHaveBeenCalledWith("course_progress_set", expect.anything());
    await act(async () => button("Ask Kern to write this chapter").click());
    expect(drafts).toEqual(['Write the chapter "Rings" of the course "Virtio" (virtio).']);
  } finally { window.removeEventListener(ADD_TO_CHAT_EVENT, listen); }
});

it("sets planned lessons apart in the outline, where choosing one asks for its chapter", async () => {
  const drafts: string[] = [];
  const listen = (event: Event) => drafts.push((event as CustomEvent<{ text: string }>).detail.text);
  window.addEventListener(ADD_TO_CHAT_EVENT, listen);
  const onSelect = vi.fn();
  try {
    const shown = { id: "virtio", agentId: "owner", title: "Virtio", updatedAt: 1, data: { engine: "reading" as const, ...JSON.parse(course.dataJson) }, progress: new Map(), bodies: new Set(course.bodies) };
    await act(async () => root.render(createElement(CourseOutline, { course: shown, activeId: "map", onSelect })));
    const row = (title: string) => [...container.querySelectorAll<HTMLButtonElement>("nav button")].find((item) => item.textContent?.endsWith(title))!;
    expect(row("virtio-net").getAttribute("aria-label")).toBe("virtio-net, Planned");
    expect(row("virtio-net").className).toContain("--planned");
    expect(row("The map").className).not.toContain("--planned");
    await act(async () => row("virtio-net").click());
    expect(onSelect).not.toHaveBeenCalled();
    expect(drafts).toEqual(['Write the chapter "Devices" of the course "Virtio" (virtio).']);
    await act(async () => row("The map").click());
    expect(onSelect).toHaveBeenCalledWith("map");
  } finally { window.removeEventListener(ADD_TO_CHAT_EVENT, listen); }
});

it("ends a lesson with the questions asked on it, oldest first, each opening the conversation there", async () => {
  const opened: unknown[] = [];
  const listen = (event: Event) => opened.push((event as CustomEvent).detail);
  window.addEventListener("loci:open-learning-discussion", listen);
  try {
    await act(async () => root.render(pane("map")));
    await settle();
    const asked = [...container.querySelectorAll<HTMLButtonElement>("[data-lesson-end] ul button")];
    expect(asked.map((item) => item.textContent)).toEqual(["What is a descriptor?", "Why two rings?"]);
    expect(container.querySelector("[data-lesson-end] nav button")?.textContent).toBe("A queue is two rings");
    await act(async () => asked[1].click());
    expect(opened).toEqual([{ sessionId: "chat", blockId: "m2" }]);
  } finally { window.removeEventListener("loci:open-learning-discussion", listen); }
});

it("shows a question on a passage beside it with the answer as it comes, and the lesson's own questions and a box to ask at its end", async () => {
  const { LessonSessionContext } = await import("./lessonSession");
  const passage = { exact: "Text of map", prefix: "", suffix: "", start: 0, end: 11 };
  vi.mocked(invoke).mockImplementation(async (name: string, args: any) => name === "lesson_questions_list" ? [
    { courseId: "virtio", lessonId: "map", sessionId: "chat", messageId: "m1", text: "Why a map?", askedAt: 1, anchor: JSON.stringify(passage) },
    { courseId: "virtio", lessonId: "map", sessionId: "chat", messageId: "m2", text: "Is this all?", askedAt: 2, answer: "No, four chapters." },
  ] : command(name, args));
  const blocks = [
    { id: "m1", role: "user", text: "> Text of map\n\nWhy a map?" },
    { id: "r1", role: "assistant", text: "So you see the whole first", streaming: true },
  ];
  const asks: unknown[] = [];
  const listen = (event: Event) => asks.push((event as CustomEvent).detail);
  window.addEventListener("loci:lesson-ask", listen);
  try {
    await act(async () => root.render(createElement(LessonSessionContext.Provider, { value: { agentId: "owner", sessionId: "chat", blocks: blocks as never, busy: true } }, pane("map"))));
    await settle();
    const note = container.querySelector<HTMLElement>('[data-lesson-note="m1"]')!;
    expect(note).not.toBeNull();
    // No room beside the text here: the note sits under its paragraph.
    expect(note.dataset.wide).toBe("false");
    expect(note.textContent).toContain("Why a map?");
    expect(note.textContent).toContain("So you see the whole first");
    const end = container.querySelector<HTMLElement>("[data-lesson-end]")!;
    expect([...end.querySelectorAll("ul button")].map((item) => item.textContent)).toEqual(["Is this all?"]);
    expect(end.textContent).toContain("No, four chapters.");
    const box = end.querySelector<HTMLTextAreaElement>("textarea")!;
    await act(async () => {
      const set = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!;
      set.call(box, "What next?");
      box.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await act(async () => { box.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })); });
    expect(asks).toEqual([{ agentId: "owner", sessionId: "chat", question: "What next?" }]);
  } finally { window.removeEventListener("loci:lesson-ask", listen); }
});

it("marks the glossary's terms in a lesson's text, except those the lesson itself teaches", async () => {
  vi.mocked(invoke).mockImplementation(async (name: string, args: any) => name === "glossary_read" ? [
    { term: "map", definition: "The whole on one page.", course: "virtio", lesson: "queue" },
    { term: "Text", definition: "Taught right here.", course: "virtio", lesson: "map" },
    { term: "ring", definition: "Not used here." },
  ] : command(name, args));
  await act(async () => root.render(pane("map")));
  await settle();
  expect(container.querySelector<HTMLElement>("[data-reading-text]")?.dataset.terms).toBe("1");
});

it("marks a revised lesson in its header until what changed is looked at, then shows the text before and now", async () => {
  const calls: string[] = [];
  vi.mocked(invoke).mockImplementation(async (name: string, args: any) => {
    calls.push(name);
    if (name === "lesson_revision_get") return args.lessonId === "map" ? { courseId: "virtio", lessonId: "map", previous: "Old text of map", revisedAt: 5, seen: false } : null;
    return command(name, args);
  });
  await act(async () => root.render(pane("map")));
  await settle();
  const revised = container.querySelector<HTMLButtonElement>(".course-pane__revised")!;
  expect(revised.hasAttribute("data-unseen")).toBe(true);
  await act(async () => revised.click());
  await settle();
  expect(document.querySelector("[data-lesson-diff]")?.textContent).toContain("Old text of map");
  expect(calls).toContain("lesson_revision_seen");
  expect(container.querySelector(".course-pane__revised")?.hasAttribute("data-unseen")).toBe(false);
});

it("moves a question whose passage a revision took away to the lesson's end, with the passage it was asked on", async () => {
  const { LessonSessionContext } = await import("./lessonSession");
  const gone = { exact: "a sentence the mentor rewrote", prefix: "", suffix: "", start: 0, end: 29 };
  vi.mocked(invoke).mockImplementation(async (name: string, args: any) => name === "lesson_questions_list" ? [
    { courseId: "virtio", lessonId: "map", sessionId: "chat", messageId: "m1", text: "Why?", askedAt: 1, anchor: JSON.stringify(gone), answer: "Because." },
  ] : command(name, args));
  await act(async () => root.render(createElement(LessonSessionContext.Provider, { value: { agentId: "owner", sessionId: "chat", blocks: [], busy: false } }, pane("map"))));
  await settle();
  expect(container.querySelector('[data-lesson-note="m1"]')).toBeNull();
  const end = container.querySelector<HTMLElement>("[data-lesson-end]")!;
  expect(end.querySelector(".course-pane__passage")?.textContent).toBe("a sentence the mentor rewrote");
  expect(end.textContent).toContain("Because.");
});
