import { startTransition, Suspense, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Sidebar } from "./shell/Sidebar";
import { TitleBar } from "./shell/TitleBar";
import { MenuBar } from "./shell/MenuBar";
import { UsageFooter } from "./shell/UsageFooter";
import { PaneTree } from "../features/workspace/ui/PaneTree";
import { ApprovalToasts } from "../features/sessions/ui/ApprovalToasts";
import { ReminderNotices } from "../features/sessions/ui/ReminderNotices";
import { TranscriptPool, TranscriptPoolOutlet } from "../features/sessions/ui/TranscriptPool";
import { FileActionError } from "../shared/ui/FileActionError";
import { HAS_NATIVE_GLASS, IS_MAC } from "../platform/tauri/platform";
import { openPathWithDefaultApp } from "../platform/tauri/fs";
import { isEqualOrInside } from "../shared/lib/paths";
import { FILE_POINTER_DRAG_EVENT, type FilePointerDragDetail } from "../shared/lib/drag";
import { paneDropFromPoint, setExternalPaneDrop } from "../features/workspace/model/paneDrop";
import { lazySurface } from "../shared/ui/lazySurface";
import { preloadNavigationWhenIdle } from "./model/preloadNavigation";
import { ProviderSignInDialog } from "../features/sessions/ui/ProviderSignInDialog";
import { latestTurnNeedsHarnessLogin, supportsHarnessLogin } from "../integrations/harness/core/authSupport";
import { registerBuiltinHarnesses } from "../integrations/harness/core/register";
import { probeHarnessAvailability } from "../integrations/harness/core/availability";
import { refreshHarnessCatalogs } from "../integrations/harness/core/registry";
import { newDefaultSession, newSession, sessionNeedsInput, type HarnessId, type Session } from "../features/sessions/model/session";
import { requestTranscriptJump } from "../features/sessions/model/transcriptJump";
import { useUnseenFinishedSessions } from "../features/sessions/hooks/useUnseenFinishedSessions";
import { liveAgentsFromSessions } from "../features/sessions/model/liveAgents";
import { TOGGLE_SECONDARY_SIDEBAR_EVENT } from "./shell/SecondarySidebar";
import { closedTabs } from "../features/workspace/model/closedTabs";
import { TabSwitcher } from "./shell/TabSwitcher";
import { TabOverview } from "./shell/TabOverview";
import { ClosedTabToast } from "./shell/ClosedTabToast";
import { SavedToast, type SavedToastData } from "./shell/SavedToast";
import { attentionOrder, heldTabIds, idleTabIds, parkingCandidates, trackTabGrowth, type TabCountMark } from "../features/workspace/model/tabParking";
import { loadTabLimit } from "../features/settings/model/settings";
import { pathKey } from "../shared/lib/paths";
import type { Tab } from "./shell/TitleBar";
import { linkFamilies } from "../features/workspace/model/tabFamily";
import { summarizeTab } from "../features/workspace/model/tabSummary";
import { filePaneId, findLeaf, leafIds } from "../features/workspace/model/layout";
import { loadProjectRailOpen, loadSessionSidebarOpen, saveProjectRailOpen, saveSessionSidebarOpen, watchSystemColorScheme } from "../features/settings/model/appearance";
import { loadCloseToTray, loadCollapsedProjectRailMode, loadLiveAgentsEnabled, loadNotesEnabled, loadSettingsSection, saveCollapsedProjectRailMode, saveSettingsSection, subscribeCollapsedProjectRailMode, subscribeLiveAgentsEnabled, subscribeNotesEnabled, type SettingsSectionId } from "../features/settings/model/settings";
import { applyUiScale, loadUiScale, saveUiScale, UI_SCALE_DEFAULT, zoomInUiScale, zoomOutUiScale } from "../features/settings/model/uiScale";
import { announceSessionFinished } from "../features/notifications/model/notifications";
import { hiddenApprovalNotices } from "../features/notifications/model/approvalToast";
import { syncDockBadge } from "../features/notifications/model/dockBadge";
import { useInputNotifications } from "../features/notifications/hooks/useInputNotifications";
import { useSessionReminders } from "../features/notifications/hooks/useSessionReminders";
import { ADD_NOTE_TO_CHAT_EVENT, type NoteComposerCard } from "../features/notes";
import { CANVASES_CHANGED_EVENT, createEmptyCanvas, deleteCanvas, loadCanvases, updateCanvas, upsertCanvas, type Canvas } from "../features/canvas/canvas";
import { SelectCanvasDialog } from "../features/canvas/ui/SelectCanvasDialog";
import { synchronizeProjectLocation, rememberProjectLocation } from "../features/projects/model/projectLocation";
import { rebaseProjectData } from "../features/projects/model/projectData";
import { looksLikeProject, replaceProjectPath, sameProjectPath } from "../features/projects/model/recents";
import { rebaseProjectSessions } from "../features/sessions/data/sessionStore";
import { ProjectNotFoundError } from "../features/projects/model/projectLocationError";
import { closeBusyWindow, hasInFlightSessions, hideCurrentWindow, isAppQuitting, persistAndCloseWindow, persistLiveTranscripts, persistQuitState, setQuitWorkspace, type BootWorkspace, type WorkspaceSaveMode } from "./model/appLifecycle";
import { useAppWorkspace, initialWorkspace } from "./hooks/useAppWorkspace";
import { useSessionRuntime } from "./hooks/useSessionRuntime";
import { useSessionSubmission } from "./hooks/useSessionSubmission";
import { useIdleSessionDetach } from "./hooks/useIdleSessionDetach";
import { useAppCommands } from "./hooks/useAppCommands";
import { useAppControl } from "./hooks/useAppControl";
import { useAppResourceNavigation } from "./hooks/useAppResourceNavigation";
import { useSaveToCanvas } from "./hooks/useSaveToCanvas";
import type { NoteOpenRequest } from "../features/notes/ui/NotesView";

