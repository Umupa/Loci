import { useCallback, useEffect, useMemo, useRef, useState, type Dispatch, type RefObject, type SetStateAction } from "react";
import { ask } from "@tauri-apps/plugin-dialog";
import { archiveProject, forgetProject, lastProjectPath, loadRecents, rememberProject, sameProjectPath, normalizeProjectPath } from "../../features/projects/model/recents";
import { isBlankSession, reconcileProjectReturn, type ProjectReturnMemory } from "../../features/projects/model/projectReturn";
import { agentForSession, agentLook, isAgentSession } from "../../features/agents/model/agent";
import type { WidgetRef } from "../../features/learning/model/types";
import type { AgentDocument } from "../../features/sessions/model/cards";
import { removeProjectData } from "../../features/projects/model/projectData";
import { forgetProjectLocation } from "../../features/projects/model/projectLocation";
import { insertTabBesideActive } from "../../features/workspace/model/tabGroups";
import { forgetHarnessSession } from "../../integrations/harness/core/registry";
import { planProjectOpenRun } from "../../features/projects/model/projectOpenRun";
import { createSessionRemover } from "../../features/sessions/model/sessionRemoval";
import { removeSessionFromWorkspace } from "../../features/sessions/model/sessionWorkspaceLifecycle";
import { newDefaultSession, newSessionLike, retargetSessionToProject, sessionDisplayTitle, type Session } from "../../features/sessions/model/session";
import { deleteSession, getSession, listSessionsByProject, saveWorkspaceSnapshot, setSessionArchived, setSessionPinned, upsertSession, type SessionSummary } from "../../features/sessions/data/sessionStore";
import { historyWithLiveSessions, mergeHistorySummary, summaryFromSession } from "../../features/sessions/data/sessionHistory";
import { rememberLoadedSession } from "../../features/sessions/data/sessionCache";
import { hasLiveSessionWork } from "../../features/sessions/model/inFlight";
import { canvasLeaf, closeLeaf, documentPaneId, widgetPaneId, showWidgetInTab, firstLeafId, removePane, filePaneId, filePanePath, layoutLeaves, leafIds, placeFileOnPane, rebaseFilePanes, showCanvasInTab, showDocumentInTab, showFileInTab, neighborLeafId, newTab, replacePaneWithLayout, setSplitRatio, showCanvasForSession, splitPane, type FocusDir, type LayoutNode, type PaneEdge, type SplitDir, type WorkspaceTab } from "../../features/workspace/model/layout";
import { applyMoveWorkspacePane, applyDetachPaneToTab, applyPlaceSessionOnPane, applyPlaceTabOnPane, filterTabsForProject, findOpenSessionTab, workspaceTabCwd, focusedWorkspaceTabCwd, planWorkspaceTabClose, switchSessionInTab } from "../../features/workspace/model/workspaceTabGroups";
import { collectWorkspaceSnapshot } from "../../features/workspace/model/workspaceSnapshot";
import { emptyTabVisitHistory, pruneTabVisitHistory, recordTabVisit, tabVisitBack, tabVisitForward } from "../../features/workspace/model/tabVisitHistory";
import type { TitleTabDropPosition } from "../../features/workspace/model/paneDrop";
import { loadSessionFolders, placeSessionInFolder, saveSessionFolders, type SessionFolderTarget } from "../../features/sessions/model/sessionFolders";
import { pickFolders } from "../../platform/tauri/fs";
import { moveFileDrafts, setFileDraft } from "../../features/files/model/fileDrafts";
import { isEqualOrInside, projectName, rebasePath } from "../../shared/lib/paths";
import { isAppQuitting, type BootWorkspace } from "../model/appLifecycle";
import { closedTabs, type ClosedTab } from "../../features/workspace/model/closedTabs";
import { pinnedFirst, setTabPinned } from "../../features/workspace/model/tabPins";

export function initialWorkspace(boot: BootWorkspace) {
  const restored = boot.resumed;
  if (restored?.tabs.length) return restored;
  const session = newDefaultSession(lastProjectPath() ?? "~");
  const tab = newTab(session.id);
  return { sessions: [session], tabs: [tab], activeTabId: tab.id, projectCwd: session.cwd };
}

type Options = {
  boot: BootWorkspace;
  initial: ReturnType<typeof initialWorkspace>;
  sessions: Session[];
  sessionsRef: RefObject<Session[]>;
  updateSessions: Dispatch<SetStateAction<Session[]>>;
  persistSession: (session: Session | undefined) => Promise<void>;
  bindSession: (session: Session) => void;
  stopSession: (id: string) => void | Promise<void>;
  flushPersistence: () => Promise<void>;
  onNavigate: () => void;
  onOpenAgent: (agentId: string) => void;
};

