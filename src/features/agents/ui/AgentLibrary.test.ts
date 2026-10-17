// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { useAgentOverview } from "../../../app/hooks/useAgentOverview";
import { invalidateCanvases } from "../../canvas/canvas";
import { NOTES_CHANGED_EVENT, type Note } from "../../notes";
import { agentCanvasScope, type Agent } from "../model/agent";
import { AgentOverview } from "./AgentOverview";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("./DocumentBody", () => ({
  shownDocument: (value: unknown) => value,
  DocumentBody: ({ document }: { document: { body: string } }) => createElement("article", { "data-test-document": true }, document.body),
}));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", null, text) }));
vi.mock("../../learning/ui/CoursePane", () => ({
  PROGRESS_EVENT: "loci:course-progress",
  CoursePane: ({ title, onBack, onExpand }: { title: string; onBack: () => void; onExpand: (id: string) => void }) => createElement("section", { "data-test-course": true }, title,
    createElement("button", { onClick: onBack }, "Back to courses"),
    createElement("button", { onClick: () => onExpand("lesson-two") }, "Expand course")),
}));
vi.mock("../../notes/ui/NotesView", () => ({ NoteEditor: ({ note }: { note: Note }) => createElement("article", { "data-test-note": true }, note.title) }));

let container: HTMLDivElement;
let root: Root;
let control: ReturnType<typeof useAgentOverview>;
let documents: { id: string; title: string; subject?: string; sourceUrl?: string; updatedAt: number; createdAt: number }[];
let notes: Note[];
let documentRead: (agent: string) => Promise<typeof documents>;
const expandCourse = vi.fn();
const expandDocument = vi.fn();
const expandNote = vi.fn();
const openCanvas = vi.fn();
const agent: Agent = { id: "agent-a", sessionId: "chat-a", name: "Ada", avatar: "loci", color: "#123456", projects: [] };
const other: Agent = { ...agent, id: "agent-b", sessionId: "chat-b", name: "Bea" };

function Host({ owner = agent }: { owner?: Agent }) {
  control = useAgentOverview();
  return createElement(AgentOverview, {
    key: owner.id, agent: owner, state: control.stateFor(owner.id), recents: [],
    onTabChange: (tab) => control.selectTab(owner.id, tab), onOpen: (page) => control.show(owner.id, page),
    onBack: () => control.back(owner.id), onClose: () => control.close(owner.id), onResize: (width) => control.resize(owner.id, width),
    onExpandCourse: expandCourse, onExpandDocument: expandDocument, onExpandNote: expandNote, onOpenCanvas: openCanvas,
  });
}
async function render(owner = agent) { await act(async () => root.render(createElement(Host, { owner }))); }
async function click(selector: string) { await act(async () => container.querySelector<HTMLButtonElement>(selector)!.click()); }
const tab = (id: string) => click(`[data-tab="${id}"]`);

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear(); invalidateCanvases(); vi.clearAllMocks();
  documents = [ { id: "doc", title: "HTTP reference", subject: "Networking", sourceUrl: "https://example.org/http", updatedAt: 2, createdAt: 1 } ];
  notes = [];
  documentRead = async (id) => id === agent.id ? documents : [];
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { agent?: string; agentId?: string; id?: string; note?: Note };
    if (command === "course_list_all") return [agent, other].map((owner) => ({ id: "same-id", agentId: owner.id, title: `${owner.name}'s course`, engine: "reading", itemCount: 8, masteredCount: 2, updatedAt: 2 }));
    if (command === "agent_documents_list") return documentRead(input.agent!);
    if (command === "agent_documents_get") return { ...documents[0], body: "Original source text" };
    if (command === "agent_read") return { text: "[]", hash: "h" };
    if (command === "canvas_list") return [agent, other].map((owner) => ({ id: owner.id, title: `${owner.name}'s drawing`, cwd: agentCanvasScope(owner.id), dataJson: "{}", tags: [], createdAt: 1, updatedAt: 2 }));
    if (command === "notes_list") return notes.filter((note) => !input.agentId || note.agentId === input.agentId);
    if (command === "notes_get") return notes.find((note) => note.id === input.id) ?? null;
    if (command === "notes_upsert") {
      const saved = { ...input.note!, title: input.note!.title || "Untitled", slug: "note", slugPending: true, createdAt: 1, updatedAt: 2 };
      notes.push(saved); return saved;
    }
    throw new Error(`Unexpected command: ${command}`);
  });
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); localStorage.clear(); vi.unstubAllGlobals(); });

it("lists five resource tabs and only the current agent's courses and drawings", async () => {
  await render();
  expect(container.querySelectorAll('[role="tab"]')).toHaveLength(5);
  expect(container.textContent).toContain("Ada's course");
  expect(container.textContent).not.toContain("Bea's course");
  expect(container.textContent).toContain("8 lessons · 2 read");
  expect(container.querySelector('[data-tab="courses"]')?.getAttribute("aria-label")).toBe("Courses, 1");
  await tab("canvases");
  expect(container.textContent).toContain("Ada's drawing");
  expect(container.textContent).not.toContain("Bea's drawing");
  await click('[data-resource-kind="canvas"]');
  expect(openCanvas).toHaveBeenCalledWith(agent.id);
});

