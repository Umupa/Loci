// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Session } from "../../features/sessions/model/session";
import type { RemoteSessionClient, RemoteSessionsState } from "./remoteSessions";
import { RemoteWorkspace } from "./RemoteWorkspace";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => undefined), emit: vi.fn(async () => undefined) }));
vi.mock("../../features/agents/ui/AgentSessionPane", () => ({
  AgentSessionPane: ({ sessionPaneProps }: { sessionPaneProps: { session: Session } }) => createElement("div", { "data-test-chat": sessionPaneProps.session.id }),
}));

const ROSTER_KEY = "loci:agent-roster";
let root: Root;
let container: HTMLDivElement;
let state: RemoteSessionsState;
/** What was sent, in order: the host's intents, and the window's own reads. */
let sent: string[];
let finishOpen: (id: string | null) => void;
const listeners = new Set<() => void>();

const client = {
  subscribe: (listener: () => void) => { listeners.add(listener); return () => listeners.delete(listener); },
  getSnapshot: () => state,
  intents: new Proxy({}, { get: () => async () => undefined }),
  openAgent: vi.fn((agentId: string) => {
    sent.push(`agent.open ${agentId}`);
    return new Promise<string | null>((resolve) => { finishOpen = resolve; });
  }),
  view: vi.fn((ids: string[]) => { sent.push(`session.view ${ids.join(",")}`); }),
  sessionWithEarlier: (session: Session) => session,
  hasEarlier: () => false,
  loadEarlier: async () => undefined,
  clearError: () => undefined,
  connect: async () => undefined,
  refreshModels: async () => undefined,
  inspectBinary: async () => undefined,
} as unknown as RemoteSessionClient;

function setSessions(sessions: Session[]) {
  state = { ...state, sessions };
  act(() => { for (const listener of listeners) listener(); });
}

const session = (id: string) => ({ id, title: "Ada", harness: "claude", blocks: [], busy: false } as unknown as Session);

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  vi.clearAllMocks();
  sent = [];
  state = { status: { state: "connected" }, sessions: [], earlier: new Map(), error: null };
  vi.mocked(invoke).mockImplementation(async (command) => {
    sent.push(command);
    if (command === "course_path_read") return { path: null };
    if (command === "agent_read") return { text: "[]", hash: "h" };
    if (command.endsWith("_list") || command === "course_list_all") return [];
    return null;
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

async function open(roster: { id: string; sessionId?: string }[]) {
  localStorage.setItem(ROSTER_KEY, JSON.stringify(roster.map((agent) => ({ name: "Ada", avatar: "loci", color: "#123456", projects: [], ...agent }))));
  await act(async () => root.render(createElement(RemoteWorkspace, { client })));
}

it("opens a mentor with a known conversation without waiting for the host to open it", async () => {
  await open([{ id: "ada", sessionId: "chat-a" }]);
  // The host hears what is shown before it opens the conversation, so it holds both.
  expect(sent.indexOf("session.view chat-a")).toBeGreaterThanOrEqual(0);
  expect(sent.indexOf("session.view chat-a")).toBeLessThan(sent.indexOf("agent.open ada"));
  // `agent.open` has not answered, yet the workspace is up and reading.
  expect(container.querySelector('[data-mentor-workspace="ada"]')).not.toBeNull();
  for (const read of ["course_list_all", "agent_documents_list", "notes_list", "course_path_read"]) expect(sent).toContain(read);
  setSessions([session("chat-a")]);
  await act(async () => finishOpen("chat-a"));
  expect(container.querySelector('[data-test-chat="chat-a"]')).not.toBeNull();
  // The same conversation all along.
  expect(new Set(vi.mocked(client.view).mock.calls.map(([ids]) => ids.join(",")).filter(Boolean))).toEqual(new Set(["chat-a"]));
});

it("moves to the new conversation the host opens for an empty one", async () => {
  await open([{ id: "ada", sessionId: "chat-old" }]);
  expect(container.textContent).toContain("Opening the conversation…");
  setSessions([session("chat-new")]);
  await act(async () => finishOpen("chat-new"));
  expect(client.view).toHaveBeenLastCalledWith(["chat-new"]);
  expect(container.querySelector('[data-test-chat="chat-new"]')).not.toBeNull();
  expect(container.textContent).not.toContain("Opening the conversation…");
});

it("waits for the host when no conversation is known", async () => {
  await open([{ id: "ada" }]);
  expect(sent.filter((entry) => entry !== "session.view ")).toEqual(["agent.open ada"]);
  expect(container.querySelector("[data-mentor-workspace]")).toBeNull();
  setSessions([session("chat-new")]);
  await act(async () => finishOpen("chat-new"));
  expect(container.querySelector('[data-test-chat="chat-new"]')).not.toBeNull();
  expect(sent).toContain("course_list_all");
});