export function useAppWorkspace(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const [tabs, setTabsState] = useState<WorkspaceTab[]>(options.initial.tabs);
  const tabsRef = useRef(tabs);
  const [activeTabId, setActiveTabId] = useState(options.initial.activeTabId);
  const activeTabIdRef = useRef(activeTabId);
  activeTabIdRef.current = activeTabId;
  const [projectCwd, setProjectCwd] = useState(options.initial.projectCwd);
  const projectCwdRef = useRef(projectCwd);
  projectCwdRef.current = projectCwd;
  const [recents, setRecents] = useState(loadRecents);
  const [history, setHistory] = useState<SessionSummary[]>(options.boot.history);
  const [historyPending, setHistoryPending] = useState(false);
  const [historyFailed, setHistoryFailed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [composerFocusToken, focusComposer] = useState(0);
  const [visits, setVisits] = useState(() => emptyTabVisitHistory(options.initial.activeTabId));
  const projectReturnMemory = useRef<ProjectReturnMemory>(options.boot.resumed?.projectReturnMemory ?? new Map());
  const loadedSessionCache = useRef(new Map<string, Session>());
  const openingSessionIds = useRef(new Set<string>());
  const skipForgetSessionIds = useRef(new Set<string>());
  const historyRequest = useRef(0);
  const sessionLoads = useRef(new Map<string, Promise<Session | null>>());
  const sessionLoadEpochs = useRef(new Map<string, number>());
  const removingSessionIds = useRef(new Set<string>());
  const deletedSessionIds = useRef(new Set<string>());
  const removingProjects = useRef(new Set<string>());

  const sessionUnavailable = useCallback((id: string) =>
    removingSessionIds.current.has(id) || deletedSessionIds.current.has(id), []);

  const invalidateLoadedSession = useCallback((id: string) => {
    openingSessionIds.current.delete(id);
    loadedSessionCache.current.delete(id);
    sessionLoads.current.delete(id);
    sessionLoadEpochs.current.set(id, (sessionLoadEpochs.current.get(id) ?? 0) + 1);
  }, []);

  const updateTabs = useCallback((next: SetStateAction<WorkspaceTab[]>) => {
    const value = typeof next === "function" ? next(tabsRef.current) : next;
    tabsRef.current = value;
    setTabsState(value);
  }, []);

  const activateTab = useCallback((id: string, record = true) => {
    const tab = tabsRef.current.find((entry) => entry.id === id);
    if (!tab) return;
    activeTabIdRef.current = id;
    setActiveTabId(id);
    const cwd = focusedWorkspaceTabCwd(tab, latest.current.sessionsRef.current);
    if (cwd) {
      projectCwdRef.current = cwd;
      setProjectCwd(cwd);
    }
    if (record) setVisits((current) => recordTabVisit(current, id));
    latest.current.onNavigate();
    focusComposer((token) => token + 1);
  }, []);

  const addSession = useCallback((session: Session, placement?: { besideSessionId?: string; edge?: PaneEdge; reveal?: boolean }) => {
    if (sessionUnavailable(session.id) || removingProjects.current.has(normalizeProjectPath(session.cwd))) {
      throw new Error("This conversation is being removed or is no longer available.");
    }
    const existing = findOpenSessionTab(tabsRef.current, latest.current.sessionsRef.current, session.id);
    if (existing && !placement?.besideSessionId) {
      if (placement?.reveal !== false) activateTab(existing.id);
      return session.id;
    }
    latest.current.updateSessions((current) => current.some((entry) => entry.id === session.id) ? current : [...current, session]);
    const target = placement?.besideSessionId && tabsRef.current.find((tab) => leafIds(tab.layout).includes(placement.besideSessionId!));
    if (target && placement?.besideSessionId && placement.edge) {
      const placed = applyPlaceSessionOnPane({
        tabs: tabsRef.current, sessions: latest.current.sessionsRef.current,
        sessionId: session.id, targetId: placement.besideSessionId, edge: placement.edge,
        replaceTarget: false, scope: "project", createReplacement: (seed) => newSessionLike(seed, session.cwd),
      });
      if (placed) {
        updateTabs(placement.reveal === false
          ? placed.tabs.map((tab) => tab.id === target.id ? { ...tab, focusedId: target.focusedId } : tab)
          : placed.tabs);
        latest.current.updateSessions(placed.sessions);
        if (placement.reveal !== false) activateTab(placed.activeTabId);
        return session.id;
      }
    }
    const tab = newTab(session.id);
    updateTabs((current) => insertTabBesideActive(current, tab, activeTabIdRef.current, (id) => {
      if (id === tab.id) return projectName(session.cwd);
      const existing = current.find((entry) => entry.id === id);
      const cwd = existing && workspaceTabCwd(existing, latest.current.sessionsRef.current);
      return cwd ? projectName(cwd) : undefined;
    }));
    if (placement?.reveal !== false) activateTab(tab.id);
    return session.id;
  }, [activateTab, sessionUnavailable, updateTabs]);

  const createSession = useCallback((cwd = projectCwdRef.current) => {
    // A new tab is a blank one that is already waiting, if there is one.
    const waiting = findBlankTab(tabsRef.current, latest.current.sessionsRef.current, cwd);
    if (waiting) {
      activateTab(waiting.tab.id);
      return waiting.sessionId;
    }
    const current = tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
    const seed = latest.current.sessionsRef.current.find((session) => session.id === current?.focusedId);
    return addSession(newSessionLike(seed, cwd));
  }, [addSession]);

  const focusPane = useCallback((id: string) => {
    const tab = tabsRef.current.find((entry) => leafIds(entry.layout).includes(id));
    if (!tab) return;
    updateTabs((current) => current.map((entry) => entry.id === tab.id ? { ...entry, focusedId: id } : entry));
    activateTab(tab.id);
  }, [activateTab, updateTabs]);

  const openProjects = useCallback((paths: readonly string[]) => {
    const steps = planProjectOpenRun({
      memory: projectReturnMemory.current,
      tabs: tabsRef.current,
      sessions: latest.current.sessionsRef.current,
      activeTabId: activeTabIdRef.current,
      paths: paths.filter((path) => !removingProjects.current.has(normalizeProjectPath(path))),
    });
    const last = steps[steps.length - 1];
    if (!last) return;
    latest.current.onNavigate();
    let nextSessions = latest.current.sessionsRef.current;
    let nextTabs = tabsRef.current;
    for (const step of steps) {
      if (step.action === "reuse-blank") {
        nextSessions = nextSessions.map((session) => session.id === step.sessionId
          ? retargetSessionToProject(session, step.path) : session);
      } else if (step.action === "create") {
        nextSessions = [...nextSessions, step.session];
        nextTabs = insertTabBesideActive(nextTabs, step.tab, step.besideTabId, (id) => {
          if (id === step.tab.id) return projectName(step.path);
          const existing = nextTabs.find((entry) => entry.id === id);
          const cwd = existing && workspaceTabCwd(existing, nextSessions);
          return cwd ? projectName(cwd) : undefined;
        });
      }
    }
    latest.current.updateSessions(nextSessions);
    updateTabs(nextTabs);
    projectCwdRef.current = last.path;
    setProjectCwd(last.path);
    if (last.action === "create") activateTab(last.tab.id);
    else if (last.action === "activate") {
      if (last.paneId) focusPane(last.paneId);
      else activateTab(last.tabId);
    } else if (last.action === "reuse-blank") focusPane(last.sessionId);
    for (const step of steps) setRecents(rememberProject(step.path));
  }, [activateTab, focusPane, updateTabs]);

  const openProject = useCallback((cwd: string) => openProjects([cwd]), [openProjects]);

  const pickProject = useCallback(async () => {
    try { openProjects(await pickFolders()); }
    catch (reason) { setError(String(reason)); }
  }, [openProjects]);

  const refreshHistory = useCallback(async (cwd = projectCwdRef.current) => {
    const request = ++historyRequest.current;
    setHistoryPending(true);
    setHistoryFailed(false);
    try {
      const rows = await listSessionsByProject(cwd);
      if (request === historyRequest.current) setHistory(rows);
    } catch { if (request === historyRequest.current) setHistoryFailed(true); }
    finally { if (request === historyRequest.current) setHistoryPending(false); }
  }, []);
  useEffect(() => { void refreshHistory(projectCwd); }, [projectCwd, refreshHistory]);

  const acceptSummary = useCallback((summary: SessionSummary) => {
    if (sameProjectPath(summary.cwd, projectCwdRef.current)) setHistory((current) => mergeHistorySummary(current, summary));
  }, []);

  const loadSession = useCallback((id: string): Promise<Session | null> => {
    if (sessionUnavailable(id)) return Promise.resolve(null);
    const open = latest.current.sessionsRef.current.find((session) => session.id === id);
    if (open) return Promise.resolve().then(() => sessionUnavailable(id) ? null
      : latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? open);
    const cached = loadedSessionCache.current.get(id);
    if (cached) {
      loadedSessionCache.current.delete(id);
      return Promise.resolve().then(() => sessionUnavailable(id) ? null : cached);
    }
    const pending = sessionLoads.current.get(id);
    if (pending) return pending;
    const epoch = sessionLoadEpochs.current.get(id) ?? 0;
    const loading = getSession(id).then((session) => {
      if (!session || sessionUnavailable(id) ||
          (sessionLoadEpochs.current.get(id) ?? 0) !== epoch ||
          removingProjects.current.has(normalizeProjectPath(session.cwd))) return null;
      return latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? session;
    }).catch(() => null);
    sessionLoads.current.set(id, loading);
    void loading.then(() => {
      if (sessionLoads.current.get(id) === loading) sessionLoads.current.delete(id);
    });
    return loading;
  }, [sessionUnavailable]);

  const openSession = useCallback(async (id: string): Promise<void> => {
    const agent = agentForSession(id);
    if (agent) { latest.current.onOpenAgent(agent.id); return; }
    if (sessionUnavailable(id)) return;
    openingSessionIds.current.add(id);
    try {
      const existing = findOpenSessionTab(tabsRef.current, latest.current.sessionsRef.current, id);
      if (existing) { focusPane(id); return; }
      const loaded = await loadSession(id);
      if (sessionUnavailable(id)) return;
      if (!loaded) throw new Error("This conversation is no longer available.");
      const appeared = findOpenSessionTab(tabsRef.current, latest.current.sessionsRef.current, id);
      if (appeared) { focusPane(id); return; }
      const session = latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? loaded;
      loadedSessionCache.current.delete(id);
      latest.current.bindSession(session);
      const active = tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
      const paneId = active && (isBlankSession(latest.current.sessionsRef.current.find((entry) => entry.id === active.focusedId))
        ? active.focusedId : leafIds(active.layout).find((paneId) =>
          isBlankSession(latest.current.sessionsRef.current.find((entry) => entry.id === paneId))));
      if (active && paneId && paneId !== id) {
        const blank = latest.current.sessionsRef.current.find((entry) => entry.id === paneId);
        if (blank) void forgetHarnessSession(blank.harness, paneId);
        const sessions = latest.current.sessionsRef.current.some((entry) => entry.id === id)
          ? latest.current.sessionsRef.current : [...latest.current.sessionsRef.current, session];
        const placed = applyPlaceSessionOnPane({
          tabs: tabsRef.current, sessions, sessionId: id, targetId: paneId, edge: "right",
          replaceTarget: true, scope: "project", createReplacement: (seed) => newSessionLike(seed, session.cwd),
        });
        if (placed) {
          latest.current.updateSessions(placed.sessions);
          updateTabs(placed.tabs);
          activateTab(placed.activeTabId);
        }
      } else addSession(session);
      setRecents(rememberProject(session.cwd));
    } catch (reason) { setError(String(reason)); }
    finally { openingSessionIds.current.delete(id); }
  }, [activateTab, addSession, focusPane, loadSession, sessionUnavailable, updateTabs]);

  const openSessionInCurrentTab = useCallback(async (id: string): Promise<void> => {
    const agent = agentForSession(id);
    if (agent) { latest.current.onOpenAgent(agent.id); return; }
    const origin = tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
    if (!origin || origin.focusedId === id || sessionUnavailable(id)) return;
    const tabId = origin.id;
    const focusedId = origin.focusedId;
    openingSessionIds.current.add(id);
    try {
      const loaded = await loadSession(id);
      if (!loaded || sessionUnavailable(id) || activeTabIdRef.current !== tabId) return;
      const current = tabsRef.current.find((tab) => tab.id === tabId);
      if (current?.focusedId !== focusedId) return;
      const next = switchSessionInTab(tabsRef.current, tabId, focusedId, id);
      if (!next) return;
      const session = latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? loaded;
      loadedSessionCache.current.delete(id);
      latest.current.bindSession(session);
      latest.current.updateSessions((sessions) => sessions.some((entry) => entry.id === id)
        ? sessions : [...sessions, session]);
      updateTabs(next);
      focusPane(id);
    } catch (reason) { setError(String(reason)); }
    finally { openingSessionIds.current.delete(id); }
  }, [focusPane, loadSession, sessionUnavailable, updateTabs]);

  const closeTabs = useCallback((ids: readonly string[], fallbackId?: string, options: { parked?: boolean } = {}) => {
    const closing = new Set(ids);
    const before = tabsRef.current;
    let nextTabs = before;
    let nextSessions = latest.current.sessionsRef.current;
    let target = activeTabIdRef.current;
    const focusedBefore = before.find((tab) => tab.id === target)?.focusedId;
    const closedRecords: Omit<ClosedTab, "batch" | "closedAt">[] = [];
    for (const original of before) {
      if (!closing.has(original.id)) continue;
      const tab = nextTabs.find((entry) => entry.id === original.id);
      if (!tab) continue;
      for (const id of leafIds(tab.layout)) {
        if (!skipForgetSessionIds.current.has(id)) {
          void latest.current.persistSession(nextSessions.find((session) => session.id === id)).catch((reason) => setError(String(reason)));
        }
      }
      const plan = planWorkspaceTabClose({
        tabs: nextTabs, sessions: nextSessions, closingTabId: tab.id, scope: "project",
      });
      if (plan.action === "close") {
        const record = describeClosedTab(tab, nextSessions, projectCwdRef.current);
        if (record) closedRecords.push(record);
        nextTabs = nextTabs.filter((entry) => entry.id !== tab.id);
        if (target === tab.id) target = plan.nextActiveTabId ?? nextTabs[0].id;
      } else {
        const seed = nextSessions.find((session) => session.id === tab.focusedId);
        if (leafIds(tab.layout).length === 1 && isBlankSession(seed)) continue;
        const replacement = newSessionLike(seed, seed && !isAgentSession(seed.id) ? seed.cwd : tab.cwd ?? projectCwdRef.current);
        nextSessions = [...nextSessions, replacement];
        nextTabs = nextTabs.map((entry) => entry.id === tab.id
          ? { ...entry, layout: { type: "leaf", id: replacement.id }, focusedId: replacement.id }
          : entry);
      }
    }
    if (closing.has(activeTabIdRef.current) && fallbackId && nextTabs.some((tab) => tab.id === fallbackId)) {
      target = fallbackId;
    }
    latest.current.updateSessions(nextSessions);
    updateTabs(nextTabs);
    closedTabs.record(closedRecords, { parked: options.parked });
    if (target !== activeTabIdRef.current || nextTabs.find((tab) => tab.id === target)?.focusedId !== focusedBefore) {
      activateTab(target);
    }
  }, [activateTab, updateTabs]);

  /**
   * Put back tabs closed together, panes and all. A conversation that is open
   * elsewhere or gone is left out, and tabs with nothing left are skipped.
   */
  const reopenClosed = useCallback(async (batch: number | "latest" = "latest"): Promise<boolean> => {
    const records = closedTabs.take(batch);
    let restored: string | undefined;
    let openedAgent = false;
    for (const record of records) {
      let layout: LayoutNode | null = record.layout;
      for (const pane of layoutLeaves(record.layout)) {
        if (pane.kind !== "session" || !layout) continue;
        const agent = agentForSession(pane.id);
        if (agent) {
          latest.current.onOpenAgent(agent.id);
          openedAgent = true;
          layout = removePane(layout, pane.id);
          continue;
        }
        if (findOpenSessionTab(tabsRef.current, latest.current.sessionsRef.current, pane.id)) {
          layout = removePane(layout, pane.id);
          continue;
        }
        const session = await loadSession(pane.id);
        if (!session || sessionUnavailable(pane.id)) {
          layout = removePane(layout, pane.id);
          continue;
        }
        loadedSessionCache.current.delete(pane.id);
        latest.current.bindSession(session);
        latest.current.updateSessions((current) => current.some((entry) => entry.id === session.id) ? current : [...current, session]);
      }
      if (!layout) continue;
      const cwd = record.cwd ?? projectCwdRef.current;
      const tab: WorkspaceTab = {
        kind: "session",
        id: crypto.randomUUID(),
        layout,
        focusedId: leafIds(layout).includes(record.focusedId) ? record.focusedId : firstLeafId(layout),
        ...(record.cwd ? { cwd: record.cwd } : {}),
        ...(record.pinned ? { pinned: true } : {}),
      };
      updateTabs((current) => pinnedFirst(insertTabBesideActive(current, tab, activeTabIdRef.current, (id) => {
        if (id === tab.id) return projectName(cwd);
        const existing = current.find((entry) => entry.id === id);
        const known = existing && workspaceTabCwd(existing, latest.current.sessionsRef.current);
        return known ? projectName(known) : undefined;
      })));
      restored = tab.id;
    }
    if (restored) activateTab(restored);
    else if (records.length && !openedAgent) setError("Those tabs are no longer available.");
    return restored !== undefined || openedAgent;
  }, [activateTab, loadSession, sessionUnavailable, updateTabs]);

  const pinTab = useCallback((id: string, pinned: boolean) => {
    updateTabs((current) => setTabPinned(current, id, pinned));
  }, [updateTabs]);

  const closePane = useCallback((id: string) => {
    const tab = tabsRef.current.find((entry) => leafIds(entry.layout).includes(id));
    if (!tab) return;
    if (!skipForgetSessionIds.current.has(id)) {
      void latest.current.persistSession(latest.current.sessionsRef.current.find((session) => session.id === id)).catch((reason) => setError(String(reason)));
    }
    const next = closeLeaf(tab, id);
    if (!next) { closeTabs([tab.id]); return; }
    updateTabs((current) => current.map((entry) => entry.id === tab.id ? { ...next, cwd: workspaceTabCwd(tab, latest.current.sessionsRef.current) ?? tab.cwd } : entry));
    activateTab(tab.id);
  }, [activateTab, closeTabs, updateTabs]);

  const split = useCallback((dir: SplitDir) => {
    const tab = tabsRef.current.find((entry) => entry.id === activeTabIdRef.current);
    if (!tab) return;
    const seed = latest.current.sessionsRef.current.find((session) => session.id === tab.focusedId);
    const session = newSessionLike(seed, seed && !isAgentSession(seed.id) ? seed.cwd : tab.cwd ?? projectCwdRef.current);
    latest.current.updateSessions((current) => [...current, session]);
    updateTabs((current) => current.map((entry) => entry.id === tab.id ? { ...entry, layout: splitPane(entry.layout, entry.focusedId, dir, session.id), focusedId: session.id } : entry));
    activateTab(tab.id);
  }, [activateTab, updateTabs]);

  const placeSession = useCallback(async (id: string, targetId: string, edge: PaneEdge) => {
    const session = await loadSession(id);
    if (!session || sessionUnavailable(id)) return;
    latest.current.bindSession(session);
    latest.current.updateSessions((current) => current.some((entry) => entry.id === id) ? current : [...current, session]);
    const target = latest.current.sessionsRef.current.find((entry) => entry.id === targetId);
    const result = applyPlaceSessionOnPane({ tabs: tabsRef.current, sessions: latest.current.sessionsRef.current, sessionId: id, targetId, edge, replaceTarget: isBlankSession(target), scope: "project", createReplacement: (seed) => newSessionLike(seed, seed?.cwd ?? projectCwdRef.current) });
    if (result) { latest.current.updateSessions(result.sessions); updateTabs(result.tabs); activateTab(result.activeTabId); }
  }, [activateTab, loadSession, sessionUnavailable, updateTabs]);

  const movePane = useCallback((id: string, targetId: string, edge: PaneEdge) => {
    const target = tabsRef.current.find((tab) => leafIds(tab.layout).includes(targetId));
    const result = applyMoveWorkspacePane(tabsRef.current, id, targetId, edge, latest.current.sessionsRef.current);
    if (result && target) { updateTabs(result); activateTab(target.id); }
  }, [activateTab, updateTabs]);

  const placeTab = useCallback((id: string, targetId: string, edge: PaneEdge) => {
    const target = latest.current.sessionsRef.current.find((entry) => entry.id === targetId);
    const result = applyPlaceTabOnPane({ tabs: tabsRef.current, sessions: latest.current.sessionsRef.current, sourceTabId: id, targetId, edge, replaceTarget: isBlankSession(target) });
    if (result) { latest.current.updateSessions(result.sessions); updateTabs(result.tabs); activateTab(result.activeTabId); }
  }, [activateTab, updateTabs]);

  const detachPane = useCallback((paneId: string, targetTabId: string, position: TitleTabDropPosition) => {
    const result = applyDetachPaneToTab({ tabs: tabsRef.current, paneId, targetTabId, position, sessions: latest.current.sessionsRef.current });
    if (result) { updateTabs(result.tabs); activateTab(result.activeTabId); }
  }, [activateTab, updateTabs]);

  const changeCwd = useCallback((id: string, cwd: string) => {
    latest.current.updateSessions((current) => current.map((session) => session.id === id ? retargetSessionToProject(session, cwd) : session));
    setRecents(rememberProject(cwd));
    projectCwdRef.current = cwd; setProjectCwd(cwd);
    focusPane(id);
  }, [focusPane]);

  const renameSession = useCallback(async (id: string, title: string) => {
    const trimmed = title.trim();
    if (!trimmed || sessionUnavailable(id)) return;
    invalidateLoadedSession(id);
    const loaded = await loadSession(id);
    if (!loaded || sessionUnavailable(id)) return;
    const session = latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? loaded;
    const updated = { ...session, title: trimmed };
    latest.current.updateSessions((current) => current.map((entry) => entry.id === id ? updated : entry));
    const saved = await upsertSession(updated);
    if (!saved || sessionUnavailable(id)) return;
    if (!latest.current.sessionsRef.current.some((entry) => entry.id === id)) {
      rememberLoadedSession(loadedSessionCache.current, updated);
    }
    acceptSummary(saved);
  }, [acceptSummary, invalidateLoadedSession, loadSession, sessionUnavailable]);

  const removeHistorySession = useCallback(async (id: string, mode: "archive" | "delete"): Promise<boolean> => {
    if (sessionUnavailable(id)) return false;
    const cached = loadedSessionCache.current.get(id);
    removingSessionIds.current.add(id);
    invalidateLoadedSession(id);
    if (mode === "delete") skipForgetSessionIds.current.add(id);
    try {
      const seed = latest.current.sessionsRef.current.find((session) => session.id === id)
        ?? cached ?? await getSession(id);
      if (!seed) return false;
      const remover = createSessionRemover({
        mode,
        scope: "project",
        replacement: seed,
        confirm: async () => mode === "archive" || await ask(
          `Delete “${sessionDisplayTitle(seed.title, seed.harness)}”? This conversation will be permanently removed.`,
          { title: "Delete conversation", kind: "warning", okLabel: "Delete", cancelLabel: "Cancel" },
        ),
        stop: async (sessionId) => {
          await latest.current.stopSession(sessionId);
          await latest.current.flushPersistence();
        },
        workspace: {
          snapshot: () => ({
            tabs: tabsRef.current,
            sessions: latest.current.sessionsRef.current,
            activeTabId: activeTabIdRef.current,
          }),
          apply: (change) => {
            if (change.type === "stopped") {
              latest.current.updateSessions((sessions) => sessions.map((session) =>
                session.id === id ? change.session : session));
              return;
            }
            const { removal } = change;
            const before = tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
            invalidateLoadedSession(id);
            if (mode === "delete") deletedSessionIds.current.add(id);
            else rememberLoadedSession(loadedSessionCache.current, change.session ?? seed);
            latest.current.updateSessions(removal.sessions);
            updateTabs(removal.tabs);
            const after = removal.tabs.find((tab) => tab.id === removal.activeTabId);
            if (removal.activeTabId !== activeTabIdRef.current || after?.focusedId !== before?.focusedId) {
              activateTab(removal.activeTabId);
            }
            if (mode === "delete") setHistory((history) => history.filter((row) => row.id !== id));
            else acceptSummary({ ...(change.savedSummary ?? summaryFromSession(change.session ?? seed)), archived: true });
          },
        },
      });
      const removed = await remover.remove(id);
      if (removed) await refreshHistory();
      return removed;
    } catch (reason) {
      setError(String(reason));
      return false;
    } finally {
      removingSessionIds.current.delete(id);
      skipForgetSessionIds.current.delete(id);
      if (cached && !deletedSessionIds.current.has(id) && !loadedSessionCache.current.has(id)
          && !latest.current.sessionsRef.current.some((session) => session.id === id)) {
        rememberLoadedSession(loadedSessionCache.current, cached);
      }
    }
  }, [acceptSummary, activateTab, invalidateLoadedSession, refreshHistory, sessionUnavailable, updateTabs]);

  const archiveSession = useCallback(async (id: string, archived: boolean): Promise<boolean> => {
    if (archived) return removeHistorySession(id, "archive");
    if (sessionUnavailable(id)) return false;
    try {
      await setSessionArchived(id, false);
      await refreshHistory();
      return true;
    } catch (reason) { setError(String(reason)); return false; }
  }, [refreshHistory, removeHistorySession, sessionUnavailable]);

  const pinSession = useCallback(async (id: string, pinned: boolean) => {
    if (sessionUnavailable(id)) return;
    const open = latest.current.sessionsRef.current.find((session) => session.id === id);
    if (open) await upsertSession(open);
    if (sessionUnavailable(id)) return;
    await setSessionPinned(id, pinned);
    await refreshHistory();
  }, [refreshHistory, sessionUnavailable]);

  const removeSession = useCallback((id: string) => removeHistorySession(id, "delete"), [removeHistorySession]);

  const removeProject = useCallback(async (cwd: string, settings: { purgeData: boolean }) => {
    const normalized = normalizeProjectPath(cwd);
    if (removingProjects.current.has(normalized)) return;
    removingProjects.current.add(normalized);
    const removedIds = new Set<string>();
    const lockedIds = new Set<string>();
    const savedSnapshots = new Set<Session>();
    try {
      if (settings.purgeData) {
        for (const id of new Set([...loadedSessionCache.current.keys(), ...sessionLoads.current.keys()])) {
          invalidateLoadedSession(id);
        }
        const sessions = latest.current.sessionsRef.current.filter((session) => sameProjectPath(session.cwd, normalized));
        for (const session of sessions) {
          lockedIds.add(session.id);
          removingSessionIds.current.add(session.id);
          skipForgetSessionIds.current.add(session.id);
          await latest.current.stopSession(session.id);
        }
        await latest.current.flushPersistence();
        const records = await listSessionsByProject(normalized);
        for (const row of records) {
          lockedIds.add(row.id);
          removingSessionIds.current.add(row.id);
          invalidateLoadedSession(row.id);
          await deleteSession(row.id);
          deletedSessionIds.current.add(row.id);
          removedIds.add(row.id);
        }
        await removeProjectData(normalized);
        forgetProjectLocation(normalized);
      } else {
        const idle = latest.current.sessionsRef.current.filter((session) =>
          sameProjectPath(session.cwd, normalized) && !hasLiveSessionWork(session));
        await Promise.all(idle.map((session) => latest.current.persistSession(session)));
        for (const session of idle) {
          savedSnapshots.add(session);
          if (latest.current.sessionsRef.current.includes(session)) {
            rememberLoadedSession(loadedSessionCache.current, session);
          }
        }
      }
      const sessions = latest.current.sessionsRef.current;
      const projectTabs = new Set(filterTabsForProject(tabsRef.current, sessions, normalized).map((tab) => tab.id));
      let nextTabs = tabsRef.current.filter((tab) => !projectTabs.has(tab.id));
      let nextSessions = sessions.filter((session) => !sameProjectPath(session.cwd, normalized)
        || (!settings.purgeData && (hasLiveSessionWork(session) || !savedSnapshots.has(session))));
      let target = activeTabIdRef.current;
      if (nextTabs.length === 0) {
        const blank = newDefaultSession("~");
        const tab = newTab(blank.id);
        nextSessions = [...nextSessions, blank];
        nextTabs = [tab];
        target = tab.id;
      } else if (!nextTabs.some((tab) => tab.id === target)) target = nextTabs[0].id;
      latest.current.updateSessions(nextSessions);
      updateTabs(nextTabs);
      const wasCurrent = sameProjectPath(projectCwdRef.current, normalized);
      const remaining = settings.purgeData ? forgetProject(normalized) : archiveProject(normalized);
      setRecents(remaining);
      if (wasCurrent) {
        const fallback = remaining[0]?.path;
        if (fallback) openProject(fallback);
        else {
          projectCwdRef.current = "~";
          setProjectCwd("~");
          activateTab(target);
        }
      } else if (target !== activeTabIdRef.current) activateTab(target);
    } catch (reason) {
      // A completed native delete cannot be undone by putting its old live
      // transcript back. Preserve every record whose delete did not succeed.
      for (const id of removedIds) {
        const removal = removeSessionFromWorkspace({
          tabs: tabsRef.current, sessions: latest.current.sessionsRef.current,
          activeTabId: activeTabIdRef.current, sessionId: id, scope: "project",
          createReplacement: (seed) => newSessionLike(seed, seed?.cwd ?? projectCwdRef.current),
        });
        latest.current.updateSessions(removal.sessions);
        updateTabs(removal.tabs);
        if (removal.activeTabId !== activeTabIdRef.current) activateTab(removal.activeTabId);
      }
      if (removedIds.size) setHistory((history) => history.filter((row) => !removedIds.has(row.id)));
      setError(String(reason));
    } finally {
      removingProjects.current.delete(normalized);
      for (const id of lockedIds) {
        removingSessionIds.current.delete(id);
        skipForgetSessionIds.current.delete(id);
      }
    }
  }, [activateTab, invalidateLoadedSession, openProject, updateTabs]);

  const placeInFolder = useCallback((id: string, target: SessionFolderTarget) => {
    const session = latest.current.sessionsRef.current.find((entry) => entry.id === id);
    if (!session) return;
    saveSessionFolders(session.cwd, placeSessionInFolder(loadSessionFolders(session.cwd), id, target));
  }, []);

  useEffect(() => {
    projectReturnMemory.current = reconcileProjectReturn({ memory: projectReturnMemory.current, tabs, sessions: options.sessions, activeTabId });
    setVisits((current) => pruneTabVisitHistory(current, new Set(tabs.map((tab) => tab.id)), activeTabId));
  }, [tabs, options.sessions, activeTabId]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      if (isAppQuitting()) return;
      const snapshot = collectWorkspaceSnapshot(tabsRef.current, latest.current.sessionsRef.current, activeTabIdRef.current, projectCwdRef.current, projectReturnMemory.current);
      void saveWorkspaceSnapshot(snapshot).catch((reason) => setError(String(reason)));
    }, 300);
    return () => window.clearTimeout(timer);
  }, [tabs, activeTabId, projectCwd, options.sessions]);

  const activeTab = tabs.find((tab) => tab.id === activeTabId) ?? tabs[0];
  const activeSession = options.sessions.find((session) => session.id === activeTab?.focusedId);
  const visibleTabs = filterTabsForProject(tabs, options.sessions, projectCwd);
  const sidebarHistory = useMemo(() => historyWithLiveSessions(history, options.sessions, projectCwd), [history, options.sessions, projectCwd]);
  const openProjectSessions = useMemo(() => options.sessions.filter((session) => sameProjectPath(session.cwd, projectCwd) && tabs.some((tab) => leafIds(tab.layout).includes(session.id))).map(summaryFromSession), [options.sessions, projectCwd, tabs]);

  const openCanvas = useCallback((canvasId: string, cwd?: string) => {
    const alreadyOpen = tabsRef.current.find((tab) => leafIds(tab.layout).includes(canvasId));
    if (alreadyOpen) {
      latest.current.updateSessions((current) => current.filter((session) => session.id !== canvasId));
      updateTabs((current) => current.map((tab) => tab.id === alreadyOpen.id ? { ...tab, cwd: tab.cwd ?? cwd ?? projectCwdRef.current, layout: replacePaneWithLayout(tab.layout, canvasId, canvasLeaf(canvasId)), focusedId: canvasId } : tab));
      activateTab(alreadyOpen.id);
      return;
    }
    const tab = newTab(canvasId);
    const canvasTab = { ...tab, cwd: cwd || projectCwdRef.current, layout: canvasLeaf(canvasId), focusedId: canvasId };
    updateTabs((current) => insertTabBesideActive(current, canvasTab, activeTabIdRef.current, () => undefined));
    activateTab(canvasTab.id);
  }, [activateTab, updateTabs]);

  const isCanvasOpen = useCallback((canvasId: string) => tabsRef.current.some((tab) => leafIds(tab.layout).includes(canvasId)), []);
  /** Put an agent's drawing next to its session, without taking focus. */
  const revealCanvas = useCallback((canvasId: string, sessionId: string) => {
    const cwd = latest.current.sessionsRef.current.find((session) => session.id === sessionId)?.cwd ?? projectCwdRef.current;
    updateTabs((current) => {
      const next = showCanvasForSession(current, activeTabIdRef.current, canvasId, sessionId);
      return next === current ? current : next.map((tab) => leafIds(tab.layout).includes(canvasId) ? { ...tab, cwd: tab.cwd ?? cwd } : tab);
    });
  }, [updateTabs]);

  /** Show a drawing in a pane of the active tab, beside whatever is open there. */
  const showCanvas = useCallback((canvasId: string) => {
    const home = tabsRef.current.find((tab) => leafIds(tab.layout).includes(canvasId))
      ?? tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
    if (!home) return;
    updateTabs((current) => current.map((tab) => tab.id === home.id ? { ...showCanvasInTab(tab, canvasId), cwd: tab.cwd ?? projectCwdRef.current } : tab));
    activateTab(home.id);
  }, [activateTab, updateTabs]);

  const showDocument = useCallback((document: AgentDocument, agentId?: string) => {
    const id = documentPaneId(document.id, agentId);
    const home = tabsRef.current.find((tab) => leafIds(tab.layout).includes(id))
      ?? tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
    if (!home) return;
    updateTabs((current) => current.map((tab) => tab.id === home.id
      ? { ...showDocumentInTab(tab, document, agentId), cwd: tab.cwd ?? projectCwdRef.current } : tab));
    activateTab(home.id);
  }, [activateTab, updateTabs]);

  const showWidget = useCallback((widget: WidgetRef, title: string, sourceSessionId?: string) => {
    const id = widgetPaneId(widget);
    const home = tabsRef.current.find((tab) => leafIds(tab.layout).includes(id))
      ?? tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
    if (!home) return;
    updateTabs((current) => current.map((tab) => tab.id === home.id
      ? { ...showWidgetInTab(tab, widget, title, sourceSessionId), cwd: tab.cwd ?? projectCwdRef.current } : tab));
    activateTab(home.id);
  }, [activateTab, updateTabs]);

  /** Show a project file in the active tab; a single click previews, `pin` keeps the pane. */
  const openFile = useCallback((path: string, pin = false) => {
    const id = filePaneId(path);
    const home = tabsRef.current.find((tab) => leafIds(tab.layout).includes(id))
      ?? tabsRef.current.find((tab) => tab.id === activeTabIdRef.current);
    if (!home) return;
    updateTabs((current) => current.map((tab) => tab.id === home.id ? { ...showFileInTab(tab, path, pin), cwd: tab.cwd ?? projectCwdRef.current } : tab));
    activateTab(home.id);
  }, [activateTab, updateTabs]);

  /** Drop a file onto the edge of a pane, moving its pane there if it is already open. */
  const placeFile = useCallback((path: string, targetId: string, edge: PaneEdge) => {
    const id = filePaneId(path);
    const target = tabsRef.current.find((tab) => leafIds(tab.layout).includes(targetId));
    if (!target) return;
    updateTabs((current) => current.flatMap((tab) => {
      if (tab.id === target.id) return [{ ...placeFileOnPane(tab, path, targetId, edge), cwd: tab.cwd ?? projectCwdRef.current }];
      // A file has one pane: it leaves the tab it was open in.
      return leafIds(tab.layout).includes(id) ? closeLeaf(tab, id) ?? [] : [tab];
    }));
    activateTab(target.id);
  }, [activateTab, updateTabs]);

  /** Keep open file panes on a file or folder that was renamed or moved. */
  const fileMoved = useCallback((from: string, to: string) => {
    moveFileDrafts((path) => rebasePath(path, from, to));
    updateTabs((current) => {
      const next = current.map((tab) => rebaseFilePanes(tab, (path) => rebasePath(path, from, to)));
      return next.some((tab, index) => tab !== current[index]) ? next : current;
    });
  }, [updateTabs]);

  /** Close the panes of a deleted file, or of every file in a deleted folder. */
  const fileDeleted = useCallback((path: string) => {
    for (const tab of tabsRef.current) {
      for (const pane of layoutLeaves(tab.layout)) {
        if (pane.kind === "file" && isEqualOrInside(filePanePath(pane.id), path)) {
          setFileDraft(filePanePath(pane.id), null);
          closePane(pane.id);
        }
      }
    }
  }, [closePane]);

  const visit = useCallback((direction: "back" | "forward") => {
    setVisits((current) => {
      const next = direction === "back" ? tabVisitBack(current) : tabVisitForward(current);
      if (next) activateTab(next.current, false);
      return next ?? current;
    });
  }, [activateTab]);

  return { isSessionUnavailable: sessionUnavailable, tabs, tabsRef, activeTabId, activeTabIdRef, projectCwd, projectCwdRef, projectReturnMemory, recents, history, historyPending, historyFailed, error, setError, composerFocusToken, activeTab, activeSession, visibleTabs, sidebarHistory, openProjectSessions, loadedSessionCache, openingSessionIds, skipForgetSessionIds, updateTabs, activateTab, addSession, createSession, focusPane, openProject, pickProject, refreshHistory, acceptSummary, loadSession, openSession, openSessionInCurrentTab, closeTabs, closePane, split, placeSession, movePane, placeTab, detachPane, changeCwd, renameSession, archiveSession, pinSession, removeSession, removeProject, placeInFolder, visits, visit, openCanvas, revealCanvas, isCanvasOpen, showCanvas, showDocument, showWidget, openFile, placeFile, fileMoved, fileDeleted, reopenClosed, pinTab,
    ratio: (splitId: string, index: number, ratio: number) => updateTabs((current) => current.map((tab) => ({ ...tab, layout: setSplitRatio(tab.layout, splitId, index, ratio) }))),
    focusDirection: (direction: FocusDir) => { const tab = tabsRef.current.find((entry) => entry.id === activeTabIdRef.current); const id = tab && neighborLeafId(tab.layout, tab.focusedId, direction); if (id) focusPane(id); },
    cycleTab: (delta: number) => { const current = filterTabsForProject(tabsRef.current, latest.current.sessionsRef.current, projectCwdRef.current); const index = current.findIndex((tab) => tab.id === activeTabIdRef.current); const next = current[(index + delta + current.length) % current.length]; if (next) activateTab(next.id); },
    reorderTabs: (ids: string[]) => updateTabs((current) => { const order = new Map(ids.map((id, index) => [id, index])); const sorted = current.filter((tab) => order.has(tab.id)).sort((a, b) => order.get(a.id)! - order.get(b.id)!); let index = 0; return pinnedFirst(current.map((tab) => order.has(tab.id) ? sorted[index++] : tab)); }),
  };
}

