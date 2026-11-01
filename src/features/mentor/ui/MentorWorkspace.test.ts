// @vitest-environment happy-dom
import { act, createElement, useContext } from "react";
import { AgentHeaderExtra } from "../../agents/ui/AgentView";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { MENTOR_VIEW_KEY, useMentorView } from "../../../app/hooks/useMentorView";
import { invalidateCanvases } from "../../canvas/canvas";
import { getFileDraft, setFileDraft } from "../../files/model/fileDrafts";
import type { Note } from "../../notes";
import { agentCanvasScope, type Agent } from "../../agents/model/agent";
import { MentorWorkspace } from "./MentorWorkspace";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/ui/DocumentBody", () => ({
  shownDocument: (value: unknown) => value,
  DocumentBody: ({ document }: { document: { body: string } }) => createElement("article", { "data-test-document": true }, document.body),
}));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", null, text) }));
vi.mock("../../learning/ui/CoursePane", () => ({
  PROGRESS_EVENT: "loci:course-progress",
  CoursePane: ({ title, itemId, openRequest, onLessonChange }: { title: string; itemId?: string; openRequest?: number; onLessonChange: (lesson: { id: string; title: string } | null) => void }) =>
    createElement("section", { "data-test-course": true, "data-item": itemId ?? "", "data-request": openRequest }, title,
      createElement("button", { onClick: () => onLessonChange({ id: "service", title: "Service" }) }, "Read service")),
}));
vi.mock("../../agents/ui/AgentFilesSection", () => ({
  AgentFilesSection: ({ agentId, onOpenFile, onFileMoved, onFileDeleted }: {
    agentId: string; onOpenFile: (path: string) => void;
    onFileMoved?: (from: string, to: string) => void; onFileDeleted?: (path: string) => void;
  }) => {
    const path = `/home/user/Loci/${agentId}/repos/notes.md`;
    const next = `/home/user/Loci/${agentId}/repos/notes-v2.md`;
    return createElement("div", null,
      createElement("button", { "data-test-files": agentId, onClick: () => onOpenFile(path) }, "notes.md"),
      createElement("button", { "data-test-file-move": agentId, onClick: () => onFileMoved?.(path, next) }, "rename notes.md"),
      createElement("button", { "data-test-file-delete": agentId, onClick: () => onFileDeleted?.(next) }, "trash notes.md"));
  },
}));
vi.mock("../../files/ui/FilePane", () => ({ FilePane: ({ path }: { path: string }) => createElement("section", { "data-test-file": path }, path) }));
vi.mock("../../canvas/ui/CanvasPane", () => ({ CanvasPane: ({ canvas }: { canvas: { title: string } }) => createElement("section", { "data-test-canvas": true }, canvas.title) }));
vi.mock("../../notes/ui/NoteEditor", () => ({ NoteEditor: ({ note }: { note: Note }) => createElement("article", { "data-test-note": true }, note.title) }));

let container: HTMLDivElement;
let root: Root;
let control: ReturnType<typeof useMentorView>;
let documents: { id: string; title: string; subject?: string; sourceUrl?: string; updatedAt: number; createdAt: number }[];
let notes: Note[];
let courseGone: boolean;
let drafts: string[];
let documentRead: (agent: string) => Promise<typeof documents>;

/** Stands in for the conversation, showing what the workspace adds to its header. */
function TestChat({ id }: { id: string }) {
  return createElement("div", { "data-test-chat": id }, useContext(AgentHeaderExtra));
}

const drawings = [{ id: "drawing-a", title: "Ada's sketch", cwd: "", dataJson: "{}", tags: [], createdAt: 1, updatedAt: 2 }];
const agent: Agent = { id: "agent-a", sessionId: "chat-a", name: "Ada", avatar: "loci", color: "#123456", projects: [] };
const other: Agent = { ...agent, id: "agent-b", sessionId: "chat-b", name: "Bea" };
const courseData = JSON.stringify({ engine: "reading", chapters: [{ title: "Workloads", lessons: [{ id: "pod", title: "Pod", document: "doc" }, { id: "service", title: "Service", document: "doc" }] }] });

