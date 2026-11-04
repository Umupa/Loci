// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Habit } from "../../features/agents/model/agentHabits";
import { newSession, type Session } from "../../features/sessions/model/session";
import type { TurnOutcome } from "../../features/sessions/model/turnOutcome";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

let stored: Habit[] = [];
let fileVersion = 0;
/** heartbeat.json, apart from habits.json. */
let heartbeat: Record<string, unknown> | undefined;
let heartbeatVersion = 0;
const AGENT = { id: "agent-1", sessionId: "chat", avatar: "ember", color: "#fff", projects: ["/code/app"] };

const respond = vi.hoisted(() => vi.fn());
vi.mock("../../integrations/harness/core/registry", () => ({
  forgetHarnessSession: vi.fn(async () => undefined),
  respondHarnessApproval: respond,
}));
vi.mock("../../features/agents/model/agent", async (original) => ({
  ...(await original<object>()),
  listAgents: () => [AGENT],
  findAgent: (id: string) => (id === AGENT.id ? AGENT : undefined),
  agentForSession: (id: string) => (id === AGENT.sessionId ? AGENT : undefined),
}));
vi.mock("../../features/agents/model/agentFiles", async (original) => {
  const actual = await original<typeof import("../../features/agents/model/agentFiles")>();
  const files = {
    ...actual,
    loadAgentFiles: vi.fn(async () => ({
      id: "a", dir: "/data/agents/a", soul: "Be brief.", soulHash: "s",
      memory: "", memoryHash: "m", memoryPath: "/data/agents/a/MEMORY.md", topics: [],
    })),
    readAgentFile: vi.fn(async (_agentId, path) => path === "heartbeat.json"
      ? { text: heartbeat ? JSON.stringify(heartbeat) : null, hash: `hb${heartbeatVersion}` }
      : { text: JSON.stringify(stored), hash: String(fileVersion) }),
    // Model the native store's atomic compare-and-save.
    writeAgentFile: vi.fn(async (_agentId, path, text, expectedHash) => {
      if (path === "heartbeat.json") {
        if (expectedHash !== `hb${heartbeatVersion}`) throw new actual.AgentFileConflict();
        heartbeat = JSON.parse(text) as Record<string, unknown>;
        return `hb${++heartbeatVersion}`;
      }
      if (expectedHash !== String(fileVersion)) throw new actual.AgentFileConflict();
      stored = JSON.parse(text) as Habit[];
      return String(++fileVersion);
    }),
    // Over the mocked read and save, as the real one does over the native store.
    editAgentFile: vi.fn(async (agentId: string, path: "heartbeat.json", edit: (text: string) => string): Promise<string> => {
      for (let attempt = 0; ; attempt++) {
        const current = await files.readAgentFile(agentId, path);
        try {
          return await files.writeAgentFile(agentId, path, edit(current.text ?? ""), current.hash);
        } catch (error) {
          if (!(error instanceof actual.AgentFileConflict) || attempt >= 2) throw error;
        }
      }
    }),
  };
  return files;
});

const { useAgentHabits } = await import("./useAgentHabits");

let root: Root;
let sessions: Session[];
let approve: ReturnType<typeof useAgentHabits>["approve"];
let posted: string[];
/** What a hidden run does when its turn is sent. */
let turn: (run: Session, prompt: string) => Promise<TurnOutcome>;
const stopped: string[] = [];
const ownApprovals = vi.fn();

const habit = (over: Partial<Habit> = {}): Habit => ({
  id: "h1", name: "Morning CI check", instructions: "Check CI.", enabled: true, createdAt: 0,
  schedule: { scheduleKind: "daily", time: "09:00", minute: 0, dayOfWeek: 1 },
  nextRunAt: Date.now() - 1_000, ...over,
});

async function mount() {
  const sessionsRef = { get current() { return sessions; }, set current(next: Session[]) { sessions = next; } };
  const runtime = {
    sessionsRef,
    updateSessions: (update: Session[] | ((current: Session[]) => Session[])) => { sessions = typeof update === "function" ? update(sessions) : update; },
    persistSession: vi.fn(async () => undefined),
    bindRestoredSession: vi.fn(),
  } as unknown as SessionRuntime;
  const submission = {
    runTurn: (id: string, prompt: string) => turn(sessions.find((session) => session.id === id)!, prompt),
    stopSessionWork: async (id: string) => void stopped.push(id),
    approve: ownApprovals,
  } as unknown as SessionSubmission;
  function Harness() {
    approve = useAgentHabits({ runtime, submission, loadSession: async () => null, onPosted: (_chat, name) => void posted.push(name) }).approve;
    return null;
  }
  root = createRoot(document.createElement("div"));
  await act(async () => root.render(createElement(Harness)));
}

