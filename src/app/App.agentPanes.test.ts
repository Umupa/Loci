// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { clearMocks, mockConvertFileSrc, mockIPC, mockWindows } from "@tauri-apps/api/mocks";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import App from "./App";
import { agentCanvasScope, type Agent } from "../features/agents/model/agent";
import { saveAgentDocuments, type StoredDocument } from "../features/agents/model/agentDocuments";
import { canvasElementsToText, type Canvas } from "../features/canvas/canvas";
import type { CanvasPane } from "../features/canvas/ui/CanvasPane";
import { clearComposerDraft, getComposerDraft, setComposerDraft } from "../features/sessions/model/draftCache";
import { newSession, type Block, type Session } from "../features/sessions/model/session";
import { clearTranscriptJump, peekTranscriptJump, requestTranscriptJump } from "../features/sessions/model/transcriptJump";
import { openLearningDiscussion } from "../features/learning/model/navigation";
import { openCourse } from "../features/learning/model/course";
import { requestOpenAppResource } from "../shared/lib/appResourceLinks";
import { canvasLeaf, coursePaneId, documentLeaf, documentPaneId, leaf, newTab, placeLayout } from "../features/workspace/model/layout";
import * as harnessRegistry from "../integrations/harness/core/registry";

const platform = vi.hoisted(() => ({ mac: false }));
vi.mock("../platform/tauri/platform", async (original) => ({
  ...(await original<typeof import("../platform/tauri/platform")>()),
  get IS_MAC() { return platform.mac; },
}));

// Catalog discovery needs signed-in CLIs; the editor itself is covered by CanvasPane tests.
vi.mock("../integrations/harness/core/registry", async (original) => ({
  ...(await original<typeof import("../integrations/harness/core/registry")>()),
  refreshHarnessCatalogs: vi.fn(),
}));
vi.mock("./model/preloadNavigation", () => ({ preloadNavigationWhenIdle: () => () => undefined }));
vi.mock("../features/notes/ui/NotesView", () => ({ NotesView: () => createElement("div", { "data-test-note": true }, "Latest note") }));
vi.mock("../features/canvas/ui/CanvasPane", () => ({
  CanvasPane: ({ canvas, focused, onFocus, onPaneDragStart, onAddToChat, chatTarget = "chat" }: ComponentProps<typeof CanvasPane>) => createElement("section", {
    "data-test-canvas": canvas.id,
    "data-focused": focused,
    onPointerDown: onFocus,
  }, createElement("header", { onPointerDown: onPaneDragStart }, canvas.title,
    createElement("button", {
      "aria-label": `Add drawing to ${chatTarget}`,
      onClick: () => onAddToChat(canvasElementsToText(canvas.title, JSON.stringify(JSON.parse(canvas.dataJson).elements, null, 2), canvas.id)),
    }, chatTarget === "agent" ? "Add to agent" : "Add to chat"))),
}));

const reading = { id: "network", title: "Network strategy", subject: "Sandbox", body: "# Network strategy\n\nStored network strategy." };
const agents: Agent[] = [
  { id: "agent-a", sessionId: "chat-a", name: "Ada", avatar: "loci", color: "#cc66aa", projects: [] },
  { id: "agent-b", sessionId: "chat-b", name: "Bea", avatar: "loci", color: "#66aacc", projects: [] },
];
const canvas: Canvas = { id: "library-drawing", title: "Network map", cwd: agentCanvasScope("agent-a"), dataJson: '{"elements":[]}', tags: [], createdAt: 1, updatedAt: 1 };
const library = new Map<string, StoredDocument>();
let root: Root;
let container: HTMLDivElement;
let sessions: Session[];
type ArchivePage = { seq: number; hasOlder: boolean; blocksJson: string };
let readArchive: ReturnType<typeof vi.fn<(id: string, before: number | null) => Promise<ArchivePage | null>>>;
let saveSessionRecord: ReturnType<typeof vi.fn<(session: Session) => Promise<Session & { createdAt: number; updatedAt: number }>>>;
let onHistoryRead: (() => void) | undefined;

function archivedPage(seq: number, blocks: Block[], hasOlder = false): ArchivePage {
  return { seq, blocksJson: JSON.stringify(blocks), hasOlder };
}

