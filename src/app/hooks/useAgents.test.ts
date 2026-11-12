// @vitest-environment happy-dom
import { act, createElement, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { createAgent, findAgent, listAgents, updateAgent } from "../../features/agents/model/agent";
import { newSession, type Block, type Session } from "../../features/sessions/model/session";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";
import { deleteQuestion, useAgents } from "./useAgents";
import { createSessionHost } from "./useSessionHost";
import { MENTOR_VIEW_KEY } from "./useMentorView";
import { ACTIVE_MENTOR_KEY } from "./useActiveMentor";
import { recalledPosition, rememberPosition } from "../../features/mentor/model/readingPositions";

const mocks = vi.hoisted(() => ({
  ask: vi.fn(), deleteSession: vi.fn(), archive: vi.fn(), page: vi.fn(),
  stop: vi.fn(), flush: vi.fn(), persist: vi.fn(), error: vi.fn(),
  show: vi.fn(), replace: vi.fn(), remove: vi.fn(), submit: vi.fn(),
  loadFiles: vi.fn(), saveFile: vi.fn(), editFile: vi.fn(),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: mocks.ask }));
vi.mock("../../platform/tauri/fs", () => ({ homeDir: vi.fn(async () => "/home/me") }));
vi.mock("../../integrations/harness/core/registry", () => ({ forgetHarnessSession: vi.fn(async () => undefined) }));
vi.mock("../../features/sessions/data/sessionStore", async (original) => ({ ...(await original<object>()), deleteSession: mocks.deleteSession }));
vi.mock("../../features/agents/model/agentTranscript", async (original) => ({
  ...(await original<object>()), archiveOlderTurns: mocks.archive, loadTranscriptPage: mocks.page,
}));
vi.mock("../../features/agents/model/agentDocuments", () => ({ saveAgentDocuments: vi.fn(), deleteAgentDocument: vi.fn(async () => undefined) }));
vi.mock("../../features/agents/model/agentFiles", () => ({
  forgetAgentContext: vi.fn(), loadAgentFiles: mocks.loadFiles, saveAgentFile: mocks.saveFile, editAgentFile: mocks.editFile,
}));
vi.mock("../../features/agents/model/agentRotation", () => ({ forgetAgentRotation: vi.fn(), saveAgentRotation: vi.fn() }));

let root: Root | undefined;
let initialSessions: Session[];
let liveSessions: Session[];
let agents: ReturnType<typeof useAgents>;
let visible: ReadonlySet<string>;
let loadSession: (id: string) => Promise<Session | null>;

function Harness({ shown }: { shown: ReadonlySet<string> }) {
  const [sessions, updateSessions] = useState(initialSessions);
  liveSessions = sessions;
  const runtime = {
    sessions, updateSessions, sessionsRef: { get current() { return liveSessions; } },
    bindRestoredSession: vi.fn(), persistSession: mocks.persist, flushPersistence: mocks.flush,
  } as unknown as SessionRuntime;
  const submission = { stopSessionWork: mocks.stop, submit: mocks.submit } as unknown as SessionSubmission;
  agents = useAgents({
    runtime, submission, loadSession: (id) => loadSession(id),
    onError: mocks.error, onShow: mocks.show, onReplaceSession: mocks.replace,
    onRemoveSession: mocks.remove, visibleSessionIds: shown,
  });
  return null;
}

async function mount() {
  root = createRoot(document.createElement("div"));
  await act(async () => root!.render(createElement(Harness, { shown: visible })));
}
async function show(ids: string[]) {
  visible = new Set(ids);
  await act(async () => root!.render(createElement(Harness, { shown: visible })));
}
function addAgent(sessionId: string, blocks: Block[] = []) {
  const agent = createAgent({ name: sessionId });
  updateAgent(agent.id, (current) => ({ ...current, sessionId }));
  const session = { ...newSession("codex", "/home/me", "codex:test", "auto"), id: sessionId, blocks };
  initialSessions.push(session);
  return agent.id;
}
function longChat(id: string): Block[] {
  return Array.from({ length: 61 }, (_, index) => ({ id: `${id}-${index}`, role: "user", text: `Turn ${index}` }));
}
function page(id: string, seq: number, hasOlder = false) {
  return { seq, hasOlder, blocks: [{ id: `${id}-${seq}`, role: "user", text: `${id} page ${seq}` }] };
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  vi.clearAllMocks();
  mocks.ask.mockResolvedValue(true);
  mocks.deleteSession.mockResolvedValue(undefined);
  mocks.stop.mockResolvedValue(undefined);
  mocks.flush.mockResolvedValue(undefined);
  mocks.persist.mockResolvedValue(undefined);
  mocks.loadFiles.mockResolvedValue({ soulHash: "initial" });
  mocks.saveFile.mockResolvedValue("saved");
  mocks.page.mockResolvedValue(undefined);
  mocks.archive.mockImplementation(async (session: Session) => session.blocks.slice(-40));
  root = undefined;
  initialSessions = [];
  liveSessions = initialSessions;
  visible = new Set();
  loadSession = async (id) => liveSessions.find((session) => session.id === id) ?? null;
});
afterEach(async () => {
  await act(async () => root?.unmount());
  vi.unstubAllGlobals();
});

