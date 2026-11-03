// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, type Session } from "../../features/sessions/model/session";
import { sessionIntents, type SessionIntents } from "../remote/sessionIntents";
import type { SessionFeed } from "../remote/sessionFeed";
import { createSessionHost, useSessionHost, type RemoteIntent } from "./useSessionHost";

const native = vi.hoisted(() => ({
  label: "main",
  call: vi.fn(),
  listen: vi.fn(),
  intent: undefined as ((event: { payload: RemoteIntent }) => void) | undefined,
  status: undefined as ((event: { payload: { enabled: boolean } }) => void) | undefined,
}));
vi.mock("../../platform/native", () => ({ getCurrentWindow: () => ({ label: native.label }) }));
vi.mock("../../platform/transport", () => ({ transport: { call: native.call, listen: native.listen } }));

/** Every source function is a mock that answers with its own name. */
function recorder<T extends object>(): T {
  const fns = new Map<string, ReturnType<typeof vi.fn>>();
  return new Proxy({}, {
    get: (_, key: string) => fns.get(key) ?? fns.set(key, vi.fn((..._args: unknown[]) => `${key} result`)).get(key),
  }) as T;
}

function sources() {
  let sessions = [{ ...newSession("claude", "/w"), id: "s", noteCard: { id: "n" } } as Session];
  const updateSessions = vi.fn((update: Session[] | ((current: Session[]) => Session[])) => {
    sessions = typeof update === "function" ? update(sessions) : update;
  });
  const agents = recorder<Parameters<typeof sessionIntents>[0]["agents"]>();
  vi.mocked(agents.chat).mockResolvedValue({ id: "agent-chat" } as Session);
  const parts = {
    submission: recorder<Parameters<typeof sessionIntents>[0]["submission"]>(),
    agents,
    agentHabits: recorder<Parameters<typeof sessionIntents>[0]["agentHabits"]>(),
    store: recorder<Parameters<typeof sessionIntents>[0]["store"]>(),
    updateSessions,
    roster: recorder<NonNullable<Parameters<typeof sessionIntents>[0]["roster"]>>(),
  };
  return { parts, sessions: () => sessions };
}

/** Every argument each source received, by source. */
function calls(parts: ReturnType<typeof sources>["parts"]) {
  const seen: Record<string, unknown> = {};
  for (const [name, source] of Object.entries(parts)) {
    if (typeof source === "function") { seen[name] = vi.mocked(source).mock.calls.length; continue; }
    for (const key of ["onSubmit", "stop", "approve", "answer", "keepQuestionOpen", "changeModel", "changeModelSettings",
      "changeRuntimeMode", "compact", "saveDraft", "removeDraft", "deleteQueuedMessage", "editQueuedMessage",
      "queuedMessageEditingChange", "steerQueuedMessage", "resumeQueue", "usageLimitResume", "usageLimitResumeAtReset",
      "usageLimitDismiss", "btwSubmit", "btwRetry", "btwStop", "btwDelete", "btwModelChange", "archiveSession",
      "removeSession", "chat", "create", "reset", "remove", "update", "reorder"]) {
      const fn = (source as Record<string, ReturnType<typeof vi.fn>>)[key];
      if (fn.mock.calls.length) seen[`${name}.${key}`] = fn.mock.calls;
    }
  }
  return seen;
}

