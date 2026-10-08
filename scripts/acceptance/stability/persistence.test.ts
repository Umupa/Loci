import { act, createElement, useRef, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useIdleSessionDetach } from "../../../src/app/hooks/useIdleSessionDetach";
import { useSessionRuntime, type SessionRuntime } from "../../../src/app/hooks/useSessionRuntime";
import { flushSessionWrites, getSession } from "../../../src/features/sessions/data/sessionStore";
import { newSession, type Session } from "../../../src/features/sessions/model/session";
import type { WorkspaceTab } from "../../../src/features/workspace/model/layout";

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), forget: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke, isTauri: () => true }));
vi.mock("../../../src/integrations/harness/core/child", () => ({ startHarnessBridge: () => () => undefined }));
vi.mock("../../../src/integrations/harness/core/registry", () => ({
  bindHarnessSession: vi.fn(), forgetHarnessSession: mocks.forget,
}));

let root: Root;
let host: HTMLDivElement;
let runtime: SessionRuntime;
let cache: Map<string, Session>;
let stored: Map<string, Session>;
let failedId: string | undefined;
let observedRejections: string[];
let trace: string[];
const reportedError = vi.fn();

function chat(id: string): Session {
  return { ...newSession("claude", "/stability-fixture"), id, blocks: [
    { id: `${id}-user`, role: "user", text: `Save ${id}` },
    { id: `${id}-answer`, role: "assistant", text: `Latest answer ${id}` },
  ] };
}

async function mount() {
  function Workspace() {
    const [sessions, setSessions] = useState<Session[]>([]);
    const sessionsRef = useRef(sessions);
    sessionsRef.current = sessions;
    const tabs = useRef<WorkspaceTab[]>([]);
    const opening = useRef(new Set<string>());
    const protectedIds = useRef(new Set<string>());
    const loaded = useRef(new Map<string, Session>());
    cache = loaded.current;
    runtime = useSessionRuntime({ sessions, sessionsRef, setSessions, onPersistenceError: reportedError });
    useIdleSessionDetach({
      sessions, sessionsRef, tabs: tabs.current, tabsRef: tabs,
      liveAgentsEnabled: false, unseenFinishedIds: new Set(),
      openingSessionIds: opening, loadedSessionCache: loaded,
      skipForgetSessionIds: protectedIds,
      onError: reportedError,
      persistSession: (session) => {
        const save = runtime.persistSession(session);
        // Observe separately, returning the original rejection to the hook.
        // This also keeps the old implementation's discarded promise observable.
        void save.catch(() => {
          observedRejections.push(session!.id);
          trace.push(`rejected:${session!.id}`);
        });
        return save;
      },
      setSessions: runtime.updateSessions,
    });
    return null;
  }
  await act(async () => root.render(createElement(Workspace)));
}

async function advance(ms: number) {
  await act(async () => { await vi.advanceTimersByTimeAsync(ms); });
  await flushSessionWrites();
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  stored = new Map();
  failedId = undefined;
  observedRejections = [];
  trace = [];
  reportedError.mockReset();
  mocks.forget.mockReset().mockImplementation(async (_provider, id) => { trace.push(`forgot:${id}`); });
  mocks.invoke.mockReset().mockImplementation(async (command, args) => {
    if (command === "session_upsert") {
      trace.push(`write:${args.session.id}`);
      if (args.session.id === failedId) throw new Error("injected disk failure");
      const record = structuredClone({ ...args.session, createdAt: 1, updatedAt: 2 });
      stored.set(record.id, record);
      return record;
    }
    if (command === "session_get") return structuredClone(stored.get(args.sessionId) ?? null);
    throw new Error(`Unexpected IPC: ${command}`);
  });
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(async () => {
  await act(async () => root.unmount());
  await flushSessionWrites();
  host.remove();
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("persistence and idle-detach acceptance", () => {
  it("recovers all 30 successfully saved chats after closing and cache eviction", async () => {
    await mount();
    const chats = Array.from({ length: 30 }, (_, i) => chat(`healthy-${i}`));
    await act(async () => runtime.updateSessions(chats));
    await advance(1000);
    expect(runtime.sessionsRef.current).toHaveLength(0);
    expect(cache.size).toBeLessThanOrEqual(12);
    expect(stored.size).toBe(30);
    for (const session of chats) expect((await getSession(session.id))?.blocks).toEqual(session.blocks);
    expect(observedRejections).toEqual([]);
  });

  it("keeps a failed snapshot recoverable after closing more chats than fit in cache", async () => {
    await mount();
    failedId = "failed-0";
    const chats = Array.from({ length: 13 }, (_, i) => chat(`failed-${i}`));
    await act(async () => runtime.updateSessions(chats));
    await advance(1000);
    expect(observedRejections).toEqual([failedId]);
    expect(stored.size).toBe(12); // Other writes really completed.
    const recovered = runtime.sessionsRef.current.find((s) => s.id === failedId)
      ?? cache.get(failedId) ?? await getSession(failedId);
    console.info(JSON.stringify({ scenario: "failed-save-eviction", trace,
      attached: runtime.sessionsRef.current.length, cached: cache.size,
      reportedErrors: reportedError.mock.calls.length, recovered: !!recovered }));
    expect(recovered, "the failed latest snapshot must remain recoverable").toMatchObject({ blocks: chats[0].blocks });
  });

  it("surfaces an idle-detach save failure through the application's persistence error callback", async () => {
    await mount();
    failedId = "failure-report";
    await act(async () => runtime.updateSessions([chat(failedId!)]));
    await advance(1000);
    expect(observedRejections).toEqual([failedId]);
    expect(reportedError).toHaveBeenCalledWith(expect.objectContaining({ message: "injected disk failure" }));
  });
});