beforeEach(async () => {
  platform.mac = false;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  for (const id of ["blank", "project-chat", ...agents.map((agent) => agent.sessionId!)]) {
    clearComposerDraft(id);
    const jump = peekTranscriptJump(id);
    if (jump) clearTranscriptJump(id, jump.token);
  }
  localStorage.setItem("loci:agent-roster", JSON.stringify(agents));
  localStorage.setItem("loci.tabAnimationsEnabled", "false");
  // These cover project tabs alongside agents; projects are off by default.
  localStorage.setItem("loci.projectsEnabled", "true");
  library.clear();
  readArchive = vi.fn(async () => null);
  saveSessionRecord = vi.fn(async (session) => ({ ...session, createdAt: 1, updatedAt: 2 }));
  onHistoryRead = undefined;
  for (const agent of agents) library.set(`${agent.id}:network`, { ...reading, body: `${reading.body}\n\nOwned by ${agent.name}.`, createdAt: 1, updatedAt: 1 });
  sessions = agents.map((agent) => ({
    ...newSession("antigravity", "/home/user"), id: agent.sessionId!,
    blocks: [
      { id: "question", role: "user", text: "Explain the network strategy." },
      { id: "reading", role: "assistant", text: `An explanation for ${agent.name}.\n\n\`\`\`loci-document\n---\nid: network\ntitle: Network strategy\nsubject: Sandbox\n---\n# Network strategy\n\nCard copy for ${agent.name}.\n\`\`\`` },
    ],
  }));
  mockWindows("main");
  mockConvertFileSrc("macos");
  mockIPC((command, args) => {
    const input = args as { agent?: string; id?: string; sessionId?: string; before?: number | null; session?: Session; document?: typeof reading };
    if (command === "session_get") {
      const session = sessions.find((entry) => entry.id === input.sessionId);
      return session ? { ...session, createdAt: 1, updatedAt: 1 } : null;
    }
    if (command === "session_upsert") return saveSessionRecord(input.session!);
    if (command === "course_list_all" || command === "notes_list") return [];
    if (command === "notes_get") return null;
    if (command === "canvas_list") return [canvas];
    if (command === "canvas_get") return input.id === canvas.id ? canvas : null;
    if (command === "course_get") return { id: input.id, agentId: (args as { agentId: string }).agentId, title: "Kubernetes",
      updatedAt: 2, engine: "reading", dataJson: JSON.stringify({ chapters: [{ title: "Workloads", lessons: [{ id: "pod", title: "Pod", file: "/books/course-content.pdf" }] }] }) };
    if (command === "course_progress_get") return [];
    if (command === "agent_documents_list") return [...library.entries()].filter(([key]) => key.startsWith(`${input.agent}:`)).map(([, entry]) => {
      const { body: _body, ...summary } = entry;
      return summary;
    });
    if (command === "agent_documents_get") return library.get(`${input.agent}:${input.id}`) ?? null;
    if (command === "agent_documents_upsert") {
      library.set(`${input.agent}:${input.document!.id}`, { ...input.document!, createdAt: 1, updatedAt: 2 });
      return;
    }
    if (command === "agent_load") return { id: input.agent, dir: `/agents/${input.agent}`, soul: "# Soul", soulHash: "soul", memory: "", memoryHash: "memory", memoryPath: `/agents/${input.agent}/MEMORY.md`, topics: [] };
    if (command === "agent_read") return { text: "[]", hash: "habits" };
    if (command === "agent_transcript_page") return readArchive(input.sessionId!, input.before ?? null);
    if (command === "learning_source_get") return { id: input.id, kind: "conversation", sessionId: "chat-a", blockId: "archived-question", title: "Earlier discussion", quote: "Archived question" };
    if (command === "session_list_by_project") { onHistoryRead?.(); return []; }
    if (["stat_files", "session_list", "list_directory", "skills_list", "list_fonts"].includes(command)) return [];
    if (command === "resolve_project_location") return { path: "/repo", identity: "fixture" };
    if (command.startsWith("plugin:window|") || ["set_dock_badge", "keybindings_set_overrides", "workspace_set_snapshot"].includes(command)) return;
    throw new Error(`Unexpected test IPC: ${command}`);
  }, { shouldMockEvents: true });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  await import("../features/agents/ui/AgentDocumentReader");
  await import("../features/canvas/ui/CanvasPane");
});