const ARGS: Record<keyof SessionIntents, unknown[]> = {
  "session.submit": ["s", "hello", [], { followUpBehavior: "queue" }],
  "session.stop": ["s"],
  "session.approve": ["s", 7, "allow"],
  "session.answer": ["s", 8, { answers: { q: "yes" } }],
  "session.keepQuestionOpen": ["s", 8],
  "session.changeModel": ["s", "codex", "codex:test"],
  "session.changeModelSettings": ["s", { effort: "high" }],
  "session.changeRuntimeMode": ["s", "auto"],
  "session.compact": ["s"],
  "session.saveDraft": ["s", "draft", []],
  "session.removeDraft": ["s", "draft-1"],
  "session.queue.delete": ["s", "q1"],
  "session.queue.edit": ["s", "q1", "edited"],
  "session.queue.editing": ["s", "q1"],
  "session.queue.steer": ["s", "q1"],
  "session.queue.resume": ["s"],
  "session.usageLimit.resume": ["s"],
  "session.usageLimit.resumeAtReset": ["s", true],
  "session.usageLimit.dismiss": ["s"],
  "session.btw.submit": ["s", [], "t1", "m1", "aside"],
  "session.btw.retry": ["s", [], "t1"],
  "session.btw.stop": ["s", [], "t1"],
  "session.btw.delete": ["s", [], "t1"],
  "session.btw.modelChange": ["s", [], "t1", "claude", "claude:test"],
  "session.dismissNoteCard": ["s"],
  "session.archive": ["s", true],
  "session.delete": ["s", { confirmed: true }],
  "agent.open": ["agent-1"],
  "agent.create": [{ id: "tutor", name: "Tutor" }],
  "agent.reset": ["agent-1", { confirmed: true }],
  "agent.remove": ["agent-1", { confirmed: true }],
  "agent.update": ["agent-1", { name: "Ada", color: "#fff" }, ["role"]],
  "agent.reorder": [["agent-2", "agent-1"]],
};

const feed = { snapshot: () => ({ kind: "snapshot", epoch: "e", seq: 3, sessions: [] }) as SessionFeed };
const intent = (name: string, args: unknown[], requestId: string = crypto.randomUUID(), connectionId = "device"): RemoteIntent =>
  ({ requestId, connectionId, name, args });