function Host({ owner = agent }: { owner?: Agent }) {
  control = useMentorView();
  return createElement(MentorWorkspace, {
    key: owner.id, agent: owner, state: control.stateFor(owner.id), chat: createElement(TestChat, { id: owner.id }), canvases: drawings,
    onOpen: (page) => control.show(owner.id, page), onClose: () => control.close(owner.id),
    onLessonChange: (lesson) => control.setLesson(owner.id, lesson), onRestoredChecked: (page, exists) => control.confirmRestored(owner.id, page, exists),
    onToggleLibrary: () => control.toggleLibrary(owner.id), onLibraryChange: (change) => control.openLibrary(owner.id, change), onDraft: (text) => drafts.push(text), onToggleChat: () => control.toggleChat(owner.id),
    onResizeLibrary: (width) => control.resizeLibrary(owner.id, width), onResizeChat: (width) => control.resizeChat(owner.id, width),
    onCanvasAddToChat: () => {}, onCanvasTitleChange: () => {}, onOpenFile: () => {},
    renderSession: (id) => createElement("section", { "data-test-session": id }), sessionTitle: () => "Delegated work",
  });
}
async function render(owner = agent) { await act(async () => root.render(createElement(Host, { owner }))); }
async function click(selector: string) { await act(async () => container.querySelector<HTMLButtonElement>(selector)!.click()); }
const tab = (segment: string) => click(`[role="tab"][data-segment="${segment}"]`);
const reader = () => container.querySelector<HTMLElement>("[data-mentor-reader]")!;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear(); invalidateCanvases(); vi.clearAllMocks();
  documents = [{ id: "doc", title: "HTTP reference", subject: "Networking", sourceUrl: "https://example.org/http", updatedAt: 2, createdAt: 1 }];
  notes = []; courseGone = false; drafts = [];
  documentRead = async (id) => id === agent.id ? documents : [];
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { agent?: string; agentId?: string; id?: string; note?: Note };
    if (command === "course_list_all") return [agent, other].map((owner) => ({ id: "kube", agentId: owner.id, title: `${owner.name}'s course`, engine: "reading", itemCount: 2, masteredCount: 1, updatedAt: 2 }));
    if (command === "course_get") return courseGone ? null : { id: input.id, agentId: input.agentId, title: "Ada's course", updatedAt: 2, engine: "reading", dataJson: courseData };
    if (command === "course_progress_get") return [{ itemId: "pod", status: "mastered" }];
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

it("lays out library, reader and conversation, listing only this mentor's things without habits", async () => {
  await render();
  const body = container.querySelector(".mentor-body")!;
  expect([...body.children].map((child) => child.className)).toEqual(["mentor-library-column", "mentor-reader", "mentor-chat-column"]);
  expect(container.querySelector('[data-test-chat="agent-a"]')).not.toBeNull();
  // The chosen segment is a labelled pill; the others are icons named for assistive tech.
  expect([...container.querySelectorAll('[role="tab"]')].map((entry) => entry.getAttribute("aria-label"))).toEqual(["Courses", "Sources, 1", "Notes, 1", "Files"]);
  expect([...container.querySelectorAll('[role="tab"]')].map((entry) => entry.textContent)).toEqual(["Courses", "", "", ""]);
  // No title bar of its own: the library's header is the window's top row.
  expect(container.querySelector(".mentor-titlebar")).toBeNull();
  expect(container.querySelector(".mentor-library-header [aria-label='Hide library']")).not.toBeNull();
  expect(container.querySelector('[role="tab"][aria-selected="true"]')?.getAttribute("data-segment")).toBe("courses");
  expect(container.textContent).toContain("Ada's course");
  expect(container.textContent).not.toContain("Bea's course");
  expect(container.textContent).toContain("1/2");
  await tab("notes");
  expect(container.textContent).toContain("Ada's drawing");
  expect(container.textContent).not.toContain("Bea's drawing");
  expect(container.textContent).not.toContain("Habits");
  expect(reader().dataset.mentorReader).toBe("empty");
  expect(reader().querySelector("[data-resource-header]")).not.toBeNull();
});