afterEach(async () => {
  await act(async () => {
    root.unmount();
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
  container.remove();
  clearMocks();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it("puts the window's buttons ahead of the mentor's title bar when the rail is collapsed", async () => {
  platform.mac = true;
  await renderApp();
  await click(railButton("Ada"));
  await settle(() => expect(agentWorkspace()).not.toBeNull());
  const titlebar = () => agentWorkspace().querySelector<HTMLElement>(".mentor-titlebar")!;
  expect(titlebar().querySelector('button[aria-label^="Back"]')).toBeNull();

  await click(container.querySelector<HTMLButtonElement>('nav[aria-label="Projects"] button[aria-label^="Toggle Projects"]')!);
  expect(container.querySelector("[data-compact-project-rail]")).not.toBeNull();
  // The collapsed rail has its own button for the sidebar; the title bar keeps only Back.
  expect(titlebar().querySelector('button[aria-label^="Back"]')).not.toBeNull();
  expect(titlebar().querySelector('button[aria-label^="Toggle Sidebar"]')).toBeNull();
  await click(titlebar().querySelector<HTMLButtonElement>('button[aria-label="Hide conversation"]')!);
  await settle(() => expect(agentWorkspace().querySelector<HTMLElement>(".mentor-chat-column")!.hidden).toBe(true));
  expect(titlebar().querySelector('button[aria-label^="Back"]')).not.toBeNull();
  await click(container.querySelector<HTMLButtonElement>('[data-compact-project-rail] button[aria-label="Expand projects"]')!);
  expect(titlebar().querySelector('button[aria-label^="Back"]')).toBeNull();
});

async function renderApp(projectSession?: Session) {
  const blank = projectSession ?? { ...newSession("antigravity", "/repo"), id: "blank" };
  const tab = newTab(blank.id);
  await act(async () => root.render(createElement(App, {
    resumed: { sessions: [blank, ...sessions], tabs: [tab], activeTabId: tab.id, projectCwd: "/repo", projectReturnMemory: new Map() },
    history: [], historyCwd: "/repo",
  })));
  // A fresh workspace can still be suspended on a lazy pane after root.render settles.
  await settle(() => {
    expect(titleTabs()).toHaveLength(1);
    expect(pane(blank.id)).not.toBeNull();
  });
}

const visible = (element: HTMLElement) => !element.closest('[aria-hidden="true"], .hidden');
const agentWorkspace = () => [...container.querySelectorAll<HTMLElement>("[data-agent-workspace]")].find(visible)!;
const pane = (id: string) => ([...container.querySelectorAll<HTMLElement>(`[data-pane-id="${id}"]`)].find(visible) ?? null)!;
const panes = () => [...container.querySelectorAll<HTMLElement>("[data-pane-id]")].filter(visible);
const titleTabs = () => [...container.querySelectorAll<HTMLElement>("[data-title-tab-id]")].map((tab) => ({ id: tab.dataset.titleTabId, text: tab.textContent }));
const railButton = (name: string) => container.querySelector<HTMLButtonElement>(`[data-agent-rail] button[aria-label^="${name},"]`)!;
const projectButton = () => container.querySelector<HTMLButtonElement>('nav[aria-label="Projects"] button[aria-label="repo"]')!;
const pointer = async (target: EventTarget, type: string, clientX = 10, clientY = 10) => { await act(async () => { target.dispatchEvent(new PointerEvent(type, { bubbles: true, button: 0, pointerId: 1, clientX, clientY })); }); };
const click = async (button: HTMLButtonElement) => { await act(async () => button.click()); };
const settle = async (assert: () => void, timeout = 5000) => {
  const startedAt = Date.now();
  for (;;) {
    // waitFor's polling interval can start another async act before the prior one settles.
    // Flush one render at a time, then retry the same assertion within its deadline.
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 50)); });
    try {
      assert();
      return;
    } catch (error) {
      if (Date.now() - startedAt >= timeout) throw error;
    }
  }
};

