// @vitest-environment happy-dom
import { act, createElement, useCallback, useRef, useState, type SetStateAction } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, type Session } from "../../features/sessions/model/session";
import { leafIds, newTab, splitPane, type WorkspaceTab } from "../../features/workspace/model/layout";
import { rememberProject } from "../../features/projects/model/recents";
import type { SessionSummary } from "../../features/sessions/data/sessionStore";
import { useAppWorkspace } from "./useAppWorkspace";

const mocks = vi.hoisted(() => ({
  ask: vi.fn(), pickFolders: vi.fn(), getSession: vi.fn(), listSessionsByProject: vi.fn(),
  upsertSession: vi.fn(), deleteSession: vi.fn(), setSessionArchived: vi.fn(),
  setSessionPinned: vi.fn(), saveWorkspaceSnapshot: vi.fn(),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: mocks.ask }));
vi.mock("../../platform/tauri/fs", () => ({ pickFolders: mocks.pickFolders, claudeShellCommands: vi.fn() }));
vi.mock("../model/appLifecycle", () => ({ isAppQuitting: () => false }));
vi.mock("../../features/sessions/data/sessionStore", async (original) => ({
  ...(await original<typeof import("../../features/sessions/data/sessionStore")>()),
  getSession: mocks.getSession,
  listSessionsByProject: mocks.listSessionsByProject,
  upsertSession: mocks.upsertSession,
  deleteSession: mocks.deleteSession,
  setSessionArchived: mocks.setSessionArchived,
  setSessionPinned: mocks.setSessionPinned,
  saveWorkspaceSnapshot: mocks.saveWorkspaceSnapshot,
}));

type StoredSession = Session & { archived?: boolean; pinned?: boolean };
const records = new Map<string, StoredSession>();
const stopSession = vi.fn();
const flushPersistence = vi.fn();
const bindSession = vi.fn();
const persistSession = vi.fn();
const onNavigate = vi.fn();
let root: Root | undefined;
let container: HTMLDivElement | undefined;
let workspace: ReturnType<typeof useAppWorkspace>;
let liveSessions: Session[];

function summary(session: StoredSession): SessionSummary {
  return {
    id: session.id, cwd: session.cwd, harness: session.harness, model: session.model,
    runtimeMode: session.runtimeMode, title: session.title, createdAt: 1, updatedAt: 1,
    archived: session.archived, pinned: session.pinned,
  };
}

function chat(id: string, cwd = "/alpha", text = "Saved conversation"): Session {
  return {
    ...newSession("codex", cwd), id, title: id,
    blocks: text ? [{ id: `${id}-user`, role: "user", text }] : [],
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

async function mount(initialSessions: Session[], initialTabs = initialSessions.map((session) => newTab(session.id))) {
  const initial = {
    sessions: initialSessions, tabs: initialTabs, activeTabId: initialTabs[0].id,
    projectCwd: initialSessions[0].cwd,
  };
  function Harness() {
    const [sessions, setSessions] = useState(initialSessions);
    const sessionsRef = useRef(sessions);
    sessionsRef.current = sessions;
    // Match useSessionRuntime: refs commit synchronously before React renders.
    const updateSessions = useCallback((update: SetStateAction<Session[]>) => {
      const next = typeof update === "function" ? update(sessionsRef.current) : update;
      sessionsRef.current = next;
      setSessions(next);
    }, []);
    workspace = useAppWorkspace({
      boot: { resumed: null, history: [], historyCwd: initial.projectCwd },
      initial, sessions, sessionsRef, updateSessions, persistSession,
      bindSession, stopSession, flushPersistence, onNavigate,
    });
    liveSessions = sessions;
    return null;
  }
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  await act(async () => root!.render(createElement(Harness)));
}

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  records.clear();
  for (const mock of [...Object.values(mocks), stopSession, flushPersistence, bindSession, persistSession, onNavigate]) mock.mockReset();
  mocks.ask.mockResolvedValue(true);
  mocks.pickFolders.mockResolvedValue([]);
  mocks.getSession.mockImplementation(async (id: string) => records.get(id) ?? null);
  mocks.listSessionsByProject.mockImplementation(async (cwd: string) =>
    [...records.values()].filter((session) => session.cwd === cwd).map(summary));
  mocks.upsertSession.mockImplementation(async (session: Session) => {
    const stored = records.get(session.id);
    const saved = { ...session, archived: stored?.archived, pinned: stored?.pinned };
    records.set(session.id, saved);
    return summary(saved);
  });
  mocks.deleteSession.mockImplementation(async (id: string) => { records.delete(id); });
  mocks.setSessionArchived.mockImplementation(async (id: string, archived: boolean) => {
    const stored = records.get(id);
    if (stored) records.set(id, { ...stored, archived });
  });
  mocks.setSessionPinned.mockImplementation(async (id: string, pinned: boolean) => {
    const stored = records.get(id);
    if (stored) records.set(id, { ...stored, pinned });
  });
  mocks.saveWorkspaceSnapshot.mockResolvedValue(undefined);
  stopSession.mockResolvedValue(undefined);
  flushPersistence.mockResolvedValue(undefined);
});

