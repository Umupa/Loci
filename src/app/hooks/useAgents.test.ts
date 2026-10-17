// @vitest-environment happy-dom
import { act, createElement, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { createAgent, findAgent, listAgents, updateAgent } from "../../features/agents/model/agent";
import { newSession, type Block, type Session } from "../../features/sessions/model/session";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";
import { useAgents } from "./useAgents";

const mocks = vi.hoisted(() => ({
  ask: vi.fn(), deleteSession: vi.fn(), archive: vi.fn(), page: vi.fn(),
  stop: vi.fn(), flush: vi.fn(), persist: vi.fn(), error: vi.fn(),
  show: vi.fn(), replace: vi.fn(), remove: vi.fn(), submit: vi.fn(),
  loadFiles: vi.fn(), saveFile: vi.fn(),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: mocks.ask }));
vi.mock("../../platform/tauri/fs", () => ({ homeDir: vi.fn(async () => "/home/me") }));
vi.mock("../../integrations/harness/core/registry", () => ({ forgetHarnessSession: vi.fn(async () => undefined) }));
vi.mock("../../features/sessions/data/sessionStore", async (original) => ({ ...(await original<object>()), deleteSession: mocks.deleteSession }));
vi.mock("../../features/agents/model/agentTranscript", async (original) => ({
  ...(await original<object>()), archiveOlderTurns: mocks.archive, loadTranscriptPage: mocks.page,
}));
vi.mock("../../features/canvas/canvas", () => ({ loadCanvases: vi.fn(async () => []), deleteCanvas: vi.fn() }));
vi.mock("../../features/agents/model/agentDocuments", () => ({ saveAgentDocuments: vi.fn(), deleteAgentDocument: vi.fn(async () => undefined) }));
vi.mock("../../features/agents/model/agentFiles", () => ({
  forgetAgentContext: vi.fn(), loadAgentFiles: mocks.loadFiles, saveAgentFile: mocks.saveFile,
}));
vi.mock("../../features/agents/model/agentRotation", () => ({ forgetAgentRotation: vi.fn() }));

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
  const agent = createAgent([], { name: sessionId });
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

it("opens an agent ready for an editable first task without starting a model or opening details", async () => {
  await mount();
  await act(async () => agents.create());
  const agent = listAgents()[0];
  expect(agent.sessionId).toBe(liveSessions[0].id);
  expect(liveSessions[0].blocks).toEqual([]);
  expect(mocks.show).toHaveBeenCalledWith(agent.id, liveSessions[0]);
  expect(agents.isDetailsOpen(agent.id)).toBe(false);
  expect(mocks.submit).not.toHaveBeenCalled();
  expect(mocks.saveFile).not.toHaveBeenCalled();
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

it("replaces the reset conversation in its existing panes and preserves agent details", async () => {
  const id = addAgent("chat");
  visible = new Set(["chat"]);
  await mount();
  await act(async () => { agents.select(id); agents.setDetailsOpenFor(id, true); });
  await act(async () => agents.reset(id));
  expect(mocks.replace).toHaveBeenCalledWith("chat", expect.objectContaining({ cwd: "/home/me", blocks: [] }));
  expect(mocks.remove).not.toHaveBeenCalled();
  const fresh = mocks.replace.mock.calls[0][1] as Session;
  expect(fresh.id).not.toBe("chat");
  expect(findAgent(id)?.sessionId).toBe(fresh.id);
  expect(liveSessions.map((session) => session.id)).toEqual([fresh.id]);
  expect(agents.isDetailsOpen(id)).toBe(true);
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