const chat = () => sessions.find((session) => session.id === "chat")!;

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  stored = [];
  fileVersion = 0;
  heartbeat = { minutes: 0 };
  heartbeatVersion = 0;
  posted = [];
  stopped.length = 0;
  respond.mockReset();
  ownApprovals.mockReset();
  sessions = [{ ...newSession("codex", "/home/me", "codex:test", "auto"), id: "chat" }];
  turn = async () => ({ status: "completed", text: "NOTHING_TO_REPORT" });
});
afterEach(async () => {
  await act(async () => root?.unmount());
});

it("runs a due habit in a hidden full-access session and posts what it found", async () => {
  stored = [habit()];
  let run: Session | undefined;
  let prompt = "";
  turn = async (session, text) => {
    run = session;
    prompt = text;
    return { status: "completed", text: "CI is red on main: the lint job fails." };
  };
  await mount();
  await vi.waitFor(() => expect(stored[0].lastOutcome).toBe("posted"));
  expect(run).toMatchObject({ ephemeral: true, runtimeMode: "full-access", harness: "codex", model: "codex:test", title: "Ember · Morning CI check" });
  expect(prompt.startsWith("<agent>")).toBe(true);
  expect(prompt).toContain("Habit: Morning CI check");
  expect(prompt).toContain("Be brief.");
  // The run is gone; only its message stays, marked as the habit's.
  expect(sessions.map((session) => session.id)).toEqual(["chat"]);
  expect(stopped).toEqual([run!.id]);
  expect(chat().blocks).toMatchObject([{ role: "assistant", text: "CI is red on main: the lint job fails.", agentHabit: { id: "h1", name: "Morning CI check" } }]);
  expect(posted).toEqual(["Ember"]);
  expect(stored[0].runs).toMatchObject([{ outcome: "posted", report: "CI is red on main: the lint job fails." }]);
  expect(stored[0].nextRunAt).toBeGreaterThan(Date.now());
});

it("stays quiet when the run has nothing to report, and records a failure without posting", async () => {
  stored = [habit(), habit({ id: "h2", name: "Flaky" })];
  turn = async (session) => session.title.endsWith("Flaky")
    ? { status: "failed", text: "", error: "Not signed in" }
    : { status: "completed", text: "NOTHING_TO_REPORT" };
  await mount();
  await vi.waitFor(() => expect(stored.map((entry) => entry.lastOutcome)).toEqual(["quiet", "failed"]));
  expect(chat().blocks).toEqual([]);
  expect(posted).toEqual([]);
  expect(stored[1].lastError).toBe("Not signed in");
});

it("skips a habit missed long ago instead of catching up", async () => {
  stored = [habit({ nextRunAt: Date.now() - 3 * 60 * 60 * 1000 })];
  const ran = vi.fn();
  turn = async () => { ran(); return { status: "completed", text: "late" }; };
  await mount();
  await vi.waitFor(() => expect(stored[0].nextRunAt).toBeGreaterThan(Date.now()));
  expect(ran).not.toHaveBeenCalled();
  expect(stored[0].lastRunAt).toBeUndefined();
});

it("puts a run's approval to the user in the agent's chat and routes the answer back", async () => {
  stored = [habit()];
  let finish!: (outcome: TurnOutcome) => void;
  let runId = "";
  turn = (session) => {
    runId = session.id;
    sessions = sessions.map((entry) => entry.id === session.id
      ? { ...entry, blocks: [{ id: "ask", role: "approval", text: "git push", tool: { title: "git push" }, approval: { requestId: 7 } } as Session["blocks"][number]] } : entry);
    return new Promise((resolve) => { finish = resolve; });
  };
  await mount();
  await vi.waitFor(() => expect(chat().blocks).toHaveLength(1), { timeout: 5_000 });
  const asked = chat().blocks[0];
  expect(asked).toMatchObject({ role: "approval", text: "git push", agentHabit: { id: "h1" } });
  expect(asked.approval!.requestId).not.toBe(7);
  await act(async () => approve("chat", asked.approval!.requestId, "allow"));
  expect(respond).toHaveBeenCalledWith("codex", runId, 7, "allow");
  expect(chat().blocks[0].approval!.decided).toBe("allow");
  expect(ownApprovals).not.toHaveBeenCalled();
  // The conversation's own approvals are untouched.
  await act(async () => approve("chat", 3, "deny"));
  expect(ownApprovals).toHaveBeenCalledWith("chat", 3, "deny");
  finish({ status: "completed", text: "Pushed the fix." });
  await vi.waitFor(() => expect(stored[0].lastOutcome).toBe("posted"));
});

