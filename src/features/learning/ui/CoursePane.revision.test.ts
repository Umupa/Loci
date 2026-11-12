// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { COURSES_CHANGED_EVENT, courseItems, deleteCourse, openCourse, saveCourse, type CourseData, type LearningStatus } from "../model/course";
import { handleAgentApp, type AgentAppHost } from "../../agent-app/model/agentApp";
import type { Session } from "../../sessions/model/session";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", null, text) }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"] }) }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));

const deferred = <T,>() => {
  let resolve!: (value: T) => void, reject!: (cause: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const data = (lessonIds = ["pod", "service"]): CourseData => ({
  engine: "reading",
  chapters: [{ title: "Workloads", lessons: lessonIds.map((id) => ({ id, title: id, document: `doc-${id}` })) }],
});
const stored = (updatedAt: number, lessonIds?: string[]) => ({
  id: "domain", agentId: "owner", title: "Kubernetes", updatedAt,
  engine: "reading", dataJson: JSON.stringify(data(lessonIds)),
});
let currentCourse: ReturnType<typeof stored>;
let deleted: boolean;
let progress: Map<string, LearningStatus>;
let container: HTMLDivElement, root: Root;
const command = async (name: string, args: any): Promise<any> => {
  if (name === "course_get") return deleted ? null : currentCourse;
  if (name === "course_progress_get") return [...progress].map(([itemId, status]) => ({ itemId, status }));
  if (name === "course_upsert") {
    deleted = false;
    currentCourse = { ...args.course, updatedAt: currentCourse.updatedAt + 1 };
    const ids = new Set(courseItems(JSON.parse(currentCourse.dataJson)).map((item) => item.id));
    for (const id of progress.keys()) if (!ids.has(id)) progress.delete(id);
    return currentCourse;
  }
  if (name === "course_delete") {
    if (args.agentId === "owner" && (args.id === null || args.id === "domain")) { deleted = true; progress.clear(); }
    return;
  }
  if (name === "course_progress_set") { progress.set(args.itemId, args.status); return; }
  if (name === "agent_documents_get") return { id: args.id, title: args.id, body: `Read ${args.id}`, createdAt: 1, updatedAt: 1 };
  throw new Error(`Unexpected invoke: ${name}`);
};
const button = (text: string) => [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent === text)!;
const reopen = async () => {
  await act(async () => openCourse({ courseId: "domain", agentId: "owner", title: "Kubernetes" }));
};
const revise = (lessonIds?: string[]) => handleAgentApp(
  { id: "agent-chat" } as Session, "revision", "courses.write",
  { id: "domain", title: "Revised Kubernetes", ...data(lessonIds) },
  { agentOf: () => ({ id: "owner" }), courses: { write: saveCourse } } as unknown as AgentAppHost,
);
const mount = async (agentId = "owner") => {
  await act(async () => root.render(createElement(CoursePane, {
    courseId: "domain", agentId, focused: true, onFocus: vi.fn(), onClose: vi.fn(),
  })));
};

beforeEach(() => {
  vi.clearAllMocks();
  currentCourse = stored(1); progress = new Map(); deleted = false;
  vi.mocked(invoke).mockImplementation(command);
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("reloads an opened course after courses.write removes a lesson", async () => {
  await mount();
  expect(container.querySelector("nav")?.textContent).toContain("pod");
  const service = [...container.querySelectorAll<HTMLButtonElement>("nav button")].find((item) => item.textContent?.endsWith("service"))!;
  await act(async () => service.click());
  await act(async () => { await revise(["service", "ingress"]); });

  expect(container.querySelector("header")?.textContent).toContain("Revised Kubernetes");
  expect(container.querySelector("nav")?.textContent).toContain("ingress");
  expect(container.querySelector("nav")?.textContent).not.toContain("pod");
  expect(container.querySelector('[aria-current="step"]')?.textContent).toContain("service");
  await act(async () => button("Mark as read").click());
  expect(progress.get("service")).toBe("mastered");
});

it("keeps a pending progress write locked across a courses.write reload", async () => {
  const write = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    if (name === "course_progress_set") await write.promise;
    return command(name, args);
  });
  await mount(); act(() => button("Mark as read").click());
  await act(async () => { await revise(); });

  expect(container.querySelector("header")?.textContent).toContain("Revised Kubernetes");
  expect(button("Saving…").disabled).toBe(true);
  act(() => button("Saving…").click());
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set")).toHaveLength(1);
  await act(async () => write.resolve(undefined));
  expect(progress.get("pod")).toBe("mastered");
  expect(button("Read ✓").disabled).toBe(true);
});

it("ignores course changes for another owner or another id", async () => {
  await mount();
  const reads = vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_get").length;
  await act(async () => {
    for (const detail of [{ agentId: "other", courseId: "domain" }, { agentId: "owner", courseId: "different" }]) {
      window.dispatchEvent(new CustomEvent(COURSES_CHANGED_EVENT, { detail }));
    }
  });
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_get")).toHaveLength(reads);
  expect(container.querySelector("nav")?.textContent).toContain("pod");
});

it("removes an opened course after its owner deletes its whole course library", async () => {
  await mount();
  expect(container.querySelector("nav")?.textContent).toContain("pod");
  await act(async () => deleteCourse("other"));
  expect(container.querySelector("nav")?.textContent).toContain("pod");
  await act(async () => deleteCourse("owner"));
  expect(invoke).toHaveBeenCalledWith("course_delete", { agentId: "owner", id: null });
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("This course is no longer available");
  expect(container.querySelector("nav")).toBeNull();
});

it("drops a lesson removed after the native progress commit without an error", async () => {
  const reply = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    const result = await command(name, args);
    return name === "course_progress_set" ? reply.promise : result;
  });
  await mount(); await act(async () => button("Mark as read").click());
  expect(progress.get("pod")).toBe("mastered");
  currentCourse = stored(2, ["service"]); progress.delete("pod"); await reopen();
  await act(async () => reply.resolve(undefined));
  expect(container.querySelector("nav")?.textContent).not.toContain("pod");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Mark as read").disabled).toBe(false);
});

