import { MentorWorkspace } from "../features/mentor/ui/MentorWorkspace";
import { MentorSearch } from "../features/mentor/ui/MentorSearch";
import type { MentorPage } from "../features/mentor/model/mentorPage";
import { AgentGallery } from "../features/agents/ui/AgentGallery";
import { setAgentReading } from "../features/agents/model/agentReading";
import { useMentorView } from "./hooks/useMentorView";
import { open as pickFile } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { Modal } from "../shared/ui/Modal";
import { ADD_TO_CHAT_EVENT, requestAddToChat, type AddToChatRequest } from "../features/sessions/model/quoteDraft";
import { queueLearningDraft } from "../features/learning/model/learningDraft";
import { OPEN_LEARNING_DISCUSSION_EVENT } from "../features/learning/model/navigation";
import { courseItems, loadCourse, OPEN_COURSE_EVENT, type OpenCourseDetail } from "../features/learning/model/course";
import { readAgentDocument } from "../features/agents/model/agentDocuments";
import { LessonMarks } from "../features/learning/ui/LessonMarks";
import { requestDocumentPlace } from "../features/agents/model/documentPlace";
import type { DiscussionRef } from "../features/learning/model/types";
import { startTransition, Suspense, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ComponentProps, type ReactNode } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { openUpdatePrompt, startUpdateChecks, usePendingUpdateVersion } from "../features/updates/model/updates";
import { UpdatePrompt } from "../features/updates/ui/UpdatePrompt";
import { WindowControls } from "./shell/WindowControls";
import { MenuBar } from "./shell/MenuBar";
import { MentorRail } from "./shell/MentorRail";
import { SettingsNav } from "./shell/SettingsRail";
import { ApprovalToasts } from "../features/sessions/ui/ApprovalToasts";
import { TranscriptPool, TranscriptPoolOutlet } from "../features/sessions/ui/TranscriptPool";
import { SessionPane } from "../features/sessions/ui/SessionPane";
import { FileActionError } from "../shared/ui/FileActionError";
import { HAS_NATIVE_GLASS, IS_MAC } from "../platform/tauri/platform";
import { OPEN_FILE_EVENT, requestFilePlace, type OpenFileFn } from "../features/files/model/filePlace";
import { pickFolders } from "../platform/tauri/fs";
import { useAgents } from "./hooks/useAgents";
import { useAgentHabits } from "./hooks/useAgentHabits";
import { useAgentDelegation } from "./hooks/useAgentDelegation";
import { useActiveMentor, loadActiveMentorId } from "./hooks/useActiveMentor";
import { useSessionStore } from "./hooks/useSessionStore";
import { AgentSessionPane } from "../features/agents/ui/AgentSessionPane";
import { OPEN_DOCUMENT_EVENT, type OpenDocumentDetail } from "../features/sessions/model/cards";
import { agentForSession, agentLook, listAgents } from "../features/agents/model/agent";
import { lazySurface } from "../shared/ui/lazySurface";
import { preloadNavigationWhenIdle } from "./model/preloadNavigation";
import { ProviderSignInDialog } from "../features/sessions/ui/ProviderSignInDialog";
import { latestTurnNeedsHarnessLogin, supportsHarnessLogin } from "../integrations/harness/core/authSupport";
import { registerBuiltinHarnesses } from "../integrations/harness/core/register";
import { probeHarnessAvailability } from "../integrations/harness/core/availability";
import { refreshHarnessCatalogs } from "../integrations/harness/core/registry";
import { sessionDisplayTitle, type HarnessId, type Session } from "../features/sessions/model/session";
import { requestTranscriptJump } from "../features/sessions/model/transcriptJump";
import { useUnseenFinishedSessions } from "../features/sessions/hooks/useUnseenFinishedSessions";
import { SavedToast, type SavedToastData } from "./shell/SavedToast";
import { requestImageZoom } from "../shared/lib/imageZoomCommands";
import { watchSystemColorScheme } from "../features/settings/model/appearance";
import { loadCloseToTray, loadSettingsSection, saveSettingsSection, type SettingsSectionId } from "../features/settings/model/settings";
import { applyUiScale, loadUiScale, saveUiScale, UI_SCALE_DEFAULT, zoomInUiScale, zoomOutUiScale } from "../features/settings/model/uiScale";
import { announceSessionFinished } from "../features/notifications/model/notifications";
import { hiddenApprovalNotices } from "../features/notifications/model/approvalToast";
import { syncDockBadge } from "../features/notifications/model/dockBadge";
import { useInputNotifications } from "../features/notifications/hooks/useInputNotifications";
import { CANVASES_CHANGED_EVENT, loadCanvases, updateCanvas, type Canvas } from "../features/canvas/canvas";
import { SelectCanvasDialog } from "../features/canvas/ui/SelectCanvasDialog";
import { synchronizeProjectLocation } from "../features/projects/model/projectLocation";
import { rebaseProjectData } from "../features/projects/model/projectData";
import { replaceProjectPath, sameProjectPath } from "../features/projects/model/recents";
import { rebaseProjectSessions } from "../features/sessions/data/sessionStore";
import { ProjectNotFoundError } from "../features/projects/model/projectLocationError";
import { closeBusyWindow, closeCurrentWindow, hasInFlightSessions, hideCurrentWindow, isAppQuitting, persistAndCloseWindow, persistLiveTranscripts, persistQuitState, setQuitWorkspace, type BootWorkspace, type WorkspaceSaveMode } from "./model/appLifecycle";
import { useSessionRuntime } from "./hooks/useSessionRuntime";
import { useSessionSubmission } from "./hooks/useSessionSubmission";
import { useIdleSessionDetach } from "./hooks/useIdleSessionDetach";
import { useAppCommands } from "./hooks/useAppCommands";
import { useAppControl, type AppControlWorkspace } from "./hooks/useAppControl";
import { useCommandContext } from "./hooks/useCommandContext";
import { useAppResourceNavigation } from "./hooks/useAppResourceNavigation";
import { useSaveToCanvas } from "./hooks/useSaveToCanvas";

