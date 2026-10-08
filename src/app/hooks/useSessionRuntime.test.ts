// @vitest-environment happy-dom
import { act,createElement,useRef,useState } from "react";
import { createRoot,type Root } from "react-dom/client";
import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { newSession,type Session } from "../../features/sessions/model/session";
import { registerHarness,resetHarnessIdlePark } from "../../integrations/harness/core/registry";
import { useSessionRuntime,type SessionRuntime } from "./useSessionRuntime";
import * as sessionStore from "../../features/sessions/data/sessionStore";

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), release: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke, isTauri: () => true }));
vi.mock("../../integrations/harness/core/child", () => ({ startHarnessBridge: () => mocks.release }));

let root: Root;
let host: HTMLDivElement;
let runtime: SessionRuntime;
let rerender: () => Promise<void>;
const onInput = vi.fn();
const onPersisted = vi.fn();
const onPersistenceError = vi.fn();
const bind = vi.fn();
const restoreTasks = vi.fn();

async function mount(initial: Session) {
  function Harness() {
    const [sessions, setSessions] = useState([initial]);
    const sessionsRef = useRef(sessions);
    sessionsRef.current = sessions;
    runtime = useSessionRuntime({ sessions, sessionsRef, setSessions, onInput, onPersisted, onPersistenceError });
    return null;
  }
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  rerender = async () => { await act(async () => root.render(createElement(Harness))); };
  await rerender();
}

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  for (const mock of [onInput, onPersisted, onPersistenceError, bind, restoreTasks, mocks.release, mocks.invoke]) mock.mockReset();
  mocks.invoke.mockImplementation(async (command: string, args?: { session?: Session }) => {
    if (command === "session_upsert") return { ...args?.session, createdAt: 1, updatedAt: Date.now() };
    return undefined;
  });
  registerHarness({
    id: "claude", live: true,
    sendTurn: async () => undefined, steerTurn: async () => undefined,
    cancelTurn: async () => undefined, respondApproval: () => undefined,
    stopSession: async () => undefined, forgetSession: async () => undefined,
    bindSession: bind, restoreTaskLists: restoreTasks,
  });
});

afterEach(async () => {
  await act(async () => root?.unmount());
  host?.remove();
  resetHarnessIdlePark();
});

