import { ContextMenu, type ContextMenuItem } from "../../shared/ui/ContextMenu";
import { Archive, Chatting, Check, ChevronDown, ChevronRight, CircleAlert, CircleDashed, FileScript, Mortarboard, PanelLeft, Pin, Plus, Search, Settings, StickyNote, } from "../../shared/ui/icons";
import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState, type ComponentProps, type KeyboardEvent as ReactKeyboardEvent, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type ReactNode, type RefObject, } from "react";
import { IS_MAC, MOD } from "../../platform/tauri/platform";
import { copyText } from "../../platform/tauri/clipboard";
import { resolveModel } from "../../features/sessions/model/models";
import { sessionDisplayTitle } from "../../features/sessions/model/session";
import { ParticleText } from "../../shared/ui/ParticleText";
import { nextUnseenFinishedSessions } from "../../features/sessions/model/sessionDone";
import { orderedSessionActionIds, pruneSessionSelection, toggleSessionSelection, } from "../../features/sessions/model/sessionSelection";
import { paneDropFromPoint, setExternalPaneDrop, } from "../../features/workspace/model/paneDrop";
import type { PaneEdge } from "../../features/workspace/model/layout";
import { suppressTextSelection } from "../../shared/lib/drag";
import { compareSessionSummaries, filterSessionsByArchive, filterSessionsByQuery, } from "../../features/sessions/data/sessionHistory";
import { loadPinnedSessionsCollapsed, savePinnedSessionsCollapsed, } from "../../features/sessions/model/pinnedSessions";
import { LIST_PAGE_SIZE, listWindowSize } from "../../shared/lib/listWindow";
import type {} from "../../features/sessions/model/session";
import type { LiveAgent } from "../../features/sessions/model/liveAgents";
import type { SessionSummary } from "../../features/sessions/data/sessionStore";
import type { SettingsSectionId } from "../../features/settings/model/settings";
import { useDragResize } from "../../shared/hooks/useDragResize";
import { useLockOverscroll } from "../../shared/hooks/useLockOverscroll";
import { looksLikeProject, sameProjectPath, type RecentProject, } from "../../features/projects/model/recents";
import { HarnessIcon } from "../../features/sessions/ui/HarnessIcon";
import { LiveAgentsPreview } from "../../features/sessions/ui/LiveAgentsPreview";
import { ProjectRail } from "./ProjectRail";
import { RailAction } from "./RailAction";
import { ActivitySpinner } from "../../features/sessions/ui/ActivitySpinner";
import { DevModeSlot, IconButton, TabVisitNav } from "./TitleBar";
import { SearchableProjectPicker } from "../../features/projects/ui/SearchableProjectPicker";
import { useProjectMenu } from "./useProjectMenu";
import { SessionsEmpty } from "../../features/sessions/ui/SessionsEmpty";
import { SecondarySidebarToggle } from "./SecondarySidebar";
import { FileTree } from "../../features/files/ui/FileTree";
const MIN_WIDTH = 260;
const MAX_WIDTH = 560;
const DEFAULT_WIDTH = 260;
let rememberedWidth = DEFAULT_WIDTH;
type SidebarTab = "sessions" | "files";
const SIDEBAR_TABS: SidebarTab[] = ["sessions", "files"];
let rememberedTab: SidebarTab = "sessions";
const TAB_LABELS: Record<SidebarTab, string> = {
    sessions: "Sessions",
    files: "Files",
};
const COMPACT_TAB_ICONS: Record<SidebarTab, typeof PanelLeft> = {
    sessions: Chatting,
    files: FileScript,
};
function projectPathBusy(paths: Iterable<string> | undefined, cwd: string): boolean {
    if (!paths)
        return false;
    for (const path of paths) {
        if (sameProjectPath(path, cwd))
            return true;
    }
    return false;
}
type Props = {
    cwd: string;
    open: boolean;
    sessions: SessionSummary[];
    busySessionIds: Set<string>;
    approvalSessionIds: Set<string>;
    activeSessionId?: string;
    status: "idle" | "error";
    /** First listing for this project has not arrived yet. */
    pending: boolean;
    onSelectSession: (sessionId: string) => void;
    onSessionNavigationOrder?: (ids: readonly string[]) => void;
    onPrefetchSession?: (sessionId: string) => void;
    onPlaceSessionOnPane?: (sessionId: string, targetId: string, edge: PaneEdge) => void;
    onRenameSession?: (sessionId: string, title: string) => void;
    onArchiveSession?: (sessionId: string, archived: boolean) => void;
    onArchiveSessions?: (sessionIds: readonly string[], archived: boolean) => void;
    onPinSession?: (sessionId: string, pinned: boolean) => void;
    onPinSessions?: (sessionIds: readonly string[], pinned: boolean) => void;
    onDeleteSession?: (sessionId: string) => void;
    onDeleteSessions?: (sessionIds: readonly string[]) => void;
    onTabChange: (tab: SidebarTab) => void;
    canGoBack?: boolean;
    canGoForward?: boolean;
    onGoBack?: () => void;
    onGoForward?: () => void;
    recents?: RecentProject[];
    busyProjectPaths?: Iterable<string>;
    liveAgents?: LiveAgent[];
    agentRail?: ReactNode;
    agentActive?: boolean;
    /** Project folders, their sessions and files; hidden when off. */
    projectsEnabled?: boolean;
    onSelectAgent?: (sessionId: string) => void;
    onSelectProject?: (path: string) => void;
    onOpenProject?: () => void;
    onRemoveProject?: (path: string, options: {
        purgeData: boolean;
    }) => void;
    onNew?: () => string | void;
    onSearch?: () => void;
    onOpenNotes?: () => void;
    onOpenCourses?: () => void;
    /** Files tab: open a project file in the workspace; `pin` keeps its pane. */
    onOpenFile?: (path: string, pin?: boolean) => void;
    /** Hides this sidebar; the same control brings it back from the title bar. */
    onToggleSidebar?: () => void;
    onFileMoved?: (from: string, to: string) => void;
    onFileDeleted?: (path: string) => void;
    searchActive?: boolean;
    notesActive?: boolean;
    coursesActive?: boolean;
    notesEnabled?: boolean;
    onToggleProjectRail?: () => void;
    projectRailOpen?: boolean;
    compactProjectRail?: boolean;
    titleBarAbove?: boolean;
    unseenFinishedIds?: Set<string>;
    settingsOpen?: boolean;
    settingsSection?: SettingsSectionId;
    onOpenSettings?: () => void;
    onOpenNotificationSettings?: (projectPath?: string) => void;
    onSelectSettingsSection?: (section: SettingsSectionId) => void;
    onCloseSettings?: () => void;
};
function SidebarComponent({ agentRail, agentActive, projectsEnabled = true, cwd, open, sessions, busySessionIds, approvalSessionIds, activeSessionId, status, pending, onSelectSession: onSelectLocalSession, onSessionNavigationOrder, onPrefetchSession: onPrefetchLocalSession, onPlaceSessionOnPane: onPlaceLocalSessionOnPane, onRenameSession: onRenameLocalSession, onArchiveSession: onArchiveLocalSession, onArchiveSessions: onArchiveLocalSessions, onPinSession: onPinLocalSession, onPinSessions: onPinLocalSessions, onDeleteSession: onDeleteLocalSession, onDeleteSessions: onDeleteLocalSessions, onTabChange, canGoBack = false, canGoForward = false, onGoBack, onGoForward, recents = [], busyProjectPaths, liveAgents = [], onSelectAgent, onSelectProject, onOpenProject, onRemoveProject, onNew, onSearch, onOpenNotes, onOpenCourses, searchActive = false, notesActive = false, coursesActive = false, notesEnabled = true, onToggleProjectRail, projectRailOpen = true, compactProjectRail = true, titleBarAbove = false, unseenFinishedIds: unseenFinishedIdsProp, settingsOpen = false, settingsSection = "general", onOpenSettings, onOpenNotificationSettings, onSelectSettingsSection, onCloseSettings, onOpenFile, onToggleSidebar, onFileMoved, onFileDeleted, }: Props) {
    const [tab, setTab] = useState<SidebarTab>(() => rememberedTab);
    const pickTab = (next: SidebarTab) => {
        rememberedTab = next;
        setTab(next);
    };
    const onSelectSession = onSelectLocalSession;
    const onPrefetchSession = onPrefetchLocalSession;
    const onPlaceSessionOnPane = onPlaceLocalSessionOnPane;
    const onRenameSession = onRenameLocalSession;
    const onArchiveSession = onArchiveLocalSession;
    const onArchiveSessions = onArchiveLocalSessions;
    const onPinSession = onPinLocalSession;
    const onPinSessions = onPinLocalSessions;
    const onDeleteSession = onDeleteLocalSession;
    const onDeleteSessions = onDeleteLocalSessions;
    const activeListedSessionId = activeSessionId;
    const listedBusySessionIds = busySessionIds;
    const listedApprovalSessionIds = approvalSessionIds;
    const projectSessions = sessions;
    const resize = useDragResize({
        min: MIN_WIDTH,
        max: () => Math.min(MAX_WIDTH, Math.floor(window.innerWidth * 0.5)),
        defaultWidth: DEFAULT_WIDTH,
        initial: rememberedWidth,
        onCommit: (next) => {
            rememberedWidth = next;
        },
    });
    const [now, setNow] = useState(() => Date.now());
    const sessionsLock = useLockOverscroll<HTMLDivElement>();
    const sessionsScrollRef = useRef<HTMLDivElement>(null);
    const [sessionMenu, setSessionMenu] = useState<{
        x: number;
        y: number;
        sessionId: string;
    } | null>(null);
    const [selectedSessionIds, setSelectedSessionIds] = useState<Set<string>>(() => new Set());
    const contextSelectionRef = useRef(false);
    const selectionAnchorRef = useRef<string | null>(null);
    const [renamingSessionId, setRenamingSessionId] = useState<string | null>(null);
    const [pinnedSessionsCollapsed, setPinnedSessionsCollapsed] = useState(() => loadPinnedSessionsCollapsed(cwd));
    const [searchQuery, setSearchQuery] = useState("");
    const [sessionListLimit, setSessionListLimit] = useState(LIST_PAGE_SIZE);
    const loadMoreRef = useRef<HTMLLIElement>(null);
    const searchInputRef = useRef<HTMLInputElement>(null);
    const busyIdsRef = useRef(busySessionIds);
    const focusedSessionIdRef = useRef(activeSessionId);
    const unseenFinishedLocalRef = useRef<Set<string>>(new Set());
    if (busyIdsRef.current !== busySessionIds ||
        focusedSessionIdRef.current !== activeSessionId) {
        unseenFinishedLocalRef.current = nextUnseenFinishedSessions({
            previousBusyIds: busyIdsRef.current,
            busyIds: busySessionIds,
            previousUnseenIds: unseenFinishedLocalRef.current,
            focusedSessionId: activeSessionId,
        });
        busyIdsRef.current = busySessionIds;
        focusedSessionIdRef.current = activeSessionId;
    }
    const unseenFinishedIds = unseenFinishedIdsProp ?? unseenFinishedLocalRef.current;
    // Revisits render straight from cache, so this is only ever true the first
    // time a project is opened.
    const pendingFirstLoad = pending && sessions.length === 0;
    const listedSessions = projectSessions;
    const visibleSessions = [
        ...filterSessionsByQuery(filterSessionsByArchive(listedSessions, false), searchQuery),
    ].sort(compareSessionSummaries);
    const searchNarrowed = Boolean(searchQuery.trim());
    // Pinned sessions sit in their own collapsible group above the flat list.
    // Only a page of the remaining cards mounts; the sentinel below asks for
    // the next page.
    const pinnedSessions = visibleSessions.filter((session) => session.pinned);
    const looseSessions = visibleSessions.filter((session) => !session.pinned);
    const pinnedExpanded = searchNarrowed || !pinnedSessionsCollapsed;
    const activeLooseIndex = looseSessions.findIndex((session) => session.id === activeListedSessionId);
    const shownLooseCount = listWindowSize(looseSessions.length, sessionListLimit, activeLooseIndex);
    const shownLoose = looseSessions.slice(0, shownLooseCount);
    const sessionNavigationIds = [
        ...(pinnedExpanded ? pinnedSessions : []),
        ...looseSessions,
    ].map((session) => session.id);
    const visibleNavigationIds = [
        ...(pinnedExpanded ? pinnedSessions : []),
        ...shownLoose,
    ].map((session) => session.id);
    const sessionNavigationKey = sessionNavigationIds.join("\0");
    useEffect(() => {
        onSessionNavigationOrder?.(sessionNavigationIds);
    }, [onSessionNavigationOrder, sessionNavigationKey]);
    useEffect(() => {
        const available = new Set(sessionNavigationIds);
        if (selectionAnchorRef.current &&
            !available.has(selectionAnchorRef.current)) {
            selectionAnchorRef.current = null;
        }
        setSelectedSessionIds((current) => pruneSessionSelection(current, available));
    }, [cwd, tab, sessionNavigationKey]);
    const hasMoreSessions = shownLooseCount < looseSessions.length;
    const sessionListKey = `${cwd}\0${searchQuery}`;
    const visibleTabs = SIDEBAR_TABS;
    const showProjectRail = Boolean(onSelectProject && onOpenProject);
    // Settings live in the rail slot, so they keep it visible even when the
    // project rail itself is collapsed.
    const railVisible = showProjectRail && (projectRailOpen || settingsOpen);
    // Keep the full rail mounted after its first reveal so reopening does not
    // recreate every project row.
    const railMounted = useRef(railVisible);
    if (railVisible)
        railMounted.current = true;
    const compactRailVisible = compactProjectRail && showProjectRail && !railVisible;
    const inProject = looksLikeProject(cwd);
    const showSidebarFooter = !projectRailOpen;
    // A blank session has no project to browse, so the shell stands alone until
    // one is picked — whether or not the rail is open.
    const sidebarAvailable = !searchActive &&
        !notesActive &&
        !coursesActive &&
        !settingsOpen &&
        projectsEnabled &&
        inProject;
    const sidebarVisible = open && sidebarAvailable;
    // With the sidebar collapsed beside the compact rail, its tab shortcuts
    // open the sidebar temporarily until the user clicks away.
    const drawerMode = compactRailVisible && !open;
    const [drawerOpen, setDrawerOpen] = useState(false);
    const drawerRef = useRef<HTMLDivElement>(null);
    const drawerVisible = drawerMode && drawerOpen && sidebarAvailable;
    // A dismissed drawer stays mounted while it slides shut. Anything that takes
    // its place (the pinned sidebar, another view) drops it at once.
    const [drawerMounted, setDrawerMounted] = useState(false);
    const drawerClosing = drawerMounted && !drawerVisible && drawerMode && sidebarAvailable;
    const drawerRendered = drawerVisible || drawerClosing;
    const drawerAnimation = useRef<Animation | null>(null);
    const panelOpen = open || drawerVisible;
    useEffect(() => {
        if (!drawerMode || !sidebarAvailable)
            setDrawerOpen(false);
    }, [drawerMode, sidebarAvailable]);
    useEffect(() => {
        if (drawerVisible)
            setDrawerMounted(true);
        else if (!drawerClosing)
            setDrawerMounted(false);
    }, [drawerVisible, drawerClosing]);
    // Grow the drawer's width so the workspace is pushed along with it. A
    // reversal mid-slide starts from wherever the width currently is.
    useLayoutEffect(() => {
        const drawer = drawerRef.current;
        if (!drawerRendered || !drawer) {
            drawerAnimation.current = null;
            return;
        }
        const full = drawer.firstElementChild instanceof HTMLElement
            ? drawer.firstElementChild.offsetWidth
            : 0;
        const from = drawerAnimation.current
            ? drawer.getBoundingClientRect().width
            : drawerClosing
                ? full
                : 0;
        drawerAnimation.current?.cancel();
        drawerAnimation.current = null;
        const reduceMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
        if (typeof drawer.animate !== "function" || reduceMotion) {
            if (drawerClosing)
                setDrawerMounted(false);
            return;
        }
        const animation = drawer.animate([{ width: `${from}px` }, { width: `${drawerClosing ? 0 : full}px` }], drawerClosing
            ? {
                duration: 160,
                easing: "cubic-bezier(0.4, 0, 1, 1)",
                fill: "forwards",
            }
            : { duration: 200, easing: "cubic-bezier(0.22, 1, 0.36, 1)" });
        drawerAnimation.current = animation;
        animation.onfinish = () => {
            if (drawerAnimation.current !== animation)
                return;
            drawerAnimation.current = null;
            if (drawerClosing)
                setDrawerMounted(false);
        };
    }, [drawerRendered, drawerClosing]);
    useEffect(() => {
        if (!drawerVisible)
            return;
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.key !== "Escape" || event.defaultPrevented)
                return;
            setDrawerOpen(false);
        };
        // The rail's own shortcuts toggle the drawer, and menus opened from it
        // stay usable; anything else dismisses it.
        const onPointerDown = (event: PointerEvent) => {
            const target = event.target;
            const el = target instanceof Element ? target : null;
            if (drawerRef.current?.contains(el))
                return;
            if (el?.closest("[data-compact-project-rail],[data-popover-side]")) {
                return;
            }
            setDrawerOpen(false);
        };
        window.addEventListener("keydown", onKeyDown);
        window.addEventListener("pointerdown", onPointerDown);
        return () => {
            window.removeEventListener("keydown", onKeyDown);
            window.removeEventListener("pointerdown", onPointerDown);
        };
    }, [drawerVisible]);
    useEffect(() => {
        setSessionListLimit(LIST_PAGE_SIZE);
        const scroller = sessionsScrollRef.current;
        if (scroller)
            scroller.scrollTop = 0;
    }, [sessionListKey]);
    useEffect(() => {
        if (!hasMoreSessions)
            return;
        const sentinel = loadMoreRef.current;
        const root = sessionsScrollRef.current;
        if (!sentinel || !root)
            return;
        const observer = new IntersectionObserver(([entry]) => {
            if (!entry?.isIntersecting)
                return;
            setSessionListLimit((current) => current + LIST_PAGE_SIZE);
        }, { root, rootMargin: "240px" });
        observer.observe(sentinel);
        return () => observer.disconnect();
    }, [tab, hasMoreSessions, shownLooseCount]);
    useEffect(() => {
        setPinnedSessionsCollapsed(loadPinnedSessionsCollapsed(cwd));
    }, [cwd]);
    useEffect(() => {
        const id = window.setInterval(() => setNow(Date.now()), 30000);
        return () => window.clearInterval(id);
    }, [tab]);
    useEffect(() => {
        if (!sessionMenu)
            return;
        const onScroll = () => {
            closeSessionMenu();
        };
        const scrollParent = sessionsScrollRef.current ?? window;
        scrollParent.addEventListener("scroll", onScroll, true);
        return () => scrollParent.removeEventListener("scroll", onScroll, true);
    }, [sessionMenu]);
    useEffect(() => {
        if (selectedSessionIds.size === 0)
            return;
        const clear = () => {
            selectionAnchorRef.current = null;
            contextSelectionRef.current = false;
            setSelectedSessionIds(new Set());
            setSessionMenu(null);
        };
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.key !== "Escape")
                return;
            clear();
        };
        // A pointer landing off the cards drops the selection; a menu acting on
        // it stays open, and the cards handle their own clicks.
        const onPointerDown = (event: PointerEvent) => {
            const target = event.target;
            const el = target instanceof Element ? target : null;
            if (el?.closest("[data-session-card],[data-popover-side]"))
                return;
            clear();
        };
        window.addEventListener("keydown", onKeyDown);
        window.addEventListener("pointerdown", onPointerDown);
        return () => {
            window.removeEventListener("keydown", onKeyDown);
            window.removeEventListener("pointerdown", onPointerDown);
        };
    }, [selectedSessionIds.size]);
    const menuSessionIds = sessionMenu
        ? orderedSessionActionIds(sessionMenu.sessionId, selectedSessionIds, sessionNavigationIds)
        : [];
    const menuSessions = menuSessionIds.flatMap((sessionId) => {
        const session = listedSessions.find((entry) => entry.id === sessionId);
        return session ? [session] : [];
    });
    const multipleMenuSessions = menuSessionIds.length > 1;
    const allMenuSessionsPinned = menuSessions.length > 0 && menuSessions.every((session) => session.pinned);
    const allMenuSessionsArchived = menuSessions.length > 0 &&
        menuSessions.every((session) => session.archived);
    const sessionMenuItems: ContextMenuItem[] = [
        ...(onPinSession || onPinSessions
            ? [
                {
                    kind: "item" as const,
                    id: "pin",
                    label: allMenuSessionsPinned ? "Unpin" : "Pin",
                },
            ]
            : []),
        ...(!multipleMenuSessions && onRenameSession
            ? [
                {
                    kind: "item" as const,
                    id: "rename",
                    label: "Rename",
                    shortcut: "F2",
                },
            ]
            : []),
        ...(!multipleMenuSessions
            ? [
                {
                    kind: "item" as const,
                    id: "copy-session-id",
                    label: "Copy session ID",
                    submenu: [
                        {
                            kind: "item" as const,
                            id: "copy-harness-session-id",
                            label: "Harness session ID",
                            disabled: !menuSessions[0]?.providerSessionId,
                        },
                        {
                            kind: "item" as const,
                            id: "copy-loci-session-id",
                            label: "Loci session ID",
                        },
                    ],
                },
            ]
            : []),
        ...(onArchiveSession ||
            onArchiveSessions ||
            onDeleteSession ||
            onDeleteSessions
            ? [
                { kind: "sep" as const },
                ...(onArchiveSession || onArchiveSessions
                    ? [
                        {
                            kind: "item" as const,
                            id: "archive",
                            label: allMenuSessionsArchived ? "Unarchive" : "Archive",
                        },
                    ]
                    : []),
                ...(onDeleteSession || onDeleteSessions
                    ? [
                        {
                            kind: "item" as const,
                            id: "delete",
                            label: "Delete",
                            shortcut: "⌫",
                            danger: true,
                        },
                    ]
                    : []),
            ]
            : []),
    ];
    const onSessionContextMenu = (sessionId: string, e: ReactMouseEvent<HTMLDivElement>) => {
        e.preventDefault();
        e.stopPropagation();
        contextSelectionRef.current = !selectedSessionIds.has(sessionId);
        if (contextSelectionRef.current) {
            setSelectedSessionIds(new Set([sessionId]));
        }
        setSessionMenu({ x: e.clientX, y: e.clientY, sessionId });
    };
    const closeSessionMenu = () => {
        setSessionMenu(null);
        if (!contextSelectionRef.current)
            return;
        contextSelectionRef.current = false;
        selectionAnchorRef.current = null;
        setSelectedSessionIds(new Set());
    };
    const onSessionMenuPick = (id: string) => {
        if (!sessionMenu)
            return;
        const sessionId = sessionMenu.sessionId;
        const sessionIds = menuSessionIds;
        const providerSessionId = menuSessions[0]?.providerSessionId;
        const archived = allMenuSessionsArchived;
        const pinned = allMenuSessionsPinned;
        closeSessionMenu();
        if (id === "pin") {
            if (sessionIds.length > 1 && onPinSessions) {
                onPinSessions(sessionIds, !pinned);
            }
            else {
                for (const id of sessionIds)
                    onPinSession?.(id, !pinned);
            }
            return;
        }
        if (id === "rename") {
            setRenamingSessionId(sessionId);
            return;
        }
        if (id === "copy-harness-session-id" || id === "copy-loci-session-id") {
            const value = id === "copy-harness-session-id" ? providerSessionId : sessionId;
            if (value) {
                void copyText(value).catch((error) => {
                    console.error("Failed to copy session ID:", error);
                });
            }
            return;
        }
        if (id === "archive") {
            if (sessionIds.length > 1 && onArchiveSessions) {
                onArchiveSessions(sessionIds, !archived);
            }
            else {
                for (const id of sessionIds)
                    onArchiveSession?.(id, !archived);
            }
            return;
        }
        if (id === "delete") {
            if (sessionIds.length > 1 && onDeleteSessions) {
                onDeleteSessions(sessionIds);
            }
            else {
                for (const id of sessionIds)
                    onDeleteSession?.(id);
            }
        }
    };
    const onSessionCardSelect = (sessionId: string, event: {
        shiftKey: boolean;
        ctrlKey: boolean;
        metaKey: boolean;
    }) => {
        contextSelectionRef.current = false;
        setSessionMenu(null);
        if (event.shiftKey) {
            const visibleIds = visibleNavigationIds;
            if (selectionAnchorRef.current &&
                !visibleIds.includes(selectionAnchorRef.current)) {
                selectionAnchorRef.current = null;
            }
            const anchor = selectionAnchorRef.current ?? activeListedSessionId ?? sessionId;
            const start = visibleIds.indexOf(anchor);
            const end = visibleIds.indexOf(sessionId);
            const range = start < 0 || end < 0
                ? [sessionId]
                : visibleIds.slice(Math.min(start, end), Math.max(start, end) + 1);
            selectionAnchorRef.current = start < 0 ? sessionId : anchor;
            setSelectedSessionIds((current) => new Set(event.ctrlKey || event.metaKey ? [...current, ...range] : range));
            return;
        }
        selectionAnchorRef.current = sessionId;
        if (event.ctrlKey || event.metaKey) {
            const next = toggleSessionSelection(selectedSessionIds, sessionId);
            if (next.size === 0)
                selectionAnchorRef.current = null;
            setSelectedSessionIds(next);
            return;
        }
        setSelectedSessionIds(new Set());
        setDrawerOpen(false);
        onSelectSession(sessionId);
    };
    // Cards are memoized. Their handlers go through one stable set that calls
    // the latest version, so a sidebar render no longer re-renders every card.
    const cardHandlers = useRef({
        onSessionCardSelect,
        onPrefetchSession,
        onPlaceSessionOnPane,
        onSessionContextMenu,
        onArchiveSession,
        setRenamingSessionId,
        onDeleteSession,
    });
    cardHandlers.current = {
        onSessionCardSelect,
        onPrefetchSession,
        onPlaceSessionOnPane,
        onSessionContextMenu,
        onArchiveSession,
        setRenamingSessionId,
        onDeleteSession,
    };
    const cardActions = useMemo(() => ({
        select: (sessionId: string, event: {
            shiftKey: boolean;
            ctrlKey: boolean;
            metaKey: boolean;
        }) => cardHandlers.current.onSessionCardSelect(sessionId, event),
        prefetch: (sessionId: string) => cardHandlers.current.onPrefetchSession?.(sessionId),
        placeOnPane: (sessionId: string, targetId: string, edge: PaneEdge) => cardHandlers.current.onPlaceSessionOnPane?.(sessionId, targetId, edge),
        contextMenu: (sessionId: string, e: ReactMouseEvent<HTMLDivElement>) => cardHandlers.current.onSessionContextMenu(sessionId, e),
        archive: (sessionId: string, archived: boolean) => cardHandlers.current.onArchiveSession?.(sessionId, archived),
        rename: (sessionId: string) => cardHandlers.current.setRenamingSessionId(sessionId),
        delete: (sessionId: string) => cardHandlers.current.onDeleteSession?.(sessionId),
    }), []);
    const sessionInsertMotion = useRef<SessionInsertMotion>({
        cwd: "",
        seen: new Set(),
    });
    // Runs after the rows' mount effects: a project's first paint never animates,
    // and rows that mount later (drawer opened) are not new.
    useLayoutEffect(() => {
        const motion = sessionInsertMotion.current;
        motion.cwd = cwd;
        for (const session of listedSessions)
            motion.seen.add(session.id);
    });
    const renderSessionCard = (session: SessionSummary, compact = false) => renamingSessionId === session.id && onRenameSession ? (<SessionRenameRow session={session} isActive={session.id === activeListedSessionId} needsApproval={listedApprovalSessionIds.has(session.id)} onCommit={(title) => {
            onRenameSession(session.id, title);
            setRenamingSessionId(null);
        }} onCancel={() => setRenamingSessionId(null)}/>) : (<SessionCard session={session} isActive={session.id === activeListedSessionId} isSelected={selectedSessionIds.has(session.id)} busy={listedBusySessionIds.has(session.id)} done={unseenFinishedIds.has(session.id)} needsApproval={listedApprovalSessionIds.has(session.id)} compact={compact} now={now} onSelect={cardActions.select} onPrefetch={onPrefetchSession ? cardActions.prefetch : undefined} onPlaceOnPane={onPlaceSessionOnPane ? cardActions.placeOnPane : undefined} onContextMenu={cardActions.contextMenu} onArchive={onArchiveSession ? cardActions.archive : undefined} onRename={onRenameSession ? cardActions.rename : undefined} onDelete={onDeleteSession ? cardActions.delete : undefined}/>);
    const sessionSearchInput = (<input ref={searchInputRef} type="text" value={searchQuery} placeholder="Search conversations..." aria-label="Search conversations" spellCheck={false} autoComplete="off" autoCorrect="off" autoCapitalize="off" onChange={(event) => setSearchQuery(event.target.value)} onKeyDown={(event) => {
            if (event.key !== "Escape")
                return;
            event.preventDefault();
            event.stopPropagation();
            if (searchQuery) {
                setSearchQuery("");
            }
        }} className="h-full w-full min-w-0 rounded-md bg-transparent py-0 pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/35"/>);
    const onCompactTabPick = (itemId: SidebarTab) => {
        if (drawerMode) {
            setDrawerOpen(!(drawerVisible && tab === itemId));
        }
        pickTab(itemId);
        onTabChange(itemId);
    };
    const workspaceTabItems = visibleTabs.map((itemId) => (<div key={itemId} className="workspace-tab relative flex min-w-0 flex-1 items-stretch">
        <button type="button" role="tab" aria-selected={tab === itemId} data-tauri-drag-region="false" onClick={() => pickTab(itemId)} className={`flex h-6 min-w-0 flex-1 items-center justify-center self-center rounded-md px-2 text-[12px] leading-none ${tab === itemId ? "bg-selection text-content" : "text-content/50 hover:text-content"}`}>
          <span className="block truncate leading-label">{TAB_LABELS[itemId]}</span>
        </button>
      </div>));
    const sidebarToggle = onToggleSidebar ? (<SecondarySidebarToggle open onToggle={onToggleSidebar} name="workspace sidebar"/>) : null;
    const workspaceHeader = (<div className="flex h-10 shrink-0 select-none items-center gap-1 border-b border-stroke pl-1.5 pr-1.5" data-tauri-drag-region="deep">
      {sidebarToggle}
      <div className="flex min-w-0 flex-1 items-center">
        {(<span className="min-w-0 truncate text-sm font-medium leading-tight">
            Workspace
          </span>)}
      </div>
      <WorkspaceTitleActions onNew={onNew}/>
    </div>);
    const sidebarContent = (<aside ref={resize.setPaneRef} className="body-glass relative flex h-full min-h-0 shrink-0 flex-col border-r border-stroke">
      {railVisible ? (<>
          {workspaceHeader}
          <div role="tablist" aria-label="Workspace" className="flex h-9 shrink-0 items-center gap-px border-b border-stroke px-2">
            {workspaceTabItems}
          </div>
        </>) : (<>
          {titleBarAbove ? null : (<div className="flex h-10 shrink-0 select-none items-center border-b border-stroke pr-1.5" data-tauri-drag-region="deep">
              {IS_MAC ? <div className="w-[78px] shrink-0"/> : null}
              <DevModeSlot />
              <TabVisitNav canGoBack={canGoBack} canGoForward={canGoForward} onGoBack={onGoBack} onGoForward={onGoForward} onTogglePanel={compactProjectRail ? undefined : onToggleProjectRail}/>
              {sidebarToggle}
            </div>)}
          {compactRailVisible ? workspaceHeader : null}
          {onSelectProject && !compactRailVisible ? (<SidebarProjectPicker cwd={cwd} recents={recents} busy={projectPathBusy(busyProjectPaths, cwd)} onSelectProject={onSelectProject} onOpenProject={onOpenProject} onRemoveProject={onRemoveProject} onNew={onNew} onSearch={onSearch} onOpenNotificationSettings={onOpenNotificationSettings} onOpenNotes={notesEnabled ? onOpenNotes : undefined} searchActive={searchActive} notesActive={notesActive}/>) : null}
          {!compactRailVisible ? (<div role="tablist" aria-label="Workspace" className="flex h-9 shrink-0 items-center gap-px overflow-visible border-b border-stroke px-2">
              {workspaceTabItems}
            </div>) : null}
        </>)}
      <>
        <div className={`flex min-h-0 flex-1 flex-col overflow-hidden ${tab === "files" ? "" : "hidden"}`}>
          {cwd && cwd !== "~" && onOpenFile ? (<FileTree key={cwd} cwd={cwd} onOpenFile={onOpenFile} onFileMoved={onFileMoved} onFileDeleted={onFileDeleted}/>) : (<p className="px-3 py-2 text-[12px] text-content/50">
              No project folder
            </p>)}
        </div>
        {tab === "sessions" && cwd && cwd !== "~" ? (<div className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
            <div className="relative flex h-7 min-w-0 flex-1 items-center">
              <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50"/>
              {sessionSearchInput}
            </div>
          </div>) : null}
        <div ref={(el) => {
            sessionsLock(el);
            sessionsScrollRef.current = el;
        }} className={`sidebar-session-scroll min-h-0 flex-1 overflow-y-auto overscroll-none ${tab === "sessions" ? "" : "hidden"}`}>
          {!cwd || cwd === "~" ? (<p className="px-3 py-2 text-[12px] text-content/50">
              No project folder
            </p>) : (<div>
              {/*
A project's first load stays deliberately blank. The listing is
served from a covering index and resolves within a frame or two,
so a placeholder only ever flashed — reading as a glitch rather
than as progress. This is checked before the empty state so that
cannot claim "No sessions yet" before the rows have landed.
*/}
              {pendingFirstLoad ? null : status === "error" &&
                projectSessions.length === 0 ? (<p className="px-3 py-2 text-[12px] text-content/50">
                  Couldn’t load sessions
                </p>) : visibleSessions.length === 0 ? (
            // A narrowed-down result is a transient answer to what the user
            // just typed, so it stays a quiet line of text. Only the genuine
            // "this project has nothing in it" case earns the illustration.
            searchNarrowed ? (<p className="px-3 py-2 text-[12px] text-content/50">
                    No matching sessions
                  </p>) :
                (<SessionsEmpty message="Sessions you start will show up here"/>)) : (<ul data-session-list className="flex flex-col gap-0.5 p-1.5 pb-10">
                  {pinnedSessions.length > 0 ? (<li data-pinned-sessions className="relative mb-1.5">
                      <div className="overflow-hidden rounded-md bg-content/5">
                        <SessionGroupRow name="Pinned" sessions={pinnedSessions} expanded={pinnedExpanded} busy={pinnedSessions.some((session) => listedBusySessionIds.has(session.id))} done={pinnedSessions.some((session) => unseenFinishedIds.has(session.id))} needsApproval={pinnedSessions.some((session) => listedApprovalSessionIds.has(session.id))} icon={(<Pin className="size-3.5 text-content" strokeWidth={1.75}/>)} onToggle={() => {
                                if (searchNarrowed)
                                    return;
                                const collapsed = !pinnedSessionsCollapsed;
                                setPinnedSessionsCollapsed(collapsed);
                                savePinnedSessionsCollapsed(cwd, collapsed);
                            }}/>
                        {pinnedExpanded ? (<ul className="flex flex-col gap-px p-1">
                            {pinnedSessions.map((session) => (<SessionListItem key={session.id} session={session} cwd={cwd} motion={sessionInsertMotion}>
                                {renderSessionCard(session, true)}
                              </SessionListItem>))}
                          </ul>) : null}
                      </div>
                    </li>) : null}
                  {shownLoose.map((session) => (<SessionListItem key={session.id} session={session} cwd={cwd} motion={sessionInsertMotion}>
                      {renderSessionCard(session)}
                    </SessionListItem>))}
                  {hasMoreSessions ? (<li ref={loadMoreRef} aria-hidden className="h-px list-none"/>) : null}
                </ul>)}
            </div>)}
        </div>

        {showSidebarFooter ? (<>
            <LiveAgentsPreview agents={liveAgents} activeSessionId={activeSessionId} onSelect={onSelectAgent} bottomSpacing={compactRailVisible}/>

            <div className="flex shrink-0 flex-col gap-px p-2 empty:hidden">

              {!compactProjectRail ? (<RailAction label="Settings" icon={Settings} onClick={onOpenSettings} shortcut={`${MOD},`} ariaLabel={`Settings (${MOD},)`}/>) : null}
            </div>
          </>) : null}
      </>
      {sessionMenu ? (<ContextMenu x={sessionMenu.x} y={sessionMenu.y} items={sessionMenuItems} ariaLabel={multipleMenuSessions
                ? `${menuSessionIds.length} selected session actions`
                : "Session actions"} onPick={onSessionMenuPick} onClose={closeSessionMenu}/>) : null}

      <div role="separator" aria-orientation="vertical" aria-label="Resize sidebar" aria-valuenow={resize.width} aria-valuemin={MIN_WIDTH} aria-valuemax={MAX_WIDTH} className={`absolute inset-y-0 -right-px z-10 w-1.5 cursor-col-resize touch-none ${resize.dragging ? "bg-content/15" : "hover:bg-content/10"}`} onPointerDown={resize.onPointerDown} onDoubleClick={resize.onDoubleClick}/>
    </aside>);
    return (<div className={`flex h-full shrink-0 ${railVisible || compactRailVisible || sidebarVisible ? "" : "hidden"}`}>
      {compactRailVisible ? (<CompactProjectRail projectsEnabled={projectsEnabled} cwd={cwd} recents={recents} busy={projectPathBusy(busyProjectPaths, cwd)} tabs={visibleTabs} activeTab={tab} tabShown={panelOpen} onSelectProject={onSelectProject} onOpenProject={onOpenProject} onRemoveProject={onRemoveProject} onTabChange={onCompactTabPick} onSearch={onSearch} searchActive={searchActive} onOpenNotificationSettings={onOpenNotificationSettings} onOpenNotes={notesEnabled ? onOpenNotes : undefined} notesActive={notesActive} onOpenCourses={onOpenCourses} coursesActive={coursesActive} onOpenSettings={onOpenSettings} onTogglePanel={onToggleProjectRail} onLeaveActive={onGoBack} titleBarAbove={titleBarAbove}/>) : null}
      {railMounted.current && onSelectProject && onOpenProject ? (<ProjectRail visible={railVisible} agentRail={agentRail} agentActive={agentActive} projectsEnabled={projectsEnabled} cwd={cwd} recents={recents} busyPaths={busyProjectPaths} liveAgents={liveAgents} activeSessionId={activeSessionId} onSelectAgent={onSelectAgent} canGoBack={canGoBack} canGoForward={canGoForward} onGoBack={onGoBack} onGoForward={onGoForward} onSearch={onSearch} searchActive={searchActive} notesEnabled={notesEnabled} onOpenNotes={onOpenNotes} notesActive={notesActive} onOpenCourses={onOpenCourses} coursesActive={coursesActive} onTogglePanel={onToggleProjectRail} onSelectProject={onSelectProject} onOpenProject={onOpenProject} onRemoveProject={onRemoveProject} settingsOpen={settingsOpen} settingsSection={settingsSection} onOpenSettings={onOpenSettings} onOpenNotificationSettings={onOpenNotificationSettings} onSelectSettingsSection={onSelectSettingsSection} onCloseSettings={onCloseSettings}/>) : null}
      {sidebarVisible ? sidebarContent : null}
      {drawerRendered ? (
        // Pinned to the right edge, so the sidebar slides in as the width grows.
        <div ref={drawerRef} data-sidebar-drawer={drawerClosing ? "closing" : "open"} inert={drawerClosing || undefined} className={`flex shrink-0 justify-end overflow-hidden ${drawerClosing ? "pointer-events-none" : ""}`}>
          {sidebarContent}
        </div>) : null}
    </div>);
}
export const Sidebar = memo(SidebarComponent);
/** Project picker whose rows open the shared project context menu. */
function SearchableProjectPickerWithMenu({ onRemoveProject, onOpenNotificationSettings, ...pickerProps }: Omit<ComponentProps<typeof SearchableProjectPicker>, "onProjectContextMenu" | "projectMenuActive"> & {
    onRemoveProject?: Props["onRemoveProject"];
    onOpenNotificationSettings?: (projectPath?: string) => void;
}) {
    const projectMenu = useProjectMenu({
        onRemoveProject,
        onOpenNotificationSettings,
    });
    return (<>
      <SearchableProjectPicker {...pickerProps} onProjectContextMenu={projectMenu.open} projectMenuActive={projectMenu.isActive}/>
      {projectMenu.element}
    </>);
}
function SidebarProjectPicker({ cwd, recents, busy, onSelectProject, onOpenProject, onRemoveProject, onNew, onSearch, onOpenNotificationSettings, onOpenNotes, searchActive = false, notesActive = false, }: {
    cwd: string;
    recents: RecentProject[];
    busy: boolean;
    onSelectProject: (path: string) => void;
    onOpenProject?: () => void;
    onRemoveProject?: Props["onRemoveProject"];
    onNew?: () => string | void;
    onSearch?: () => void;
    onOpenNotificationSettings?: (projectPath?: string) => void;
    onOpenNotes?: () => void;
    searchActive?: boolean;
    notesActive?: boolean;
}) {
    return (<div className="flex h-9 items-center gap-0.5 border-b border-stroke px-2" data-tauri-drag-region="deep">
      <SearchableProjectPickerWithMenu cwd={cwd} recents={recents} busy={busy} className="flex-1" onSelectProject={onSelectProject} onOpenProject={onOpenProject} onRemoveProject={onRemoveProject} onOpenNotificationSettings={onOpenNotificationSettings}/>
      <div className="ml-auto flex items-center">
        {onNew ? (<IconButton label={`New tab (${MOD}T)`} onClick={onNew}>
            <Plus className="size-3.5" strokeWidth={1.75}/>
          </IconButton>) : null}
        {onSearch ? (<IconButton label={`Search (${MOD}K)`} active={searchActive} onClick={onSearch}>
            <Search className="size-3.5" strokeWidth={1.75}/>
          </IconButton>) : null}

        {onOpenNotes ? (<IconButton label="Notes" active={notesActive} onClick={onOpenNotes}>
            <StickyNote className="size-3.5" strokeWidth={1.75}/>
          </IconButton>) : null}

      </div>

    </div>);
}
function CompactProjectRail({ projectsEnabled = true, cwd, recents, busy, tabs, activeTab, tabShown, onSelectProject, onOpenProject, onRemoveProject, onTabChange, onSearch, searchActive, onOpenNotificationSettings, onOpenNotes, notesActive, onOpenCourses, coursesActive = false, onOpenSettings, onTogglePanel, onLeaveActive, titleBarAbove, }: {
    cwd: string;
    recents: RecentProject[];
    busy: boolean;
    tabs: SidebarTab[];
    activeTab: SidebarTab;
    tabShown: boolean;
    onSelectProject?: (path: string) => void;
    onOpenProject?: () => void;
    onRemoveProject?: Props["onRemoveProject"];
    onTabChange: (tab: SidebarTab) => void;
    onSearch?: () => void;
    searchActive: boolean;
    onOpenNotificationSettings?: (projectPath?: string) => void;
    onOpenNotes?: () => void;
    notesActive: boolean;
    onOpenCourses?: () => void;
    coursesActive?: boolean;
    onOpenSettings?: () => void;
    onTogglePanel?: () => void;
    onLeaveActive?: () => void;
    titleBarAbove: boolean;
    projectsEnabled?: boolean;
}) {
    const action = (active: boolean, open?: () => void) => active && onLeaveActive ? onLeaveActive : open;
    const workspaceActive = !searchActive && !notesActive && !coursesActive;
    const openWorkspaceTab = (nextTab: SidebarTab) => {
        if (!workspaceActive)
            onLeaveActive?.();
        onTabChange(nextTab);
    };
    return (<nav aria-label="Project shortcuts" data-compact-project-rail className="sidebar-glass relative flex h-full w-10 shrink-0 flex-col items-center">
      {titleBarAbove ? null : (<div className="h-10 w-full shrink-0 border-b border-stroke" data-tauri-drag-region="deep"/>)}
      <span aria-hidden data-compact-rail-divider className={`pointer-events-none absolute bottom-0 right-0 w-px bg-stroke ${titleBarAbove ? "top-0" : "top-10"}`}/>
      <div data-compact-rail-actions className="flex w-full shrink-0 flex-col items-center gap-1.5 py-1.5">
        <CompactRailAction label="Expand projects" icon={PanelLeft} onClick={onTogglePanel}/>
        {onSelectProject && projectsEnabled ? (<SearchableProjectPickerWithMenu cwd={cwd} recents={recents} busy={busy} compact className="w-full justify-center" onSelectProject={onSelectProject} onOpenProject={onOpenProject} onRemoveProject={onRemoveProject} onOpenNotificationSettings={onOpenNotificationSettings}/>) : null}
        <div role="tablist" aria-label="Workspace" aria-orientation="vertical" className="flex flex-col items-center gap-1.5">
          {(projectsEnabled ? tabs : []).map((itemId) => (<CompactRailAction key={itemId} tab label={TAB_LABELS[itemId]} icon={COMPACT_TAB_ICONS[itemId]} active={workspaceActive && tabShown && activeTab === itemId} onClick={() => openWorkspaceTab(itemId)}/>))}
        </div>
        <CompactRailAction label={`Search (${MOD}K)`} icon={Search} active={searchActive} onClick={action(searchActive, onSearch)}/>

        {onOpenCourses ? (<CompactRailAction label="Courses" icon={Mortarboard} active={coursesActive} onClick={action(coursesActive, onOpenCourses)}/>) : null}
        {onOpenNotes ? (<CompactRailAction label="Notes" icon={StickyNote} active={notesActive} onClick={action(notesActive, onOpenNotes)}/>) : null}

      </div>
      <div className="min-h-2 flex-1"/>
      <div className="flex w-full flex-col items-center gap-1 py-1.5">
        <CompactRailAction label={`Settings (${MOD},)`} icon={Settings} onClick={onOpenSettings}/>
      </div>

    </nav>);
}
function CompactRailAction({ label, icon: Icon, tab = false, active = false, dot = false, onClick, onOpenContextMenu, }: {
    label: string;
    icon: typeof PanelLeft;
    tab?: boolean;
    active?: boolean;
    dot?: boolean;
    onClick?: () => void;
    onOpenContextMenu?: (x: number, y: number) => void;
}) {
    return (<button type="button" role={tab ? "tab" : undefined} title={label} aria-label={label} aria-selected={tab ? active : undefined} aria-pressed={tab ? undefined : active} disabled={!onClick} onClick={onClick} onContextMenu={onOpenContextMenu
            ? (event) => {
                event.preventDefault();
                event.stopPropagation();
                event.currentTarget.focus();
                onOpenContextMenu(event.clientX, event.clientY);
            }
            : undefined} onKeyDown={onOpenContextMenu
            ? (event) => {
                if (event.key !== "ContextMenu" &&
                    !(event.shiftKey && event.key === "F10"))
                    return;
                event.preventDefault();
                event.stopPropagation();
                event.currentTarget.focus();
                const rect = event.currentTarget.getBoundingClientRect();
                onOpenContextMenu(rect.right, rect.top);
            }
            : undefined} className={`relative grid size-8 shrink-0 place-items-center rounded-md active:scale-[0.97] ${active
            ? "bg-selection text-content"
            : "text-content/50 hover:bg-content/10 hover:text-content"} disabled:cursor-default disabled:opacity-35`}>
      <Icon className={`size-4 ${dot ? "compact-rail-icon-with-dot" : ""}`} strokeWidth={1.75}/>
      {dot ? (<span aria-hidden className="absolute right-1.5 top-1.5 size-1.5 rounded-full bg-accent"/>) : null}
    </button>);
}
function WorkspaceTitleActions({ onNew, }: {
    onNew?: () => void;
}) {
    if (!onNew)
        return null;
    return (<div className="flex shrink-0 items-center gap-0.5" data-tauri-drag-region="false">

      {onNew ? (<IconButton label={`New session (${MOD}T)`} onClick={onNew}>
          <Plus className="size-3.5" strokeWidth={1.75}/>
        </IconButton>) : null}
    </div>);
}
function SessionGroupRow({ name, sessions, expanded, busy, done, needsApproval, icon, onToggle, }: {
    name: string;
    sessions: SessionSummary[];
    expanded: boolean;
    busy: boolean;
    done: boolean;
    needsApproval: boolean;
    icon: ReactNode;
    onToggle: () => void;
}) {
    const count = sessions.length;
    return (<button type="button" title={name} aria-expanded={expanded} data-tauri-drag-region="false" onClick={onToggle} className={`group relative flex w-full touch-none items-center gap-1.5 px-2 h-8 text-left ${expanded
            ? "rounded-md text-content hover:bg-content/10"
            : "text-content/80 hover:bg-content/10 hover:text-content"}`}>
      <span className="relative grid size-4 shrink-0 place-items-center text-content/50">
        {expanded ? (<>
            <span className="group-hover:hidden group-focus-visible:hidden">
              {icon}
            </span>
            <ChevronDown className="hidden size-3.5 text-content group-hover:block group-focus-visible:block" strokeWidth={1.75}/>
          </>) : (<>
            <span className="group-hover:hidden group-focus-visible:hidden">
              {icon}
            </span>
            <ChevronRight className="hidden size-3.5 group-hover:block group-focus-visible:block text-content" strokeWidth={1.75}/>
          </>)}
      </span>
      <span className="relative min-w-0 flex-1 truncate text-[13px] font-semibold leading-snug text-content">
        {name}
      </span>
      <span className="relative flex shrink-0 items-center gap-1 text-[11px] tabular-nums text-content/45">
        {!expanded && needsApproval ? (<CircleAlert className="size-3 text-amber-400" strokeWidth={1.75}/>) : !expanded && busy ? (<ActivitySpinner className="inline-block w-3 select-none text-center text-[11px] leading-none text-accent"/>) : !expanded && done ? (<Check className="size-3 text-emerald-400" strokeWidth={2.25}/>) : null}
        <span>{count}</span>
      </span>
    </button>);
}
const SESSION_PREFETCH_DELAY_MS = 120;
/** Rows created this recently slide in; older ones are just being listed. */
const SESSION_INSERT_WINDOW_MS = 15000;
type SessionInsertMotion = {
    cwd: string;
    seen: Set<string>;
};
function SessionListItem({ session, cwd, motion, children, }: {
    session: SessionSummary;
    cwd: string;
    motion: RefObject<SessionInsertMotion>;
    children: ReactNode;
}) {
    const ref = useRef<HTMLLIElement>(null);
    // Decided once per row: effects can replay (StrictMode, reordering), and a
    // row that already slid in must not do it again.
    const played = useRef(false);
    useLayoutEffect(() => {
        if (played.current)
            return;
        played.current = true;
        const state = motion.current;
        const fresh = state.cwd === cwd &&
            !state.seen.has(session.id) &&
            (session.createdAt === 0 ||
                Date.now() - session.createdAt < SESSION_INSERT_WINDOW_MS);
        state.seen.add(session.id);
        const el = ref.current;
        const content = el?.firstElementChild;
        if (!fresh ||
            !el ||
            !(content instanceof HTMLElement) ||
            typeof el.animate !== "function" ||
            window.matchMedia?.("(prefers-reduced-motion: reduce)").matches)
            return;
        // The card takes its place at once; everything below starts where it was
        // and slides down, uncovering it as it fades in.
        const offset = el.offsetHeight +
            (parseFloat(getComputedStyle(el.parentElement ?? el).rowGap) || 0);
        const timing = {
            duration: 380,
            easing: "cubic-bezier(0.32, 0.72, 0, 1)",
        };
        for (let node: Element | null = el; node && !node.hasAttribute("data-session-list"); node = node.parentElement) {
            for (let below = node.nextElementSibling; below; below = below.nextElementSibling) {
                if (!(below instanceof HTMLElement))
                    continue;
                below.animate([{ transform: `translateY(${-offset}px)` }, { transform: "none" }],
                // Stack with a push already in flight instead of restarting it.
                { ...timing, composite: "add" });
            }
        }
        content.animate([{ opacity: 0 }, { opacity: 1 }], {
            duration: 220,
            easing: "ease-out",
        });
    }, []);
    return <li ref={ref}>{children}</li>;
}
const SessionCard = memo(function SessionCard({ session, isActive, isSelected, busy, done, needsApproval, compact = false, now, onSelect, onPrefetch, onPlaceOnPane, onContextMenu, onArchive, onRename, onDelete, }: {
    session: SessionSummary;
    isActive: boolean;
    isSelected: boolean;
    busy: boolean;
    done: boolean;
    needsApproval: boolean;
    compact?: boolean;
    now: number;
    onSelect: (sessionId: string, event: {
        shiftKey: boolean;
        ctrlKey: boolean;
        metaKey: boolean;
    }) => void;
    onPrefetch?: (sessionId: string) => void;
    onPlaceOnPane?: (sessionId: string, targetId: string, edge: PaneEdge) => void;
    onContextMenu?: (sessionId: string, e: ReactMouseEvent<HTMLDivElement>) => void;
    onArchive?: (sessionId: string, archived: boolean) => void;
    onRename?: (sessionId: string) => void;
    onDelete?: (sessionId: string) => void;
}) {
    const skipClickUntil = useRef(0);
    const prefetchTimer = useRef<number | null>(null);
    const [dragging, setDragging] = useState(false);
    const draft = !!session.draft;
    const title = sessionDisplayTitle(session.title, session.harness);
    const time = formatRelative(session.updatedAt, now);
    const model = compact
        ? null
        : resolveModel(session.harness, session.model).name;
    const statusClass = needsApproval
        ? "text-amber-400"
        : busy
            ? "text-accent"
            : done
                ? "text-emerald-400"
                : draft
                    ? "text-content/55"
                    : "text-content/45";
    const status = (<span className={`flex shrink-0 items-center gap-1 text-[11px] tabular-nums ${statusClass}`}>
      {needsApproval ? (<>
          <CircleAlert className="size-3" strokeWidth={1.75}/>
          <span>{"Need approval"}</span>
        </>) : busy ? (<>
          <ActivitySpinner className="inline-block w-3 select-none text-center text-[11px] leading-none text-accent"/>
          <span>Working...</span>
        </>) : done ? (<>
          <Check className="size-3" strokeWidth={2.25}/>
          <span>Done</span>
        </>) : draft ? (<>
          <CircleDashed className="size-3" strokeWidth={1.75}/>
          <span>Draft</span>
        </>) : (<span>{time}</span>)}
    </span>);
    const onKeyDown = (e: ReactKeyboardEvent<HTMLDivElement>) => {
        if (e.target !== e.currentTarget)
            return;
        if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            onSelect(session.id, e);
            return;
        }
        if (e.key === "F2" && onRename) {
            e.preventDefault();
            onRename(session.id);
            return;
        }
        if ((e.key === "Delete" || e.key === "Backspace") && onDelete) {
            e.preventDefault();
            onDelete(session.id);
        }
    };
    const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
        if (event.button !== 0)
            return;
        // Warm the transcript during the press. Opening stays on click so a
        // drag-to-pane gesture does not switch conversations.
        if (prefetchTimer.current != null) {
            window.clearTimeout(prefetchTimer.current);
            prefetchTimer.current = null;
        }
        onPrefetch?.(session.id);
        if (!onPlaceOnPane)
            return;
        const handle = event.currentTarget;
        const pointerId = event.pointerId;
        const startX = event.clientX;
        const startY = event.clientY;
        let active = false;
        let lastX = startX;
        let lastY = startY;
        handle.setPointerCapture(pointerId);
        const restoreSelection = suppressTextSelection();
        const onMove = (ev: PointerEvent) => {
            lastX = ev.clientX;
            lastY = ev.clientY;
            if (!active) {
                if (Math.hypot(ev.clientX - startX, ev.clientY - startY) < 5)
                    return;
                active = true;
                setDragging(true);
                setExternalPaneDrop({
                    fromId: session.id,
                    overId: null,
                    edge: "left",
                });
            }
            const over = paneDropFromPoint(ev.clientX, ev.clientY);
            if (!over || over.id === session.id) {
                setExternalPaneDrop({
                    fromId: session.id,
                    overId: over?.id === session.id ? session.id : null,
                    edge: over?.edge ?? "left",
                });
                return;
            }
            setExternalPaneDrop({
                fromId: session.id,
                overId: over.id,
                edge: over.edge,
            });
        };
        const onUp = () => finish(true);
        const onKey = (ev: KeyboardEvent) => {
            if (ev.key !== "Escape")
                return;
            ev.preventDefault();
            finish(false);
        };
        function finish(commit: boolean) {
            window.removeEventListener("pointermove", onMove);
            window.removeEventListener("pointerup", onUp);
            window.removeEventListener("pointercancel", onUp);
            window.removeEventListener("keydown", onKey);
            restoreSelection();
            setDragging(false);
            setExternalPaneDrop(null);
            try {
                handle.releasePointerCapture(pointerId);
            }
            catch {
                /* already released */
            }
            if (!active)
                return;
            skipClickUntil.current = performance.now() + 400;
            if (!commit)
                return;
            const over = paneDropFromPoint(lastX, lastY);
            if (over && over.id !== session.id) {
                onPlaceOnPane?.(session.id, over.id, over.edge);
            }
        }
        window.addEventListener("pointermove", onMove);
        window.addEventListener("pointerup", onUp);
        window.addEventListener("pointercancel", onUp);
        window.addEventListener("keydown", onKey);
    };
    useEffect(() => () => {
        if (prefetchTimer.current != null) {
            window.clearTimeout(prefetchTimer.current);
            prefetchTimer.current = null;
        }
    }, [onPrefetch, session.id]);
    const schedulePrefetch = () => {
        if (!onPrefetch || prefetchTimer.current != null)
            return;
        prefetchTimer.current = window.setTimeout(() => {
            prefetchTimer.current = null;
            onPrefetch(session.id);
        }, SESSION_PREFETCH_DELAY_MS);
    };
    const cancelScheduledPrefetch = () => {
        if (prefetchTimer.current == null)
            return;
        window.clearTimeout(prefetchTimer.current);
        prefetchTimer.current = null;
    };
    const archiveLabel = session.archived ? "Unarchive" : "Archive";
    const cardPaddingY = compact ? "py-1.5" : "py-2";
    return (<div className="group relative">
      <div title={title} data-session-card={session.id} data-session-selected={isSelected ? "true" : undefined} data-tauri-drag-region="false" onPointerDown={onPointerDown} onPointerEnter={schedulePrefetch} onPointerLeave={cancelScheduledPrefetch} onClick={(event) => {
            if (performance.now() < skipClickUntil.current)
                return;
            onSelect(session.id, event);
        }} onContextMenu={onContextMenu
            ? (event) => onContextMenu(session.id, event)
            : undefined} className={`relative border flex w-full cursor-default select-none touch-none flex-col rounded-md px-2.5 text-left ${cardPaddingY} ${dragging ? "opacity-40" : ""} ${isSelected
                ? `bg-accent/15 text-content ${draft ? "border-content/30 border-dashed" : "border-transparent"}`
                : needsApproval
                    ? "bg-content/20 text-content border-content/30 border-dashed"
                    : isActive
                        ? `bg-selection text-content ${draft ? "border-content/30 border-dashed" : "border-transparent"}`
                        : draft
                            ? "border-content/25 border-dashed text-content/80 hover:bg-content/5 hover:text-content"
                            : `text-content/80 hover:text-content border-transparent ${"hover:bg-content/5"}`}`}>
        <div role="button" tabIndex={0} aria-current={isActive ? "true" : undefined} aria-pressed={isSelected} data-session-select={session.id} onKeyDown={onKeyDown} onMouseDown={(event) => {
            if (event.button !== 0)
                return;
            // Shift-click can trigger :focus-visible. Mouse selection should
            // only highlight the card; Tab can still focus this button.
            event.preventDefault();
            // Clear prior focus too, so shortcuts cannot target another card.
            const focused = event.currentTarget.ownerDocument.activeElement;
            if (focused instanceof HTMLElement)
                focused.blur();
        }} className="rounded-sm outline-none focus-visible:ring-1 focus-visible:ring-accent/50">
          {compact ? null : (<span className="relative flex items-center gap-2">
              <span className="flex min-w-0 flex-1 items-center gap-1.5">
                <HarnessIcon harness={session.harness} className="size-3.5 shrink-0"/>
                <span className="min-w-0 truncate text-[11px] text-content/50">
                  {model}
                </span>
              </span>
              <span className="flex shrink-0 items-center gap-1.5">

                {status}
              </span>
            </span>)}
          <span className={`relative flex min-w-0 items-center gap-1.5 ${compact ? "" : "mt-1"}`}>
            {session.pinned ? (<Pin className="size-3 shrink-0 text-content/45" strokeWidth={1.75}/>) : null}
            <ParticleText text={title} className="line-clamp-1 text-[13px] font-semibold leading-snug text-content"/>
            {compact ? (<span className="flex shrink-0 items-center gap-1.5">

                {status}
              </span>) : null}
          </span>
        </div>
        {null}
        <span className="relative mt-1 flex items-center gap-2">
          {(<span className="min-w-0 flex-1"/>)}
          <span className="relative flex shrink-0 items-center gap-px">
            {onArchive ? (<button type="button" data-no-drag data-tauri-drag-region="false" title={archiveLabel} aria-label={`${archiveLabel} ${title}`} onPointerDown={(event) => event.stopPropagation()} onClick={(event) => {
                event.stopPropagation();
                onArchive(session.id, !session.archived);
            }} className="pointer-events-none grid size-5 place-items-center rounded-md text-content/50 opacity-0 hover:bg-content/10 hover:text-content group-focus-within:pointer-events-auto group-focus-within:opacity-100 group-hover:pointer-events-auto group-hover:opacity-100">
                <Archive className="size-3 shrink-0" strokeWidth={1.75}/>
              </button>) : null}



          </span>
        </span>
      </div>

    </div>);
});
function SessionRenameRow({ session, isActive, needsApproval, onCommit, onCancel, }: {
    session: SessionSummary;
    isActive: boolean;
    needsApproval: boolean;
    onCommit: (title: string) => void;
    onCancel: () => void;
}) {
    const inputRef = useRef<HTMLInputElement>(null);
    const finished = useRef(false);
    const [value, setValue] = useState(() => sessionDisplayTitle(session.title, session.harness));
    useEffect(() => {
        const input = inputRef.current;
        if (!input)
            return;
        input.focus();
        input.select();
    }, []);
    const finish = (success: boolean) => {
        if (finished.current)
            return;
        if (success) {
            const trimmed = value.trim();
            if (!trimmed) {
                onCancel();
                return;
            }
            finished.current = true;
            onCommit(trimmed);
            return;
        }
        finished.current = true;
        onCancel();
    };
    const onKeyDown = (e: ReactKeyboardEvent<HTMLInputElement>) => {
        if (e.key === "Enter") {
            e.preventDefault();
            finish(true);
            return;
        }
        if (e.key === "Escape") {
            e.preventDefault();
            finish(false);
        }
    };
    return (<div className={`flex w-full flex-col rounded-md px-2.5 py-2 ${needsApproval
            ? "bg-amber-400/10 text-content"
            : isActive
                ? "bg-selection text-content"
                : "text-content/80"}`}>
      <input ref={inputRef} value={value} onChange={(e) => setValue(e.target.value)} onBlur={() => finish(true)} onKeyDown={onKeyDown} className="w-full rounded bg-content/10 px-2 py-1 text-[13px] font-semibold leading-snug text-content outline-none ring-1 ring-accent/40"/>
    </div>);
}
function formatRelative(value: number, now: number): string {
    if (!Number.isFinite(value) || value <= 0)
        return "";
    const seconds = Math.max(0, Math.round((now - value) / 1000));
    if (seconds < 60)
        return "now";
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60)
        return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
        const rest = minutes % 60;
        return rest ? `${hours}h ${rest}m` : `${hours}h`;
    }
    const days = Math.floor(hours / 24);
    if (days < 7)
        return `${days}d`;
    try {
        return new Intl.DateTimeFormat("en", {
            month: "short",
            day: "numeric",
        }).format(new Date(value));
    }
    catch {
        return "";
    }
}
