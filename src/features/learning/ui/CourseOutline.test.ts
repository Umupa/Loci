// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { LearningStatus } from "../model/course";
import { LiveCourseOutline, PROGRESS_EVENT } from "./CourseOutline";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../canvas/concepts", () => ({ setConceptStatus: vi.fn() }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", null, text) }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"] }) }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));

const course = {
  id: "domain", agentId: "owner", title: "Kubernetes", updatedAt: 1, engine: "reading",
  dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Workloads", lessons: [{ id: "pod", title: "pod", document: "doc-pod" }, { id: "service", title: "service", document: "doc-service" }] }] }),
};
let progress: Map<string, LearningStatus>;
let container: HTMLDivElement, root: Root;

beforeEach(() => {
  progress = new Map([["pod", "mastered"]]);
  vi.mocked(invoke).mockImplementation(async (name: string, args: any): Promise<any> => {
    if (name === "course_get") return course;
    if (name === "course_progress_get") return [...progress].map(([itemId, status]) => ({ itemId, status }));
    if (name === "course_progress_set") { progress.set(args.itemId, args.status); return; }
    if (name === "agent_documents_get") return { id: args.id, title: args.id, body: `Read ${args.id}`, createdAt: 1, updatedAt: 1 };
    throw new Error(`Unexpected invoke: ${name}`);
  });
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); vi.clearAllMocks(); });

const rows = () => [...container.querySelectorAll<HTMLButtonElement>('nav[aria-label="Course navigation"] button')];

it("shows the saved read marks and follows progress made elsewhere", async () => {
  const onSelect = vi.fn();
  await act(async () => root.render(createElement(LiveCourseOutline, { courseId: "domain", agentId: "owner", activeId: "service", onSelect })));
  expect(rows().map((row) => row.getAttribute("aria-label"))).toEqual(["pod, Read", "service, Not started"]);
  expect(rows()[1].getAttribute("aria-current")).toBe("step");
  await act(async () => { window.dispatchEvent(new CustomEvent(PROGRESS_EVENT, { detail: { courseId: "domain", agentId: "owner", itemId: "service", status: "learning" } })); });
  expect(rows()[1].getAttribute("aria-label")).toBe("service, Reading");
  act(() => rows()[0].click());
  expect(onSelect).toHaveBeenCalledWith("pod");
});

it("as the reader, has no sidebar and no Back, and opening a lesson from outside starts reading it", async () => {
  const render = (openRequest: number, itemId?: string) => root.render(createElement(CoursePane, {
    courseId: "domain", agentId: "owner", focused: true, onFocus: vi.fn(), onClose: vi.fn(), reader: true, itemId, openRequest,
  }));
  await act(async () => render(0));
  expect(container.querySelector(".course-pane__body > nav")).toBeNull();
  expect(container.querySelector('[aria-label="Back to courses"]')).toBeNull();
  expect(container.querySelector('[aria-label="Close"]')).not.toBeNull();
  progress.delete("service");
  await act(async () => render(1, "service"));
  expect(invoke).toHaveBeenCalledWith("course_progress_set", expect.objectContaining({ itemId: "service", status: "learning" }));
});