it("opens whatever is chosen in place of what was read, and closes back to an empty reader", async () => {
  await render();
  await tab("sources");
  await click('[data-resource-kind="document"]');
  await vi.waitFor(() => expect(container.querySelector("[data-test-document]")?.textContent).toBe("Original source text"));
  expect(reader().dataset.mentorReader).toBe("document");
  expect(container.querySelector('[data-resource-id="doc"]')?.getAttribute("aria-current")).toBe("true");
  expect(container.querySelector('[aria-label="Back to documents"]')).toBeNull();
  await act(async () => control.show(agent.id, { kind: "canvas", id: "drawing-a" }));
  expect(await vi.waitFor(() => container.querySelector("[data-test-canvas]")!)).toBeTruthy();
  expect(container.querySelector("[data-test-document]")).toBeNull();
  await act(async () => control.show(agent.id, { kind: "canvas", id: "gone" }));
  expect(reader().textContent).toContain("This drawing is no longer available.");
  await click('[data-mentor-reader] button');
  expect(reader().dataset.mentorReader).toBe("empty");
});

it("shows the course once, with its progress, and opens lessons from its outline", async () => {
  await render();
  const panel = () => container.querySelector<HTMLElement>('[data-library-section="courses"]')!;
  await vi.waitFor(() => expect(panel().querySelector('nav[aria-label="Course navigation"]')).not.toBeNull());
  expect(panel().querySelector(".library-switcher")?.textContent).toBe("Ada's course");
  expect(panel().textContent).toContain("1/2");
  expect(panel().querySelector("[data-library-continue]")).toBeNull();
  expect(panel().textContent?.match(/Ada's course/g)).toHaveLength(1);
  const lessons = () => [...panel().querySelectorAll<HTMLButtonElement>("[data-library-lesson]")];
  expect(lessons().map((lesson) => lesson.getAttribute("aria-label"))).toEqual(["Pod, Read", "Service, Not started"]);
  expect(lessons()[0].className).toContain("library-lesson--mastered");

  await act(async () => lessons()[1].click());
  const course = () => container.querySelector<HTMLElement>("[data-test-course]")!;
  expect(course().dataset.item).toBe("service");
  expect(lessons()[1].getAttribute("aria-current")).toBe("step");
  const before = Number(course().dataset.request);
  await act(async () => lessons()[0].click());
  expect(course().dataset.item).toBe("pod");
  expect(Number(course().dataset.request)).toBe(before + 1);
  await click("[data-test-course] button");
  expect(control.stateFor(agent.id).lesson?.title).toBe("Service");
  expect(lessons()[1].getAttribute("aria-current")).toBe("step");
});

it("switches course from the menu, landing in it, and asks the mentor for a new one without sending", async () => {
  const kubeData = courseData;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { agent?: string; agentId?: string; id?: string; courseId?: string };
    if (command === "course_list_all") return [
      { id: "kube", agentId: agent.id, title: "Kubernetes", engine: "reading", itemCount: 2, masteredCount: 1, updatedAt: 2 },
      { id: "sds", agentId: agent.id, title: "SDS", engine: "reading", itemCount: 2, masteredCount: 0, updatedAt: 1 },
    ];
    if (command === "course_get") return { id: input.id, agentId: input.agentId, title: input.id === "sds" ? "SDS" : "Kubernetes", updatedAt: 2, engine: "reading", dataJson: kubeData };
    if (command === "course_progress_get") return input.courseId === "sds" ? [{ itemId: "pod", status: "learning" }] : [{ itemId: "pod", status: "mastered" }];
    if (command === "agent_documents_list" || command === "notes_list") return [];
    if (command === "canvas_list") return [];
    throw new Error(`Unexpected command: ${command}`);
  });
  await render();
  await vi.waitFor(() => expect(container.querySelector(".library-switcher")?.textContent).toBe("Kubernetes"));
  await click(".library-switcher");
  const items = () => [...document.querySelectorAll<HTMLElement>('[role="menu"] [role^="menuitem"]')];
  expect(items().map((item) => item.textContent)).toEqual([expect.stringContaining("Kubernetes"), expect.stringContaining("SDS"), "Ask Ada for a new course"]);
  expect(items()[0].getAttribute("aria-checked")).toBe("true");
  await act(async () => items()[1].click());
  // Picking a course opens it at the lesson to continue with: the one begun.
  await vi.waitFor(() => expect(container.querySelector<HTMLElement>("[data-test-course]")?.dataset.item).toBe("pod"));
  expect(control.stateFor(agent.id).course).toBe("sds");
  await vi.waitFor(() => expect(container.querySelector(".library-switcher")?.textContent).toBe("SDS"));
  await vi.waitFor(() => expect(container.querySelector('[data-library-lesson="pod"] .library-mark--learning')).not.toBeNull());
  await click(".library-switcher");
  await act(async () => items().at(-1)!.click());
  expect(drafts).toEqual(["I'd like a new course on "]);
});