const SearchView = lazySurface(async () => ({ default: (await import("../features/search/ui/SearchView")).SearchView }), { suspense: false });
const SettingsView = lazySurface(async () => ({ default: (await import("../features/settings/ui/SettingsView")).SettingsView }), { suspense: false });
const NotesView = lazySurface(async () => ({ default: (await import("../features/notes/ui/NotesView")).NotesView }), { suspense: false });

const CanvasesView = lazySurface(async () => ({ default: (await import("../features/canvas/ui/CanvasesView")).CanvasesView }), { suspense: false });

registerBuiltinHarnesses();
type Surface = "chat" | "search" | "notes" | "canvases" | "settings";

export default function App(boot: BootWorkspace) {
  return <Suspense fallback={null}><Workspace {...boot} /></Suspense>;
}

function signInRequestKey(session: Session): string {
  const lastUser = [...session.blocks].reverse().find((block) => block.role === "user");
  return `${session.id}:${lastUser?.id ?? session.blocks[session.blocks.length - 1]?.id ?? "auth"}`;
}

function Workspace(boot: BootWorkspace) {
  const [initial] = useState(() => initialWorkspace(boot));
  const [sessions, setSessions] = useState<Session[]>(initial.sessions);
  const sessionsRef = useRef(sessions);
  const [surface, setSurface] = useState<Surface>("chat");
  const surfaceRef = useRef(surface);
  surfaceRef.current = surface;
  const settingsReturn = useRef<Surface>("chat");
  const [settingsSection, setSettingsSection] = useState(loadSettingsSection);
  const [settingsAnchor, setSettingsAnchor] = useState<string | null>(null);
  const [notificationProjectPath, setNotificationProjectPath] = useState<string | null>(null);
  const [notificationSettingsRequest, setNotificationSettingsRequest] = useState(0);
  const [projectRailOpen, setProjectRailOpen] = useState(loadProjectRailOpen);
  const [sessionSidebarOpen, setSessionSidebarOpen] = useState(loadSessionSidebarOpen);
  const [searchFocusToken, setSearchFocusToken] = useState(0);
  const [noteOpenRequest, setNoteOpenRequest] = useState<NoteOpenRequest>();
  const [savedToast, setSavedToast] = useState<SavedToastData | null>(null);
  const [sessionOrder, setSessionOrder] = useState<readonly string[]>([]);
  const [reminderNoticesHeight, setReminderNoticesHeight] = useState(0);
  const [transcriptPool] = useState(() => new TranscriptPool());
  const [canvases, setCanvases] = useState<Canvas[]>([]);
  const [providerSignIn, setProviderSignIn] = useState<{ key: string; sessionId: string; harness: HarnessId } | null>(null);
  const seenSignInRequests = useRef(new Set(initial.sessions.filter((session) => latestTurnNeedsHarnessLogin(session.blocks)).map(signInRequestKey)));
  const workspaceRef = useRef<ReturnType<typeof useAppWorkspace> | null>(null);
  const closeSurface = useCallback(() => setSurface("chat"), []);
  const notesEnabled = useSyncExternalStore(subscribeNotesEnabled, loadNotesEnabled);
  const liveAgentsEnabled = useSyncExternalStore(subscribeLiveAgentsEnabled, loadLiveAgentsEnabled);
  const collapsedProjectRailMode = useSyncExternalStore(subscribeCollapsedProjectRailMode, loadCollapsedProjectRailMode);

  const isForeground = useCallback((id: string) => {
    const workspace = workspaceRef.current;
    const tab = workspace?.tabsRef.current.find((entry) => entry.id === workspace.activeTabIdRef.current);
    return surfaceRef.current === "chat" && !!tab && leafIds(tab.layout).includes(id);
  }, []);
  const runtime = useSessionRuntime({ sessions, sessionsRef, setSessions, isForeground,
    onPersisted: (summary) => workspaceRef.current?.acceptSummary(summary),
    onPersistenceError: (error) => workspaceRef.current?.setError(String(error)),
    onFinished: (session) => { void announceSessionFinished(session, isForeground(session.id)); },
  });
  const submission = useSessionSubmission({ runtime,
    synchronizeProject: async (cwd) => {
      const location = await synchronizeProjectLocation(cwd);
      if (!location) throw new ProjectNotFoundError(cwd);
      if (!location.moved) return;
      await rebaseProjectSessions(cwd, location.path);
      rebaseProjectData(cwd, location.path);
      replaceProjectPath(cwd, location.path);
      runtime.updateSessions((current) => current.map((session) => sameProjectPath(session.cwd, cwd) ? { ...session, cwd: location.path } : session));
      if (sameProjectPath(workspaceRef.current?.projectCwdRef.current ?? "", cwd)) workspaceRef.current?.openProject(location.path);
    },
    onDraftDiscarded: () => { void workspaceRef.current?.refreshHistory(); },
  });
  const workspace = useAppWorkspace({ boot, initial, sessions, sessionsRef,
    updateSessions: runtime.updateSessions,
    persistSession: runtime.persistSession,
    bindSession: runtime.bindRestoredSession,
    stopSession: submission.stop,
    flushPersistence: runtime.flushPersistence,
    onNavigate: closeSurface,
  });
  workspaceRef.current = workspace;
  const { saveToCanvas: _saveToCanvas, selection: canvasSelection } = useSaveToCanvas({ canvases, workspaceRef });
  const saveToCanvas = async (text: string, anchor?: HTMLElement | null) => {
    const id = await _saveToCanvas(text, anchor);
    const title = canvases.find((c) => c.id === id)?.title ?? "";
    setSavedToast({ type: "canvas", id, title });
  };
  const active = workspace.activeSession;
  const busySessionIds = useMemo(() => new Set(sessions.filter((session) => session.busy).map((session) => session.id)), [sessions]);
  const approvalSessionIds = useMemo(() => new Set(sessions.filter(sessionNeedsInput).map((session) => session.id)), [sessions]);
  const unseenFinishedIds = useUnseenFinishedSessions(busySessionIds, surface === "chat" ? active?.id : undefined);
  const liveAgents = useMemo(() => liveAgentsEnabled ? liveAgentsFromSessions(sessions, unseenFinishedIds) : [], [sessions, unseenFinishedIds, liveAgentsEnabled]);
  useInputNotifications(sessions, surface === "chat" ? active?.id : undefined);
  useEffect(() => syncDockBadge(sessions), [sessions]);
  useEffect(() => {
    let stopped = false;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow().onFocusChanged(({ payload: focused }) => {
      if (!focused) return;
      runtime.flushEvents();
      syncDockBadge(sessionsRef.current);
      const view = workspaceRef.current;
      if (surfaceRef.current === "chat" && document.activeElement === document.body && view?.activeSession) view.focusPane(view.activeSession.id);
    }).then((release) => { if (stopped) release(); else unlisten = release; });
    return () => { stopped = true; unlisten?.(); };
  }, [runtime.flushEvents]);
  const ensureSaved = useCallback(async (ids: readonly string[]) => {
    await Promise.all(ids.map((id) => runtime.persistSession(id)));
  }, [runtime.persistSession]);
  const reminders = useSessionReminders(workspace.openSession, ensureSaved, sessions.map((session) => session.id));
  useIdleSessionDetach({ sessions, sessionsRef, tabs: workspace.tabs, tabsRef: workspace.tabsRef,
    liveAgentsEnabled, unseenFinishedIds, openingSessionIds: workspace.openingSessionIds,
    loadedSessionCache: workspace.loadedSessionCache, skipForgetSessionIds: workspace.skipForgetSessionIds,
    persistSession: runtime.persistSession,
    onError: (error) => workspaceRef.current?.setError(String(error)), setSessions: runtime.updateSessions,
  });
  useAppControl({ workspace, runtime, submission });
  useAppResourceNavigation({ workspace, notesEnabled, onOpenNote: (id) => {
    setNoteOpenRequest((previous) => ({ id, sequence: (previous?.sequence ?? 0) + 1 }));
    setSurface("notes");
  } });

  const openSettings = useCallback((section?: SettingsSectionId, anchor: string | null = null) => {
    if (surfaceRef.current !== "settings") settingsReturn.current = surfaceRef.current;
    if (section) { setSettingsSection(section); saveSettingsSection(section); }
    setSettingsAnchor(anchor);
    startTransition(() => setSurface("settings"));
  }, []);
  const onSelectSettingsSection = useCallback((section: SettingsSectionId) => {
    setSettingsSection(section); saveSettingsSection(section); setSettingsAnchor(null);
  }, []);
  const openSearch = useCallback(() => startTransition(() => { setSurface("search"); setSearchFocusToken((token) => token + 1); }), []);
  const openCanvases = useCallback(() => startTransition(() => setSurface("canvases")), []);
  const newCanvas = useCallback(async () => {
    const view = workspaceRef.current!;
    try { return await upsertCanvas(createEmptyCanvas(view.projectCwdRef.current)); }
    catch (error) { view.setError(String(error)); return undefined; }
  }, []);
  const renameCanvas = (id: string, title: string) => {
    void updateCanvas(id, { title }).catch((error) => workspace.setError(String(error)));
  };
  const handleDeleteCanvas = (id: string) => {
    void deleteCanvas(id).catch((error) => workspace.setError(String(error)));
  };
  const canvasAddToChat = (text: string) => {
    const view = workspaceRef.current!;
    const session = { ...newDefaultSession(view.projectCwdRef.current, view.activeSession?.runtimeMode), title: "Canvas context" };
    view.addSession({ ...session, noteCard: { id: crypto.randomUUID(), slug: "canvas-context", title: "Canvas context", body: text } });
  };
  const openCanvas = (id: string) => workspace.openCanvas(id, canvases.find((canvas) => canvas.id === id)?.cwd);
  const openNotes = useCallback(() => { if (loadNotesEnabled()) startTransition(() => { setNoteOpenRequest(undefined); setSurface("notes"); }); }, []);
  const toggleProjectRail = useCallback(() => setProjectRailOpen((open) => { saveProjectRailOpen(!open); return !open; }), []);
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const openTabSwitcher = useCallback(() => {
    // The switcher lists what the toast announced, so the toast has done its job.
    closedTabs.dismissNotice();
    setSwitcherOpen((open) => !open);
  }, []);
  const [overviewOpen, setOverviewOpen] = useState(false);
  const openTabOverview = useCallback(() => {
    closedTabs.dismissNotice();
    setSwitcherOpen(false);
    setOverviewOpen((open) => !open);
  }, []);
  const closedHistory = useSyncExternalStore(closedTabs.subscribe, closedTabs.history);
  // Tabs in the order they were last in view, for the switcher.
  const recentTabs = useRef<string[]>([]);
  const summariesRef = useRef<Tab[]>([]);
  // Go to whatever is waiting on the user, approvals before finished work.
  const jumpToAttention = useCallback(() => {
    const view = workspaceRef.current;
    const next = view && attentionOrder(summariesRef.current, view.activeTabIdRef.current)[0];
    if (view && next) view.activateTab(next);
  }, []);
  // The shortcut folds whichever second column the page in view has.
  const toggleSessionSidebar = useCallback(() => {
    if (surfaceRef.current === "notes" || surfaceRef.current === "canvases") {
      window.dispatchEvent(new Event(TOGGLE_SECONDARY_SIDEBAR_EVENT));
      return;
    }
    setSessionSidebarOpen((open) => { saveSessionSidebarOpen(!open); return !open; });
  }, []);
  const persistWindow = useCallback(async (mode: WorkspaceSaveMode = "transition") => {
    runtime.flushEvents();
    await runtime.flushPersistence();
    const view = workspaceRef.current!;
    await persistQuitState(sessionsRef.current, view.tabsRef.current, view.activeTabIdRef.current, view.projectCwdRef.current, view.projectReturnMemory.current, mode);
  }, [runtime.flushEvents, runtime.flushPersistence]);
  const reload = useCallback(() => { void persistWindow().then(() => window.location.reload()).catch((error) => workspaceRef.current?.setError(String(error))); }, [persistWindow]);
  useAppCommands({ workspace, submission, sessionsRef, surfaceOpen: surface !== "chat", closeSurface,
    openSearch, openSettings, openNotes, toggleProjectRail, toggleSessionSidebar, openTabSwitcher, jumpToAttention, openTabOverview, reload, sessionOrder,
  });

  useEffect(() => {
    void probeHarnessAvailability();
    void applyUiScale(loadUiScale());
    return watchSystemColorScheme();
  }, []);
  useEffect(() => { if (active) void refreshHarnessCatalogs([active.harness]); }, [active?.harness]);
  useEffect(() => preloadNavigationWhenIdle([SearchView.preload, SettingsView.preload, NotesView.preload]), []);
  useLayoutEffect(() => runtime.flushEvents(), [workspace.activeTabId, surface, runtime.flushEvents]);
  useEffect(() => {
    const flush = () => runtime.flushEvents();
    document.addEventListener("visibilitychange", flush);
    return () => document.removeEventListener("visibilitychange", flush);
  }, [runtime.flushEvents]);
  useEffect(() => {
    if (!active || !supportsHarnessLogin(active.harness) || !latestTurnNeedsHarnessLogin(active.blocks)) return;
    const key = signInRequestKey(active);
    if (seenSignInRequests.current.has(key)) return;
    seenSignInRequests.current.add(key);
    setProviderSignIn({ key, sessionId: active.id, harness: active.harness });
  }, [active]);
  useEffect(() => { if (providerSignIn && providerSignIn.sessionId !== active?.id) setProviderSignIn(null); }, [active?.id, providerSignIn]);
  useEffect(() => { void rememberProjectLocation(workspace.projectCwd); }, [workspace.projectCwd]);
  useEffect(() => { if (!notesEnabled && surface === "notes") closeSurface(); }, [notesEnabled, surface, closeSurface]);
  useEffect(() => {
    const refresh = () => { void loadCanvases().then(setCanvases).catch((error) => workspaceRef.current?.setError(String(error))); };
    refresh();
    window.addEventListener(CANVASES_CHANGED_EVENT, refresh);
    return () => window.removeEventListener(CANVASES_CHANGED_EVENT, refresh);
  }, []);
  useEffect(() => {
    const onAdd = (event: Event) => {
      const card = (event as CustomEvent<NoteComposerCard>).detail;
      if (!card) return;
      const view = workspaceRef.current!;
      const cwd = card.sourceCwd && looksLikeProject(card.sourceCwd) ? card.sourceCwd : view.projectCwdRef.current;
      const session = { ...newDefaultSession(cwd, view.activeSession?.runtimeMode), title: card.title, noteCard: card };
      view.addSession(session);
    };
    window.addEventListener(ADD_NOTE_TO_CHAT_EVENT, onAdd);
    return () => window.removeEventListener(ADD_NOTE_TO_CHAT_EVENT, onAdd);
  }, [runtime.updateSessions]);
  useEffect(() => {
    const release = setQuitWorkspace(() => sessionsRef.current, () => workspace.tabsRef.current,
      () => workspace.activeTabIdRef.current, () => workspace.projectCwdRef.current,
      () => workspace.projectReturnMemory.current, runtime.flushEvents);
    let stop: (() => void) | undefined;
    let disposed = false;
    void getCurrentWindow().onCloseRequested((event) => {
      event.preventDefault();
      runtime.flushEvents();
      const toTray = loadCloseToTray();
      if (hasInFlightSessions(sessionsRef.current)) {
        if (!toTray && !IS_MAC) { void closeBusyWindow(); return; }
        void persistLiveTranscripts(sessionsRef.current);
        void hideCurrentWindow();
        return;
      }
      void persistAndCloseWindow(persistWindow, toTray).catch((error) => workspaceRef.current?.setError(String(error)));
    }).then((unlisten) => { if (disposed) unlisten(); else stop = unlisten; });
    const unload = () => { if (!isAppQuitting()) void persistWindow("unload"); };
    window.addEventListener("beforeunload", unload);
    return () => { disposed = true; release(); stop?.(); window.removeEventListener("beforeunload", unload); };
  }, [runtime.flushEvents, persistWindow, workspace.tabsRef, workspace.activeTabIdRef, workspace.projectCwdRef, workspace.projectReturnMemory]);

  const compactProjectRail = collapsedProjectRailMode === "compact";
  const compactRailActive = compactProjectRail && !projectRailOpen;
  const compactTitleBar = IS_MAC && compactRailActive && surface === "chat";
  const openFile = useCallback((path: string) => { void openPathWithDefaultApp(path).catch((error) => workspaceRef.current?.setError(String(error))); }, []);
  const pinFile = useCallback((path: string) => workspaceRef.current?.openFile(path, true), []);
  // A link inside an open document: project files open beside it, anything
  // else goes to the app the system uses for it.
  const openProjectFile = useCallback((path: string) => {
    const view = workspaceRef.current;
    if (view && isEqualOrInside(path, view.projectCwdRef.current)) view.openFile(path);
    else openFile(path);
  }, [openFile]);
  useEffect(() => {
    // A file dragged out of the Files tree shows the same edge hint as a
    // dragged pane, and lands as its own pane where it is dropped.
    const onDrag = (event: Event) => {
      const detail = (event as CustomEvent<FilePointerDragDetail>).detail;
      if (detail.type === "end") { setExternalPaneDrop(null); return; }
      const over = paneDropFromPoint(detail.x, detail.y);
      const fromId = filePaneId(detail.path);
      if (detail.type === "move") {
        setExternalPaneDrop(over && over.id !== fromId ? { fromId, overId: over.id, edge: over.edge } : null);
        return;
      }
      setExternalPaneDrop(null);
      if (over && over.id !== fromId) workspaceRef.current?.placeFile(detail.path, over.id, over.edge);
    };
    window.addEventListener(FILE_POINTER_DRAG_EVENT, onDrag);
    return () => window.removeEventListener(FILE_POINTER_DRAG_EVENT, onDrag);
  }, []);
  const onRailBack = () => surface !== "chat" ? closeSurface() : workspace.visit("back");
  const notificationsSettings = (path?: string) => {
    setNotificationProjectPath(path ?? workspace.projectCwd);
    setNotificationSettingsRequest((request) => request + 1);
    openSettings("general", "project-notifications");
  };
  const applyZoom = (direction: -1 | 0 | 1) => {
    void applyUiScale(saveUiScale(direction === 0 ? UI_SCALE_DEFAULT : direction === 1 ? zoomInUiScale(loadUiScale()) : zoomOutUiScale(loadUiScale())));
  };
  const tabSummaries = useMemo(() => linkFamilies(workspace.tabs.map((tab) => summarizeTab(tab, {
    sessions,
    canvasTitle: (id) => canvases.find((canvas) => canvas.id === id)?.title,
    needsInput: approvalSessionIds,
    unseenFinished: unseenFinishedIds,
    fallbackCwd: workspace.projectCwd,
  })), workspace.tabs), [workspace.tabs, sessions, canvases, approvalSessionIds, unseenFinishedIds, workspace.projectCwd]);
  // The strip shows this project's tabs; the switcher reaches all of them.
  const titleTabs = useMemo(() => {
    const byId = new Map(tabSummaries.map((tab) => [tab.id, tab]));
    return workspace.visibleTabs.flatMap((tab) => byId.get(tab.id) ?? []);
  }, [tabSummaries, workspace.visibleTabs]);
  const focusedLeaf = workspace.activeTab && findLeaf(workspace.activeTab.layout, workspace.activeTab.focusedId);
  summariesRef.current = tabSummaries;
  // Tabs that hold something unfinished are never put away or closed in bulk.
  const heldIds = useMemo(() => heldTabIds(workspace.tabs, sessions), [workspace.tabs, sessions]);
  const idleIds = useMemo(() => idleTabIds(titleTabs, workspace.activeTabId, heldIds), [titleTabs, workspace.activeTabId, heldIds]);
  // When a project's tab count grows past its limit, the longest-idle tabs are
  // put away. Switching project or restoring a layout is not growth.
  const parkBaseline = useRef<TabCountMark | null>(null);
  useEffect(() => {
    const project = pathKey(workspace.projectCwd);
    const count = titleTabs.length;
    const { mark, grew } = trackTabGrowth(parkBaseline.current, project, count);
    parkBaseline.current = mark;
    const view = workspaceRef.current;
    if (!view || !grew) return;
    const ids = parkingCandidates({ tabs: titleTabs, activeId: view.activeTabIdRef.current, recent: recentTabs.current, held: heldTabIds(view.tabsRef.current, sessionsRef.current), limit: loadTabLimit() });
    if (ids.length) view.closeTabs(ids, undefined, { parked: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [titleTabs.length, workspace.projectCwd]);
  useEffect(() => {
    recentTabs.current = [workspace.activeTabId, ...recentTabs.current.filter((id) => id !== workspace.activeTabId)].slice(0, 60);
  }, [workspace.activeTabId]);
  const workspaceTitleBar = <TitleBar tabs={titleTabs} activeId={workspace.activeTabId} cwd={workspace.projectCwd}
    projectRailOpen={projectRailOpen} sessionSidebarOpen={sessionSidebarOpen} compactRail={compactTitleBar}
    canGoBack={workspace.visits.back.length > 0} canGoForward={workspace.visits.forward.length > 0}
    onGoBack={onRailBack} onGoForward={() => workspace.visit("forward")}
    onToggleSidebar={toggleProjectRail} onToggleSessionSidebar={toggleSessionSidebar}
    onSelect={workspace.activateTab} onOpenSettings={() => openSettings()} onOpenNotes={notesEnabled ? openNotes : undefined}
    onClose={(id) => workspace.closeTabs([id])} onCloseMany={workspace.closeTabs}
    onArchiveTab={(id) => { for (const sessionId of leafIds(workspace.tabs.find((tab) => tab.id === id)!.layout).filter((paneId) => sessions.some((session) => session.id === paneId))) void workspace.archiveSession(sessionId, true); }}
    onDeleteTab={(id) => { for (const sessionId of leafIds(workspace.tabs.find((tab) => tab.id === id)!.layout).filter((paneId) => sessions.some((session) => session.id === paneId))) void workspace.removeSession(sessionId); }}
    onReorder={workspace.reorderTabs} onPin={workspace.pinTab} recent={recentTabs.current} onOpenSwitcher={openTabSwitcher} idleTabCount={idleIds.length} onCloseIdle={() => workspace.closeTabs(idleIds)} onPlaceOnPane={workspace.placeTab} recents={workspace.recents} onSelectProject={workspace.openProject} />;
  const sessionPaneProps = {
    recents: workspace.recents, hideProjectPicker: true,
    onFocus: workspace.focusPane, onClose: workspace.closePane, onCwdChange: workspace.changeCwd,
    onModelChange: submission.changeModel, onModelSettingsChange: submission.changeModelSettings, onRuntimeModeChange: submission.changeRuntimeMode,
    onSubmit: submission.onSubmit, onSaveDraft: submission.saveDraft, onRemoveDraft: submission.removeDraft,
    onStop: submission.stop, onCompactContext: submission.compact, onPlaceSessionInFolder: workspace.placeInFolder,
    onDeleteQueuedMessage: submission.deleteQueuedMessage, onEditQueuedMessage: submission.editQueuedMessage,
    onQueuedMessageEditingChange: submission.queuedMessageEditingChange, onSteerQueuedMessage: submission.steerQueuedMessage, onResumeQueue: submission.resumeQueue,
    onUsageLimitResume: submission.usageLimitResume, onUsageLimitResumeAtReset: submission.usageLimitResumeAtReset, onUsageLimitDismiss: submission.usageLimitDismiss,
    onNoteCardDismiss: (id: string) => runtime.updateSessions((current) => current.map((session) => session.id === id ? { ...session, noteCard: undefined } : session)),
    onNoteSaved: (noteId: string) => setSavedToast({ type: "note", id: noteId }),
    onSaveToCanvas: saveToCanvas,
    onApproval: submission.approve, onQuestionReply: submission.answer, onQuestionInteraction: submission.keepQuestionOpen,
    onOpenFile: openFile, onBtwSubmit: submission.btwSubmit, onBtwRetry: submission.btwRetry, onBtwDelete: submission.btwDelete,
    onBtwStop: submission.btwStop, onBtwModelChange: submission.btwModelChange,
  };

  return <>
    <div className={`workspace-background flex h-full flex-col text-content ${HAS_NATIVE_GLASS ? "bg-background-base/[var(--window-background-opacity)]" : "bg-background-base"}`}>
      {compactTitleBar ? workspaceTitleBar : null}
      <div className="flex min-h-0 min-w-0 flex-1">
        <Sidebar cwd={workspace.projectCwd} open={sessionSidebarOpen} sessions={workspace.sidebarHistory} openSessions={workspace.openProjectSessions}
          busySessionIds={busySessionIds} approvalSessionIds={approvalSessionIds} activeSessionId={active?.id}
          status={workspace.historyFailed ? "error" : "idle"} pending={workspace.historyPending}
          onSelectSession={(id) => void workspace.openSession(id)} onSessionNavigationOrder={setSessionOrder}
          onPrefetchSession={(id) => { void workspace.loadSession(id); }} onPlaceSessionOnPane={(...args) => void workspace.placeSession(...args)}
          onRenameSession={(...args) => void workspace.renameSession(...args)} onArchiveSession={(...args) => void workspace.archiveSession(...args)}
          onArchiveSessions={(ids, archived) => { for (const id of ids) void workspace.archiveSession(id, archived); }}
          onPinSession={(...args) => void workspace.pinSession(...args)} onPinSessions={(ids, pinned) => { for (const id of ids) void workspace.pinSession(id, pinned); }}
          onDeleteSession={(id) => void workspace.removeSession(id)} onDeleteSessions={(ids) => { for (const id of ids) void workspace.removeSession(id); }}
          reminders={reminders.reminders} onSetReminders={reminders.schedule} onCancelReminders={reminders.cancel}
          onTabChange={closeSurface} canGoBack={surface !== "chat" || workspace.visits.back.length > 0} canGoForward={workspace.visits.forward.length > 0}
          onGoBack={onRailBack} onGoForward={() => workspace.visit("forward")}
          recents={workspace.recents} busyProjectPaths={sessions.filter((session) => session.busy).map((session) => session.cwd)}
          liveAgents={liveAgents} onSelectAgent={(id) => void workspace.openSession(id)} onSelectProject={workspace.openProject} onOpenProject={workspace.pickProject}
          onRemoveProject={(...args) => void workspace.removeProject(...args)} onNew={() => workspace.createSession()} onSearch={openSearch}
          onOpenNotes={notesEnabled ? openNotes : undefined} searchActive={surface === "search"} notesActive={surface === "notes"} notesEnabled={notesEnabled}
          onOpenCanvases={openCanvases} canvasesActive={surface === "canvases"}
          onOpenFile={workspace.openFile} onToggleSidebar={toggleSessionSidebar} onFileMoved={workspace.fileMoved} onFileDeleted={workspace.fileDeleted}
          canvases={canvases} activeCanvasId={surface === "chat" && focusedLeaf?.leafKind === "canvas" ? focusedLeaf.id : undefined}
          onOpenCanvas={workspace.showCanvas} onOpenCanvasInTab={openCanvas} onNewCanvas={newCanvas} onRenameCanvas={renameCanvas} onDeleteCanvas={handleDeleteCanvas}
          projectRailOpen={projectRailOpen} compactProjectRail={compactProjectRail} titleBarAbove={compactTitleBar} onToggleProjectRail={toggleProjectRail}
          unseenFinishedIds={unseenFinishedIds} settingsOpen={surface === "settings"} settingsSection={settingsSection} onOpenSettings={() => openSettings()}
          onOpenNotificationSettings={notificationsSettings} onSelectSettingsSection={onSelectSettingsSection} onCloseSettings={() => setSurface(settingsReturn.current)} />
        <div className="body-glass flex min-h-0 min-w-0 flex-1 flex-col">
          <div className={surface === "chat" ? "flex min-h-0 min-w-0 flex-1 flex-col" : "hidden"} aria-hidden={surface !== "chat"} inert={surface !== "chat" || undefined}>
            {!IS_MAC ? <MenuBar onNew={() => workspace.createSession()} onSwitchTab={openTabSwitcher} onNextAttention={jumpToAttention} onTabOverview={openTabOverview} onReopenTab={() => { void workspace.reopenClosed("latest"); }} onToggleSidebar={toggleProjectRail} onToggleSessionSidebar={toggleSessionSidebar}
              onCloseCurrentTab={() => workspace.closeTabs([workspace.activeTabId])} onCloseOtherTabs={() => workspace.closeTabs(workspace.visibleTabs.filter((tab) => tab.id !== workspace.activeTabId).map((tab) => tab.id))}
              onCloseAllTabs={() => workspace.closeTabs(workspace.visibleTabs.map((tab) => tab.id))} onPickProject={workspace.pickProject} onSearch={openSearch} onOpenNotes={notesEnabled ? openNotes : undefined}
              onZoomIn={() => applyZoom(1)} onZoomOut={() => applyZoom(-1)} onZoomReset={() => applyZoom(0)} /> : null}
            {compactTitleBar ? null : workspaceTitleBar}
            <main className="relative flex min-h-0 min-w-0 flex-1">
              <div className="relative min-h-0 min-w-0 flex-1">
                {workspace.tabs.map((tab) => <div key={tab.id} aria-hidden={tab.id !== workspace.activeTabId} className={tab.id === workspace.activeTabId ? "tab-pane-in absolute inset-0 flex h-full min-h-0 flex-col" : "hidden"}>
                  <PaneTree {...sessionPaneProps} visible={surface === "chat" && tab.id === workspace.activeTabId} layout={tab.layout} sessions={sessions}
                    focusedId={surface === "chat" && tab.id === workspace.activeTabId ? tab.focusedId : ""} composerFocused={surface === "chat"}
                    composerFocusToken={workspace.composerFocusToken} onRatio={workspace.ratio} onMovePane={workspace.movePane} onDetachPane={workspace.detachPane} transcriptPool={transcriptPool}
                    canvases={canvases}
                    onCanvasFocus={(id) => workspace.focusPane(id)}
                    onCanvasAddToChat={canvasAddToChat}
                    onCanvasTitleChange={renameCanvas}
                    projectCwd={tab.cwd ?? workspace.projectCwd} onFilePaneFocus={workspace.focusPane}
                    onFilePanePin={pinFile} onOpenProjectFile={openProjectFile} />
                </div>)}
              </div>
            </main>
          </div>
          {surface === "search" ? <SearchView open cwd={workspace.projectCwd} recents={workspace.recents} history={workspace.history} sessions={sessions}
            focusToken={searchFocusToken} besideRail={projectRailOpen || compactProjectRail} compactRail={compactRailActive} onClose={closeSurface} onToggleSidebar={toggleProjectRail}
            onOpenSession={(id, blockId, query) => { if (blockId) requestTranscriptJump(id, blockId, query); void workspace.openSession(id); }} onOpenProject={workspace.openProject} /> : null}
          {surface === "notes" ? <NotesView besideRail={projectRailOpen || compactProjectRail} compactRail={compactRailActive} cwd={workspace.projectCwd} openRequest={noteOpenRequest} recents={workspace.recents} onClose={closeSurface} onToggleSidebar={toggleProjectRail} /> : null}
          {surface === "canvases" ? <CanvasesView canvases={canvases} cwd={workspace.projectCwd} besideRail={projectRailOpen || compactProjectRail} compactRail={compactRailActive} onClose={closeSurface} onToggleSidebar={toggleProjectRail} onOpenCanvas={openCanvas} onNewCanvas={newCanvas} onTitleChange={renameCanvas} onDeleteCanvas={handleDeleteCanvas} onAddToChat={canvasAddToChat} /> : null}
          {surface === "settings" ? <SettingsView section={settingsSection} anchor={settingsAnchor} notificationProjectPath={notificationProjectPath} notificationSettingsRequest={notificationSettingsRequest}
            recents={workspace.recents} cwd={workspace.projectCwd} sessions={workspace.sidebarHistory} besideRail onClose={() => setSurface(settingsReturn.current)} onSelectSection={onSelectSettingsSection}
            onOpenSession={(id) => void workspace.openSession(id)} onArchiveSession={(...args) => void workspace.archiveSession(...args)} onDeleteSession={(id) => void workspace.removeSession(id)}
            onRestoreProject={workspace.openProject} onDeleteProject={(path) => void workspace.removeProject(path, { purgeData: true })}
            collapsedProjectRailMode={collapsedProjectRailMode} onCollapsedProjectRailModeChange={saveCollapsedProjectRailMode} /> : null}
          {surface === "chat" ? <UsageFooter providers={active && (active.harness === "claude" || active.harness === "codex") ? [active.harness] : []} session={active ? { ...active, authRequired: latestTurnNeedsHarnessLogin(active.blocks) } : undefined} project={active?.cwd ?? workspace.projectCwd} onManageAccounts={() => openSettings("providers", "provider-accounts")}
            onSelectAccount={(provider, accountId) => {
              const current = workspaceRef.current?.activeSession;
              if (!current || current.harness !== provider || (current.providerAccountId ?? "default") === accountId) return;
              if (!current.blocks.length && !current.busy) runtime.updateSessions((entries) => entries.map((session) => session.id === current.id ? { ...session, providerAccountId: accountId } : session));
              else workspace.addSession({ ...newSession(current.harness, current.cwd, current.model, current.runtimeMode, current.modelSettings), providerAccountId: accountId });
            }} /> : null}
        </div>
      </div>
      <ApprovalToasts notices={hiddenApprovalNotices(sessions, workspace.activeTabId, workspace.tabs, surface === "chat")} topOffset={12 + (reminderNoticesHeight ? reminderNoticesHeight + 8 : 0)} onFocusSession={(id) => void workspace.openSession(id)} onApproval={submission.approve} />
      <ReminderNotices reminders={reminders.due} error={reminders.error} onOpen={reminders.open} onSnooze={reminders.schedule} onDismiss={reminders.cancel} onRetry={reminders.refresh} onOpenSettings={() => openSettings("general", "notifications")} onHeightChange={setReminderNoticesHeight} />
      {overviewOpen ? <TabOverview tabs={tabSummaries} activeId={workspace.activeTabId} projectPath={workspace.projectCwd} recent={recentTabs.current}
        onDismiss={() => setOverviewOpen(false)} onActivate={workspace.activateTab}
        onCloseTabs={(ids) => workspace.closeTabs(ids)} onParkTabs={(ids) => workspace.closeTabs(ids, undefined, { parked: true })}
        onPinTabs={(ids, pinned) => { for (const id of ids) workspace.pinTab(id, pinned); }} /> : null}
      {switcherOpen ? <TabSwitcher tabs={tabSummaries} activeId={workspace.activeTabId} projectPath={workspace.projectCwd}
        recent={recentTabs.current} closed={closedHistory} onDismiss={() => setSwitcherOpen(false)}
        onActivate={workspace.activateTab} onCloseTab={(id) => workspace.closeTabs([id])} onPin={workspace.pinTab}
        onReopen={(batch) => { void workspace.reopenClosed(batch); }} onOpenOverview={openTabOverview} /> : null}
      <ClosedTabToast onUndo={(batch) => { void workspace.reopenClosed(batch); }} />
      {savedToast && (
        <SavedToast
          toast={savedToast}
          onDismiss={() => setSavedToast(null)}
          onOpen={(t) => {
            if (t.type === "canvas") {
              workspace.showCanvas(t.id);
            } else {
              setNoteOpenRequest((prev) => ({ id: t.id, sequence: (prev?.sequence ?? 0) + 1 }));
              setSurface("notes");
            }
          }}
        />
      )}
      {providerSignIn ? <ProviderSignInDialog key={providerSignIn.key} harness={providerSignIn.harness} onClose={() => setProviderSignIn(null)} /> : null}
      {canvasSelection ? <SelectCanvasDialog anchor={canvasSelection.anchor ?? null} canvases={canvasSelection.canvases} onSelect={canvasSelection.resolver} onCancel={() => { canvasSelection.rejecter(new DOMException("Cancelled", "AbortError")); }} /> : null}
      {workspace.error ? <FileActionError message={workspace.error} onDismiss={() => workspace.setError(null)} /> : null}
    </div>
    <TranscriptPoolOutlet pool={transcriptPool} />
  </>;
}
