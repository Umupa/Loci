// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { clearMocks, mockConvertFileSrc, mockIPC, mockWindows } from "@tauri-apps/api/mocks";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import App from "./App";
import { ACTIVE_MENTOR_KEY } from "./hooks/useActiveMentor";
import { agentCanvasScope, type Agent } from "../features/agents/model/agent";
import { saveAgentDocuments, type StoredDocument } from "../features/agents/model/agentDocuments";
import { canvasElementsToText, type Canvas } from "../features/canvas/canvas";
import type { CanvasPane } from "../features/canvas/ui/CanvasPane";
import type { Note } from "../features/notes";
import { clearComposerDraft, getComposerDraft, setComposerDraft } from "../features/sessions/model/draftCache";
import { newSession, type Block, type Session } from "../features/sessions/model/session";
import { clearTranscriptJump, peekTranscriptJump, requestTranscriptJump } from "../features/sessions/model/transcriptJump";
import { openLearningDiscussion } from "../features/learning/model/navigation";
import { openCourse } from "../features/learning/model/course";
import { requestOpenAppResource } from "../shared/lib/appResourceLinks";
import * as filePlace from "../features/files/model/filePlace";
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
vi.mock("../features/notes/ui/NoteEditor", () => ({ NoteEditor: ({ note }: { note: Note }) => createElement("article", { "data-test-note": true }, note.title) }));
vi.mock("../features/canvas/ui/CanvasPane", () => ({
  CanvasPane: ({ canvas, focused, onFocus, onAddToChat, chatTarget = "chat" }: ComponentProps<typeof CanvasPane>) => createElement("section", {
    "data-test-canvas": canvas.id,
    "data-focused": focused,
    onPointerDown: onFocus,
  }, createElement("header", null, canvas.title,
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
let notes: Note[];
type ArchivePage = { seq: number; hasOlder: boolean; blocksJson: string };
let readArchive: ReturnType<typeof vi.fn<(id: string, before: number | null) => Promise<ArchivePage | null>>>;
let saveSessionRecord: ReturnType<typeof vi.fn<(session: Session) => Promise<Session & { createdAt: number; updatedAt: number }>>>;
const externalOpen = vi.fn();
let requestPlace: ReturnType<typeof vi.spyOn>;

function archivedPage(seq: number, blocks: Block[], hasOlder = false): ArchivePage {
  return { seq, blocksJson: JSON.stringify(blocks), hasOlder };
}

beforeEach(async () => {
  platform.mac = false;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  for (const id of ["delegated", ...agents.map((agent) => agent.sessionId!)]) {
    clearComposerDraft(id);
    const jump = peekTranscriptJump(id);
    if (jump) clearTranscriptJump(id, jump.token);
  }
  localStorage.setItem("loci:agent-roster", JSON.stringify(agents));
  library.clear();
  notes = [];
  externalOpen.mockClear();
  requestPlace = vi.spyOn(filePlace, "requestFilePlace");
  readArchive = vi.fn(async () => null);
  saveSessionRecord = vi.fn(async (session) => ({ ...session, createdAt: 1, updatedAt: 2 }));
  for (const agent of agents) library.set(`${agent.id}:network`, { ...reading, body: `${reading.body}\n\nOwned by ${agent.name}.`, createdAt: 1, updatedAt: 1 });
  sessions = [...agents.map((agent) => ({
    ...newSession("antigravity", "/home/user"), id: agent.sessionId!,
    blocks: [
      { id: "question", role: "user", text: "Explain the network strategy." },
      { id: "reading", role: "assistant", text: `An explanation for ${agent.name}.\n\n\`\`\`loci-document\n---\nid: network\ntitle: Network strategy\nsubject: Sandbox\n---\n# Network strategy\n\nCard copy for ${agent.name}.\n\`\`\`` },
    ],
  }) as Session), { ...newSession("antigravity", "/repo"), id: "delegated", title: "Delegated work",
    blocks: [{ id: "task", role: "user", text: "Check the jailer docs." }, { id: "done", role: "assistant", text: "The jailer chroots first." }] }];
  mockWindows("main");
  mockConvertFileSrc("macos");
  mockIPC((command, args) => {
    const input = args as { agent?: string; agentId?: string; id?: string; sessionId?: string; before?: number | null; session?: Session; document?: typeof reading };
    if (command === "session_get") {
      const session = sessions.find((entry) => entry.id === input.sessionId);
      return session ? { ...session, createdAt: 1, updatedAt: 1 } : null;
    }
    if (command === "session_upsert") return saveSessionRecord(input.session!);
    if (command === "course_list_all") return [];
    if (command === "notes_list") return notes.filter((note) => !input.agentId || note.agentId === input.agentId);
    if (command === "notes_get") return notes.find((note) => note.id === input.id) ?? null;
    if (command === "notes_upsert") {
      const saved = { ...(args as { note: Note }).note, slug: "note", slugPending: true, createdAt: 1, updatedAt: 2 };
      notes.push(saved);
      return saved;
    }
    if (command === "canvas_list") return [canvas];
    if (command === "canvas_get") return input.id === canvas.id ? canvas : null;
    if (command === "course_get") return { id: input.id, agentId: input.agentId, title: "Kubernetes",
      updatedAt: 2, engine: "reading", dataJson: JSON.stringify({ chapters: [{ title: "Workloads", lessons: [{ id: "pod", title: "Pod", file: "/books/course-content.pdf" }] }] }) };
    if (command === "course_progress_get" || command === "course_progress_set") return [];
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
    if (command === "agent_write") return "written";
    if (command === "agent_transcript_page") return readArchive(input.sessionId!, input.before ?? null);
    if (command === "learning_source_get") return { id: input.id, kind: "conversation", sessionId: "chat-a", blockId: "archived-question", title: "Earlier discussion", quote: "Archived question" };
    if (command === "open_path_with_default_app") return externalOpen(args);
    if (command === "read_text_file") return "# Container processes\n\nA container starts a process.";
    if (["stat_files", "session_list", "session_list_by_project", "list_directory", "skills_list", "list_fonts"].includes(command)) return [];
    if (command === "resolve_project_location") return { path: "/repo", identity: "fixture" };
    if (command === "home_dir") return "/home/user";
    if (command === "agent_workdir_create") return `/home/user/Loci/${(args as { slug: string }).slug}`;
    if (command === "agent_workdir_ensure") return (args as { path: string }).path;
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

async function renderApp(resumed: Session[] = []) {
  await act(async () => root.render(createElement(App, {
    resumed: resumed.length ? { sessions: resumed } : null,
  })));
}
async function renderMentor(name = "Ada") {
  await renderApp();
  await click(railButton(name));
  await settle(() => expect(pane(name === "Ada" ? "chat-a" : "chat-b")).not.toBeNull());
}

const workspace = () => container.querySelector<HTMLElement>("[data-mentor-workspace]")!;
const reader = () => container.querySelector<HTMLElement>("[data-mentor-reader]")!;
const pane = (id: string) => container.querySelector<HTMLElement>(`[data-pane-id="${id}"]`)!;
const panes = () => [...container.querySelectorAll<HTMLElement>("[data-pane-id]")];
const railButton = (name: string) => container.querySelector<HTMLButtonElement>(`[data-agent-rail] button[aria-label^="${name}"]`)!;
const click = async (button: HTMLButtonElement) => { await act(async () => button.click()); };
/** Shows one of the library's segments. */
const segment = async (name: string) => {
  await settle(() => expect(container.querySelector(`[role="tab"][data-segment="${name}"]`)).not.toBeNull());
  await click(container.querySelector<HTMLButtonElement>(`[role="tab"][data-segment="${name}"]`)!);
};
const settle = async (assert: () => void, timeout = 5000) => {
  const startedAt = Date.now();
  for (;;) {
    // waitFor's polling interval can start another async act before the prior one settles.
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 50)); });
    try {
      assert();
      return;
    } catch (error) {
      if (Date.now() - startedAt >= timeout) throw error;
    }
  }
};

it("opens on the mentor shown last, with mentors on the rail and no tabs or projects", async () => {
  localStorage.setItem(ACTIVE_MENTOR_KEY, "agent-b");
  await renderApp();
  await settle(() => expect(workspace()?.dataset.mentorWorkspace).toBe("agent-b"));
  expect(railButton("Bea").getAttribute("aria-current")).toBe("true");
  expect(container.querySelectorAll("[data-agent-rail] [data-agent-id]")).toHaveLength(2);
  expect(container.querySelector('[data-agent-rail] button[aria-label="New mentor"]')).not.toBeNull();
  expect(container.querySelector('nav[aria-label="Projects"]')).toBeNull();
  expect(container.querySelector("[data-title-tab-id]")).toBeNull();
  expect(workspace().querySelector(".mentor-breadcrumb")?.textContent).toBe("Bea");
  await click(railButton("Ada"));
  await settle(() => expect(workspace()?.dataset.mentorWorkspace).toBe("agent-a"));
  expect(localStorage.getItem(ACTIVE_MENTOR_KEY)).toBe("agent-a");
});

it("leaves room for the window's buttons in the rail on macOS", async () => {
  platform.mac = true;
  await renderMentor();
  expect(container.querySelector(".mentor-rail[data-mac]")).not.toBeNull();
  expect(workspace().querySelector(".mentor-titlebar button[aria-label^='Back']")).toBeNull();
});

it("starts on the mentor workspace's empty state when there is no mentor, and offers the gallery", async () => {
  localStorage.setItem("loci:agent-roster", "[]");
  localStorage.setItem("loci.settingsSection", "chat");
  await renderApp();
  await settle(() => expect(container.querySelector("[data-mentors-empty]")).not.toBeNull());
  expect(container.querySelector("[data-app-settings]")).toBeNull();
  expect(workspace()).toBeNull();
  const create = container.querySelector<HTMLButtonElement>("[data-mentors-empty] button.primary-action")!;
  expect(create.textContent).toBe("Create a mentor");
  await click(create);
  const gallery = () => document.querySelector<HTMLElement>('[role="dialog"]');
  await settle(() => expect(gallery()?.textContent).toContain("New mentor"));
  expect([...document.querySelectorAll<HTMLElement>("[data-agent-template]")].map((card) => card.dataset.agentTemplate)).toEqual(["learning-guide", "repo-lens"]);
  expect(gallery()!.textContent).toContain("Blank mentor");
});

it("keeps the window's buttons while no mentor is open", async () => {
  localStorage.setItem("loci:agent-roster", "[]");
  await renderApp();
  await settle(() => expect(container.querySelector("[data-mentors-empty]")).not.toBeNull());
  expect(container.querySelector('[data-mentors-empty] [aria-label="Minimize window"]')).not.toBeNull();
  expect(container.querySelector('[data-mentors-empty] [aria-label="Close window"]')).not.toBeNull();
});

it("says which mentor is opening before its workspace arrives", async () => {
  await act(async () => {
    const original = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (command: string, args: unknown, options: unknown) => {
      if (command === "session_get") await new Promise((resolve) => setTimeout(resolve, 150));
      return original(command, args, options);
    };
  });
  await renderApp();
  await settle(() => expect(container.querySelector("[data-mentors-empty] [role=status]")?.textContent).toBe("Opening Ada…"), 2000);
  await settle(() => expect(workspace()?.dataset.mentorWorkspace).toBe("agent-a"));
});

it("opens another mentor when the open one is removed in another window", async () => {
  await renderMentor("Ada");
  localStorage.setItem("loci:agent-roster", JSON.stringify(agents.slice(1)));
  await act(async () => { window.dispatchEvent(new StorageEvent("storage", { key: "loci:agent-roster" })); });
  await settle(() => expect(workspace()?.dataset.mentorWorkspace).toBe("agent-b"));
});

it("opens a course in its owning mentor's reader", async () => {
  await renderMentor("Bea");
  await act(async () => openCourse({ courseId: "kubernetes", agentId: "agent-a", title: "Kubernetes", sourceSessionId: "chat-a" }));
  await settle(() => expect(container.querySelector('[data-mentor-workspace="agent-a"] [data-mentor-reader]')?.textContent).toContain("course-content.pdf"));
  expect(panes().map((entry) => entry.dataset.paneId)).toEqual(["chat-a"]);
  expect(container.querySelector('[data-library-section="courses"]')?.textContent).toContain("Pod");
});

it("keeps an opened mentor when its idle save finishes before the view renders", async () => {
  let finishSave!: () => void;
  saveSessionRecord.mockImplementation(async (session) => {
    if (session.id !== "chat-a") return { ...session, createdAt: 1, updatedAt: 2 };
    await new Promise<void>((resolve) => { finishSave = resolve; });
    return { ...session, createdAt: 1, updatedAt: 2 };
  });
  await renderMentor();
  await act(async () => { sessions[0].title = "Changed"; });
  await settle(() => expect(workspace()?.querySelector('[data-agent-view="agent-a"]')).toBeTruthy(), 2000);
  finishSave?.();
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

it.each(["chat-a", "missing"])("reports an unavailable learning discussion when its block was removed from %s", async (id) => {
  readArchive.mockResolvedValue(archivedPage(1, [{ id: "other-history", role: "user", text: "A different discussion" }]));
  await renderApp();
  await act(async () => openLearningDiscussion({ sessionId: id, blockId: "removed-question" }));
  await settle(() => expect(container.querySelector('[role="alert"]')?.textContent).toContain("This discussion is no longer available."), 2000);
  expect(peekTranscriptJump(id)).toBeNull();
});

it("leaves a newer note open when an older conversation source finishes loading its archive", async () => {
  notes = [{ id: "latest-note", title: "Latest note", body: "", tags: [], slug: "latest", createdAt: 1, updatedAt: 1 } as Note];
  let finishOlder!: (page: ArchivePage) => void;
  readArchive.mockImplementation(async (_id, before) => before === null
    ? archivedPage(2, [{ id: "newer", role: "user", text: "Newer archived question" }], true)
    : new Promise((resolve) => { finishOlder = resolve; }));
  await renderMentor();
  await act(async () => requestOpenAppResource({ kind: "source", id: "old-source" }));
  await settle(() => expect(readArchive).toHaveBeenCalledWith("chat-a", 2), 2000);
  // A note no mentor owns reads in the open mentor's reader, and stays unowned.
  await act(async () => requestOpenAppResource({ kind: "note", id: "latest-note" }));
  await settle(() => expect(reader().querySelector("[data-test-note]")?.textContent).toBe("Latest note"));
  await act(async () => finishOlder(archivedPage(1, [{ id: "archived-question", role: "user", text: "Archived question" }])));
  expect(reader().querySelector("[data-test-note]")?.textContent).toBe("Latest note");
  expect(peekTranscriptJump("chat-a")).toBeNull();
});

it("retries a pending transcript jump when manual archive loading adds its target block", async () => {
  readArchive.mockResolvedValue(archivedPage(1, [{ id: "archived-question", role: "user", text: "Archived question", durationMs: 1000 }]));
  await renderMentor();
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

it("offers Save to canvas for completed mentor responses", async () => {
  sessions[0] = { ...sessions[0], blocks: sessions[0].blocks.map((block) => block.role === "user" ? { ...block, durationMs: 1000 } : block) };
  await renderMentor();
  await settle(() => expect(pane("chat-a").querySelector('[data-turn-actions] button[aria-label="Save to canvas"]')).not.toBeNull(), 10000);
  expect(pane("chat-a").querySelector<HTMLButtonElement>('button[aria-label="Save to canvas"]')!.disabled).toBe(false);
}, 15000);

it("adds a library canvas to the mentor's draft without starting a turn", async () => {
  const sendTurn = vi.spyOn(harnessRegistry, "sendHarnessTurn");
  const agentDraft = "Explain this map.";
  setComposerDraft("chat-a", agentDraft);
  await renderMentor();
  await settle(() => expect(pane("chat-a")?.querySelector("textarea")).toBeTruthy());
  await segment("notes");
  await settle(() => expect(container.querySelector('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')).not.toBeNull());
  await click(container.querySelector<HTMLButtonElement>('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')!);
  await settle(() => expect(reader().querySelector("[data-test-canvas]")).not.toBeNull());
  const addToAgent = reader().querySelector<HTMLButtonElement>('button[aria-label="Add drawing to agent"]')!;
  const input = pane("chat-a").querySelector<HTMLTextAreaElement>("textarea")!;
  expect(input.value).toBe(agentDraft);
  await click(addToAgent);
  const canvasText = canvasElementsToText(canvas.title, "[]", canvas.id);
  await settle(() => {
    expect(input.value).toBe(`${agentDraft}\n\n${canvasText}\n\n`);
    expect(getComposerDraft("chat-a")).toBe(input.value);
  });
  expect(panes()).toHaveLength(1);
  expect(getComposerDraft("chat-b")).toBeUndefined();
  expect(sendTurn).not.toHaveBeenCalled();
}, 15000);

it("reads one thing at a time beside the mentor: each opened item replaces the last", async () => {
  await renderMentor();
  expect(workspace().querySelector("[data-agent-view] header h1")?.textContent).toBe("Ada");
  const body = workspace().querySelector(".mentor-body")!;
  // The library is on the left, the reading in the middle, the conversation on the right.
  expect(body.firstElementChild!.querySelector('[data-mentor-library="agent-a"]')).not.toBeNull();
  expect(body.children[1].hasAttribute("data-mentor-reader")).toBe(true);
  expect(body.lastElementChild!.contains(pane("chat-a"))).toBe(true);
  expect(reader().dataset.mentorReader).toBe("empty");

  await click(pane("chat-a").querySelector<HTMLButtonElement>('[data-card="document"]')!);
  await settle(() => expect(reader().textContent).toContain("Owned by Ada."));
  expect(workspace().querySelector(".mentor-breadcrumb")?.textContent).toBe("AdaNetwork strategy");
  await act(async () => saveAgentDocuments("agent-a", [{ ...reading, body: "# Revised network\n\nLive revision from Ada." }]));
  await settle(() => expect(reader().textContent).toContain("Live revision from Ada."));

  await segment("notes");
  await settle(() => expect(workspace().querySelector('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')).not.toBeNull());
  await click(workspace().querySelector<HTMLButtonElement>('[data-resource-kind="canvas"][data-resource-id="library-drawing"]')!);
  await settle(() => expect(reader().querySelector("[data-test-canvas]")).not.toBeNull());
  expect(reader().textContent).not.toContain("Live revision from Ada.");
  expect(panes()).toHaveLength(1);

  // Cmd-W closes what the reader shows, not the conversation.
  await act(async () => { window.dispatchEvent(new KeyboardEvent("keydown", { key: "w", code: "KeyW", ctrlKey: true, bubbles: true, cancelable: true })); });
  await settle(() => expect(reader().dataset.mentorReader).toBe("empty"));
  expect(pane("chat-a")).not.toBeNull();
}, 15000);

it("shows only the current mentor when switching, each with what it was reading", async () => {
  await renderApp();
  const workspaces = () => [...container.querySelectorAll<HTMLElement>("[data-mentor-workspace]")];
  await act(async () => openCourse({ courseId: "kubernetes", agentId: "agent-a", title: "Kubernetes", sourceSessionId: "chat-a" }));
  await settle(() => expect(container.querySelector('[data-mentor-workspace="agent-a"] [data-mentor-reader]')?.textContent).toContain("course-content.pdf"));
  for (const name of ["Bea", "Ada", "Bea", "Ada"]) {
    await click(railButton(name));
    await settle(() => expect(workspace()?.querySelector(`[data-agent-view="agent-${name === "Ada" ? "a" : "b"}"]`)).toBeTruthy());
    expect(workspaces()).toHaveLength(1);
    expect(panes()).toHaveLength(1);
  }
  expect(workspaces()[0].textContent).toContain("course-content.pdf");
  await click(railButton("Bea"));
  await settle(() => expect(workspaces().map((entry) => entry.dataset.mentorWorkspace)).toEqual(["agent-b"]));
  expect(workspaces()[0].textContent).not.toContain("course-content.pdf");
  expect(railButton("Bea").getAttribute("aria-current")).toBe("true");
}, 15000);

it("shows a session a mentor started in the reader, and never on its own", async () => {
  await renderApp([sessions[2]]);
  await settle(() => expect(workspace()?.dataset.mentorWorkspace).toBe("agent-a"));
  // A standalone session is not listed or shown anywhere by itself.
  expect(pane("delegated")).toBeNull();
  await act(async () => requestOpenAppResource({ kind: "session", id: "delegated" }));
  await settle(() => expect(reader().querySelector('[data-pane-id="delegated"]')?.textContent).toContain("The jailer chroots first."));
  expect(workspace().querySelector(".mentor-breadcrumb")?.textContent).toBe("AdaDelegated work");
  expect(pane("chat-a")).not.toBeNull();
});

it("opens a saved note in the mentor that owns it after switching mentors", async () => {
  sessions[0] = { ...sessions[0], blocks: sessions[0].blocks.map((block) => block.role === "user" ? { ...block, durationMs: 1000 } : block) };
  await renderMentor("Ada");
  await settle(() => expect(pane("chat-a").querySelector('button[aria-label="Save as note"]')).not.toBeNull(), 10000);
  await act(async () => pane("chat-a").querySelector<HTMLButtonElement>('button[aria-label="Save as note"]')!.click());
  const openToast = () => [...document.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Open");
  await settle(() => expect(openToast()).toBeDefined(), 3000);
  await click(railButton("Bea"));
  await settle(() => expect(workspace().dataset.mentorWorkspace).toBe("agent-b"));
  await click(openToast()!);
  await settle(() => expect(workspace().dataset.mentorWorkspace).toBe("agent-a"));
  await settle(() => expect(reader().querySelector("[data-test-note]")).not.toBeNull());
});

it("opens links in a mentor's reply in its reader, once, at the linked lines", async () => {
  sessions[0] = { ...sessions[0], cwd: "/repo", blocks: [{ id: "reading", role: "assistant", text: "请打开 [container-process.md](sources/container-process.md#L1-L3) 研读。" }] };
  await renderMentor();
  const link = () => pane("chat-a").querySelector<HTMLAnchorElement>('a[href^="/repo/sources/container-process.md"]');
  await settle(() => expect(link()).not.toBeNull());
  await click(link()! as unknown as HTMLButtonElement);
  await settle(() => expect(reader().querySelector(".markdown-preview h1")?.textContent).toBe("Container processes"));
  expect(externalOpen).not.toHaveBeenCalled();
  expect(requestPlace).toHaveBeenCalledWith("/repo/sources/container-process.md", { lines: [1, 3] });
  const preview = reader().querySelector(".markdown-preview h1");
  await click(link()! as unknown as HTMLButtonElement);
  expect(container.querySelectorAll(".markdown-preview h1")).toHaveLength(1);
  expect(reader().querySelector(".markdown-preview h1")).toBe(preview);
});

it("finds a lesson with Cmd-K and opens it in its mentor's reader", async () => {
  await act(async () => {
    const original = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (command: string, args: unknown, options: unknown) => command === "course_list_all"
      ? [{ id: "kubernetes", agentId: "agent-a", title: "Kubernetes", engine: "reading", itemCount: 1, masteredCount: 0, updatedAt: 2 }]
      : original(command, args, options);
  });
  await renderMentor("Bea");
  await act(async () => { window.dispatchEvent(new KeyboardEvent("keydown", { key: "k", code: "KeyK", ctrlKey: true, bubbles: true, cancelable: true })); });
  const input = () => container.querySelector<HTMLInputElement>('[data-app-search] input')!;
  await settle(() => expect(input()).not.toBeNull());
  await settle(() => expect(container.querySelector('[data-app-search] [data-search-kind="mentor"]')).not.toBeNull());
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input(), "pod");
    input().dispatchEvent(new Event("input", { bubbles: true }));
  });
  await settle(() => expect(container.querySelector('[data-app-search] [data-search-kind="lesson"]')).not.toBeNull());
  await click(container.querySelector<HTMLButtonElement>('[data-app-search] [data-search-kind="lesson"]')!);
  await settle(() => expect(container.querySelector('[data-mentor-workspace="agent-a"] [data-mentor-reader]')?.textContent).toContain("course-content.pdf"));
  expect(container.querySelector("[data-app-search]")).toBeNull();
});

it("creates a mentor from the gallery while Settings is open and switches to its workspace", async () => {
  localStorage.setItem("loci:agent-roster", "[]");
  // Real IPC takes time; the first-mentor effect must not take over a creation in flight.
  await act(async () => {
    const original = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (command: string, args: unknown, options: unknown) => {
      if (["agent_write", "agent_read", "agent_workdir_create", "agent_workdir_ensure", "session_get"].includes(command)) await new Promise((resolve) => setTimeout(resolve, 150));
      return original(command, args, options);
    };
  });
  await renderApp();
  await settle(() => expect(container.querySelector("[data-mentors-empty]")).not.toBeNull());
  await click(container.querySelector<HTMLButtonElement>('[data-agent-rail] button[aria-label="Settings"]')!);
  await settle(() => expect(container.querySelector("[data-app-settings]")).not.toBeNull());
  await act(async () => { window.dispatchEvent(new KeyboardEvent("keydown", { key: "t", code: "KeyT", ctrlKey: true, bubbles: true, cancelable: true })); });
  await settle(() => expect(document.querySelector("[data-agent-template]")).not.toBeNull());
  await click(document.querySelector<HTMLButtonElement>('[data-agent-template="learning-guide"] button[aria-label^="Add"]')!);
  // The rail and the surface change at once, before the new mentor's conversation is ready.
  expect(container.querySelectorAll("[data-agent-rail] [data-agent-id]")).toHaveLength(1);
  expect(container.querySelector("[data-app-settings]")).toBeNull();
  await settle(() => expect(workspace()).not.toBeNull());
  const created = JSON.parse(localStorage.getItem("loci:agent-roster")!)[0].id;
  expect(workspace().dataset.mentorWorkspace).toBe(created);
  expect(localStorage.getItem(ACTIVE_MENTOR_KEY)).toBe(created);
  expect(railButton("Mentor").getAttribute("aria-current")).toBe("true");
});

it("opens Settings on MCP when the composer asks to manage servers", async () => {
  await renderMentor();
  await act(async () => { window.dispatchEvent(new Event("loci:open-mcp-settings")); });
  await settle(() => expect(container.querySelector("[data-app-settings]")).not.toBeNull());
  expect(localStorage.getItem("loci.settingsSection")).toBe("mcp");
});

it("shows a mentor another window created on the rail at once", async () => {
  await renderMentor();
  const roster = JSON.parse(localStorage.getItem("loci:agent-roster")!);
  localStorage.setItem("loci:agent-roster", JSON.stringify([...roster, { id: "agent-c", name: "Cy", avatar: "loci", color: "#123456", projects: [] }]));
  await act(async () => { window.dispatchEvent(new StorageEvent("storage", { key: "loci:agent-roster" })); });
  expect(container.querySelectorAll("[data-agent-rail] [data-agent-id]")).toHaveLength(3);
  expect(railButton("Cy")).not.toBeNull();
});

it("offers to try again when the first mentor cannot be opened", async () => {
  let fail = true;
  await act(async () => {
    const original = window.__TAURI_INTERNALS__.invoke;
    window.__TAURI_INTERNALS__.invoke = async (command: string, args: unknown, options: unknown) => {
      if (fail && (command === "agent_workdir_create" || command === "home_dir")) throw new Error("disk unavailable");
      if (fail && command === "session_get") return null;
      return original(command, args, options);
    };
  });
  await renderApp();
  await settle(() => expect(container.querySelector("[data-mentors-empty] [role=status]")?.textContent).toBe("Couldn't open Ada."), 3000);
  fail = false;
  const retry = [...container.querySelectorAll<HTMLButtonElement>("[data-mentors-empty] button")].find((button) => button.textContent === "Try again")!;
  expect(retry).toBeDefined();
  await click(retry);
  await settle(() => expect(workspace()?.dataset.mentorWorkspace).toBe("agent-a"));
});