it("gives focus back to the course switcher when its menu closes", async () => {
  await render();
  await vi.waitFor(() => expect(container.querySelector(".library-switcher")).not.toBeNull());
  const switcher = container.querySelector<HTMLButtonElement>(".library-switcher")!;
  await act(async () => { switcher.focus(); switcher.click(); });
  expect(document.activeElement).not.toBe(switcher);
  await act(async () => { document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); });
  expect(document.activeElement).toBe(switcher);
});

it("filters the segment being shown", async () => {
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "course_list_all" || command === "notes_list" || command === "canvas_list") return [];
    if (command === "agent_documents_list") return [...documents, { ...documents[0], id: "dns", title: "DNS notes", sourceUrl: undefined }];
    throw new Error(`Unexpected command: ${command}`);
  });
  await render();
  await tab("sources");
  const filter = () => container.querySelector<HTMLInputElement>('input[aria-label="Filter sources"]')!;
  await vi.waitFor(() => expect(container.querySelectorAll("[data-resource-kind]")).toHaveLength(2));
  // First-hand sources and the mentor's own guides are listed apart.
  expect([...container.querySelectorAll("[data-library-group]")].map((group) => group.textContent)).toEqual(["Sources", "Mentor's guides"]);
  expect(container.querySelector('[data-resource-id="dns"]')?.textContent).toContain("Mentor's guide");
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(filter(), "dns");
    filter().dispatchEvent(new Event("input", { bubbles: true }));
  });
  expect(filter().value).toBe("dns");
  expect([...container.querySelectorAll("[data-resource-kind]")].map((row) => row.getAttribute("data-resource-id"))).toEqual(["dns"]);
});

it("offers to ask for a course when the mentor has none", async () => {
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "course_list_all" || command === "agent_documents_list" || command === "notes_list" || command === "canvas_list") return [];
    throw new Error(`Unexpected command: ${command}`);
  });
  await render();
  await vi.waitFor(() => expect(container.textContent).toContain("No course yet."));
  expect(container.querySelector('[role="tab"][aria-selected="true"]')?.getAttribute("data-segment")).toBe("courses");
  await click(".library-ask");
  expect(drafts).toEqual(["I'd like a new course on "]);
});

it("reports a failed list in its own segment, with a retry", async () => {
  let noteLoads = 0;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { agentId?: string; id?: string };
    if (command === "course_list_all") return [{ id: "kube", agentId: agent.id, title: "Ada's course", engine: "reading", itemCount: 2, masteredCount: 1, updatedAt: 2 }];
    if (command === "course_get") return { id: input.id, agentId: input.agentId, title: "Ada's course", updatedAt: 2, engine: "reading", dataJson: courseData };
    if (command === "course_progress_get") return [];
    if (command === "agent_documents_list") return documents;
    if (command === "notes_list") { noteLoads += 1; throw new Error("disk full"); }
    if (command === "canvas_list") return [];
    if (command === "agent_read") return { text: "[]", hash: "h" };
    throw new Error(`Unexpected command: ${command}`);
  });
  await render();
  await vi.waitFor(() => expect(container.textContent).toContain("Ada's course"));
  expect(container.textContent).not.toContain("Couldn't load notes");
  await tab("sources");
  expect(container.querySelector('[data-resource-id="doc"]')).not.toBeNull();
  expect(container.textContent).not.toContain("Couldn't load notes");
  await tab("notes");
  await vi.waitFor(() => expect(container.textContent).toContain("Couldn't load notes."));
  const retry = [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Retry")!;
  const before = noteLoads;
  await act(async () => retry.click());
  expect(noteLoads).toBeGreaterThan(before);
});