it("opens the overview's course contents from its title and closes after selecting a lesson", async () => {
  const back = vi.fn();
  await act(async () => root.render(createElement(CoursePane, {
    courseId: "domain", agentId: "owner", itemId: "service", focused: true, onFocus: vi.fn(), onClose: vi.fn(), onBack: back,
  })));
  expect(document.querySelector('nav[aria-label="Course navigation"]')).toBeNull();
  expect(container.querySelector("main")?.textContent).toContain("Read doc-service");
  // Beside a conversation the header keeps to moving through the course.
  expect(container.querySelector('[aria-label="Expand course to pane"]')).toBeNull();
  await act(async () => container.querySelector<HTMLButtonElement>('[aria-label="Lesson actions"]')!.click());
  expect([...document.querySelectorAll('[role^="menuitem"]')].map((item) => item.textContent)).toEqual(["Mark as read", "Test my understanding", "Highlights & notes", "Full-width text"]);
  await act(async () => container.querySelector<HTMLButtonElement>('[aria-label="Lesson actions"]')!.click());
  const contents = container.querySelector<HTMLButtonElement>('[aria-label="Course contents"]')!;
  expect(contents.closest("h3")).not.toBeNull();
  expect(contents.textContent).toContain("Kubernetes");
  await act(async () => contents.click());
  const popup = document.querySelector('[role="dialog"][aria-label="Course contents"]')!;
  expect(popup.textContent).toContain("Workloads");
  expect(popup.querySelector('[aria-current="step"]')?.getAttribute("aria-label")).toBe("service, Not started");
  expect(document.activeElement).toBe(popup.querySelector('[aria-current="step"]'));
  await act(async () => popup.querySelector<HTMLButtonElement>('[aria-label="pod, Not started"]')!.click());
  expect(document.querySelector('[role="dialog"][aria-label="Course contents"]')).toBeNull();
  expect(contents.getAttribute("aria-expanded")).toBe("false");
  expect(document.activeElement).toBe(contents);
  expect(container.querySelector("main")?.textContent).toContain("Read doc-pod");
  await act(async () => contents.click());
  expect(document.querySelector('[aria-current="step"]')?.getAttribute("aria-label")).toBe("pod, Reading");
  await act(async () => contents.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  await act(async () => container.querySelector<HTMLButtonElement>('[aria-label="Back to courses"]')!.click());
  expect(back).toHaveBeenCalledOnce();
});

it("supports keyboard lesson navigation and dismisses course contents without changing the selection", async () => {
  progress.set("pod", "mastered");
  await act(async () => root.render(createElement(CoursePane, {
    courseId: "domain", agentId: "owner", itemId: "service", focused: true, onFocus: vi.fn(), onClose: vi.fn(), onBack: vi.fn(),
  })));
  const contents = container.querySelector<HTMLButtonElement>('[aria-label="Course contents"]')!;
  await act(async () => contents.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
  const popup = () => document.querySelector('[role="dialog"][aria-label="Course contents"]');
  expect(document.activeElement?.getAttribute("aria-label")).toBe("service, Not started");
  expect(popup()?.querySelector("progress")?.getAttribute("aria-label")).toBe("Course completion, 1 / 2 read");
  await act(async () => document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "Home", bubbles: true })));
  expect(document.activeElement?.getAttribute("aria-label")).toBe("pod, Read");
  await act(async () => document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
  expect(document.activeElement?.getAttribute("aria-label")).toBe("service, Not started");
  await act(async () => document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(popup()).toBeNull();
  expect(document.activeElement).toBe(contents);
  expect(container.querySelector("main")?.textContent).toContain("Read doc-service");
  await act(async () => contents.click());
  await act(async () => container.querySelector("main")!.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })));
  expect(popup()).toBeNull();
  expect(container.querySelector("main")?.textContent).toContain("Read doc-service");
});


