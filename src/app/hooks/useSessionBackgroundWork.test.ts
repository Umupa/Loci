// @vitest-environment happy-dom
import { act, createElement, useRef, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, type Session } from "../../features/sessions/model/session";
import { newTab, type WorkspaceTab } from "../../features/workspace/model/layout";
import { registerHarness, resetHarnessIdlePark, type TextPromptInput } from "../../integrations/harness/core/registry";
import { useSessionRuntime, type SessionRuntime } from "./useSessionRuntime";
import { useSessionSubmission, type SessionSubmission } from "./useSessionSubmission";
import { useIdleSessionDetach } from "./useIdleSessionDetach";
import { createSessionRemover } from "../../features/sessions/model/sessionRemoval";
import { rememberLoadedSession } from "../../features/sessions/data/sessionCache";

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), forget: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke, isTauri: () => true }));
vi.mock("../../integrations/harness/core/child", () => ({ startHarnessBridge: () => () => undefined }));

let root: Root;
let host: HTMLDivElement;
let runtime: SessionRuntime;
let actions: SessionSubmission;
let tabs: { current: WorkspaceTab[] };
let cache: Map<string, Session>;
let stored: Map<string, Session>;
let pending: Array<{ input: TextPromptInput; resolve: (value: string) => void }>;
let setTabs: (next: WorkspaceTab[]) => void;

function chat(id: string): Session {
  return { ...newSession("codex", "/background-fixture", "codex:test"), id, blocks: [
    { id: "user", role: "user", text: "Main question" },
    { id: "answer", role: "assistant", text: "Main answer" },
  ] };
}