const SettingsView = lazySurface(async () => ({ default: (await import("../features/settings/ui/SettingsView")).SettingsView }), { suspense: false });

registerBuiltinHarnesses();
type Surface = "mentor" | "settings";

export default function App(boot: BootWorkspace) {
  return <Suspense fallback={null}><Workspace {...boot} /></Suspense>;
}

function signInRequestKey(session: Session): string {
  const lastUser = [...session.blocks].reverse().find((block) => block.role === "user");
  return `${session.id}:${lastUser?.id ?? session.blocks[session.blocks.length - 1]?.id ?? "auth"}`;
}

/**
 * The window: the mentor rail on the far left, then the open mentor's
 * workspace (library, reader, conversation), or Settings.
 */
function Workspace(boot: BootWorkspace) {
  // Interrupted turns come back with their sessions; nothing else is reopened.
  const [initialSessions] = useState(() => boot.resumed?.sessions ?? []);
  const [sessions, setSessions] = useState<Session[]>(initialSessions);
  const sessionsRef = useRef(sessions);
  const [surface, setSurface] = useState<Surface>("mentor");
  const surfaceRef = useRef(surface);
  surfaceRef.current = surface;
  // One window asks about updates, not each of them.
  useEffect(() => (getCurrentWindow().label === "main" ? startUpdateChecks() : undefined), []);
  const pendingUpdateVersion = usePendingUpdateVersion();
  const [settingsSection, setSettingsSection] = useState(loadSettingsSection);
  const [settingsAnchor, setSettingsAnchor] = useState<string | null>(null);
  const [savedToast, setSavedToast] = useState<SavedToastData | null>(null);
  const [transcriptPool] = useState(() => new TranscriptPool());
  const [canvases, setCanvases] = useState<Canvas[]>([]);
  const [agentGalleryOpen, setAgentGalleryOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [providerSignIn, setProviderSignIn] = useState<{ key: string; sessionId: string; harness: HarnessId } | null>(null);
  const seenSignInRequests = useRef(new Set(initialSessions.filter((session) => latestTurnNeedsHarnessLogin(session.blocks)).map(signInRequestKey)));
  const storeRef = useRef<ReturnType<typeof useSessionStore> | null>(null);
  const reportError = useCallback((error: unknown) => storeRef.current?.setError(String(error)), []);

  const mentor = useActiveMentor();
  const mentorRef = useRef(mentor);
  mentorRef.current = mentor;
  const mentorView = useMentorView();
  const mentorViewRef = useRef(mentorView);
  mentorViewRef.current = mentorView;
  const readerSaveGuards = useRef(new Map<string, () => Promise<boolean>>());
  const readerGuard = useCallback((id: string, save: (() => Promise<boolean>) | null) => {
    if (save) readerSaveGuards.current.set(id, save);
    else readerSaveGuards.current.delete(id);
  }, []);
  /** Waits for the reader's unsaved edits; false when they could not be saved. */
  const leaveReader = useCallback(async (agentId: string) => {
    const guard = readerSaveGuards.current.get(agentId);
    return !guard || await guard();
  }, []);
  /** The session the current mentor's reader shows, if it shows one. */
  const readerSessionId = () => {
    const agentId = mentorRef.current.currentRef.current?.agentId;
    const page = agentId ? mentorViewRef.current.readingFor(agentId) : undefined;
    return page?.kind === "session" ? page.id : undefined;
  };
  const isForeground = useCallback((id: string) => surfaceRef.current === "mentor"
    && (mentorRef.current.currentRef.current?.sessionId === id || readerSessionId() === id), []);

  const runtime = useSessionRuntime({ sessions, sessionsRef, setSessions, isForeground,
    onPersistenceError: reportError,
    onFinished: (session) => { if (!session.ephemeral) void announceSessionFinished(session, isForeground(session.id)); },
  });
  const submission = useSessionSubmission({ runtime,
    canStartSessionWork: (id) => !storeRef.current?.isSessionUnavailable(id),
    // A session an agent started in a folder that has since moved follows it.
    synchronizeProject: async (cwd) => {
      const location = await synchronizeProjectLocation(cwd);
      if (!location) throw new ProjectNotFoundError(cwd);
      if (!location.moved) return;
      await rebaseProjectSessions(cwd, location.path);
      rebaseProjectData(cwd, location.path);
      replaceProjectPath(cwd, location.path);
      runtime.updateSessions((current) => current.map((session) => sameProjectPath(session.cwd, cwd) ? { ...session, cwd: location.path } : session));
    },
  });
  const store = useSessionStore({ sessionsRef, updateSessions: runtime.updateSessions, stopSession: submission.stopSessionWork, flushPersistence: runtime.flushPersistence });
  storeRef.current = store;

  const agentsRef = useRef<ReturnType<typeof useAgents> | null>(null);
  const visibleSessionIds = useMemo(() => {
    const page = mentor.current ? mentorView.stateFor(mentor.current.agentId).page : undefined;
    return new Set(surface === "mentor" && mentor.current ? [mentor.current.sessionId, ...(page?.kind === "session" ? [page.id] : [])] : []);
  }, [surface, mentor.current, mentorView]);
  const agents = useAgents({ runtime, submission,
    loadSession: (id) => storeRef.current!.loadSession(id),
    onError: reportError,
    onShow: (agentId, session) => { mentorRef.current.open(agentId, session); surfaceRef.current = "mentor"; setSurface("mentor"); },
    onReplaceSession: (oldId, session) => mentorRef.current.replaceSession(oldId, session),
    onRemoveSession: (id) => mentorRef.current.forgetSession(id),
    visibleSessionIds,
  });
  agentsRef.current = agents;
  const activeAgent = mentor.current ? agents.agents.find((agent) => agent.id === mentor.current!.agentId) : undefined;
  const focusedAgent = surface === "mentor" ? activeAgent : undefined;
  const selectAgent = agents.select;
  useEffect(() => selectAgent(focusedAgent?.id), [focusedAgent?.id, selectAgent]);
  // The window opens on the mentor it showed last, or the first one; removing
  // the open mentor moves to another rather than leaving the window empty.
  const openingFirst = useRef(false);
  // While a mentor is being created, it is the one that opens, not the first on the rail.
  const creatingMentor = useRef(false);
  /** Which mentor the window opens on, while none is open. */
  const firstMentor = useMemo(() => agents.agents.find((agent) => agent.id === loadActiveMentorId()) ?? agents.agents[0],
    [agents.agents]);
  const [firstMentorFailed, setFirstMentorFailed] = useState(false);
  const openFirstMentor = useCallback(() => {
    if (!firstMentor || openingFirst.current || creatingMentor.current) return;
    openingFirst.current = true;
    setFirstMentorFailed(false);
    void agentsRef.current!.open(firstMentor.id).finally(() => {
      openingFirst.current = false;
      setFirstMentorFailed(mentorRef.current.currentRef.current?.agentId !== firstMentor.id);
    });
  }, [firstMentor]);
  useEffect(() => {
    if (mentor.current || !firstMentor) return;
    openFirstMentor();
  }, [mentor.current, firstMentor]); // eslint-disable-line react-hooks/exhaustive-deps
  // A mentor deleted in another window (or a creation that failed after it
  // joined the roster) cannot stay open; the effect above then opens another.
  useEffect(() => {
    const current = mentor.current;
    if (!current || agents.agents.some((agent) => agent.id === current.agentId)) return;
    mentor.forgetSession(current.sessionId);
  }, [mentor.current, agents.agents]); // eslint-disable-line react-hooks/exhaustive-deps

  /** Opens a mentor and waits for its workspace; false when that did not happen. */
  const showMentor = useCallback(async (agentId: string) => {
    const current = mentorRef.current.currentRef.current?.agentId;
    if (current && current !== agentId && !await leaveReader(current)) return false;
    if (surfaceRef.current !== "mentor" || current !== agentId) await agentsRef.current?.open(agentId);
    return mentorRef.current.currentRef.current?.agentId === agentId;
  }, [leaveReader]);
  /** Creates a mentor from any surface and opens its workspace. */
  const createMentor = useCallback(async (template?: Parameters<typeof agents.create>[0]) => {
    creatingMentor.current = true;
    surfaceRef.current = "mentor";
    setSurface("mentor");
    try {
      const id = await agentsRef.current!.create(template);
      if (mentorRef.current.currentRef.current?.agentId !== id) await showMentor(id);
    } catch (error) { reportError(error); }
    finally { creatingMentor.current = false; }
  }, [reportError, showMentor]); // eslint-disable-line react-hooks/exhaustive-deps
  /** Reads something in the open mentor's reader, in place of what was there. */
  const showInMentor = useCallback(async (page: MentorPage, agentId = mentorRef.current.currentRef.current?.agentId) => {
    if (!agentId) throw new Error("Open a mentor first.");
    if (!await leaveReader(agentId)) return;
    if (!await showMentor(agentId)) return;
    mentorViewRef.current.show(agentId, page);
  }, [leaveReader, showMentor]);
  /** A mentor's own conversation opens the mentor; any other opens in the reader. */
  const showSession = useCallback(async (id: string) => {
    const owner = agentForSession(id);
    if (owner) { await showMentor(owner.id); return; }
    await storeRef.current!.ensureSession(id, runtime.bindRestoredSession);
    await showInMentor({ kind: "session", id });
  }, [runtime.bindRestoredSession, showInMentor, showMentor]);
  const showSessionRef = useRef(showSession);
  showSessionRef.current = showSession;
  const showMentorRef = useRef(showMentor);
  showMentorRef.current = showMentor;
  const showInMentorRef = useRef(showInMentor);
  showInMentorRef.current = showInMentor;

  // Resource cards and the library share one reader in the owning mentor.
  useEffect(() => {
    const open = (event: Event) => {
      const detail = (event as CustomEvent<OpenDocumentDetail>).detail;
      if (!detail) return;
      const owner = detail.agentId && agentsRef.current?.agents.some((agent) => agent.id === detail.agentId) ? detail.agentId : undefined;
      void showInMentor({ kind: "document", document: detail }, owner).catch(reportError);
    };
    window.addEventListener(OPEN_DOCUMENT_EVENT, open);
    return () => window.removeEventListener(OPEN_DOCUMENT_EVENT, open);
  }, [reportError, showInMentor]);

  const { saveToCanvas: _saveToCanvas, selection: canvasSelection } = useSaveToCanvas({ canvases });
  const saveToCanvas = async (agentId: string, text: string, anchor?: HTMLElement | null) => {
    const id = await _saveToCanvas(text, agentId, anchor);
    const title = canvases.find((c) => c.id === id)?.title ?? "";
    setSavedToast({ type: "canvas", id, title });
  };
  const agentHabits = useAgentHabits({ runtime, submission,
    loadSession: (id) => storeRef.current!.loadSession(id),
    onPosted: (chat, name) => { void announceSessionFinished({ ...chat, title: name }, isForeground(chat.id)); },
  }, true);
  const viewedSessionId = surface === "mentor" ? mentor.current?.sessionId : undefined;
  // A hidden run speaks through whoever started it, so nothing here counts or announces it.
  const shownSessions = useMemo(() => sessions.some((session) => session.ephemeral) ? sessions.filter((session) => !session.ephemeral) : sessions, [sessions]);
  const busySessionIds = useMemo(() => new Set(shownSessions.filter((session) => session.busy).map((session) => session.id)), [shownSessions]);
  const unseenFinishedIds = useUnseenFinishedSessions(busySessionIds, viewedSessionId);
  // A mentor that finished a reply while the user was elsewhere.
  const unseenAgentIds = useMemo(() => new Set(agents.agents.filter((agent) => agent.sessionId && unseenFinishedIds.has(agent.sessionId)).map((agent) => agent.id)), [agents.agents, unseenFinishedIds]);
  useInputNotifications(shownSessions, viewedSessionId);
  useEffect(() => syncDockBadge(shownSessions), [shownSessions]);
  useEffect(() => {
    let stopped = false;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow().onFocusChanged(({ payload: focused }) => {
      if (!focused) return;
      runtime.flushEvents();
      syncDockBadge(sessionsRef.current);
    }).then((release) => { if (stopped) release(); else unlisten = release; });
    return () => { stopped = true; unlisten?.(); };
  }, [runtime.flushEvents]);
  // The open mentor's conversation and its reader stay in memory, even behind Settings.
  const readerPage = mentor.current ? mentorView.stateFor(mentor.current.agentId).page : undefined;
  const keepIds = useMemo(() => [mentor.current?.sessionId, readerPage?.kind === "session" ? readerPage.id : undefined].filter((id): id is string => !!id),
    [mentor.current?.sessionId, readerPage]);
  useIdleSessionDetach({ sessions, sessionsRef, keepIds, isForeground,
    openingSessionIds: store.openingSessionIds,
    loadedSessionCache: store.loadedSessionCache, skipForgetSessionIds: store.skipForgetSessionIds,
    persistSession: runtime.persistSession, onError: reportError, setSessions: runtime.updateSessions,
  });
  const delegation = useAgentDelegation({ runtime, submission, loadSession: (id) => storeRef.current!.loadSession(id) });
  const controlWorkspace: AppControlWorkspace = {
    loadSession: store.loadSession,
    addSession: (session, options) => {
      store.addSession(session);
      if (options?.reveal) void showSessionRef.current(session.id).catch(reportError);
    },
    archiveSession: store.archiveSession, removeSession: store.removeSession,
    isCanvasOpen: (id) => {
      const agentId = surfaceRef.current === "mentor" ? mentorRef.current.currentRef.current?.agentId : undefined;
      const page = agentId ? mentorViewRef.current.readingFor(agentId) : undefined;
      return page?.kind === "canvas" && page.id === id;
    },
    // An agent's drawing shows in its own reader; any other in the open mentor's.
    revealCanvas: (id, sessionId) => {
      const owner = agentForSession(sessionId)?.id ?? mentorRef.current.currentRef.current?.agentId;
      if (owner) mentorViewRef.current.show(owner, { kind: "canvas", id });
    },
  };
  const commands = useCommandContext({ workspace: controlWorkspace, runtime, submission, delegation,
    agents: () => agentsRef.current,
    activeAgentId: () => mentorRef.current.currentRef.current?.agentId ?? null,
    showMentor: (id) => showMentorRef.current(id),
    showInMentor: (page, agentId) => showInMentorRef.current(page, agentId),
    leaveReader,
    mentorView: () => mentorViewRef.current,
  });
  useAppControl({ workspace: controlWorkspace, runtime, submission, delegation, commands });
  const [learningTargetRequest, setLearningTargetRequest] = useState<AddToChatRequest | null>(null);
  const revealLearningConversation = useCallback(async (id: string, blockId?: string, isCurrent: () => boolean = () => true) => {
    const agent = agentForSession(id);
    const session = sessionsRef.current.find((entry) => entry.id === id) ?? await storeRef.current!.loadSession(id);
    if (!session) throw new Error("This discussion is no longer available.");
    if (blockId && !session.blocks.some((block) => block.id === blockId)
      && !(agent && await agentsRef.current!.ensureBlockLoaded(id, blockId))) {
      throw new Error("This discussion is no longer available.");
    }
    if (!isCurrent()) return;
    await showSessionRef.current(id);
  }, []);
  const openLearningFile = useCallback((path: string) => { void showInMentor({ kind: "file", path }).catch(reportError); }, [reportError, showInMentor]);
  const openPdf = useCallback(() => {
    void pickFile({ multiple: false, directory: false, filters: [{ name: "PDF", extensions: ["pdf"] }] })
      .then((path) => { if (typeof path === "string") openLearningFile(path); })
      .catch(reportError);
  }, [openLearningFile, reportError]);
  useEffect(() => {
    const queued = (request: AddToChatRequest, id: string) => {
      queueLearningDraft(id, { ...request, targetSessionId: id });
      void revealLearningConversation(id).catch(reportError);
    };
    const add = (event: Event) => {
      const request = (event as CustomEvent<AddToChatRequest>).detail;
      if (!request || (!request.targetSessionId && !request.sources?.length)) return;
      event.stopImmediatePropagation();
      const target = request.targetSessionId ?? mentorRef.current.currentRef.current?.sessionId;
      if (target) queued(request, target); else setLearningTargetRequest(request);
    };
    const discussion = (event: Event) => {
      const ref = (event as CustomEvent<DiscussionRef>).detail;
      if (!ref?.sessionId || !ref.blockId) return;
      void revealLearningConversation(ref.sessionId, ref.blockId).then(() => requestTranscriptJump(ref.sessionId, ref.blockId)).catch(reportError);
    };
    const course = (event: Event) => {
      const detail = (event as CustomEvent<OpenCourseDetail>).detail;
      if (!detail?.courseId || !detail.agentId) return;
      // A course belongs to its mentor; one kept by an ordinary session reads in the open mentor.
      const owner = agentsRef.current?.agents.some((agent) => agent.id === detail.agentId) ? detail.agentId : undefined;
      void showInMentor({ kind: "course", course: detail }, owner).catch(reportError);
    };
    window.addEventListener(ADD_TO_CHAT_EVENT, add, true);
    window.addEventListener(OPEN_LEARNING_DISCUSSION_EVENT, discussion);
    window.addEventListener(OPEN_COURSE_EVENT, course);
    return () => {
      window.removeEventListener(ADD_TO_CHAT_EVENT, add, true);
      window.removeEventListener(OPEN_LEARNING_DISCUSSION_EVENT, discussion);
      window.removeEventListener(OPEN_COURSE_EVENT, course);
    };
  }, [reportError, revealLearningConversation, showInMentor]);
  useEffect(() => {
    const open = (event: Event) => {
      const path = (event as CustomEvent<{ path?: string }>).detail?.path;
      if (path) openLearningFile(path);
    };
    window.addEventListener(OPEN_FILE_EVENT, open);
    return () => window.removeEventListener(OPEN_FILE_EVENT, open);
  }, [openLearningFile]);
  useEffect(() => {
    const release = listen("open_pdf", openPdf);
    return () => { void release.then((stop) => stop()); };
  }, [openPdf]);
  useAppResourceNavigation({
    openSession: (id) => showSessionRef.current(id),
    openFile: openLearningFile,
    fileBase: () => sessionsRef.current.find((session) => session.id === (readerSessionId() ?? mentorRef.current.currentRef.current?.sessionId))?.cwd,
    mentorBase: () => mentorRef.current.currentRef.current?.agentId,
    openDocument: async (agentId, documentId, place) => {
      const found = await readAgentDocument(agentId, documentId);
      if (found?.body == null) return false;
      // A lesson already showing this document keeps the reader; the passage is shown in the lesson.
      const state = mentorViewRef.current.stateFor(agentId);
      let inLesson = false;
      if (state.page?.kind === "course" && state.lesson) {
        const course = await loadCourse(state.page.course.courseId, agentId).catch(() => null);
        const lesson = course ? courseItems(course.data).find((item) => item.id === state.lesson!.id) : undefined;
        inLesson = !!lesson && "document" in lesson && lesson.document === documentId;
      }
      if (place) requestDocumentPlace(agentId, documentId, place);
      if (inLesson) { await showMentorRef.current(agentId); return true; }
      await showInMentor({ kind: "document", document: { id: found.id, title: found.title, body: found.body, ...(found.subject ? { subject: found.subject } : {}) } }, agentId);
      return true;
    },
    // A drawing an agent keeps opens in that agent's reader; any other in the open mentor's.
    openCanvas: (canvas, owner) => showInMentor({ kind: "canvas", id: canvas.id }, owner),
    // A note an agent owns opens in its reader; any other opens in the open mentor's, still unowned.
    openNote: (id, owner) => showInMentor({ kind: "note", id }, owner),
    onOpenConversation: revealLearningConversation,
    onError: reportError,
  });

  const openSettings = useCallback((section?: SettingsSectionId, anchor: string | null = null) => {
    if (section) { setSettingsSection(section); saveSettingsSection(section); }
    setSettingsAnchor(anchor);
    startTransition(() => setSurface("settings"));
  }, []);
  const closeSettings = useCallback(() => setSurface("mentor"), []);
  // The composer's MCP picker hands its settings link to the app rather than the pane.
  useEffect(() => {
    const openMcp = () => openSettings("mcp");
    window.addEventListener("loci:open-mcp-settings", openMcp);
    return () => window.removeEventListener("loci:open-mcp-settings", openMcp);
  }, [openSettings]);
  const onSelectSettingsSection = useCallback((section: SettingsSectionId) => {
    setSettingsSection(section); saveSettingsSection(section); setSettingsAnchor(null);
  }, []);
  const renameCanvas = (id: string, title: string) => {
    void updateCanvas(id, { title }).catch(reportError);
  };
  const canvasAddToAgent = (text: string) => {
    const current = mentorRef.current.currentRef.current;
    if (current) requestAddToChat(text, "plain", { targetSessionId: current.sessionId });
  };
  const persistWindow = useCallback(async (mode: WorkspaceSaveMode = "transition") => {
    runtime.flushEvents();
    await runtime.flushPersistence();
    await persistQuitState(sessionsRef.current, mode);
  }, [runtime.flushEvents, runtime.flushPersistence]);
  const reload = useCallback(() => { void persistWindow().then(() => window.location.reload()).catch(reportError); }, [persistWindow, reportError]);
  const applyZoom = (direction: -1 | 0 | 1) => {
    if (requestImageZoom(direction === 0 ? "zoom-reset" : direction === 1 ? "zoom-in" : "zoom-out")) return;
    void applyUiScale(saveUiScale(direction === 0 ? UI_SCALE_DEFAULT : direction === 1 ? zoomInUiScale(loadUiScale()) : zoomOutUiScale(loadUiScale())));
  };
  const withMentor = (work: (agentId: string) => void) => () => {
    const id = mentorRef.current.currentRef.current?.agentId;
    if (id) work(id);
  };
  const toggleLibrary = withMentor((id) => mentorViewRef.current.toggleLibrary(id));
  const toggleChat = withMentor((id) => mentorViewRef.current.toggleChat(id));
  /** Closes what the reader shows; false when it was already empty. */
  const closeReader = () => {
    if (surfaceRef.current === "settings") { closeSettings(); return true; }
    const id = mentorRef.current.currentRef.current?.agentId;
    if (!id || !mentorViewRef.current.readingFor(id)) return false;
    void leaveReader(id).then((saved) => { if (saved) mentorViewRef.current.close(id); });
    return true;
  };
  const stepMentor = (delta: number) => {
    const roster = listAgents();
    const index = roster.findIndex((agent) => agent.id === mentorRef.current.currentRef.current?.agentId);
    const next = roster[(index + delta + roster.length) % roster.length];
    if (next) void showMentor(next.id);
  };
  useAppCommands({ submission, sessionsRef,
    mentorIds: () => listAgents().map((agent) => agent.id),
    activeMentorId: () => mentorRef.current.currentRef.current?.agentId ?? null,
    focusedSessionId: () => {
      if (surfaceRef.current !== "mentor") return null;
      const focusedReader = document.activeElement?.closest("[data-mentor-reader]");
      return (focusedReader ? readerSessionId() : undefined) ?? mentorRef.current.currentRef.current?.sessionId ?? null;
    },
    openMentor: (id) => { void showMentor(id); },
    newMentor: () => setAgentGalleryOpen(true),
    closeReader, closeWindow: () => { void closeCurrentWindow(); },
    toggleLibrary, toggleChat,
    openSearch: () => setSearchOpen((open) => !open),
    openSettings: () => openSettings(),
    openSession: (id) => { void showSessionRef.current(id).catch(reportError); },
    reload,
  });

  const active = surface === "mentor" ? sessions.find((session) => session.id === (readerSessionId() ?? mentor.current?.sessionId)) : undefined;
  useEffect(() => {
    void probeHarnessAvailability();
    void applyUiScale(loadUiScale());
    return watchSystemColorScheme();
  }, []);
  useEffect(() => { if (active) void refreshHarnessCatalogs([active.harness]); }, [active?.harness]);
  useEffect(() => preloadNavigationWhenIdle([SettingsView.preload]), []);
  useLayoutEffect(() => runtime.flushEvents(), [mentor.current?.sessionId, surface, runtime.flushEvents]);
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
  useEffect(() => {
    const refresh = () => { void loadCanvases().then(setCanvases).catch(reportError); };
    refresh();
    window.addEventListener(CANVASES_CHANGED_EVENT, refresh);
    return () => window.removeEventListener(CANVASES_CHANGED_EVENT, refresh);
  }, [reportError]);
  useEffect(() => {
    const release = setQuitWorkspace(() => sessionsRef.current, runtime.flushEvents);
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
      void persistAndCloseWindow(persistWindow, toTray).catch(reportError);
    }).then((unlisten) => { if (disposed) unlisten(); else stop = unlisten; });
    const unload = () => { if (!isAppQuitting()) void persistWindow("unload"); };
    window.addEventListener("beforeunload", unload);
    return () => { disposed = true; release(); stop?.(); window.removeEventListener("beforeunload", unload); };
  }, [runtime.flushEvents, persistWindow, reportError]);

  const openAgentFile = useCallback<OpenFileFn>((path, place) => {
    if (place) requestFilePlace(path, place);
    void showInMentor({ kind: "file", path }).catch(reportError);
  }, [reportError, showInMentor]);

  const paneProps = (session: Session, focused: boolean): ComponentProps<typeof SessionPane> => ({
    session, visible: true, focused, inSplit: false, composerFocused: true, composerFocusToken: mentor.composerFocusToken,
    recents: [...store.recents], hideProjectPicker: true, transcriptPool,
    onFocus: () => undefined, onClose: () => undefined, onCwdChange: () => undefined,
    onModelChange: submission.changeModel, onModelSettingsChange: submission.changeModelSettings, onRuntimeModeChange: submission.changeRuntimeMode,
    onSubmit: submission.onSubmit, onSaveDraft: submission.saveDraft, onRemoveDraft: submission.removeDraft,
    onStop: submission.stop, onCompactContext: submission.compact,
    onDeleteQueuedMessage: submission.deleteQueuedMessage, onEditQueuedMessage: submission.editQueuedMessage,
    onQueuedMessageEditingChange: submission.queuedMessageEditingChange, onSteerQueuedMessage: submission.steerQueuedMessage, onResumeQueue: submission.resumeQueue,
    onUsageLimitResume: submission.usageLimitResume, onUsageLimitResumeAtReset: submission.usageLimitResumeAtReset, onUsageLimitDismiss: submission.usageLimitDismiss,
    onNoteCardDismiss: (id: string) => runtime.updateSessions((current) => current.map((entry) => entry.id === id ? { ...entry, noteCard: undefined } : entry)),
    onNoteSaved: (noteId: string) => setSavedToast({ type: "note", id: noteId, agentId: agentForSession(session.id)?.id }),
    onApproval: submission.approve, onQuestionReply: submission.answer, onQuestionInteraction: submission.keepQuestionOpen,
    onOpenFile: openAgentFile, onBtwSubmit: submission.btwSubmit, onBtwRetry: submission.btwRetry, onBtwDelete: submission.btwDelete,
    onBtwStop: submission.btwStop, onBtwModelChange: submission.btwModelChange,
  });
  const mentorChat = (agentId: string, sessionId: string) => {
    const agent = agents.agents.find((entry) => entry.id === agentId);
    const live = sessions.find((entry) => entry.id === sessionId);
    if (!agent || !live) return null;
    const earlier = agents.earlierBlocksFor(sessionId);
    const session = earlier?.length ? { ...live, blocks: [...earlier, ...live.blocks] } : live;
    return <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-pane-id={sessionId}>
      <AgentSessionPane agent={agent} state={agents.states.get(agent.id) ?? { status: "idle" }}
        sessionPaneProps={{ ...paneProps(session, true), onApproval: agentHabits.approve,
          onSaveToCanvas: (text, anchor) => saveToCanvas(agent.id, text, anchor) }}
        detailsOpen={agents.isDetailsOpen(agent.id)} onToggleDetails={() => agents.setDetailsOpenFor(agent.id, (open) => !open)}
        onReset={() => void agents.reset(agent.id)} onDelete={() => void agents.remove(agent.id)}
        onPickFolders={() => pickFolders("Choose folders")}
        onLoadEarlier={agents.hasEarlier(sessionId) ? () => void agents.loadEarlier(sessionId) : undefined} />
    </div>;
  };
  const readerSession = (id: string) => {
    const session = sessions.find((entry) => entry.id === id);
    if (!session) return <p role="status" className="mentor-reader-empty">Opening the conversation…</p>;
    return <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-pane-id={id}><SessionPane {...paneProps(session, false)} composerFocused={false} /></div>;
  };
  const sessionTitle = (id: string) => {
    const session = sessions.find((entry) => entry.id === id);
    return session ? sessionDisplayTitle(session.title, session.harness) : "Conversation";
  };
  const shownIds = surface === "mentor" ? visibleSessionIds : new Set<string>();

  return <>
    <div className={`workspace-background flex h-full flex-col text-content ${HAS_NATIVE_GLASS ? "bg-background-base/[var(--window-background-opacity)]" : "bg-background-base"}`}>
      {!IS_MAC ? <MenuBar onNewMentor={() => setAgentGalleryOpen(true)} onCloseReader={() => { if (!closeReader()) void closeCurrentWindow(); }}
        onPreviousMentor={() => stepMentor(-1)} onNextMentor={() => stepMentor(1)} onToggleLibrary={toggleLibrary} onToggleChat={toggleChat}
        onOpenPdf={openPdf} onSearch={() => setSearchOpen(true)} onOpenSettings={() => openSettings()}
        onZoomIn={() => applyZoom(1)} onZoomOut={() => applyZoom(-1)} onZoomReset={() => applyZoom(0)} /> : null}
      <div className="flex min-h-0 min-w-0 flex-1">
        <MentorRail activeId={activeAgent?.id} states={agents.states} unseenIds={unseenAgentIds} settingsOpen={surface === "settings"}
          onOpen={(id) => void showMentor(id)} onOpenDetails={(id) => { agents.setDetailsOpenFor(id, true); void showMentor(id); }}
          onCreate={() => setAgentGalleryOpen(true)} onDelete={(id) => void agents.remove(id)}
          onSearch={() => setSearchOpen(true)} onOpenSettings={() => surface === "settings" ? closeSettings() : openSettings()}
          updateVersion={pendingUpdateVersion} onViewUpdate={openUpdatePrompt} />
        {surface === "settings" ? <aside className="flex w-[220px] shrink-0 flex-col border-r border-stroke" aria-label="Settings sections">
          <div className="h-10 shrink-0" data-tauri-drag-region="deep" />
          <SettingsNav section={settingsSection} onSelect={onSelectSettingsSection} onClose={closeSettings} />
        </aside> : null}
        <div className="body-glass flex min-h-0 min-w-0 flex-1 flex-col">
          {surface === "mentor" && mentor.current && focusedAgent ? <section data-agent-workspace={focusedAgent.id} className="flex min-h-0 min-w-0 flex-1 flex-col">
            <MentorWorkspace key={focusedAgent.id} agent={focusedAgent} state={mentorView.stateFor(focusedAgent.id)}
              courseBadge={(courseId, lessonId) => <LessonMarks agentId={focusedAgent.id} courseId={courseId} lessonId={lessonId} />}
              trailing={IS_MAC ? undefined : <WindowControls />}
              canvases={canvases}
              onOpen={(page) => mentorView.show(focusedAgent.id, page)} onClose={() => mentorView.close(focusedAgent.id)}
              onLessonChange={(lesson) => mentorView.setLesson(focusedAgent.id, lesson)}
              onRestoredChecked={(page, exists) => mentorView.confirmRestored(focusedAgent.id, page, exists)}
              onToggleLibrary={() => mentorView.toggleLibrary(focusedAgent.id)}
              onLibraryChange={(change) => mentorView.openLibrary(focusedAgent.id, change)}
              onDraft={(text) => {
                if (!focusedAgent.sessionId) return;
                // The draft waits in the composer; the conversation comes into view to show it.
                if (!mentorView.stateFor(focusedAgent.id).chat) mentorView.toggleChat(focusedAgent.id);
                requestAddToChat(text, "prompt", { targetSessionId: focusedAgent.sessionId });
              }}
              onToggleChat={() => mentorView.toggleChat(focusedAgent.id)}
              onResizeLibrary={(width) => mentorView.resizeLibrary(focusedAgent.id, width)} onResizeChat={(width) => mentorView.resizeChat(focusedAgent.id, width)}
              onBeforeLeave={readerGuard} onReading={(reading) => setAgentReading(focusedAgent.id, reading)}
              onCanvasAddToChat={canvasAddToAgent} onCanvasTitleChange={renameCanvas} onOpenFile={openAgentFile}
              renderSession={readerSession} sessionTitle={sessionTitle}
              chat={mentorChat(mentor.current.agentId, mentor.current.sessionId)} />
          </section> : null}
          {surface === "mentor" && !focusedAgent ? <MentorsEmpty hasMentors={agents.agents.length > 0}
            openingName={firstMentor ? agentLook(firstMentor).name : undefined} failed={firstMentorFailed}
            onCreate={() => setAgentGalleryOpen(true)} onRetry={openFirstMentor}
            trailing={IS_MAC ? undefined : <WindowControls />} /> : null}
          {surface === "settings" ? <SettingsView section={settingsSection} anchor={settingsAnchor}
            cwd="~" besideRail onClose={closeSettings} onSelectSection={onSelectSettingsSection}
            onOpenMentorSettings={(id) => { agents.setDetailsOpenFor(id, true); void showMentor(id); }} /> : null}
        </div>
      </div>
      <ApprovalToasts notices={hiddenApprovalNotices(shownSessions, shownIds)} onFocusSession={(id) => void showSession(id).catch(reportError)} onApproval={submission.approve} />
      {searchOpen ? <MentorSearch onClose={() => setSearchOpen(false)} onPick={(item) => {
        // A note no mentor owns opens in the open mentor's reader.
        const work = item.page ? showInMentor(item.page, item.agentId) : item.agentId ? showMentor(item.agentId) : Promise.resolve();
        void work.catch(reportError);
      }} /> : null}
      {agentGalleryOpen ? <AgentGallery onClose={() => setAgentGalleryOpen(false)} onPick={(template) => void createMentor(template ?? undefined)} /> : null}
      {savedToast && (
        <SavedToast
          toast={savedToast}
          onDismiss={() => setSavedToast(null)}
          onOpen={(t) => {
            // A note still belongs to the mentor it was saved in, whichever mentor is open now.
            const owner = t.type === "note" ? t.agentId : undefined;
            void showInMentor(t.type === "canvas" ? { kind: "canvas", id: t.id } : { kind: "note", id: t.id }, owner).catch(reportError);
          }}
        />
      )}
      {providerSignIn ? <ProviderSignInDialog key={providerSignIn.key} harness={providerSignIn.harness} onClose={() => setProviderSignIn(null)} /> : null}
      <UpdatePrompt />
      {canvasSelection ? <SelectCanvasDialog anchor={canvasSelection.anchor ?? null} canvases={canvasSelection.canvases} onSelect={canvasSelection.resolver} onCancel={() => { canvasSelection.rejecter(new DOMException("Cancelled", "AbortError")); }} /> : null}
      {store.error ? <FileActionError message={store.error} onDismiss={() => store.setError(null)} /> : null}
      {learningTargetRequest ? <Modal title="Choose a mentor" description="Your passage will be added as a draft to the mentor's conversation." onClose={() => setLearningTargetRequest(null)}>
        <div className="flex max-h-80 flex-col gap-1 overflow-auto p-3">
          {agents.agents.filter((agent) => agent.sessionId).map((agent) => <button key={agent.id} type="button" className="rounded-lg px-3 py-2 text-left text-sm hover:bg-content/8" onClick={() => {
            queueLearningDraft(agent.sessionId!, { ...learningTargetRequest, targetSessionId: agent.sessionId! });
            setLearningTargetRequest(null);
            void revealLearningConversation(agent.sessionId!).catch(reportError);
          }}>{agentLook(agent).name}</button>)}
          {!agents.agents.some((agent) => agent.sessionId) ? <p className="p-3 text-sm text-content/60">Create a mentor, then ask about this passage.</p> : null}
        </div>
      </Modal> : null}
    </div>
    <TranscriptPoolOutlet pool={transcriptPool} />
  </>;
}

