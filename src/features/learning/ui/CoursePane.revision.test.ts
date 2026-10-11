// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { setConceptStatus } from "../../canvas/concepts";
import { COURSES_CHANGED_EVENT, courseItems, deleteCourse, openCourse, saveCourse, type CourseData, type LearningStatus } from "../model/course";
import { handleAgentApp, type AgentAppHost } from "../../agent-app/model/agentApp";
import type { Session } from "../../sessions/model/session";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../canvas/concepts", () => ({ setConceptStatus: vi.fn() }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", null, text) }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"] }) }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));

const deferred = <T,>() => {
  let resolve!: (value: T) => void, reject!: (cause: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const data = (canvasId: string, lessonIds = ["pod", "service"]): CourseData => ({
  engine: "reading", canvasId,
  chapters: [{ title: "Workloads", lessons: lessonIds.map((id) => ({ id, title: id, document: `doc-${id}` })) }],
});
const stored = (canvasId: string, updatedAt: number, conceptIds?: string[]) => ({
  id: "domain", agentId: "owner", title: "Kubernetes", updatedAt,
  engine: "reading", dataJson: JSON.stringify(data(canvasId, conceptIds)),
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
const revise = (canvasId: string, lessonIds?: string[]) => handleAgentApp(
  { id: "agent-chat" } as Session, "revision", "courses.write",
  { id: "domain", title: "Revised Kubernetes", ...data(canvasId, lessonIds) },
  { agentOf: () => ({ id: "owner", projects: [] }), courses: { write: saveCourse } } as unknown as AgentAppHost,
);
const mount = async (agentId = "owner") => {
  await act(async () => root.render(createElement(CoursePane, {
    courseId: "domain", agentId, focused: true, onFocus: vi.fn(), onClose: vi.fn(),
  })));
};

beforeEach(() => {
  vi.clearAllMocks();
  currentCourse = stored("canvas-a", 1); progress = new Map(); deleted = false;
  vi.mocked(invoke).mockImplementation(command);
  vi.mocked(setConceptStatus).mockResolvedValue(undefined);
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("reloads an opened course after courses.write removes a lesson and changes its canvas", async () => {
  await mount();
  expect(container.querySelector("nav")?.textContent).toContain("pod");
  const service = [...container.querySelectorAll<HTMLButtonElement>("nav button")].find((item) => item.textContent?.endsWith("service"))!;
  await act(async () => service.click());
  await act(async () => { await revise("canvas-b", ["service", "ingress"]); });

  expect(container.querySelector("header")?.textContent).toContain("Revised Kubernetes");
  expect(container.querySelector("nav")?.textContent).toContain("ingress");
  expect(container.querySelector("nav")?.textContent).not.toContain("pod");
  expect(container.querySelector('[aria-current="step"]')?.textContent).toContain("service");
  await act(async () => button("Mark as read").click());
  expect(setConceptStatus).toHaveBeenLastCalledWith("canvas-b", "domain", "service", "mastered", "owner");
});

it("keeps a pending progress write locked across a courses.write reload and uses the revised canvas", async () => {
  const write = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    if (name === "course_progress_set") await write.promise;
    return command(name, args);
  });
  await mount(); act(() => button("Mark as read").click());
  await act(async () => { await revise("canvas-b"); });

  expect(container.querySelector("header")?.textContent).toContain("Revised Kubernetes");
  expect(button("Saving…").disabled).toBe(true);
  act(() => button("Saving…").click());
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set")).toHaveLength(1);
  await act(async () => write.resolve(undefined));
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(setConceptStatus).not.toHaveBeenCalledWith("canvas-a", "domain", "pod", "mastered", "owner");
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

it("synchronizes a pending progress save to the revised canvas and keeps map failures retryable", async () => {
  const write = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_progress_set" ? write.promise : command(name, args));
  await mount(); act(() => button("Mark as read").click());
  currentCourse = stored("canvas-b", 2); await reopen();
  vi.mocked(setConceptStatus).mockRejectedValueOnce(new Error("current drawing failed"));
  await act(async () => { progress.set("pod", "mastered"); write.resolve(undefined); });

  expect(setConceptStatus).toHaveBeenCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("current drawing failed");
  expect(button("Read ✓").disabled).toBe(true);
  await act(async () => button("Retry map update").click());
  expect(setConceptStatus).toHaveBeenLastCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set")).toHaveLength(1);
});

it("waits for a revised course that is still loading when the progress save finishes", async () => {
  const write = deferred<unknown>(), read = deferred<unknown>();
  await mount();
  vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_progress_set" ? write.promise : command(name, args));
  act(() => button("Mark as read").click());
  currentCourse = stored("canvas-b", 2);
  vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_get" ? read.promise : name === "course_progress_set" ? write.promise : command(name, args));
  await reopen();
  await act(async () => { progress.set("pod", "mastered"); write.resolve(undefined); });
  expect(setConceptStatus).not.toHaveBeenCalled();
  await act(async () => read.resolve(currentCourse));
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(button("Read ✓").disabled).toBe(true);
});

it("reconciles the current canvas when the course changes during a queued map write", async () => {
  const mapWrite = deferred<void>();
  vi.mocked(setConceptStatus).mockReturnValueOnce(mapWrite.promise);
  await mount(); await act(async () => button("Mark as read").click());
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-a", "domain", "pod", "mastered", "owner");
  currentCourse = stored("canvas-b", 2); await reopen();
  await act(async () => mapWrite.reject(new Error("previous drawing failed")));
  expect(setConceptStatus).toHaveBeenLastCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(setConceptStatus).toHaveBeenCalledTimes(2);
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Read ✓").disabled).toBe(true);
});

it("does not synchronize a concept removed after the native progress commit", async () => {
  const reply = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    const result = await command(name, args);
    return name === "course_progress_set" ? reply.promise : result;
  });
  await mount(); await act(async () => button("Mark as read").click());
  expect(progress.get("pod")).toBe("mastered");
  currentCourse = stored("canvas-b", 2, ["service"]); progress.delete("pod"); await reopen();
  await act(async () => reply.resolve(undefined));
  expect(setConceptStatus).not.toHaveBeenCalled();
  expect(container.querySelector("nav")?.textContent).not.toContain("pod");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Mark as read").disabled).toBe(false);
});

it("finishes a committed progress save against persisted course data after its pane closes", async () => {
  const reply = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    const result = await command(name, args);
    return name === "course_progress_set" ? reply.promise : result;
  });
  await mount(); await act(async () => button("Mark as read").click());
  act(() => root.unmount()); root = createRoot(container);
  currentCourse = stored("canvas-b", 2);
  await act(async () => reply.resolve(undefined));
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(progress.get("pod")).toBe("mastered");
});

it("finishes the original owner's map save without attaching its error to another owner", async () => {
  const reply = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args: any) => {
    if (args.agentId === "other") {
      if (name === "course_get") return { ...stored("canvas-other", 1), agentId: "other" };
      if (name === "course_progress_get") return [];
    }
    const result = await command(name, args);
    return name === "course_progress_set" ? reply.promise : result;
  });
  await mount(); await act(async () => button("Mark as read").click());
  await mount("other");
  vi.mocked(setConceptStatus).mockRejectedValueOnce(new Error("original owner's drawing failed"));
  await act(async () => reply.resolve(undefined));
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-a", "domain", "pod", "mastered", "owner");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Mark as read").disabled).toBe(false);
});
