// @vitest-environment happy-dom
import { act,createElement,useRef,useState } from "react";
import { createRoot,type Root } from "react-dom/client";
import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { newSession,type Session } from "../../features/sessions/model/session";
import { registerHarness,resetHarnessIdlePark } from "../../integrations/harness/core/registry";
import { useSessionRuntime,type SessionRuntime } from "./useSessionRuntime";

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), release: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke, isTauri: () => true }));
vi.mock("../../integrations/harness/core/child", () => ({ startHarnessBridge: () => mocks.release }));

let root: Root;
let host: HTMLDivElement;
let runtime: SessionRuntime;
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
  await act(async () => root.render(createElement(Harness)));
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
