// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { setConceptStatus } from "../../canvas/concepts";
import { openCourse, type CourseData, type LearningStatus } from "../model/course";
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
const data = (canvasId: string, conceptIds = ["pod", "service"]): CourseData => ({
  engine: "domain-navigation", canvasId, learningPath: conceptIds,
  concepts: conceptIds.map((id) => ({ id, title: id, content: `Learn ${id}`, prerequisites: [], leadsTo: [] })),
});
const stored = (canvasId: string, updatedAt: number, conceptIds?: string[]) => ({
  id: "domain", agentId: "owner", title: "Kubernetes", updatedAt,
  engine: "domain-navigation", dataJson: JSON.stringify(data(canvasId, conceptIds)),
});
let currentCourse: ReturnType<typeof stored>;
let progress: Map<string, LearningStatus>;
let container: HTMLDivElement, root: Root;
const command = async (name: string, args: any): Promise<any> => {
  if (name === "course_get") return currentCourse;
  if (name === "course_progress_get") return [...progress].map(([itemId, status]) => ({ itemId, status }));
  if (name === "course_progress_set") { progress.set(args.itemId, args.status); return; }
  throw new Error(`Unexpected invoke: ${name}`);
};
const button = (text: string) => [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent === text)!;
const reopen = async () => {
  await act(async () => openCourse({ courseId: "domain", agentId: "owner", title: "Kubernetes" }));
};
const mount = async (agentId = "owner") => {
  await act(async () => root.render(createElement(CoursePane, {
    courseId: "domain", agentId, focused: true, onFocus: vi.fn(), onClose: vi.fn(),
  })));
};

beforeEach(() => {
  vi.clearAllMocks();
  currentCourse = stored("canvas-a", 1); progress = new Map();
  vi.mocked(invoke).mockImplementation(command);
  vi.mocked(setConceptStatus).mockResolvedValue(undefined);
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("synchronizes a pending progress save to the revised canvas and keeps map failures retryable", async () => {
  const write = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_progress_set" ? write.promise : command(name, args));
  await mount(); act(() => button("Mark as mastered").click());
  currentCourse = stored("canvas-b", 2); await reopen();
  vi.mocked(setConceptStatus).mockRejectedValueOnce(new Error("current drawing failed"));
  await act(async () => { progress.set("pod", "mastered"); write.resolve(undefined); });

  expect(setConceptStatus).toHaveBeenCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("current drawing failed");
  expect(button("Mastered ✓").disabled).toBe(true);
  await act(async () => button("Retry map update").click());
  expect(setConceptStatus).toHaveBeenLastCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set")).toHaveLength(1);
});

it("waits for a revised course that is still loading when the progress save finishes", async () => {
  const write = deferred<unknown>(), read = deferred<unknown>();
  await mount();
  vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_progress_set" ? write.promise : command(name, args));
  act(() => button("Mark as mastered").click());
  currentCourse = stored("canvas-b", 2);
  vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_get" ? read.promise : name === "course_progress_set" ? write.promise : command(name, args));
  await reopen();
  await act(async () => { progress.set("pod", "mastered"); write.resolve(undefined); });
  expect(setConceptStatus).not.toHaveBeenCalled();
  await act(async () => read.resolve(currentCourse));
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(button("Mastered ✓").disabled).toBe(true);
});

it("reconciles the current canvas when the course changes during a queued map write", async () => {
  const mapWrite = deferred<void>();
  vi.mocked(setConceptStatus).mockReturnValueOnce(mapWrite.promise);
  await mount(); await act(async () => button("Mark as mastered").click());
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-a", "domain", "pod", "mastered", "owner");
  currentCourse = stored("canvas-b", 2); await reopen();
  await act(async () => mapWrite.reject(new Error("previous drawing failed")));
  expect(setConceptStatus).toHaveBeenLastCalledWith("canvas-b", "domain", "pod", "mastered", "owner");
  expect(setConceptStatus).toHaveBeenCalledTimes(2);
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Mastered ✓").disabled).toBe(true);
});

it("does not synchronize a concept removed after the native progress commit", async () => {
  const reply = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    const result = await command(name, args);
    return name === "course_progress_set" ? reply.promise : result;
  });
  await mount(); await act(async () => button("Mark as mastered").click());
  expect(progress.get("pod")).toBe("mastered");
  currentCourse = stored("canvas-b", 2, ["service"]); progress.delete("pod"); await reopen();
  await act(async () => reply.resolve(undefined));
  expect(setConceptStatus).not.toHaveBeenCalled();
  expect(container.querySelector("nav")?.textContent).not.toContain("pod");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Mark as mastered").disabled).toBe(false);
});

it("finishes a committed progress save against persisted course data after its pane closes", async () => {
  const reply = deferred<unknown>();
  vi.mocked(invoke).mockImplementation(async (name, args) => {
    const result = await command(name, args);
    return name === "course_progress_set" ? reply.promise : result;
  });
  await mount(); await act(async () => button("Mark as mastered").click());
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
  await mount(); await act(async () => button("Mark as mastered").click());
  await mount("other");
  vi.mocked(setConceptStatus).mockRejectedValueOnce(new Error("original owner's drawing failed"));
  await act(async () => reply.resolve(undefined));
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-a", "domain", "pod", "mastered", "owner");
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(button("Mark as mastered").disabled).toBe(false);
});