describe("createSessionHost", () => {
  it.each(Object.keys(ARGS) as (keyof SessionIntents)[])("runs %s as the window's own control does", async (name) => {
    const direct = sources();
    const directTable = sessionIntents(direct.parts);
    const expected = await (directTable[name] as (...args: unknown[]) => unknown)(...ARGS[name]);

    const remote = sources();
    const host = createSessionHost({ intents: () => sessionIntents(remote.parts), feed, onLeases: vi.fn() });
    // Through JSON, as the arguments arrive from another device.
    const received = await host.handle(intent(name, JSON.parse(JSON.stringify(ARGS[name]))));

    expect(received).toEqual(expected);
    expect(calls(remote.parts)).toEqual(calls(direct.parts));
    expect(remote.sessions()).toEqual(direct.sessions());
  });

  it("answers approvals through the habits, which route a hidden run's request back to it", async () => {
    const { parts } = sources();
    const host = createSessionHost({ intents: () => sessionIntents(parts), feed, onLeases: vi.fn() });
    await host.handle(intent("session.approve", ["s", 7, "deny"]));
    expect(parts.agentHabits.approve).toHaveBeenCalledWith("s", 7, "deny");
    expect(parts.submission.approve).not.toHaveBeenCalled();
  });

  it("runs a repeated request once and answers it the same way", async () => {
    const { parts } = sources();
    const host = createSessionHost({ intents: () => sessionIntents(parts), feed, onLeases: vi.fn() });
    const sent = intent("session.submit", ["s", "once"], "r1");
    const first = await host.handle(sent);
    const again = await host.handle({ ...sent, connectionId: "reconnected" });
    expect(again).toBe(first);
    expect(parts.submission.onSubmit).toHaveBeenCalledOnce();
    await expect(host.handle(intent("session.submit", ["s", "other"], "r1"))).rejects.toThrow("different input");
  });

  it("runs a failed request again when it is retried", async () => {
    const { parts } = sources();
    vi.mocked(parts.submission.stop).mockRejectedValueOnce(new Error("busy")).mockResolvedValueOnce(undefined);
    const host = createSessionHost({ intents: () => sessionIntents(parts), feed, onLeases: vi.fn() });
    await expect(host.handle(intent("session.stop", ["s"], "r2"))).rejects.toThrow("busy");
    await expect(host.handle(intent("session.stop", ["s"], "r2"))).resolves.toBeUndefined();
    expect(parts.submission.stop).toHaveBeenCalledTimes(2);
  });

  it.each([["session.delete", ["s"]], ["agent.reset", ["a"]], ["agent.remove", ["a", { confirmed: false }]]])(
    "refuses %s unless the sending device confirmed it", async (name, args) => {
      const { parts } = sources();
      const host = createSessionHost({ intents: () => sessionIntents(parts), feed, onLeases: vi.fn() });
      await expect(host.handle(intent(name, args))).rejects.toThrow("must be confirmed");
      expect(calls(parts)).toEqual({ updateSessions: 0 });
    });

  it("refuses an intent it does not know, including inherited names", async () => {
    const { parts } = sources();
    const host = createSessionHost({ intents: () => sessionIntents(parts), feed, onLeases: vi.fn() });
    await expect(host.handle(intent("harness.spawn", []))).rejects.toThrow("Unknown intent");
    await expect(host.handle(intent("toString", []))).rejects.toThrow("Unknown intent");
  });

  it("keeps what every device shows until its connection ends", async () => {
    const onLeases = vi.fn();
    const host = createSessionHost({ intents: () => sessionIntents(sources().parts), feed, onLeases });
    await host.handle(intent("session.view", [["a", "b"]], undefined, "mac-mini"));
    await host.handle(intent("session.view", [["b", "c"]], undefined, "laptop"));
    expect(onLeases).toHaveBeenLastCalledWith(["a", "b", "c"]);
    await host.handle(intent("session.view", [[]], undefined, "mac-mini"));
    expect(onLeases).toHaveBeenLastCalledWith(["b", "c"]);
  });

  it("looks for a provider's CLI on the host for a connected window, and only for a provider it knows", async () => {
    const inspectBinary = vi.fn(async () => ({ path: "/opt/homebrew/bin/codex", version: "0.9" }));
    const host = createSessionHost({ intents: () => sessionIntents(sources().parts), feed, onLeases: vi.fn(), inspectBinary });
    await expect(host.handle(intent("providers.inspectBinary", ["codex", null]))).resolves.toEqual({ path: "/opt/homebrew/bin/codex", version: "0.9" });
    expect(inspectBinary).toHaveBeenCalledWith("codex", null);
    await expect(host.handle(intent("providers.inspectBinary", ["rm -rf", "/x"]))).rejects.toThrow("Unknown provider");
    expect(inspectBinary).toHaveBeenCalledOnce();
  });

  it("answers a snapshot from the feed", async () => {
    const host = createSessionHost({ intents: () => sessionIntents(sources().parts), feed, onLeases: vi.fn() });
    await expect(host.handle(intent("session.snapshot", []))).resolves.toMatchObject({ kind: "snapshot", seq: 3 });
  });
});