it("keeps a later selection across revisions and honors an explicit reopen at the original lesson", async () => {
  const props = { courseId: "domain", agentId: "owner", itemId: "pod", openRequest: 1, focused: true, onFocus: vi.fn(), onClose: vi.fn() };
  await act(async () => root.render(createElement(CoursePane, props)));
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>('nav[aria-label="Course navigation"] button')].find((item) => item.textContent?.endsWith("service"))!.click());
  await act(async () => { await revise(); });
  expect(container.querySelector('[aria-current="step"]')?.textContent).toContain("service");
  await act(async () => root.render(createElement(CoursePane, { ...props, openRequest: 2 })));
  expect(container.querySelector('[aria-current="step"]')?.textContent).toContain("pod");
});

it("marks a lesson read once the reader scrolls to its end, or when it goes on to the next lesson from there", async () => {
  await mount();
  // The lesson ends with the next one, its title the way on.
  expect(container.querySelector("[data-lesson-end] nav button")?.textContent).toBe("service");
  const main = container.querySelector<HTMLElement>(".course-pane__main")!;
  Object.defineProperties(main, { scrollHeight: { value: 2000, configurable: true }, clientHeight: { value: 600, configurable: true } });
  main.scrollTop = 500;
  await act(async () => main.dispatchEvent(new Event("scroll")));
  expect(progress.get("pod")).toBeUndefined();
  main.scrollTop = 1380;
  await act(async () => main.dispatchEvent(new Event("scroll")));
  expect(progress.get("pod")).toBe("mastered");
  await act(async () => container.querySelector<HTMLButtonElement>("[data-lesson-end] nav button")!.click());
  expect(progress.get("service")).toBe("learning");
  expect(container.querySelector("[data-lesson-end] nav")).toBeNull();
});

it("marks a short lesson read only when the reader goes on from its end", async () => {
  await mount();
  expect(progress.get("pod")).toBeUndefined();
  await act(async () => container.querySelector<HTMLButtonElement>("[data-lesson-end] nav button")!.click());
  expect(progress.get("pod")).toBe("mastered");
  expect(progress.get("service")).toBe("learning");
});