it("creates an owned note and opens it in the reader", async () => {
  await render();
  await tab("notes");
  await click('[aria-label="New note"]');
  expect(invoke).toHaveBeenCalledWith("notes_upsert", { note: expect.objectContaining({ agentId: "agent-a", sourceSessionId: "chat-a" }) });
  await vi.waitFor(() => expect(container.querySelector("[data-test-note]")?.textContent).toBe("Untitled"));
  await render(other);
  expect(container.querySelector('[data-resource-kind="note"]')).toBeNull();
});

it("comes back to the lesson a mentor was showing, remembering identifiers only", async () => {
  await render();
  await vi.waitFor(() => expect(container.querySelector('[data-library-lesson="pod"]')).not.toBeNull());
  await click('[data-library-lesson="pod"]');
  await click("[data-test-course] button");
  await act(async () => control.resizeChat(agent.id, 520));
  const stored = JSON.parse(localStorage.getItem(MENTOR_VIEW_KEY)!);
  expect(stored[agent.id]).toEqual({ library: true, libraryWidth: 260, chat: true, width: 520, course: "kube",
    page: { kind: "course", course: { courseId: "kube", agentId: "agent-a", title: "Ada's course", itemId: "service" } } });
  await render(other);
  expect(reader().dataset.mentorReader).toBe("empty");
  // A new window reads the same preferences back.
  act(() => root.unmount()); root = createRoot(container);
  await render();
  await vi.waitFor(() => expect(container.querySelector<HTMLElement>("[data-test-course]")?.dataset.item).toBe("service"));
  expect(control.stateFor(agent.id).restored).toBe(false);
});

it("drops a remembered page that no longer exists", async () => {
  localStorage.setItem(MENTOR_VIEW_KEY, JSON.stringify({ [agent.id]: { open: true, tab: "documents", width: 480, chat: false,
    page: { kind: "course", course: { courseId: "kube", agentId: "agent-a", title: "Old", itemId: "pod" } } } }));
  courseGone = true;
  await render();
  await vi.waitFor(() => expect(reader().dataset.mentorReader).toBe("empty"));
  // The earlier overview's conversation width and visibility carry over.
  expect(control.stateFor(agent.id)).toMatchObject({ chat: false, chatWidth: 480, library: true });
  expect(container.querySelector<HTMLElement>(".mentor-chat-column")!.hidden).toBe(true);
});

it("shows one segment at a time, remembered per mentor, and ignores an old mentor's late listing", async () => {
  let finish!: (value: typeof documents) => void;
  documentRead = async (id) => id === agent.id ? new Promise((resolve) => { finish = resolve; }) : [];
  await render();
  await tab("sources");
  expect(container.querySelector("[data-mentor-library]")?.getAttribute("data-library-segment")).toBe("sources");
  expect(container.querySelector('[data-resource-kind="course"]')).toBeNull();
  await render(other);
  expect(container.querySelector("[data-mentor-library]")?.getAttribute("data-library-segment")).toBe("courses");
  await tab("sources");
  await act(async () => finish(documents));
  expect(container.textContent).not.toContain("HTTP reference");
  expect(container.textContent).toContain("First-hand material Bea saves");
  await render();
  expect(container.querySelector("[data-mentor-library]")?.getAttribute("data-library-segment")).toBe("sources");
  await click('[aria-label="Hide library"]');
  expect(container.querySelector<HTMLElement>(".mentor-library-column")!.hidden).toBe(true);
  // The open conversation's ✕ sits in its own header; the reader's header takes the library's toggle.
  expect(container.querySelector('[aria-label="Hide conversation"]')!.querySelectorAll("svg")).toHaveLength(1);
  expect(reader().querySelector("[data-resource-header] [aria-label='Show library']")).not.toBeNull();
  await click('[aria-label="Hide conversation"]');
  expect(container.querySelector<HTMLElement>(".mentor-chat-column")!.hidden).toBe(true);
  expect(container.querySelector('[aria-label="Chat with Ada"]')).not.toBeNull();
});