it("opens a document inside the overview, returns to its scroll position, and expands the stored content", async () => {
  await render(); await tab("documents");
  expect(container.textContent).toContain("Networking · example.org");
  const list = container.querySelector<HTMLElement>('[role="tabpanel"]')!;
  act(() => { list.scrollTop = 120; list.dispatchEvent(new Event("scroll")); });
  await click('[data-resource-kind="document"]');
  expect(container.querySelector("[data-test-document]")?.textContent).toBe("Original source text");
  expect(container.querySelector('[role="tablist"]')).toBeNull();
  await click('[aria-label="Back to documents"]');
  expect(container.querySelector('[role="tabpanel"]')?.scrollTop).toBe(120);
  expect(container.querySelector('[data-resource-id="doc"]')?.getAttribute("aria-current")).toBe("true");
  await click('[data-resource-kind="document"]'); await click('[aria-label="Expand document to pane"]');
  expect(expandDocument).toHaveBeenCalledWith(expect.objectContaining({ id: "doc", body: "Original source text" }));
  expect(container.querySelector('[role="tabpanel"]')).not.toBeNull();
});

it("expands a course with its owner, discussion target and selected lesson", async () => {
  await render(); await click('[data-resource-kind="course"]');
  expect(container.querySelector("[data-test-course]")?.textContent).toContain("Ada's course");
  await act(async () => [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Expand course")!.click());
  expect(expandCourse).toHaveBeenCalledWith(expect.objectContaining({ agentId: agent.id, sourceSessionId: "chat-a", courseId: "same-id", itemId: "lesson-two" }));
  expect(container.querySelector('[role="tabpanel"]')).not.toBeNull();
});

it("creates an owned note, opens it in place and refreshes its list count", async () => {
  await render(); await tab("notes"); await click('[aria-label="New note"]');
  expect(invoke).toHaveBeenCalledWith("notes_upsert", { note: expect.objectContaining({ agentId: "agent-a", sourceSessionId: "chat-a" }) });
  expect(container.querySelector("[data-test-note]")?.textContent).toBe("Untitled");
  await click('[aria-label="Back to notes"]');
  expect(container.querySelector('[data-tab="notes"]')?.getAttribute("aria-label")).toBe("Notes, 1");
  await render(other); await tab("notes");
  expect(container.querySelector('[data-resource-kind="note"]')).toBeNull();
});

it("refreshes notes without reloading unrelated resources", async () => {
  await render(); await tab("notes");
  vi.mocked(invoke).mockClear();
  await act(async () => window.dispatchEvent(new Event(NOTES_CHANGED_EVENT)));
  expect(invoke).toHaveBeenCalledWith("notes_list", { agentId: agent.id });
  expect(invoke).not.toHaveBeenCalledWith("course_list_all");
});

it("retains loaded documents on a failed refresh, with an explicit retry", async () => {
  await render(); await tab("documents");
  documentRead = async () => { throw new Error("Library unavailable"); };
  await act(async () => window.dispatchEvent(new Event("focus")));
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("Library unavailable");
  expect(container.querySelector('[data-resource-id="doc"]')).not.toBeNull();
  documentRead = async () => [];
  await click('[role="alert"] button');
  expect(container.querySelector('[role="alert"]')).toBeNull();
  expect(container.textContent).toContain("The material behind this agent's courses and reports");
});

it("ignores an old agent's delayed listing after switching owners", async () => {
  let finish!: (value: typeof documents) => void;
  documentRead = async (id) => id === agent.id ? new Promise((resolve) => { finish = resolve; }) : [];
  await render(); await tab("documents");
  expect(container.textContent).toContain("Loading library");
  await render(other); await tab("documents");
  await act(async () => finish(documents));
  expect(container.textContent).not.toContain("HTTP reference");
  expect(container.querySelector('[data-tab="documents"]')?.getAttribute("aria-label")).toBe("Library, 0");
});

it("persists each agent's tab and width without persisting reader contents", async () => {
  await render(); await tab("documents");
  await act(async () => control.resize(agent.id, 520));
  await click('[data-resource-kind="document"]');
  const stored = JSON.parse(localStorage.getItem("loci:agent-overviews.v1")!);
  expect(stored[agent.id]).toEqual({ open: true, tab: "documents", width: 520 });
  expect(JSON.stringify(stored)).not.toContain("Original source text");
  await render(other);
  expect(container.querySelector('[data-tab="courses"]')?.getAttribute("aria-selected")).toBe("true");
  await render();
  expect(container.querySelector("[data-test-document]")).not.toBeNull();
});

it("shows habit groups and the stored reports in a detail page", async () => {
  const original = vi.mocked(invoke).getMockImplementation()!;
  const now = Date.now();
  vi.mocked(invoke).mockImplementation(async (command, args) => command === "agent_read" ? { text: JSON.stringify([
    { id: "morning", name: "Reading reminder", instructions: "Review the next chapter.", schedule: { scheduleKind: "daily", time: "09:00", minute: 0, dayOfWeek: 1 }, enabled: true, createdAt: now - 1000, nextRunAt: now + 86400000,
      lastRunAt: now - 500, lastOutcome: "posted", runs: [{ at: now - 500, durationMs: 2300, outcome: "posted", report: "Read the controllers chapter today." }] },
  ]), hash: "habits" } : original(command, args));
  await render(); await tab("habits");
  expect(container.textContent).toContain("Done today");
  await click('[aria-label="Habit: Reading reminder"]');
  expect(container.textContent).not.toContain("Read the controllers chapter today.");
  await click("[data-habit-run] button");
  expect(container.textContent).toContain("Read the controllers chapter today.");
  expect(container.textContent).toContain("Runs while Loci is open.");
  await click('[aria-label="Back to habits"]');
  expect(container.querySelector('[data-tab="habits"]')?.getAttribute("aria-selected")).toBe("true");
});