/** Before the first mentor, or while the last one is opening. */
function MentorsEmpty({ hasMentors, openingName, failed, onCreate, onRetry, trailing }: {
  hasMentors: boolean; openingName?: string; failed: boolean; onCreate: () => void; onRetry: () => void; trailing?: ReactNode;
}) {
  return <div className="flex min-h-0 flex-1 flex-col" data-mentors-empty>
    <div className="flex h-10 shrink-0 items-center justify-end pr-2" data-tauri-drag-region="deep">{trailing}</div>
    {hasMentors ? <div className="flex flex-1 flex-col items-center justify-center gap-3 p-8 text-center">
      <p role="status" className="text-sm text-content/60">
        {failed ? `Couldn't open ${openingName ?? "your mentor"}.` : `Opening ${openingName ?? "your mentor"}…`}
      </p>
      {failed ? <button type="button" className="primary-action rounded-lg px-3 py-1.5 text-sm font-medium" onClick={onRetry}>Try again</button> : null}
    </div> : <div className="flex flex-1 flex-col items-center justify-center gap-3 p-8 text-center">
      <h1 className="text-base font-semibold">Create your first mentor</h1>
      <p className="max-w-sm text-sm text-content/60">A mentor is a resident agent for one topic you are learning. It keeps your courses, sources, notes and drawings, and reads along with you.</p>
      <button type="button" className="primary-action rounded-lg px-3 py-1.5 text-sm font-medium" onClick={onCreate}>Create a mentor</button>
    </div>}
  </div>;
}