describe("session runtime", () => {
  it("does not loop on autosave failure but still rejects an explicit flush", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    try {
      const initial = { ...newSession("claude", "/project"), blocks: [{ id: "user", role: "user" as const, text: "Content" }] };
      await mount(initial);
      mocks.invoke.mockRejectedValue(new Error("disk unavailable"));
      await act(async () => runtime.updateSessions([{ ...initial, title: "Changed" }]));
      await act(async () => { await vi.advanceTimersByTimeAsync(10_000); });
      expect(mocks.invoke).toHaveBeenCalledTimes(1);
      expect(onPersistenceError).toHaveBeenCalledOnce();
      await expect(runtime.flushPersistence()).rejects.toThrow("disk unavailable");
      expect(mocks.invoke).toHaveBeenCalledTimes(2);
      mocks.invoke.mockResolvedValue(undefined);
      await runtime.flushPersistence();
    } finally { vi.clearAllTimers(); vi.useRealTimers(); }
  });

  it("lets an explicit flush wait for a newer snapshot behind a slow write", async () => {
    const initial = newSession("claude", "/project");
    await mount(initial);
    let finish!: () => void;
    const held = new Promise<void>((resolve) => { finish = resolve; });
    mocks.invoke.mockImplementation(async (_command, args) => {
      await held;
      return { ...args.session, createdAt: 1, updatedAt: 2 };
    });
    const first = { ...initial, blocks: [{ id: "user", role: "user" as const, text: "First" }] };
    await act(async () => runtime.updateSessions([first]));
    const saving = runtime.persistSession(first);
    const latest = { ...first, title: "Latest" };
    await act(async () => runtime.updateSessions([latest]));
    let flushed = false;
    const flushing = runtime.flushPersistence().then(() => { flushed = true; });
    await Promise.resolve();
    expect(flushed).toBe(false);
    finish();
    await Promise.all([saving, flushing]);
    expect(flushed).toBe(true);
    expect(mocks.invoke.mock.calls.map(([, args]) => args.session.title)).toEqual([first.title, "Latest"]);
  });

  it("keeps one autosave in flight under slow storage and then saves the latest state", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const upsert = vi.spyOn(sessionStore, "upsertSession");
    let finish!: () => void;
    const held = new Promise<void>((resolve) => { finish = resolve; });
    try {
      const initial = { ...newSession("claude", "/project"), blocks: [{ id: "user", role: "user" as const, text: "Content" }] };
      await mount(initial);
      mocks.invoke.mockImplementation(async (_command, args) => {
        await held;
        return { ...args.session, createdAt: 1, updatedAt: 2 };
      });
      for (let version = 1; version <= 30; version += 1) {
        await act(async () => runtime.updateSessions([{ ...initial, title: `version-${version}` }]));
        await act(async () => { await vi.advanceTimersByTimeAsync(350); });
      }
      const queuedBeforeRelease = upsert.mock.calls.length;
      await act(async () => { finish(); await held; await vi.advanceTimersByTimeAsync(1000); });
      await runtime.flushPersistence();
      console.info(JSON.stringify({ scenario: "slow-storage-autosave", revisions: 30,
        queuedBeforeRelease, writes: mocks.invoke.mock.calls.length }));
      expect(queuedBeforeRelease).toBe(1);
      expect(mocks.invoke.mock.calls.map(([, args]) => args.session.title)).toEqual(["version-1", "version-30"]);
    } finally {
      finish();
      upsert.mockRestore();
      vi.clearAllTimers();
      vi.useRealTimers();
    }
  });

  it("shares a pending write for 100 identical save requests", async () => {
    const initial = newSession("claude", "/project");
    await mount(initial);
    const updated = { ...initial, blocks: [{ id: "user", role: "user" as const, text: "Save once" }] };
    await act(async () => runtime.updateSessions([updated]));
    let finish!: () => void;
    const held = new Promise<void>((resolve) => { finish = resolve; });
    mocks.invoke.mockImplementation(async (_command, args) => {
      await held;
      return { ...args.session, createdAt: 1, updatedAt: 2 };
    });
    const requests = Array.from({ length: 100 }, () => runtime.persistSession(updated));
    await Promise.resolve();
    finish();
    await Promise.all(requests);
    console.info(JSON.stringify({ scenario: "duplicate-pending-save", requests: 100, writes: mocks.invoke.mock.calls.length }));
    expect(mocks.invoke).toHaveBeenCalledTimes(1);
  });

  it("persists a return to the last saved snapshot after a different write is queued", async () => {
    const initial = { ...newSession("claude", "/project"), blocks: [{ id: "user", role: "user" as const, text: "Original" }] };
    await mount(initial);
    const changed = { ...initial, title: "Temporary change" };
    let finish!: () => void;
    const held = new Promise<void>((resolve) => { finish = resolve; });
    mocks.invoke.mockImplementation(async (_command, args) => {
      await held;
      return { ...args.session, createdAt: 1, updatedAt: 2 };
    });
    const first = runtime.persistSession(changed);
    const restored = runtime.persistSession(initial);
    finish();
    await Promise.all([first, restored]);
    expect(mocks.invoke.mock.calls.map(([, args]) => args.session.title)).toEqual(["Temporary change", initial.title]);
  });

  it("does not rescan unchanged transcripts on parent-only renders", async () => {
    const session = newSession("claude", "/project");
    session.blocks = Array.from({ length: 10_000 }, (_, i) => ({
      id: `block-${i}`, role: "user" as const, text: `Message ${i}`,
    }));
    const fingerprint = vi.spyOn(sessionStore, "persistFingerprint");
    try {
      await mount(session);
      expect(fingerprint).toHaveBeenCalled();
      fingerprint.mockClear();
      const started = performance.now();
      for (let i = 0; i < 100; i += 1) await rerender();
      console.info(JSON.stringify({ scenario: "unchanged-parent-renders", renders: 100,
        blocks: 10_000, elapsedMs: performance.now() - started, fingerprintCalls: fingerprint.mock.calls.length }));
      expect(fingerprint).not.toHaveBeenCalled();
    } finally { fingerprint.mockRestore(); }
  });

  it("invalidates removed turns without reusing their token when the session reopens", async () => {
    const session = newSession("claude", "/project");
    await mount(session);
    const first = runtime.beginTurn(session.id);
    await act(async () => runtime.updateSessions([]));
    expect(runtime.isCurrentTurn(session.id, first)).toBe(false);
    expect(runtime.hasActiveTurn(session.id)).toBe(false);
    await act(async () => runtime.updateSessions([session]));
    const second = runtime.beginTurn(session.id);
    expect(second).not.toBe(first);
    expect(runtime.isCurrentTurn(session.id, first)).toBe(false);
    expect(runtime.isCurrentTurn(session.id, second)).toBe(true);
    runtime.forgetTurn(session.id);
    expect(runtime.isCurrentTurn(session.id, second)).toBe(false);
    expect(runtime.beginTurn(session.id)).not.toBe(second);
  });

  it("keeps failed writes pending so a later quit flush cannot silently succeed", async () => {
    const session = newSession("claude", "/project");
    await mount(session);
    await act(async () => runtime.updateSessions((previous) => previous.map((entry) => ({
      ...entry, blocks: [{ id: "user", role: "user", text: "Keep the latest content" }],
    }))));
    mocks.invoke.mockRejectedValueOnce(new Error("disk unavailable"))
      .mockRejectedValueOnce(new Error("disk still unavailable"));
    await expect(runtime.flushPersistence()).rejects.toThrow("disk unavailable");
    await expect(runtime.flushPersistence()).rejects.toThrow("disk still unavailable");
    expect(onPersisted).not.toHaveBeenCalled();
    await runtime.flushPersistence();
    expect(onPersisted).toHaveBeenCalledOnce();
    expect(mocks.invoke).toHaveBeenLastCalledWith("session_upsert", expect.objectContaining({
      session: expect.objectContaining({ blocks: [{ id: "user", role: "user", text: "Keep the latest content" }] }),
    }));
  });

  it("binds a restored provider thread and its task state only once", async () => {
    const session = newSession("claude", "/project", "claude:sonnet-5");
    const tasks = { key: "tasks", items: [{ id: "1", text: "Read report", status: "pending" as const }] };
    session.providerSessionId = "provider-thread";
    session.providerAccountId = "work";
    session.blocks = [{ id: "user", role: "user", text: "Start" }, { id: "tasks", role: "tasks", text: "Read report", taskList: tasks }];
    await mount(session);
    expect(bind).toHaveBeenCalledExactlyOnceWith(session.id, "provider-thread", "/project", "work");
    expect(restoreTasks).toHaveBeenCalledExactlyOnceWith(session.id, [tasks]);
    await runtime.flushPersistence();
    expect(mocks.invoke).not.toHaveBeenCalledWith("session_upsert", expect.anything());
    await act(async () => runtime.updateSessions((previous) => previous.map((entry) => ({ ...entry, title: "Renamed" }))));
    expect(bind).toHaveBeenCalledOnce();
    await act(async () => runtime.updateSessions([]));
    // Closing can forget the native process; reopening must seed resume state again.
    act(() => runtime.bindRestoredSession(session));
    expect(bind).toHaveBeenCalledTimes(2);
  });

  it("flushes preceding text when a question arrives and notifies once", async () => {
    const session = newSession("claude", "/project");
    session.blocks = [{ id: "user", role: "user", text: "Start" }];
    await mount(session);
    await act(async () => {
      runtime.enqueueEvent(session.id, { type: "message.delta", text: "Choose a source." });
      runtime.enqueueEvent(session.id, { type: "question.asked", requestId: 8, questions: [
        { id: "source", prompt: "Which source?", multiSelect: false, allowCustom: true, options: [{ id: "local", label: "Local" }] },
      ] });
    });
    expect(runtime.sessionsRef.current[0].blocks.at(-1)?.text).toBe("Choose a source.");
    expect(runtime.sessionsRef.current[0].pendingQuestion?.requestId).toBe(8);
    expect(onInput).toHaveBeenCalledOnce();
    await act(async () => runtime.updateSessions((previous) => previous.map((entry) => ({ ...entry, title: "Question" }))));
    expect(onInput).toHaveBeenCalledOnce();
    await act(async () => runtime.enqueueEvent(session.id, { type: "question.resolved", requestId: 8, decision: "answered" }));
    expect(runtime.sessionsRef.current[0].pendingQuestion).toBeUndefined();
  });

  it("retries a failed save and does not claim that the failed snapshot persisted", async () => {
    const session = newSession("claude", "/project");
    await mount(session);
    await act(async () => runtime.updateSessions((previous) => previous.map((entry) => ({
      ...entry, blocks: [{ id: "user", role: "user", text: "Remember this" }],
    }))));
    mocks.invoke.mockRejectedValueOnce(new Error("disk unavailable"));
    await expect(runtime.flushPersistence()).rejects.toThrow("disk unavailable");
    expect(onPersisted).not.toHaveBeenCalled();
    await runtime.persistSession(session.id);
    expect(onPersisted).toHaveBeenCalledOnce();
    expect(onPersisted.mock.calls[0][0].title).toBe(session.title);
    const before = mocks.invoke.mock.calls.length;
    await runtime.persistSession(session.id);
    expect(mocks.invoke.mock.calls).toHaveLength(before);
  });
});