afterEach(async () => {
  await act(async () => root?.unmount());
  container?.remove();
  root = undefined;
  container = undefined;
});

describe("workspace lifecycle integration", () => {
  it("coalesces two concurrent opens into one pane for the stored session", async () => {
    const stored = chat("stored");
    const pending = deferred<Session>();
    mocks.getSession.mockReturnValue(pending.promise);
    await mount([chat("blank", "/alpha", "")]);
    let first!: Promise<void>;
    let second!: Promise<void>;
    act(() => {
      first = workspace.openSession(stored.id);
      second = workspace.openSession(stored.id);
    });
    await act(async () => { pending.resolve(stored); await Promise.all([first, second]); });
    expect(workspace.tabs.flatMap((tab) => leafIds(tab.layout)).filter((id) => id === stored.id)).toHaveLength(1);
    expect(liveSessions.filter((session) => session.id === stored.id)).toHaveLength(1);
  });

  it("does not restore a deleted conversation when its earlier read completes", async () => {
    const stored = chat("deleted");
    records.set(stored.id, stored);
    const pending = deferred<Session>();
    mocks.getSession.mockReturnValueOnce(pending.promise);
    await mount([chat("blank", "/alpha", "")]);
    let opening!: Promise<void>;
    act(() => { opening = workspace.openSession(stored.id); });
    await act(async () => { expect(await workspace.removeSession(stored.id)).toBe(true); });
    expect(mocks.deleteSession.mock.calls.some(([id]) => id === stored.id)).toBe(true);
    await act(async () => { pending.resolve(stored); await opening; });
    expect(liveSessions.some((session) => session.id === stored.id)).toBe(false);
    expect(workspace.tabs.some((tab) => leafIds(tab.layout).includes(stored.id))).toBe(false);
  });

  it("keeps a closed conversation's rename when it is later pinned and opened", async () => {
    const stored = chat("closed");
    records.set(stored.id, stored);
    await mount([chat("visible")]);
    await act(async () => { await workspace.renameSession(stored.id, "Revised title"); });
    expect(records.get(stored.id)?.title).toBe("Revised title");
    await act(async () => { await workspace.pinSession(stored.id, true); });
    expect(records.get(stored.id)?.title).toBe("Revised title");
    expect(records.get(stored.id)?.pinned).toBe(true);
    await act(async () => { await workspace.openSession(stored.id); });
    expect(workspace.activeSession?.title).toBe("Revised title");
  });

  it("stops a running conversation before archiving it", async () => {
    const running = { ...chat("running"), busy: true };
    records.set(running.id, running);
    await mount([running]);
    await act(async () => { expect(await workspace.archiveSession(running.id, true)).toBe(true); });
    expect(stopSession).toHaveBeenCalledWith(running.id);
    expect(stopSession.mock.invocationCallOrder[0]).toBeLessThan(mocks.setSessionArchived.mock.invocationCallOrder[0]);
    expect(workspace.tabs.some((tab) => leafIds(tab.layout).includes(running.id))).toBe(false);
  });

  it("leaves a usable neutral session after deleting the only project", async () => {
    const only = chat("only");
    records.set(only.id, only);
    rememberProject(only.cwd);
    await mount([only]);
    await act(async () => { await workspace.removeProject(only.cwd, { purgeData: true }); });
    expect(workspace.activeSession).toBeDefined();
    expect(workspace.activeSession?.cwd).toBe("~");
    expect(workspace.projectCwd).toBe("~");
    expect(workspace.tabs.flatMap((tab) => leafIds(tab.layout)).every((id) => liveSessions.some((session) => session.id === id))).toBe(true);
  });

  it("closing the last tab of a project does not switch to another project", async () => {
    const alpha = chat("alpha", "/alpha");
    const beta = chat("beta", "/beta");
    await mount([alpha, beta]);
    await act(async () => { workspace.closeTabs([workspace.activeTabId]); });
    expect(workspace.projectCwd).toBe("/alpha");
    expect(workspace.activeSession?.cwd).toBe("/alpha");
    expect(workspace.tabs.some((tab) => leafIds(tab.layout).includes(beta.id))).toBe(true);
  });

  it("opens every folder selected in one picker result", async () => {
    await mount([chat("blank", "~", "")]);
    mocks.pickFolders.mockResolvedValue(["/alpha", "/beta"]);
    await act(async () => { await workspace.pickProject(); });
    const visibleCwds = new Set(workspace.tabs.flatMap((tab) => leafIds(tab.layout))
      .map((id) => liveSessions.find((session) => session.id === id)?.cwd));
    expect(visibleCwds).toEqual(new Set(["/alpha", "/beta"]));
    expect(workspace.projectCwd).toBe("/beta");
  });

  it("moves a whole split tree onto another pane without losing its sessions", async () => {
    const sessions = [chat("a"), chat("b"), chat("target")];
    const source = { ...newTab("a"), id: "source", layout: splitPane(newTab("a").layout, "a", "down", "b"), focusedId: "b" };
    const target = { ...newTab("target"), id: "target-tab" };
    await mount(sessions, [source, target]);
    await act(async () => { workspace.placeTab(source.id, "target", "right"); });
    expect(workspace.tabs).toHaveLength(1);
    expect(new Set(leafIds(workspace.tabs[0].layout))).toEqual(new Set(["a", "b", "target"]));
    expect(workspace.tabs[0].layout.type).toBe("split");
    expect(workspace.activeSession?.id).toBe("b");
    expect(liveSessions.map((session) => session.id)).toEqual(["a", "b", "target"]);
  });

  it("does not replace the current project's history with an older response", async () => {
    const alpha = chat("alpha", "/alpha");
    const beta = chat("beta", "/beta");
    const pending = deferred<SessionSummary[]>();
    mocks.listSessionsByProject.mockImplementation((cwd: string) =>
      cwd === "/alpha" ? pending.promise : Promise.resolve([summary(beta)]));
    await mount([alpha, beta]);
    await act(async () => { workspace.openProject("/beta"); });
    expect(workspace.history.map((session) => session.id)).toEqual([beta.id]);
    await act(async () => { pending.resolve([summary(alpha)]); });
    expect(workspace.projectCwd).toBe("/beta");
    expect(workspace.history.map((session) => session.id)).toEqual([beta.id]);
  });

  it("keeps the conversation open when its native deletion fails", async () => {
    const stored = chat("kept");
    records.set(stored.id, stored);
    await mount([stored]);
    const originalTab = workspace.activeTabId;
    mocks.deleteSession.mockRejectedValueOnce(new Error("database locked"));
    await act(async () => { expect(await workspace.removeSession(stored.id)).toBe(false); });
    expect(workspace.activeTabId).toBe(originalTab);
    expect(workspace.activeSession?.id).toBe(stored.id);
    expect(records.has(stored.id)).toBe(true);
    expect(await workspace.loadSession(stored.id)).not.toBeNull();
    expect(workspace.error).toContain("database locked");
  });

  it("does not delete or detach a conversation when the persistence barrier fails", async () => {
    const stored = chat("kept");
    records.set(stored.id, stored);
    await mount([stored]);
    flushPersistence.mockRejectedValueOnce(new Error("pending save failed"));
    await act(async () => { expect(await workspace.removeSession(stored.id)).toBe(false); });
    expect(mocks.deleteSession).not.toHaveBeenCalled();
    expect(workspace.activeSession?.id).toBe(stored.id);
    expect(await workspace.loadSession(stored.id)).not.toBeNull();
  });

  it("blocks app reads during confirmation and releases the barrier on cancel", async () => {
    const stored = chat("kept");
    records.set(stored.id, stored);
    const confirmation = deferred<boolean>();
    mocks.ask.mockReturnValue(confirmation.promise);
    await mount([stored]);
    let removing!: Promise<boolean>;
    act(() => { removing = workspace.removeSession(stored.id); });
    expect(await workspace.loadSession(stored.id)).toBeNull();
    await act(async () => { confirmation.resolve(false); expect(await removing).toBe(false); });
    expect(await workspace.loadSession(stored.id)).not.toBeNull();
    expect(stopSession).not.toHaveBeenCalled();
    expect(mocks.deleteSession).not.toHaveBeenCalled();
  });

  it("replaces the current pane for session navigation without creating a tab", async () => {
    const initial = chat("initial");
    const stored = chat("next");
    records.set(stored.id, stored);
    await mount([initial]);
    const originalTab = workspace.activeTabId;
    await act(async () => { await workspace.openSessionInCurrentTab(stored.id); });
    expect(workspace.tabs).toHaveLength(1);
    expect(workspace.activeTabId).toBe(originalTab);
    expect(workspace.activeSession?.id).toBe(stored.id);
    expect(bindSession).toHaveBeenCalledWith(stored);
  });

  it("does not let a delayed current-tab navigation replace a newly focused pane", async () => {
    const first = chat("first");
    const second = chat("second");
    const pending = deferred<Session>();
    mocks.getSession.mockReturnValueOnce(pending.promise);
    await mount([first, second]);
    let opening!: Promise<void>;
    act(() => { opening = workspace.openSessionInCurrentTab("slow"); });
    await act(async () => { workspace.focusPane(second.id); });
    const focusedTab = workspace.activeTabId;
    await act(async () => { pending.resolve(chat("slow")); await opening; });
    expect(workspace.activeTabId).toBe(focusedTab);
    expect(workspace.activeSession?.id).toBe(second.id);
    expect(workspace.tabs.flatMap((tab) => leafIds(tab.layout))).not.toContain("slow");
  });

  it("adds an operator split with reveal false without moving focus", async () => {
    const visible = chat("visible");
    await mount([visible]);
    const originalTab = workspace.activeTabId;
    const created = chat("operator-created");
    await act(async () => {
      workspace.addSession(created, { besideSessionId: visible.id, edge: "right", reveal: false });
    });
    expect(workspace.tabs).toHaveLength(1);
    expect(leafIds(workspace.tabs[0].layout)).toEqual([visible.id, created.id]);
    expect(workspace.activeTabId).toBe(originalTab);
    expect(workspace.activeSession?.id).toBe(visible.id);
  });

  it("inserts a new conversation next to the active tab and keeps its group", async () => {
    const sessions = [chat("first"), chat("second"), chat("third")];
    const tabs = sessions.map((session, index) => ({
      ...newTab(session.id), id: `tab-${session.id}`, ...(index < 2 ? { groupId: "group" } : {}),
    }));
    await mount(sessions, tabs);
    let created!: string;
    await act(async () => { created = workspace.createSession(); });
    expect(workspace.tabs.map((tab) => tab.focusedId)).toEqual(["first", created, "second", "third"]);
    expect(workspace.tabs[1].groupId).toBe("group");
  });

  it("preserves the latest closed-session cache when deletion is cancelled", async () => {
    const stored = chat("cached");
    records.set(stored.id, stored);
    await mount([chat("visible")]);
    workspace.loadedSessionCache.current.set(stored.id, { ...stored, title: "Latest cached title" });
    mocks.ask.mockResolvedValue(false);
    await act(async () => { expect(await workspace.removeSession(stored.id)).toBe(false); });
    expect((await workspace.loadSession(stored.id))?.title).toBe("Latest cached title");
    expect(mocks.deleteSession).not.toHaveBeenCalled();
  });

  it("keeps undeleted sessions usable after a project purge partially fails", async () => {
    const first = chat("first");
    const second = chat("second");
    records.set(first.id, first);
    records.set(second.id, second);
    rememberProject(first.cwd);
    await mount([first, second]);
    mocks.deleteSession.mockImplementation(async (id: string) => {
      if (id === second.id) throw new Error("database unavailable");
      records.delete(id);
    });
    await act(async () => { await workspace.removeProject(first.cwd, { purgeData: true }); });
    expect(workspace.activeSession?.id).toBe(second.id);
    expect(workspace.sidebarHistory.some((row) => row.id === first.id)).toBe(false);
    expect(workspace.tabs.some((tab) => tab.id === workspace.activeTabId)).toBe(true);
    expect(await workspace.loadSession(first.id)).toBeNull();
    expect((await workspace.loadSession(second.id))?.id).toBe(second.id);
    expect(workspace.error).toContain("database unavailable");
  });
});