it("opens an agent ready for an editable first task without starting a model", async () => {
  await mount();
  await act(async () => agents.create());
  const agent = listAgents()[0];
  expect(agent.sessionId).toBe(liveSessions[0].id);
  expect(liveSessions[0].blocks).toEqual([]);
  expect(mocks.show).toHaveBeenCalledWith(agent.id, liveSessions[0]);
  expect(mocks.submit).not.toHaveBeenCalled();
  expect(mocks.saveFile).not.toHaveBeenCalled();
});

it("starts an agent from a template with its look and Soul in place before it opens", async () => {
  const { AGENT_TEMPLATES } = await import("../../features/agents/templates");
  const template = AGENT_TEMPLATES.find((entry) => entry.id === "repo-lens")!;
  mocks.editFile.mockImplementation(async () => {
    expect(mocks.show).not.toHaveBeenCalled();
    return "hash";
  });
  await mount();
  await act(async () => agents.create(template));
  const agent = listAgents()[0];
  expect(agent).toMatchObject({ name: "Lens", role: "Open-source reader", avatar: "tide" });
  expect(mocks.editFile).toHaveBeenCalledWith(agent.id, "soul", expect.any(Function));
  expect(mocks.editFile.mock.calls[0][2]("")).toContain("You read an open-source repository");
  expect(mocks.show).toHaveBeenCalledWith(agent.id, liveSessions[0]);
});

it("protects every visible agent conversation from archiving, including unfocused panes", async () => {
  addAgent("first", longChat("first"));
  addAgent("second", longChat("second"));
  addAgent("hidden", longChat("hidden"));
  visible = new Set(["first", "second"]);
  await mount();
  expect(mocks.archive).toHaveBeenCalledOnce();
  expect(mocks.archive.mock.calls[0][0].id).toBe("hidden");
  expect(liveSessions.find((session) => session.id === "first")!.blocks).toHaveLength(61);
  expect(liveSessions.find((session) => session.id === "second")!.blocks).toHaveLength(61);
  expect(liveSessions.find((session) => session.id === "hidden")!.blocks).toHaveLength(40);
});

it("keeps each visible agent's archived history when another pane receives focus", async () => {
  const first = addAgent("first");
  const second = addAgent("second");
  visible = new Set(["first", "second"]);
  mocks.page.mockImplementation(async (id: string, before?: number) => page(id, before == null ? 2 : 1, before == null));
  await mount();
  await act(async () => { agents.select(first); await agents.loadEarlier("first"); });
  await act(async () => { agents.select(second); await agents.loadEarlier("second"); });
  expect(agents.earlierBlocksFor("first")).toEqual(page("first", 2).blocks);
  expect(agents.earlierBlocksFor("second")).toEqual(page("second", 2).blocks);
  await act(async () => { agents.select(first); await agents.loadEarlier("first"); });
  expect(agents.earlierBlocksFor("first")).toEqual([...page("first", 1).blocks, ...page("first", 2).blocks]);
  expect(agents.hasEarlier("first")).toBe(false);
  expect(agents.hasEarlier("second")).toBe(true);
  expect(agents.viewAgent?.id).toBe(first);
});

it("does not remove live turns when their pane opens during archiving, or repeat them in history", async () => {
  const blocks = longChat("chat");
  addAgent("chat", blocks);
  let finish!: (kept: Block[]) => void;
  mocks.archive.mockImplementation(() => new Promise((resolve) => { finish = resolve; }));
  await mount();
  mocks.page.mockResolvedValue({ seq: 1, blocks: blocks.slice(0, 21), hasOlder: false });
  await show(["chat"]);
  await act(async () => finish(blocks.slice(-40)));
  expect(liveSessions[0].blocks).toHaveLength(61);
  await act(async () => agents.loadEarlier("chat"));
  expect(agents.earlierBlocksFor("chat")).toEqual([]);
  expect(mocks.persist).not.toHaveBeenCalled();
});

