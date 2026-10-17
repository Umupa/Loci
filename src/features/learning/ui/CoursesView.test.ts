// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { COURSES_CHANGED_EVENT, type CourseSummary } from "../model/course";
import { CoursesView } from "./CoursesView";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../../app/shell/TitleBar", () => ({ OverlayNav: () => null }));
vi.mock("../../../app/shell/WindowControls", () => ({ WindowControls: () => null }));
vi.mock("../../agents/ui/AgentAvatar", () => ({ AgentAvatar: () => null }));
vi.mock("./CoursePane", () => ({ CoursePane: () => null, PROGRESS_EVENT: "loci:course-progress" }));
vi.mock("../../agents/model/agent", () => ({
  agentsSnapshot: () => "roster", subscribeAgents: () => () => undefined,
  listAgents: () => [{ id: "owner", name: "Tutor" }], agentLook: (agent: { name: string }) => ({ name: agent.name }),
}));

const deferred = <T,>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((yes) => { resolve = yes; });
  return { promise, resolve };
};
const summary = (title: string): CourseSummary => ({ id: "domain", agentId: "owner", engine: "reading", title, updatedAt: 42, itemCount: 2, masteredCount: 0 });
let container: HTMLDivElement, root: Root;
beforeEach(() => {
  vi.clearAllMocks(); vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("retains the latest course list when an earlier refresh returns after a course revision", async () => {
  const earlier = deferred<CourseSummary[]>(), latest = deferred<CourseSummary[]>();
  vi.mocked(invoke).mockReturnValueOnce(earlier.promise).mockReturnValueOnce(latest.promise);
  await act(async () => root.render(createElement(CoursesView, { onClose: vi.fn() })));
  act(() => window.dispatchEvent(new CustomEvent(COURSES_CHANGED_EVENT, { detail: { agentId: "owner", courseId: "domain" } })));
  await act(async () => latest.resolve([summary("Current course")]));
  expect(container.textContent).toContain("Current course");
  await act(async () => earlier.resolve([summary("Previous course")]));
  expect(container.textContent).toContain("Current course");
  expect(container.textContent).not.toContain("Previous course");
  expect(vi.mocked(invoke).mock.calls.map(([name]) => name)).toEqual(["course_list_all", "course_list_all"]);
});