/** A tab holding one empty conversation in this project, ready to be used. */
export function findBlankTab(tabs: readonly WorkspaceTab[], sessions: readonly Session[], cwd: string): { tab: WorkspaceTab; sessionId: string } | null {
  for (const tab of filterTabsForProject([...tabs], [...sessions], cwd)) {
    const ids = leafIds(tab.layout);
    if (ids.length !== 1) continue;
    const session = sessions.find((entry) => entry.id === ids[0]);
    if (session && isBlankSession(session) && sameProjectPath(session.cwd, cwd)) return { tab, sessionId: session.id };
  }
  return null;
}

/** What a closed tab needs to come back, or nothing for a tab that held no work. */
function describeClosedTab(tab: WorkspaceTab, sessions: readonly Session[], fallbackCwd: string): Omit<ClosedTab, "batch" | "closedAt"> | null {
  const panes = layoutLeaves(tab.layout);
  const holdsWork = panes.some((pane) => pane.kind !== "session" || !isBlankSession(sessions.find((entry) => entry.id === pane.id)));
  if (!holdsWork) return null;
  const focused = panes.find((pane) => pane.id === tab.focusedId) ?? panes[0];
  const session = sessions.find((entry) => entry.id === focused?.id) ?? sessions.find((entry) => panes.some((pane) => pane.id === entry.id));
  const agent = session && agentForSession(session.id);
  const cwd = workspaceTabCwd(tab, sessions) ?? fallbackCwd;
  const title = focused?.kind === "file" ? filePanePath(focused.id).split("/").pop() ?? ""
    : focused?.kind === "canvas" ? "Drawing"
      : focused?.kind === "document" ? focused.document?.title ?? "Document"
      : agent ? agentLook(agent).name : session ? sessionDisplayTitle(session.title, session.harness) : "";
  return {
    layout: tab.layout,
    focusedId: tab.focusedId,
    cwd,
    title,
    project: projectName(cwd),
    ...(tab.pinned ? { pinned: true } : {}),
    ...(focused && focused.kind !== "session" ? { paneKind: focused.kind } : {}),
  };
}