it("starts the conversation over in place, deleting nothing and asking nothing", async () => {
  const said: Block[] = [{ id: "u1", role: "user", text: "hi" }, { id: "a1", role: "assistant", text: "hello" }];
  const id = addAgent("chat", said);
  visible = new Set(["chat"]);
  await mount();
  await act(async () => { agents.select(id); });
  await act(async () => { expect(await agents.reset(id)).toBe(true); });
  expect(mocks.ask).not.toHaveBeenCalled();
  expect(mocks.deleteSession).not.toHaveBeenCalled();
  expect(mocks.replace).not.toHaveBeenCalled();
  expect(findAgent(id)?.sessionId).toBe("chat");
  const [chat] = liveSessions;
  expect(chat.id).toBe("chat");
  expect(chat.blocks.slice(0, 2)).toEqual(said);
  expect(chat.blocks[2].role).toBe("divider");
  expect(chat.providerSessionId).toBeUndefined();
  expect(mocks.persist).toHaveBeenCalledWith("chat");
});

it("says what deleting a mentor throws away, and forgets what the window kept about it", async () => {
  const id = addAgent("chat");
  const other = addAgent("other");
  localStorage.setItem(MENTOR_VIEW_KEY, JSON.stringify({ [id]: { library: true }, [other]: { library: false } }));
  localStorage.setItem(`loci.noteTarget.${id}`, JSON.stringify({ kind: "new" }));
  localStorage.setItem(`loci.noteTarget.${other}`, JSON.stringify({ kind: "new" }));
  localStorage.setItem(ACTIVE_MENTOR_KEY, id);
  rememberPosition(id, "document:d", { ratio: 0.5 });
  await mount();
  await act(async () => agents.remove(id));
  const [question] = mocks.ask.mock.calls[0] as [string];
  expect(question).toBe(deleteQuestion("chat"));
  expect(question).toMatch(/folder \(sources, courses, notes, repos and memory\) moves to the Trash/);
  expect(question).toMatch(/conversation, highlights and progress are deleted/);
  expect(mocks.deleteSession).toHaveBeenCalledWith("chat");
  expect(Object.keys(JSON.parse(localStorage.getItem(MENTOR_VIEW_KEY)!))).toEqual([other]);
  expect(localStorage.getItem(`loci.noteTarget.${id}`)).toBeNull();
  expect(localStorage.getItem(`loci.noteTarget.${other}`)).not.toBeNull();
  expect(localStorage.getItem(ACTIVE_MENTOR_KEY)).toBeNull();
  expect(recalledPosition(id, "document:d")).toBeUndefined();
  expect(findAgent(other)).toBeDefined();
});

it("does not delete anything when the question is declined", async () => {
  const id = addAgent("chat");
  mocks.ask.mockResolvedValue(false);
  await mount();
  let removed: boolean | undefined;
  await act(async () => { removed = await agents.remove(id); });
  expect(removed).toBe(false);
  expect(mocks.deleteSession).not.toHaveBeenCalled();
  expect(findAgent(id)).toBeDefined();
});

it("removes panes for a deleted agent even when its conversation was not loaded", async () => {
  const id = addAgent("chat");
  initialSessions = [];
  await mount();
  await act(async () => agents.remove(id));
  expect(mocks.remove).toHaveBeenCalledWith("chat");
  expect(findAgent(id)).toBeUndefined();
});

it("does not let a pending open override a later pane selection", async () => {
  const first = addAgent("first");
  const second = addAgent("second");
  let finish!: (session: Session) => void;
  loadSession = () => new Promise((resolve) => { finish = resolve; });
  await mount();
  let opening!: Promise<void>;
  await act(async () => { opening = agents.open(first); agents.select(second); });
  await act(async () => { finish(initialSessions[0]); await opening; });
  expect(mocks.show).not.toHaveBeenCalled();
  expect(agents.viewAgent?.id).toBe(second);
});

it("leaves older turns in a conversation a connected device views", async () => {
  addAgent("remote", longChat("remote"));
  addAgent("hidden", longChat("hidden"));
  let leased: string[] = [];
  const host = createSessionHost({ intents: () => { throw new Error("unused"); }, feed: { snapshot: () => { throw new Error("unused"); } }, onLeases: (ids) => { leased = ids; } });
  await host.handle({ requestId: "view-1", connectionId: "mac-mini", name: "session.view", args: [["remote"]] });
  // App.tsx counts the leased ids as shown, beside what its own window shows.
  visible = new Set(leased);
  await mount();
  expect(mocks.archive.mock.calls.map(([session]) => session.id)).toEqual(["hidden"]);
  expect(liveSessions.find((session) => session.id === "remote")!.blocks).toHaveLength(61);
});