describe("useSessionHost", () => {
  let root: Root;
  let host!: ReturnType<typeof useSessionHost>;
  const sessionsRef = { current: [] as Session[] };
  let table: SessionIntents;

  function Harness() {
    host = useSessionHost(sessionsRef, () => table);
    return null;
  }
  async function mount() {
    root = createRoot(document.createElement("div"));
    await act(async () => root.render(createElement(Harness)));
    await act(async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); });
  }
  const commands = () => native.call.mock.calls.map(([command]) => command);

  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    native.label = "main";
    native.intent = undefined;
    native.status = undefined;
    native.call.mockReset().mockResolvedValue(undefined);
    native.listen.mockReset().mockImplementation(async (event: string, handler) => {
      const slot = event === "loci-remote-intent" ? "intent" : "status";
      native[slot] = handler;
      return () => { if (native[slot] === handler) native[slot] = undefined; };
    });
    sessionsRef.current = [{ ...newSession("claude", "/w"), id: "s" }];
    table = sessionIntents(sources().parts);
  });
  afterEach(() => {
    act(() => root.unmount());
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("neither listens nor publishes while remote access is off", async () => {
    native.call.mockRejectedValue(new Error("command remote_status not found"));
    await mount();
    host.sessionsChanged([]);
    expect(commands()).toEqual(["remote_status"]);
    expect(native.listen.mock.calls.map(([event]) => event)).toEqual(["remote-status-changed"]);
    expect(host.leasedIds).toEqual([]);
  });

  it("hosts only in the main window", async () => {
    native.label = "window-2";
    await mount();
    expect(native.call).not.toHaveBeenCalled();
  });

  it("publishes the feed and answers intents while remote access is on", async () => {
    native.call.mockImplementation(async (command: string) => command === "remote_status" ? { enabled: true } : undefined);
    await mount();
    expect(native.listen).toHaveBeenCalledWith("loci-remote-intent", expect.any(Function));
    expect(native.call).toHaveBeenCalledWith("remote_session_publish", { feed: expect.objectContaining({ kind: "snapshot", seq: 0 }) });

    await act(async () => {
      native.intent!({ payload: intent("session.view", [["s"]], "r-view") });
      native.intent!({ payload: intent("session.submit", ["s", "hi"], "r-send") });
      native.intent!({ payload: intent("nope", [], "r-bad") });
      for (let i = 0; i < 10; i++) await Promise.resolve();
    });
    expect(host.leasedIds).toEqual(["s"]);
    expect(table["session.submit"]).toHaveBeenCalledWith("s", "hi");
    expect(native.call).toHaveBeenCalledWith("remote_intent_reply", { requestId: "r-send", ok: true, value: "onSubmit result" });
    expect(native.call).toHaveBeenCalledWith("remote_intent_reply", { requestId: "r-view", ok: true, value: null });
    expect(native.call).toHaveBeenCalledWith("remote_intent_reply", { requestId: "r-bad", ok: false, error: "Unknown intent: nope" });

    vi.useFakeTimers();
    host.sessionsChanged([{ ...sessionsRef.current[0], title: "renamed" }]);
    vi.advanceTimersByTime(50);
    expect(native.call).toHaveBeenLastCalledWith("remote_session_publish", {
      feed: expect.objectContaining({ kind: "patch", seq: 1, changes: [{ id: "s", meta: { title: "renamed" } }] }),
    });
  });

  it("starts and stops hosting as remote access is turned on and off, without a reload", async () => {
    await mount();
    expect(native.intent).toBeUndefined();

    await act(async () => { native.status!({ payload: { enabled: true } }); for (let i = 0; i < 10; i++) await Promise.resolve(); });
    expect(native.intent).toBeDefined();
    const snapshots = () => native.call.mock.calls.filter(([command, args]) => command === "remote_session_publish" && args.feed.kind === "snapshot");
    expect(snapshots()).toHaveLength(1);

    await act(async () => { native.intent!({ payload: intent("session.view", [["s"]]) }); for (let i = 0; i < 10; i++) await Promise.resolve(); });
    expect(host.leasedIds).toEqual(["s"]);
    await act(async () => { native.status!({ payload: { enabled: false } }); for (let i = 0; i < 10; i++) await Promise.resolve(); });
    expect(native.intent).toBeUndefined();
    expect(host.leasedIds).toEqual([]);
    vi.useFakeTimers();
    const published = native.call.mock.calls.length;
    host.sessionsChanged([{ ...sessionsRef.current[0], title: "while off" }]);
    vi.advanceTimersByTime(50);
    expect(native.call.mock.calls.length).toBe(published);
    vi.useRealTimers();

    await act(async () => { native.status!({ payload: { enabled: true } }); for (let i = 0; i < 10; i++) await Promise.resolve(); });
    expect(snapshots()).toHaveLength(2);
    // A new feed: devices take a snapshot instead of patches from the old one.
    expect(snapshots()[1][1].feed.epoch).not.toBe(snapshots()[0][1].feed.epoch);
  });
});
