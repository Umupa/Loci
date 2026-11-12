// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Agent } from "../../agents/model/agent";
import type { CourseSummary } from "../../learning/model/course";
import { ADD_TO_CHAT_EVENT } from "../../sessions/model/quoteDraft";
import type { Block } from "../../sessions/model/session";
import type { MentorPage } from "../model/mentorPage";
import { KnowledgeTree } from "./KnowledgeTree";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

let root: Root;
let host: HTMLDivElement;
let opened: MentorPage[];
let drafts: string[];
const agent: Agent = { id: "a", name: "Ada", avatar: "loci", color: "#123456", sessionId: "chat-a" };
const summary: CourseSummary = { id: "k8s", agentId: "a", title: "Kubernetes", engine: "reading", itemCount: 4, masteredCount: 1, updatedAt: 1, createdAt: 1 };
const data = JSON.stringify({ engine: "reading", chapters: [
  { id: "loop", title: "Control loop", lessons: [{ id: "a", title: "A" }, { id: "b", title: "B" }] },
  { title: "Pods", after: ["loop"], lessons: [{ id: "c", title: "C" }, { id: "d", title: "D" }] },
] });
const draft = (event: Event) => drafts.push((event as CustomEvent<{ text: string }>).detail.text);

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.setItem("loci:agent-roster", JSON.stringify([agent]));
  opened = []; drafts = [];
  window.addEventListener(ADD_TO_CHAT_EVENT, draft);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount()); host.remove();
  window.removeEventListener(ADD_TO_CHAT_EVENT, draft);
  localStorage.clear(); vi.unstubAllGlobals(); vi.clearAllMocks();
});

function serve(bodies: string[], read: string[]) {
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { id?: string; agentId?: string };
    if (command === "course_get") return { id: input.id, agentId: input.agentId, title: "Kubernetes", updatedAt: 1, engine: "reading", dataJson: data, bodies };
    if (command === "course_progress_get") return read.map((itemId) => ({ itemId, status: "mastered" }));
    throw new Error(`Unexpected command: ${command}`);
  });
}

async function render(turn?: Block[]) {
  await act(async () => root.render(createElement(KnowledgeTree, { agent, courses: [summary], onOpen: (page) => opened.push(page), turn })));
}
const lesson = (id: string) => host.querySelector<SVGGElement>(`[data-tree-lesson="${id}"]`)!;

it("draws each lesson's state, rings the one to go on with, and opens a lesson or asks for a planned chapter", async () => {
  serve(["a", "b"], ["a"]);
  await render();
  await vi.waitFor(() => expect(lesson("d")).not.toBeNull());
  expect(["a", "b", "c", "d"].map((id) => lesson(id).dataset.state)).toEqual(["read", "unread", "planned", "planned"]);
  expect(host.querySelector(".knowledge-tree__count")?.textContent).toBe("1/ 4");
  expect(lesson("b").dataset.current).toBe("true");
  expect(host.querySelectorAll("[data-tree-chapter]")).toHaveLength(2);
  expect(host.querySelector('[data-tree-chapter="1"]')?.hasAttribute("data-planned")).toBe(true);
  expect(host.querySelectorAll('[data-tree-lesson="b"] .knowledge-tree__vein')).toHaveLength(4);
  await act(async () => lesson("b").dispatchEvent(new MouseEvent("click", { bubbles: true })));
  expect(opened).toEqual([{ kind: "course", course: { courseId: "k8s", agentId: "a", title: "Kubernetes", itemId: "b" } }]);
  await act(async () => lesson("c").dispatchEvent(new MouseEvent("click", { bubbles: true })));
  expect(drafts).toEqual(['Write the chapter "Pods" of the course "Kubernetes" (k8s).']);
});

it("shows what the mentor is doing while nothing is written yet", async () => {
  serve([], []);
  const turn = [
    { id: "u", role: "user", text: "Teach me Kubernetes" },
    { id: "t1", role: "tool", text: "", tool: { callId: "1", kind: "execute", title: "loci app sources write", status: "completed", rawInput: { command: 'loci app sources write --id k8s-pods --title "Pod lifecycle" --path /w/pods.md --sourceUrl https://kubernetes.io' } } },
  ] as unknown as Block[];
  await render(turn);
  await vi.waitFor(() => expect(host.querySelector("[data-first-turn]")).not.toBeNull());
  expect(host.querySelector("[data-knowledge-tree]")).toBeNull();
  expect(host.textContent).not.toBe("");
  // Without a running turn, the tree shows, planned as it is.
  await render(undefined);
  await vi.waitFor(() => expect(host.querySelector("[data-knowledge-tree]")).not.toBeNull());
});