async function mount(initial: Session) {
  function Workspace() {
    const [sessions, update] = useState([initial]);
    const sessionsRef = useRef(sessions);
    const [openTabs, updateTabs] = useState([newTab(initial.id)]);
    const tabsRef = useRef(openTabs);
    tabsRef.current = openTabs;
    tabs = tabsRef;
    setTabs = updateTabs;
    const loaded = useRef(new Map<string, Session>());
    const opening = useRef(new Set<string>());
    const protectedIds = useRef(new Set<string>());
    cache = loaded.current;
    runtime = useSessionRuntime({ sessions, sessionsRef, setSessions: update });
    actions = useSessionSubmission({ runtime });
    useIdleSessionDetach({
      sessions, sessionsRef, tabs: openTabs, tabsRef, liveAgentsEnabled: false,
      unseenFinishedIds: new Set(), openingSessionIds: opening,
      loadedSessionCache: loaded, skipForgetSessionIds: protectedIds,
      persistSession: runtime.persistSession, setSessions: runtime.updateSessions,
      onError: (error) => { throw error; },
    });
    return createElement("output", null, JSON.stringify(sessions));
  }
  await act(async () => root.render(createElement(Workspace)));
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  stored = new Map();
  pending = [];
  mocks.forget.mockReset().mockResolvedValue(undefined);
  mocks.invoke.mockReset().mockImplementation(async (command, args) => {
    if (command === "session_upsert") {
      const row = structuredClone({ ...args.session, createdAt: 1, updatedAt: 2 });
      stored.set(row.id, row);
      return row;
    }
    return undefined;
  });
  registerHarness({
    id: "codex", live: true, sendTurn: async () => undefined,
    steerTurn: async () => undefined, cancelTurn: async () => undefined,
    respondApproval: () => undefined, bindSession: () => undefined,
    stopSession: async () => undefined, forgetSession: mocks.forget,
    runTextPrompt: (input) => new Promise<string>((resolve) => pending.push({ input, resolve })),
  });
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(async () => {
  await act(async () => { for (const request of pending) request.resolve("cleanup"); });
  await act(async () => root.unmount());
  host.remove();
  resetHarnessIdlePark();
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("background side-question lifetime", () => {
  it("archives a stopped partial side answer and can continue it after a warm-cache reopen", async () => {
    const initial = chat("archived-side");
    await mount(initial);
    await act(async () => {
      actions.btwSubmit(initial.id, initial.blocks, "side", "question", "Explain");
      pending[0].input.onEvent?.({ type: "message.delta", text: "Partial answer" });
    });
    const remover = createSessionRemover({
      mode: "archive", scope: "project", replacement: initial,
      confirm: async () => true,
      stop: async (id) => { await actions.stopSessionWork(id); await runtime.flushPersistence(); },
      workspace: {
        snapshot: () => ({ sessions: runtime.sessionsRef.current, tabs: tabs.current, activeTabId: tabs.current[0].id }),
        apply: (change) => {
          if (change.type === "stopped") {
            runtime.updateSessions((sessions) => sessions.map((session) => session.id === initial.id ? change.session : session));
          } else {
            rememberLoadedSession(cache, change.session!);
            runtime.updateSessions(change.removal.sessions);
            setTabs(change.removal.tabs);
          }
        },
      },
    });
    await act(async () => { expect(await remover.remove(initial.id)).toBe(true); });
    const cached = cache.get(initial.id)!;
    expect(pending[0].input.signal?.aborted).toBe(true);
    expect(cached.blocks[0].btwThreads?.[0]).toMatchObject({ status: "ready", pendingBlocks: undefined });
    expect(cached.blocks[0].btwThreads?.[0].messages[1].text).toBe("Partial answer");
    expect(stored.get(initial.id)?.blocks[0].btwThreads?.[0].status).toBe("ready");
    await act(async () => {
      runtime.bindRestoredSession(cached);
      runtime.updateSessions([cached]);
      setTabs([newTab(cached.id)]);
      expect(actions.btwSubmit(cached.id, cached.blocks, "side", "retry", "Continue")).toBe(true);
    });
    expect(pending).toHaveLength(2);
  });

  it("cancels a request when its source thread is removed but the session remains", async () => {
    const initial = chat("edited");
    await mount(initial);
    await act(async () => { actions.btwSubmit(initial.id, initial.blocks, "side", "question", "Explain"); });
    await act(async () => runtime.updateSessions([chat(initial.id)]));
    expect(runtime.sessionsRef.current).toHaveLength(1);
    expect(pending[0].input.signal?.aborted).toBe(true);
    await act(async () => pending[0].input.onEvent?.({ type: "message.delta", text: "late" }));
    expect(runtime.sessionsRef.current[0].blocks[0].btwThreads).toBeUndefined();
  });

  it("cancels only the removed owner while another side question completes normally", async () => {
    const first = chat("first");
    const second = chat("second");
    await mount(first);
    await act(async () => { actions.btwSubmit(first.id, first.blocks, "side", "question", "First"); });
    await act(async () => {
      runtime.updateSessions([...runtime.sessionsRef.current, second]);
      setTabs([newTab(first.id), newTab(second.id)]);
      actions.btwSubmit(second.id, second.blocks, "side", "question", "Second");
    });
    await act(async () => runtime.updateSessions(runtime.sessionsRef.current.filter((session) => session.id !== first.id)));
    expect(pending[0].input.signal?.aborted).toBe(true);
    expect(pending[1].input.signal?.aborted).toBe(false);
    await act(async () => pending[1].resolve("Second answer"));
    expect(runtime.sessionsRef.current[0].blocks[0].btwThreads?.[0].messages[1].text).toBe("Second answer");
  });

  it("keeps a closed chat attached until its side answer is saved and then releases it", async () => {
    const initial = chat("background");
    await mount(initial);
    await act(async () => { expect(actions.btwSubmit(initial.id, initial.blocks, "side", "question", "Explain")).toBe(true); });
    expect(runtime.sessionsRef.current[0].busy).toBeFalsy();
    await act(async () => setTabs([]));
    expect(tabs.current).toEqual([]);
    await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
    expect(runtime.sessionsRef.current).toHaveLength(1);
    expect(mocks.forget).not.toHaveBeenCalled();
    expect(pending[0].input.signal?.aborted).toBe(false);
    await act(async () => {
      pending[0].input.onEvent?.({ type: "message.delta", text: "Background result" });
      pending[0].resolve("Background result");
    });
    await act(async () => { await vi.advanceTimersByTimeAsync(1000); });
    expect(runtime.sessionsRef.current).toEqual([]);
    expect(cache.get(initial.id)?.blocks[0].btwThreads?.[0].status).toBe("ready");
    expect(stored.get(initial.id)?.blocks[0].btwThreads?.[0].messages[1].text).toBe("Background result");
    expect(mocks.forget).toHaveBeenCalledExactlyOnceWith(initial.id);
  });

  it("cancels side requests when 100 owning sessions are explicitly removed", async () => {
    await mount(chat("initial"));
    for (let i = 0; i < 100; i += 1) {
      const session = chat(`removed-${i}`);
      await act(async () => {
        runtime.updateSessions([session]);
        setTabs([newTab(session.id)]);
        expect(actions.btwSubmit(session.id, session.blocks, "side", "question", "Explain")).toBe(true);
      });
      await act(async () => runtime.updateSessions([]));
    }
    const uncancelled = pending.filter((request) => !request.input.signal?.aborted).length;
    console.info(JSON.stringify({ scenario: "removed-side-question-owners", requests: pending.length, uncancelled }));
    expect(pending).toHaveLength(100);
    expect(uncancelled).toBe(0);
    await act(async () => pending[0].input.onEvent?.({ type: "message.delta", text: "late" }));
    expect(runtime.sessionsRef.current).toEqual([]);
  });
});
