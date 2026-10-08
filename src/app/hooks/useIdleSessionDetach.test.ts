// @vitest-environment happy-dom
import {
  act,
  createElement,
  useState,
  type Dispatch,
  type SetStateAction,
} from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  flushSessionWrites,
  getSession,
  upsertSession,
  type SessionRecord,
} from "../../features/sessions/data/sessionStore";
import { useUnseenFinishedSessions } from "../../features/sessions/hooks/useUnseenFinishedSessions";
import { liveAgentsFromSessions } from "../../features/sessions/model/liveAgents";
import {
  newSession,
  type Session,
} from "../../features/sessions/model/session";
import {
  newTab,
  type WorkspaceTab,
} from "../../features/workspace/model/layout";
import { useIdleSessionDetach } from "./useIdleSessionDetach";

const mocks = vi.hoisted(() => ({
  invoke: vi.fn(),
  forgetHarnessSession: vi.fn(),
}));

vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));
vi.mock("../../integrations/harness/core/registry", () => ({
  forgetHarnessSession: mocks.forgetHarnessSession,
}));

let root: Root | undefined;
let container: HTMLDivElement;
let stored: Map<string, SessionRecord>;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  mocks.forgetHarnessSession.mockReset().mockResolvedValue(undefined);
  stored = new Map();
  mocks.invoke.mockReset().mockImplementation(async (command, args) => {
    if (command === "session_upsert") {
      const record = structuredClone({
        ...args.session,
        createdAt: 1,
        updatedAt: 2,
      });
      stored.set(record.id, record);
      return record;
    }
    if (command === "session_get") {
      return structuredClone(stored.get(args.sessionId) ?? null);
    }
    throw new Error(`Unexpected command: ${command}`);
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(async () => {
  act(() => root?.unmount());
  container.remove();
  await flushSessionWrites();
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function chat(id: string, patch: Partial<Session> = {}): Session {
  return {
    ...newSession("claude", "/repo"),
    id,
    blocks: [
      { id: `${id}-user`, role: "user", text: "Review the assigned files" },
      {
        id: `${id}-answer`,
        role: "assistant",
        text: "The assignment is complete.",
      },
    ],
    ...patch,
  };
}

type WorkspaceState = {
  sessions: Session[];
  tabs: WorkspaceTab[];
  busySessionIds: ReadonlySet<string>;
  activeSessionId: string;
  liveAgentsEnabled: boolean;
};

function mountWorkspace(initial: Partial<WorkspaceState> = {}, save?: (session: Session) => Promise<void>) {
  let props: WorkspaceState = {
    sessions: [chat("ordinary", { busy: true }), chat("other")],
    tabs: [newTab("other")],
    busySessionIds: new Set(["ordinary"]),
    activeSessionId: "other",
    liveAgentsEnabled: true,
    ...initial,
  };
  const sessionsRef = { current: props.sessions };
  const tabsRef = { current: props.tabs };
  const openingSessionIds = { current: new Set<string>() };
  const loadedSessionCache = { current: new Map<string, Session>() };
  const skipForgetSessionIds = { current: new Set<string>() };
  const onError = vi.fn();
  const persistSession = vi.fn(async (session: Session | undefined) => {
    if (session) {
      if (save) await save(session);
      else await upsertSession(session);
    }
  });
  let snapshot!: {
    sessions: Session[];
    unseenFinishedIds: Set<string>;
    setSessions: Dispatch<SetStateAction<Session[]>>;
  };

  function Workspace(state: WorkspaceState) {
    const [sessions, setSessions] = useState(state.sessions);
    sessionsRef.current = sessions;
    tabsRef.current = state.tabs;
    const unseenFinishedIds = useUnseenFinishedSessions(
      state.busySessionIds,
      state.activeSessionId,
    );
    useIdleSessionDetach({
      ...state,
      sessions,
      sessionsRef,
      tabsRef,
      unseenFinishedIds,
      openingSessionIds,
      loadedSessionCache,
      skipForgetSessionIds,
      persistSession,
      onError,
      setSessions,
    });
    snapshot = { sessions, unseenFinishedIds, setSessions };
    return null;
  }

  act(() => root!.render(createElement(Workspace, props)));
  const update = (patch: Partial<WorkspaceState>) => {
    props = { ...props, ...patch };
    act(() => {
      if (patch.sessions) snapshot.setSessions(patch.sessions);
      root!.render(createElement(Workspace, props));
    });
  };
  return {
    snapshot: () => snapshot,
    update,
    finish: () =>
      update({
        sessions: snapshot.sessions.map((session) => ({
          ...session,
          busy: false,
        })),
        busySessionIds: new Set(),
      }),
    persistSession,
    onError,
    openingSessionIds: openingSessionIds.current,
    cache: loadedSessionCache.current,
    skipForgetSessionIds: skipForgetSessionIds.current,
  };
}

async function advance(milliseconds = 250) {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(milliseconds);
  });
  await flushSessionWrites();
}

describe("idle session detachment", () => {
  it("retains unsaved content until the write succeeds", async () => {
    let complete!: () => void;
    const saving = new Promise<void>((resolve) => { complete = resolve; });
    const workspace = mountWorkspace({ sessions: [chat("hidden")], tabs: [], busySessionIds: new Set() }, () => saving);
    await advance();
    expect(workspace.snapshot().sessions.map((s) => s.id)).toEqual(["hidden"]);
    expect(workspace.cache.size).toBe(0);
    expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
    await act(async () => complete());
    expect(workspace.snapshot().sessions).toEqual([]);
    expect(workspace.cache.has("hidden")).toBe(true);
    expect(mocks.forgetHarnessSession).toHaveBeenCalledExactlyOnceWith("claude", "hidden");
  });

  it.each([0, 100, 250])("retries a failed save after reopening for %i ms and closing", async (openFor) => {
    const failure = new Error("disk unavailable");
    const save = vi.fn().mockRejectedValueOnce(failure).mockResolvedValue(undefined);
    const workspace = mountWorkspace({ sessions: [chat("hidden")], tabs: [], busySessionIds: new Set() }, save);
    await advance();
    expect(workspace.onError).toHaveBeenCalledExactlyOnceWith(failure);
    expect(workspace.snapshot().sessions).toHaveLength(1);
    expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
    workspace.update({ sessions: [...workspace.snapshot().sessions] });
    await advance(1000);
    expect(save).toHaveBeenCalledTimes(1);
    workspace.update({ tabs: [newTab("hidden")] });
    await advance(openFor);
    workspace.update({ tabs: [] });
    await advance();
    expect(save).toHaveBeenCalledTimes(2);
    expect(workspace.snapshot().sessions).toEqual([]);
  });

  it("retries after navigation even when the earlier save fails after its detach timer ran", async () => {
    let reject!: (error: Error) => void;
    const saving = new Promise<void>((_resolve, fail) => { reject = fail; });
    const save = vi.fn().mockReturnValueOnce(saving).mockResolvedValue(undefined);
    const workspace = mountWorkspace({ sessions: [chat("hidden")], tabs: [], busySessionIds: new Set() }, save);
    await advance();
    workspace.update({ tabs: [newTab("hidden")] });
    workspace.update({ tabs: [] });
    await advance();
    await act(async () => reject(new Error("earlier write failed")));
    await advance();
    expect(save).toHaveBeenCalledTimes(2);
    expect(workspace.snapshot().sessions).toEqual([]);
  });

  it.each(["reopened", "busy", "replaced", "protected", "unmounted"] as const)(
    "does not release a %s session when an older save completes", async (change) => {
      let complete!: () => void;
      const saving = new Promise<void>((resolve) => { complete = resolve; });
      const workspace = mountWorkspace({ sessions: [chat("hidden")], tabs: [], busySessionIds: new Set() }, () => saving);
      await advance();
      if (change === "reopened") workspace.update({ tabs: [newTab("hidden")] });
      if (change === "busy") workspace.update({ sessions: [chat("hidden", { busy: true })] });
      if (change === "replaced") workspace.update({ sessions: [chat("hidden", { title: "New snapshot" })] });
      if (change === "protected") workspace.skipForgetSessionIds.add("hidden");
      if (change === "unmounted") { act(() => root!.unmount()); root = undefined; }
      await act(async () => complete());
      expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
      expect(workspace.cache.size).toBe(0);
      if (change !== "unmounted") expect(workspace.snapshot().sessions).toHaveLength(1);
      if (change === "replaced") {
        await advance();
        expect(workspace.persistSession).toHaveBeenLastCalledWith(expect.objectContaining({ title: "New snapshot" }));
        expect(workspace.cache.get("hidden")?.title).toBe("New snapshot");
      }
    },
  );

  it("keeps unseen completed chats until they are focused", async () => {
    const workspace = mountWorkspace();
    workspace.finish();
    await advance();
    expect(workspace.snapshot().unseenFinishedIds).toEqual(new Set(["ordinary"]));
    expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
    expect(liveAgentsFromSessions(workspace.snapshot().sessions, workspace.snapshot().unseenFinishedIds)).toMatchObject([{ id: "ordinary", done: true }]);
    workspace.update({ tabs: [newTab("ordinary")], activeSessionId: "ordinary" });
    await advance();
    expect(workspace.snapshot().unseenFinishedIds.size).toBe(0);
    workspace.update({ tabs: [newTab("other")], activeSessionId: "other" });
    await advance();
    expect(workspace.snapshot().sessions.map((session) => session.id)).not.toContain("ordinary");
    expect(mocks.forgetHarnessSession).toHaveBeenCalledWith("claude", "ordinary");
  });

  it("detaches unseen finished chats when the activity overview is disabled", async () => {
    const workspace = mountWorkspace();
    workspace.finish();
    await advance();
    workspace.update({ liveAgentsEnabled: false });
    await advance();
    expect(workspace.snapshot().sessions.map((session) => session.id)).toEqual(["other"]);
    expect(mocks.forgetHarnessSession).toHaveBeenCalledExactlyOnceWith("claude", "ordinary");
  });

  it.each(["busy", "opening", "protected"] as const)("keeps a %s hidden chat attached", async (reason) => {
    const workspace = mountWorkspace({
      sessions: [chat("hidden", { busy: reason === "busy" }), chat("other")],
      tabs: [newTab("other")], busySessionIds: new Set(reason === "busy" ? ["hidden"] : []),
    });
    if (reason === "opening") workspace.openingSessionIds.add("hidden");
    if (reason === "protected") workspace.skipForgetSessionIds.add("hidden");
    await advance();
    expect(workspace.snapshot().sessions.map((session) => session.id)).toContain("hidden");
    expect(workspace.persistSession).not.toHaveBeenCalled();
    expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
  });

  it("persists a closed transcript before forgetting its provider and can reload after cache eviction", async () => {
    const hidden = chat("hidden", { providerSessionId: "provider-thread" });
    const workspace = mountWorkspace({ sessions: [hidden, chat("other")], busySessionIds: new Set() });
    await advance(249);
    expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
    await advance(1);
    expect(workspace.snapshot().sessions.map((session) => session.id)).toEqual(["other"]);
    expect(workspace.persistSession).toHaveBeenCalledExactlyOnceWith(hidden);
    expect(mocks.forgetHarnessSession).toHaveBeenCalledExactlyOnceWith("claude", "hidden");
    expect(workspace.cache.get("hidden")).toEqual(hidden);
    workspace.cache.clear();
    const loaded = await getSession("hidden");
    expect(loaded).toMatchObject({ providerSessionId: hidden.providerSessionId, blocks: hidden.blocks });
  });

  it("cancels pending detachment when the workspace unmounts", async () => {
    const workspace = mountWorkspace({ sessions: [chat("hidden"), chat("other")], busySessionIds: new Set() });
    act(() => root!.unmount()); root = undefined;
    await advance();
    expect(workspace.persistSession).not.toHaveBeenCalled();
    expect(mocks.forgetHarnessSession).not.toHaveBeenCalled();
  });
});