it("starts a newly chosen segment at its top", async () => {
  await render();
  const panel = () => container.querySelector<HTMLElement>(".mentor-library-panel")!;
  panel().scrollTop = 180;
  await tab("files");
  expect(panel().scrollTop).toBe(0);
});

it("closes the reader on Escape from anywhere in the workspace, except from a text field", async () => {
  await render();
  await tab("sources");
  await vi.waitFor(() => expect(container.querySelector('[data-resource-kind="document"]')).not.toBeNull());
  await click('[data-resource-kind="document"]');
  expect(reader().dataset.mentorReader).toBe("document");
  const filter = () => container.querySelector<HTMLInputElement>('input[aria-label="Filter sources"]')!;
  await act(async () => filter().dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(reader().dataset.mentorReader).toBe("document");
  const tabButton = container.querySelector<HTMLElement>('[role="tab"][data-segment="sources"]')!;
  await act(async () => tabButton.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(reader().dataset.mentorReader).toBe("empty");
});

it("filters only the segment it was typed in, and moves through a list with the arrow keys", async () => {
  notes = [{ id: "n1", slug: "n1", title: "Pods by hand", body: "", tags: [], agentId: agent.id, createdAt: 1, updatedAt: 5 } as Note];
  await render();
  await tab("notes");
  expect([...container.querySelectorAll("[data-resource-kind]")].map((row) => row.getAttribute("data-resource-kind"))).toEqual(["note", "canvas"]);
  const filter = () => container.querySelector<HTMLInputElement>('input[aria-label="Filter notes"]')!;
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
    setter.call(filter(), "drawing"); filter().dispatchEvent(new Event("input", { bubbles: true }));
  });
  expect([...container.querySelectorAll("[data-resource-kind]")].map((row) => row.getAttribute("data-resource-id"))).toEqual([agent.id]);
  await tab("sources");
  expect(container.querySelector<HTMLInputElement>('input[aria-label="Filter sources"]')!.value).toBe("");
  expect(container.querySelector('[data-resource-id="doc"]')).not.toBeNull();
  await tab("notes");
  expect(filter().value).toBe("drawing");
  await act(async () => filter().dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(filter().value).toBe("");
  await act(async () => filter().dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
  expect(document.activeElement?.getAttribute("data-resource-id")).toBe("n1");
  await act(async () => document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
  expect(document.activeElement?.getAttribute("data-resource-kind")).toBe("canvas");
  // ← and → move between the segments.
  const selected = container.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]')!;
  await act(async () => selected.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })));
  expect(container.querySelector('[role="tab"][aria-selected="true"]')?.getAttribute("data-segment")).toBe("files");
  expect(document.activeElement?.getAttribute("data-segment")).toBe("files");
});

it("keeps the open file's reader and pending edits with it when the file is renamed or trashed", async () => {
  const from = "/home/user/Loci/agent-a/repos/notes.md";
  const to = "/home/user/Loci/agent-a/repos/notes-v2.md";
  await render();
  await tab("files");
  await click('[data-test-files="agent-a"]');
  await vi.waitFor(() => expect(container.querySelector("[data-test-file]")?.getAttribute("data-test-file")).toBe(from));
  setFileDraft(from, { text: "edited", base: "original" });
  await click('[data-test-file-move="agent-a"]');
  expect(control.stateFor(agent.id).page).toEqual({ kind: "file", path: to });
  expect(getFileDraft(from)).toBeNull();
  expect(getFileDraft(to)).toEqual({ text: "edited", base: "original" });
  expect(container.querySelector("[data-test-file]")?.getAttribute("data-test-file")).toBe(to);
  await click('[data-test-file-delete="agent-a"]');
  expect(container.querySelector("[data-test-file]")).toBeNull();
  expect(reader().dataset.mentorReader).toBe("empty");
  expect(getFileDraft(to)).toBeNull();
});

it("shows a conversation as the reader without remembering it, with a header that closes it", async () => {
  await render();
  await act(async () => control.show(agent.id, { kind: "session", id: "delegated" }));
  expect(reader().querySelector('[data-test-session="delegated"]')).not.toBeNull();
  expect(reader().querySelector("[data-resource-header]")?.textContent).toContain("Delegated work");
  expect(JSON.parse(localStorage.getItem(MENTOR_VIEW_KEY)!)[agent.id].page).toBeUndefined();
  await click('[data-resource-header] [aria-label="Close"]');
  expect(reader().dataset.mentorReader).toBe("empty");
});