it("opens a course in its owning agent workspace and a project course in its source tab", async () => {
  const project = { ...newSession("antigravity", "/repo"), id: "project-chat" };
  await renderApp(project);
  const agentCourse = { courseId: "kubernetes", agentId: "agent-a", title: "Kubernetes", sourceSessionId: "chat-a" };
  await act(async () => openCourse(agentCourse));
  await settle(() => expect(container.querySelector('[data-mentor-workspace="agent-a"] [data-mentor-reader]')?.textContent).toContain("course-content.pdf"));
  expect(agentWorkspace()).toBeTruthy();
  expect(panes().map((entry) => entry.dataset.paneId)).toEqual(["chat-a"]);
  expect(container.querySelector('[aria-label="Expand course to pane"]')).toBeNull();
  const projectCourse = { ...agentCourse, agentId: project.id, sourceSessionId: project.id };
  await act(async () => openCourse(projectCourse));
  await settle(() => {
    expect(pane(coursePaneId(projectCourse.courseId, projectCourse.agentId))?.textContent).toContain("course-content.pdf");
    expect(pane(project.id)).toBeTruthy();
  });
  expect(titleTabs()).toHaveLength(1);
});

it("keeps an opened agent when its idle save finishes before the view renders", async () => {
  let finishSave!: () => void;
  // The first committed history read runs after the runtime captures its saved
  // fingerprint and before the idle-detach effect starts its timer.
  onHistoryRead = () => {
    sessions[0].title = "Changed since the boot snapshot";
    onHistoryRead = undefined;
  };
  saveSessionRecord.mockImplementation(async (session) => {
    if (session.id !== "chat-a") return { ...session, createdAt: 1, updatedAt: 2 };
    await new Promise<void>((resolve) => { finishSave = resolve; });
    return { ...session, createdAt: 1, updatedAt: 2 };
  });
  try {
    await renderApp();
    await settle(() => expect(finishSave).toBeDefined(), 2000);
    await act(async () => {
      railButton("Ada").click();
      finishSave();
      await Promise.resolve();
    });
    await settle(() => expect(agentWorkspace()?.querySelector('[data-agent-view="agent-a"]')).toBeTruthy(), 2000);
  } finally { finishSave?.(); }
});

it.each(["discussion", "source"] as const)("waits for the second archive page before locating a learning %s", async (entry) => {
  let finishOlder!: (page: ArchivePage) => void;
  readArchive.mockImplementation(async (id, before) => {
    expect(id).toBe("chat-a");
    if (before === null) return archivedPage(2, [{ id: "newer-archived", role: "user", text: "A newer archived question" }], true);
    if (before === 2) return new Promise((resolve) => { finishOlder = resolve; });
    throw new Error(`Unexpected archive cursor: ${before}`);
  });
  await renderApp();
  await act(async () => {
    if (entry === "discussion") openLearningDiscussion({ sessionId: "chat-a", blockId: "archived-question" });
    else requestOpenAppResource({ kind: "source", id: "old-source" });
  });
  await settle(() => expect(readArchive).toHaveBeenCalledWith("chat-a", 2), 2000);
  expect(peekTranscriptJump("chat-a")).toBeNull();
  expect(pane("chat-a")?.textContent ?? "").not.toContain("Archived question");
  await act(async () => finishOlder(archivedPage(1, [
    { id: "archived-question", role: "user", text: "Archived question", durationMs: 1000 },
    { id: "archived-answer", role: "assistant", text: "Archived answer" },
  ])));
  await settle(() => {
    expect(pane("chat-a").querySelector('[data-transcript-search-current="true"]')?.textContent).toContain("Archived question");
    expect(peekTranscriptJump("chat-a")).toBeNull();
  });
  expect(readArchive.mock.calls).toEqual([["chat-a", null], ["chat-a", 2]]);
  expect(pane("chat-a").textContent).toContain("An explanation for Ada.");
});

it.each(["chat-a", "blank"])("reports an unavailable learning discussion when its block was removed from %s", async (id) => {
  readArchive.mockResolvedValue(archivedPage(1, [{ id: "other-history", role: "user", text: "A different discussion" }]));
  await renderApp();
  await act(async () => openLearningDiscussion({ sessionId: id, blockId: "removed-question" }));
  await settle(() => expect(container.querySelector('[role="alert"]')?.textContent).toContain("This discussion is no longer available."), 2000);
  expect(peekTranscriptJump(id)).toBeNull();
});