const MIN = 60_000;
const said = (startedAt: number): Session["blocks"] => [
  { id: "u", role: "user", text: "Can you find the Pin RFC later?", startedAt, durationMs: 1_000 },
  { id: "r", role: "assistant", text: "Sure, I will look for it." },
];

it("wakes its heartbeat once the chat sits idle and posts what it proposes", async () => {
  heartbeat = { lastRunAt: Date.now() - 50 * MIN, quietStreak: 2, recent: [], memoryHash: "m" };
  sessions[0] = { ...sessions[0], blocks: said(Date.now() - 40 * MIN) };
  let run: Session | undefined;
  let prompt = "";
  turn = async (session, text) => {
    run = session;
    prompt = text;
    return { status: "completed", text: "Shall I look for the Pin RFC now?" };
  };
  await mount();
  await vi.waitFor(() => expect(chat().blocks).toHaveLength(3));
  expect(run).toMatchObject({ ephemeral: true, runtimeMode: "auto", harness: "codex", title: "Ember · Heartbeat" });
  expect(prompt).toContain("[Heartbeat]");
  expect(prompt).toContain("User: Can you find the Pin RFC later?");
  expect(chat().blocks[2]).toMatchObject({ role: "assistant", text: "Shall I look for the Pin RFC now?", agentHabit: { id: "heartbeat", name: "Heartbeat" } });
  expect(posted).toEqual(["Ember"]);
  // The user wrote since the last one, so the streak started over.
  await vi.waitFor(() => expect(heartbeat).toMatchObject({ quietStreak: 0, recent: ["Shall I look for the Pin RFC now?"] }));
  expect(heartbeat!.lastRunAt).toBeGreaterThan(Date.now() - MIN);
  expect(sessions.map((session) => session.id)).toEqual(["chat"]);
});

it("drops a quiet heartbeat without a trace in the chat", async () => {
  heartbeat = { lastRunAt: Date.now() - 50 * MIN, quietStreak: 0, recent: [], memoryHash: "m" };
  sessions[0] = { ...sessions[0], blocks: said(Date.now() - 40 * MIN) };
  const ran = vi.fn();
  turn = async () => { ran(); return { status: "completed", text: "Nothing new.\n\nNOTHING_TO_REPORT" }; };
  await mount();
  await vi.waitFor(() => expect(heartbeat).toMatchObject({ quietStreak: 1 }));
  expect(ran).toHaveBeenCalledTimes(1);
  expect(chat().blocks).toHaveLength(2);
  expect(posted).toEqual([]);
  expect(sessions.map((session) => session.id)).toEqual(["chat"]);
});

it("only marks where its heartbeat starts, and skips the model when nothing moved", async () => {
  const ran = vi.fn();
  turn = async () => { ran(); return { status: "completed", text: "Something" }; };
  heartbeat = {};
  sessions[0] = { ...sessions[0], blocks: said(Date.now() - 400 * MIN) };
  await mount();
  await vi.waitFor(() => expect(heartbeat!.lastRunAt).toBeGreaterThan(0));
  await act(async () => root.unmount());

  heartbeat = { lastRunAt: Date.now() - 200 * MIN, quietStreak: 0, recent: [], memoryHash: "m" };
  await mount();
  await vi.waitFor(() => expect(heartbeat!.lastRunAt).toBeGreaterThan(Date.now() - MIN));
  expect(ran).not.toHaveBeenCalled();
  expect(chat().blocks).toHaveLength(2);
});

it("leaves the heartbeat alone when it is turned off", async () => {
  heartbeat = { minutes: 0, lastRunAt: Date.now() - 500 * MIN, quietStreak: 0, recent: [] };
  sessions[0] = { ...sessions[0], blocks: said(Date.now() - 400 * MIN) };
  const ran = vi.fn();
  turn = async () => { ran(); return { status: "completed", text: "Something" }; };
  await mount();
  await act(async () => new Promise((resolve) => setTimeout(resolve, 50)));
  expect(ran).not.toHaveBeenCalled();
  expect(heartbeatVersion).toBe(0);
});