it("keeps the reader 360px when a column saved on a bigger window is dragged wider", async () => {
  const inner = Object.getOwnPropertyDescriptor(window, "innerWidth");
  Object.defineProperty(window, "innerWidth", { configurable: true, value: 1600 });
  localStorage.setItem(MENTOR_VIEW_KEY, JSON.stringify({ [agent.id]: { libraryWidth: 500, chatWidth: 420 } }));
  try {
    await render();
    const body = container.querySelector<HTMLElement>(".mentor-body")!;
    Object.defineProperty(body, "clientWidth", { configurable: true, value: 1400 });
    await act(async () => window.dispatchEvent(new Event("resize")));
    const handle = container.querySelector<HTMLElement>('[aria-label="Resize library"]')!;
    for (let step = 0; step < 12; step++) {
      await act(async () => handle.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })));
    }
    // 1400 − 360 for the reader − the conversation's 420 leaves the library 620.
    expect(control.stateFor(agent.id).libraryWidth).toBe(620);
    expect(control.stateFor(agent.id).chatWidth).toBe(420);
  } finally {
    if (inner) Object.defineProperty(window, "innerWidth", inner);
    else delete (window as unknown as Record<string, unknown>).innerWidth;
  }
});

it("re-clamps both columns when the window shrinks below their saved widths", async () => {
  const inner = Object.getOwnPropertyDescriptor(window, "innerWidth");
  Object.defineProperty(window, "innerWidth", { configurable: true, value: 1600 });
  localStorage.setItem(MENTOR_VIEW_KEY, JSON.stringify({ [agent.id]: { libraryWidth: 620, chatWidth: 420 } }));
  try {
    await render();
    const body = container.querySelector<HTMLElement>(".mentor-body")!;
    Object.defineProperty(body, "clientWidth", { configurable: true, value: 1000 });
    await act(async () => window.dispatchEvent(new Event("resize")));
    expect(control.stateFor(agent.id).libraryWidth).toBe(220);
    expect(control.stateFor(agent.id).chatWidth).toBe(420);
    expect(container.querySelector<HTMLElement>(".mentor-library-column")!.style.width).toBe("220px");
  } finally {
    if (inner) Object.defineProperty(window, "innerWidth", inner);
    else delete (window as unknown as Record<string, unknown>).innerWidth;
  }
});

it("puts the library away after a choice while it covers the reader", async () => {
  await render();
  const body = container.querySelector<HTMLElement>(".mentor-body")!;
  Object.defineProperty(body, "clientWidth", { configurable: true, value: 800 });
  await act(async () => window.dispatchEvent(new Event("resize")));
  expect(container.querySelector(".mentor-library-scrim")).not.toBeNull();
  await tab("sources");
  await vi.waitFor(() => expect(container.querySelector('[data-resource-kind="document"]')).not.toBeNull());
  await click('[data-resource-kind="document"]');
  expect(control.stateFor(agent.id).library).toBe(false);
  expect(control.stateFor(agent.id).page).toMatchObject({ kind: "document" });
  expect(container.querySelector<HTMLElement>(".mentor-library-column")!.hidden).toBe(true);
  expect(container.querySelector(".mentor-library-scrim")).toBeNull();
});

it("lists the mentor's working folder under Files and opens a file from it in the reader", async () => {
  await render();
  await tab("files");
  const files = container.querySelector<HTMLButtonElement>('[data-library-section="files"] [data-test-files="agent-a"]')!;
  expect(files).not.toBeNull();
  await act(async () => files.click());
  await vi.waitFor(() => expect(container.querySelector("[data-test-file]")?.getAttribute("data-test-file")).toBe("/home/user/Loci/agent-a/repos/notes.md"));
  expect(control.stateFor(agent.id).page).toEqual({ kind: "file", path: "/home/user/Loci/agent-a/repos/notes.md" });
  await render(other);
  await tab("files");
  expect(container.querySelector('[data-test-files="agent-b"]')).not.toBeNull();
});