it("leaves a newer note open when an older conversation source finishes loading its archive", async () => {
  let finishOlder!: (page: ArchivePage) => void;
  readArchive.mockImplementation(async (_id, before) => before === null
    ? archivedPage(2, [{ id: "newer", role: "user", text: "Newer archived question" }], true)
    : new Promise((resolve) => { finishOlder = resolve; }));
  await renderApp();
  await act(async () => requestOpenAppResource({ kind: "source", id: "old-source" }));
  await settle(() => expect(readArchive).toHaveBeenCalledWith("chat-a", 2), 2000);
  await act(async () => requestOpenAppResource({ kind: "note", id: "latest-note" }));
  await settle(() => expect(container.querySelector("[data-test-note]")).not.toBeNull());
  await act(async () => finishOlder(archivedPage(1, [{ id: "archived-question", role: "user", text: "Archived question" }])));
  expect(container.querySelector("[data-test-note]")?.textContent).toBe("Latest note");
  expect(agentWorkspace()).toBeUndefined();
  expect(peekTranscriptJump("chat-a")).toBeNull();
});

it("reports an archive read failure without queuing a jump to an unloaded learning discussion", async () => {
  readArchive.mockImplementation(async (_id, before) => {
    if (before === null) return archivedPage(2, [{ id: "newer", role: "user", text: "Newer archived question" }], true);
    throw new Error("Archive read failed");
  });
  await renderApp();
  await act(async () => openLearningDiscussion({ sessionId: "chat-a", blockId: "archived-question" }));
  await settle(() => expect(container.querySelector('[role="alert"]')?.textContent).toContain("Archive read failed"), 2000);
  expect(peekTranscriptJump("chat-a")).toBeNull();
});

it("retries a pending transcript jump when manual archive loading adds its target block", async () => {
  readArchive.mockResolvedValue(archivedPage(1, [{ id: "archived-question", role: "user", text: "Archived question", durationMs: 1000 }]));
  await renderApp();
  await click(railButton("Ada"));
  await settle(() => expect(pane("chat-a")?.querySelector("textarea")).not.toBeNull());
  await act(async () => requestTranscriptJump("chat-a", "archived-question"));
  await act(async () => { await new Promise((resolve) => requestAnimationFrame(resolve)); });
  expect(peekTranscriptJump("chat-a")).not.toBeNull();
  const history = [...pane("chat-a").querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Show archived history")!;
  expect(history).toBeDefined();
  await click(history);
  await settle(() => {
    expect(pane("chat-a").querySelector('[data-transcript-search-current="true"]')?.textContent).toContain("Archived question");
    expect(peekTranscriptJump("chat-a")).toBeNull();
  }, 2000);
});

it("offers Save to canvas for completed agent responses only", async () => {
  const projectSession: Session = {
    ...newSession("antigravity", "/repo"), id: "project-chat",
    blocks: [
      { id: "project-question", role: "user", text: "Explain this project.", durationMs: 1000 },
      { id: "project-answer", role: "assistant", text: "The project checks passed." },
    ],
  };
  sessions[0] = {
    ...sessions[0],
    blocks: sessions[0].blocks.map((block) => block.role === "user" ? { ...block, durationMs: 1000 } : block),
  };
  await renderApp(projectSession);
  await settle(() => expect(pane(projectSession.id).querySelector('[data-turn-actions] button[aria-label="Copy response"]')).not.toBeNull());
  expect(pane(projectSession.id).textContent).toContain("The project checks passed.");
  expect(pane(projectSession.id).querySelector('button[aria-label="Save to canvas"]')).toBeNull();

  await click(railButton("Ada"));
  await settle(() => expect(pane("chat-a").querySelector('[data-turn-actions] button[aria-label="Save to canvas"]')).not.toBeNull(), 10000);
  expect(pane("chat-a").textContent).toContain("An explanation for Ada.");
  expect(pane("chat-a").querySelector<HTMLButtonElement>('button[aria-label="Save to canvas"]')!.disabled).toBe(false);
}, 15000);

it("adds a Library canvas to the current agent draft without creating or submitting a project conversation", async () => {
  const sendTurn = vi.spyOn(harnessRegistry, "sendHarnessTurn");
  const projectDraft = "Keep this project question.";
  const agentDraft = "Explain this map.";
  setComposerDraft("blank", projectDraft);
  setComposerDraft("chat-a", agentDraft);
  await renderApp();
  const originalTabs = titleTabs();
  const originalProjectPane = pane("blank");

  await click(railButton("Ada"));
  await settle(() => expect(pane("chat-a")?.querySelector("textarea")).toBeTruthy());
  await settle(() => expect(container.querySelector('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')).not.toBeNull());
  await click(container.querySelector<HTMLButtonElement>('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')!);
  const overview = () => container.querySelector<HTMLElement>('[data-mentor-workspace="agent-a"] [data-mentor-reader]')!;
  await settle(() => expect(overview().querySelector("[data-test-canvas]")).not.toBeNull());
  const addToAgent = overview().querySelector<HTMLButtonElement>('button[aria-label="Add drawing to agent"]')!;
  expect(addToAgent.textContent).toBe("Add to agent");
  const input = pane("chat-a").querySelector<HTMLTextAreaElement>("textarea")!;
  expect(input.value).toBe(agentDraft);

  await click(addToAgent);
  const canvasText = canvasElementsToText(canvas.title, "[]", canvas.id);
  await settle(() => {
    expect(input.value).toBe(`${agentDraft}\n\n${canvasText}\n\n`);
    expect(getComposerDraft("chat-a")).toBe(input.value);
  });
  expect(panes()).toHaveLength(1);
  expect(titleTabs()).toEqual(originalTabs);
  expect(container.querySelector('[data-pane-id="blank"]')).toBe(originalProjectPane);
  expect(getComposerDraft("blank")).toBe(projectDraft);
  expect(getComposerDraft("chat-b")).toBeUndefined();
  expect(sendTurn).not.toHaveBeenCalled();

  await click(projectButton());
  await settle(() => expect(pane("blank")).toBe(originalProjectPane));
  expect(panes()).toHaveLength(1);
  expect(pane("blank").querySelector<HTMLTextAreaElement>("textarea")!.value).toBe(projectDraft);
  expect(sendTurn).not.toHaveBeenCalled();
}, 15000);

it("reads one thing at a time beside the agent: each opened item replaces the last", async () => {
  await renderApp();
  const originalTabs = titleTabs();
  const originalSessionPane = container.querySelector('[data-pane-id="blank"]');
  await click(railButton("Ada"));
  await settle(() => expect(agentWorkspace()?.querySelector('[data-agent-view="agent-a"]')).toBeTruthy());
  expect(titleTabs()).toEqual(originalTabs);
  expect(visible(originalSessionPane as HTMLElement)).toBe(false);
  expect(agentWorkspace().querySelector("header h1")?.textContent).toBe("Ada");
  expect(panes()).toHaveLength(1);
  const body = agentWorkspace().querySelector(".mentor-body")!;
  // The library is on the left, the reading in the middle, the conversation on the right.
  expect(body.firstElementChild!.querySelector('[data-mentor-library="agent-a"]')).not.toBeNull();
  expect(body.children[1].hasAttribute("data-mentor-reader")).toBe(true);
  expect(body.lastElementChild!.contains(pane("chat-a"))).toBe(true);
  expect(agentWorkspace().querySelector('[data-mentor-reader="empty"]')).not.toBeNull();

  const overview = () => container.querySelector<HTMLElement>('[data-mentor-workspace="agent-a"] [data-mentor-reader]')!;
  await click(pane("chat-a").querySelector<HTMLButtonElement>('[data-card="document"]')!);
  await settle(() => expect(overview().textContent).toContain("Owned by Ada."));
  expect(overview().querySelector('[aria-label="Expand document to pane"]')).toBeNull();
  expect(agentWorkspace().querySelector(".mentor-breadcrumb")?.textContent).toBe("AdaNetwork strategy");
  await act(async () => saveAgentDocuments("agent-a", [{ ...reading, body: "# Revised network\n\nLive revision from Ada." }]));
  await settle(() => expect(overview().textContent).toContain("Live revision from Ada."));

  await click(agentWorkspace().querySelector<HTMLButtonElement>('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')!);
  await settle(() => expect(overview().querySelector("[data-test-canvas]")).not.toBeNull());
  expect(overview().textContent).not.toContain("Live revision from Ada.");
  expect(panes()).toHaveLength(1);

  await click(pane("chat-a").querySelector<HTMLButtonElement>('[data-card="document"]')!);
  await settle(() => expect(overview().textContent).toContain("Live revision from Ada."));
  expect(overview().querySelector("[data-test-canvas]")).toBeNull();
  expect(panes()).toHaveLength(1);

  await click(overview().querySelector<HTMLButtonElement>('button[aria-label="Close"]')!);
  await settle(() => expect(overview().dataset.mentorReader).toBe("empty"));
  expect(pane("chat-a")).not.toBeNull();
  expect(titleTabs()).toEqual(originalTabs);
}, 15000);

it("shows only the current agent when switching, each with what it was reading", async () => {
  await renderApp();
  const originalTabs = titleTabs();
  const originalSessionPane = container.querySelector('[data-pane-id="blank"]');
  const overviews = () => [...container.querySelectorAll<HTMLElement>("[data-mentor-workspace]")];
  await act(async () => openCourse({ courseId: "kubernetes", agentId: "agent-a", title: "Kubernetes", sourceSessionId: "chat-a" }));
  await settle(() => expect(container.querySelector('[data-mentor-workspace="agent-a"] [data-mentor-reader]')?.textContent).toContain("course-content.pdf"));

  for (const name of ["Bea", "Ada", "Bea", "Ada"]) {
    await click(railButton(name));
    await settle(() => expect(agentWorkspace()?.querySelector(`[data-agent-view="agent-${name === "Ada" ? "a" : "b"}"]`)).toBeTruthy());
    expect(overviews()).toHaveLength(1);
    expect(panes()).toHaveLength(1);
  }
  expect(overviews()[0].textContent).toContain("course-content.pdf");
  await click(railButton("Bea"));
  await settle(() => expect(overviews().map((entry) => entry.dataset.mentorWorkspace)).toEqual(["agent-b"]));
  expect(overviews()[0].textContent).not.toContain("course-content.pdf");
  expect(railButton("Bea").getAttribute("aria-current")).toBe("true");
  expect(titleTabs()).toEqual(originalTabs);

  await click(projectButton());
  await settle(() => expect(agentWorkspace()).toBeUndefined());
  expect(container.querySelector('[data-pane-id="blank"]')).toBe(originalSessionPane);
  expect(railButton("Bea").getAttribute("aria-current")).toBeNull();
}, 15000);

it("moves an older agent tab into the agent workspace without changing the project session", async () => {
  const project = { ...newSession("antigravity", "/repo"), id: "project-chat", title: "Project work" };
  const projectTab = newTab(project.id);
  const documentId = documentPaneId(reading.id, "agent-a");
  const agentTab = {
    ...newTab("chat-a"), cwd: "/repo", focusedId: canvas.id,
    layout: placeLayout(
      placeLayout(leaf("chat-a"), documentLeaf(reading, "agent-a"), "chat-a", "right"),
      canvasLeaf(canvas.id), documentId, "right",
    ),
  };
  await act(async () => root.render(createElement(App, {
    resumed: { sessions: [project, ...sessions], tabs: [projectTab, agentTab], activeTabId: agentTab.id, projectCwd: "/repo", projectReturnMemory: new Map() },
    history: [], historyCwd: "/repo",
  })));
  await settle(() => expect(titleTabs()).toEqual([{ id: projectTab.id, text: "Project work" }]));
  const projectPane = container.querySelector<HTMLElement>(`[data-pane-id="${project.id}"]`);
  const originalTabs = titleTabs();

  await settle(() => expect(pane("chat-a")?.textContent).toContain("An explanation for Ada."));
  expect(railButton("Ada").getAttribute("aria-current")).toBe("true");
  expect(panes().map((entry) => entry.dataset.paneId)).toEqual(["chat-a"]);
  expect(agentWorkspace().querySelector("[data-title-tab-id]")).toBeNull();

  await click(projectButton());
  await settle(() => expect(pane(project.id)).toBe(projectPane));
  expect(panes()).toHaveLength(1);
  expect(titleTabs()).toEqual(originalTabs);
}, 15000);

