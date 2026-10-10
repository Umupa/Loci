import { CheckCircle, ChevronDown, ChevronLeft, ChevronRight, ExcalidrawIcon, PanelLeft, Settings, SidebarLeft, StickyNote, X, } from "../../shared/ui/icons";
import { FileTypeIcon } from "../../shared/ui/FileTypeIcon";
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent, type ReactNode, } from "react";
import { basename } from "../../platform/tauri/fs";
import { looksLikeProject } from "../../features/projects/model/recents";
import type { HarnessId } from "../../features/sessions/model/session";
import { CwdPicker } from "../../features/projects/ui/CwdPicker";
import { useLockOverscroll } from "../../shared/hooks/useLockOverscroll";
import { useAnimatedReorder, type ReorderExternalDrop, } from "../../shared/hooks/useAnimatedReorder";
import { useTabCloseMotion } from "../../features/workspace/hooks/useTabCloseMotion";
import { TabWidthMotion } from "./ClosingTab";
import { ApprovalDot, TabGlyph, TabHoverCard } from "./TabParts";
import { useGlide } from "../../shared/hooks/useGlide";
import { foldFamilies } from "../../features/workspace/model/tabFamily";
import { FAMILY_CHIP_WIDTH, FAMILY_CONNECTOR_WIDTH, chooseTitled, tabStripLayout } from "../../features/workspace/model/tabStripLayout";
import { HarnessIcon } from "../../features/sessions/ui/HarnessIcon";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { ActivitySpinner } from "../../features/sessions/ui/ActivitySpinner";
import { TabLabel } from "../../shared/ui/TabLabel";
import { WindowControls } from "./WindowControls";
import { IS_MAC, IS_WIN, MOD, SHIFT } from "../../platform/tauri/platform";
import type { RecentProject } from "../../features/projects/model/recents";
import { ContextMenu, type ContextMenuItem } from "../../shared/ui/ContextMenu";
import { paneDropFromPoint, setExternalPaneDrop, useExternalTitleTabDrop, } from "../../features/workspace/model/paneDrop";
import type { PaneEdge } from "../../features/workspace/model/layout";
export type { Tab, TabStatus } from "../../features/workspace/model/tabSummary";
import type { Tab } from "../../features/workspace/model/tabSummary";
type Props = {
    tabs: Tab[];
    activeId: string;
    cwd: string;
    projectRailOpen?: boolean;
    sessionSidebarOpen?: boolean;
    compactRail?: boolean;
    canGoBack?: boolean;
    canGoForward?: boolean;
    onGoBack?: () => void;
    onGoForward?: () => void;
    onToggleSidebar: () => void;
    onToggleSessionSidebar?: () => void;
    onSelect: (id: string) => void;
    onOpenSettings?: () => void;
    onOpenNotes?: () => void;
    onClose: (id: string) => void;
    onCloseMany: (ids: string[], fallbackId: string) => void;
    onArchiveTab?: (id: string) => void;
    onDeleteTab?: (id: string) => void;
    onReorder: (ids: string[], movedId?: string) => void;
    onPin?: (id: string, pinned: boolean) => void;
    /** Tab ids, most recently used first: in a crowded strip these keep their titles. */
    recent?: readonly string[];
    /** How many tabs "Close Idle Tabs" would close, and the action itself. */
    idleTabCount?: number;
    onCloseIdle?: () => void;
    /** Open the tab switcher, which reaches every open tab. */
    onOpenSwitcher?: () => void;
    onPlaceOnPane?: (tabId: string, targetId: string, edge: PaneEdge) => void;
    recents?: RecentProject[];
    onSelectProject?: (path: string) => void;
};
function sessionMeta(tab: Tab): string {
    if (tab.more.length === 1)
        return tab.more[0];
    if (tab.sessionCount > 1)
        return `${tab.sessionCount} sessions`;
    return "";
}
export function tabCopy(tab: Tab): {
    headline: string;
    meta: string;
    tooltip: string;
} {
    const project = tab.project.trim() || "~";
    const conversation = tab.title.trim();
    const meta = sessionMeta(tab);
    const tooltipParts = [project];
    if (conversation)
        tooltipParts.push(conversation);
    tooltipParts.push(...tab.more);
    return { headline: conversation || "New session", meta, tooltip: tooltipParts.join(" · ") };
}
/** Which tab-strip edges still have overflow to scroll toward. */
export function tabStripOverflow(scrollLeft: number, clientWidth: number, scrollWidth: number): {
    left: boolean;
    right: boolean;
} {
    const maxScroll = scrollWidth - clientWidth;
    if (maxScroll <= 1)
        return { left: false, right: false };
    return {
        left: scrollLeft > 1,
        right: scrollLeft < maxScroll - 1,
    };
}
export function titleTabClosable(tab: Tab, tabCount: number): boolean {
    return tabCount > 1 || !tab.blank;
}
export type TitleTabContextAction = "others" | "right" | "left";
/** Tab ids affected by a context-menu action relative to its clicked tab. */
export function titleTabContextCloseIds(tabs: readonly Tab[], targetId: string, action: TitleTabContextAction): string[] {
    const targetIndex = tabs.findIndex((tab) => tab.id === targetId);
    if (targetIndex < 0)
        return [];
    // Pinned tabs are the ones the user chose to keep, so bulk closes pass them by.
    if (action === "left") {
        return tabs.slice(0, targetIndex).filter((tab) => !tab.pinned).map((tab) => tab.id);
    }
    if (action === "right") {
        return tabs.slice(targetIndex + 1).filter((tab) => !tab.pinned).map((tab) => tab.id);
    }
    return tabs.filter((tab) => tab.id !== targetId && !tab.pinned).map((tab) => tab.id);
}
function TabHarnesses({ harnesses, busyHarnesses, doneHarnesses, dimmed, approval, }: {
    harnesses: HarnessId[];
    busyHarnesses: HarnessId[];
    doneHarnesses: HarnessId[];
    dimmed: boolean;
    approval: boolean;
}) {
    const shown = harnesses.slice(0, 3);
    const extra = harnesses.length - shown.length;
    const opacity = dimmed ? "opacity-55" : "opacity-100";
    const busy = new Set(busyHarnesses);
    const done = new Set(doneHarnesses);
    return (<span className="flex shrink-0 items-center">
      {shown.map((harness, i) => {
            const status = busy.has(harness)
                ? "busy"
                : done.has(harness)
                    ? "done"
                    : "idle";
            return (<span key={harness} data-harness-status={status} className={`relative grid size-3.5 shrink-0 place-items-center ${i > 0 ? "-ml-0.5" : ""}`}>
            {/* Only the icon dims: the dot that asks for attention stays bright. */}
            <span className={`grid size-full place-items-center ${status === "done" ? "opacity-100" : opacity}`}>
              {status === "busy" ? (<ActivitySpinner className="inline-block w-3.5 select-none text-center text-[11px] leading-none text-accent"/>) : status === "done" ? (<CheckCircle className="size-3.5 shrink-0 text-teal-400" strokeWidth={2}/>) : (<HarnessIcon harness={harness} className="size-3.5 shrink-0"/>)}
            </span>
            {approval && i === 0 ? <ApprovalDot /> : null}
          </span>);
        })}
      {extra > 0 ? (<span className={`pl-0.5 text-[10px] leading-none ${dimmed ? "text-content/50" : "text-content"}`}>
          +{extra}
        </span>) : null}
    </span>);
}
type SortableApi = ReturnType<typeof useAnimatedReorder>;
/** What a parent shows of the tabs it started: how many, how urgent, and a way to fold them. */
function FamilyChip({ tab, expanded, onToggle, corner, }: {
    tab: Tab;
    expanded: boolean;
    onToggle: () => void;
    /** On an icon tab it is a small badge on the corner rather than a chip. */
    corner?: boolean;
}) {
    const status = tab.descendantStatus ?? "idle";
    const tone = status === "approval" ? "bg-amber-400/20 text-amber-400" : status === "done" ? "bg-teal-400/20 text-teal-400" : status === "busy" ? "bg-accent/20 text-accent" : "bg-content/10 text-content/60";
    const label = `${expanded ? "Hide" : "Show"} ${tab.descendantCount} started ${tab.descendantCount === 1 ? "tab" : "tabs"}`;
    return (<button type="button" data-family-toggle aria-expanded={expanded} title={label} aria-label={label} data-no-drag data-tauri-drag-region="false" onPointerDown={(event) => event.stopPropagation()} onClick={(event) => {
            event.stopPropagation();
            onToggle();
        }} className={`absolute z-10 flex h-4 items-center gap-px rounded-full px-1 text-[10px] font-medium leading-none tabular-nums ${tone} ${corner ? "-bottom-1 -right-1 h-[15px] min-w-[15px] justify-center ring-[1.5px] ring-background-base" : "right-7 top-1/2 -translate-y-1/2"}`}>
      {corner ? null : <ChevronRight className={`size-2.5 transition-transform ${expanded ? "rotate-90" : ""}`} strokeWidth={2}/>}
      {tab.descendantCount}
    </button>);
}
function TitleTabItem({ tab, active, closable, canDrag, variant, expanded = false, onToggleFamily, sortable, onSelect, onClose, onContextMenu, onHover, itemRef, }: {
    tab: Tab;
    /** Whether this tab's started tabs are showing in the strip. */
    expanded?: boolean;
    onToggleFamily?: () => void;
    active: boolean;
    closable: boolean;
    canDrag: boolean;
    /** "icon" shows only the tab's glyph: a pinned tab, or an idle one in a crowded strip. */
    variant: "full" | "icon";
    sortable: SortableApi;
    onSelect: (id: string) => void;
    onClose: (id: string) => void;
    onContextMenu: (id: string, event: ReactMouseEvent<HTMLDivElement>) => void;
    onHover?: (id: string, element: HTMLElement | null) => void;
    itemRef?: (el: HTMLDivElement | null) => void;
}) {
    const { headline, meta, tooltip } = tabCopy(tab);
    const accessibleLabel = (tab.doneHarnesses?.length ?? 0) > 0
        ? `${tooltip} · Response complete`
        : tab.status === "approval"
            ? `${tooltip} · Needs your approval`
            : tooltip;
    return (<div ref={(el) => {
            sortable.setItemRef(tab.id, el);
            itemRef?.(el);
        }} className="reorder-item tab-motion group @container relative flex h-full cursor-default touch-none items-center self-stretch min-w-0 w-full" data-tauri-drag-region="false" onPointerEnter={(event) => onHover?.(tab.id, event.currentTarget)} onPointerLeave={() => onHover?.(tab.id, null)} onContextMenu={(event) => {
            event.preventDefault();
            event.stopPropagation();
            onContextMenu(tab.id, event);
        }} onMouseDownCapture={(event) => {
            if (event.button === 1)
                event.preventDefault();
        }} onAuxClick={(event) => {
            if (event.button !== 1 || !closable)
                return;
            event.preventDefault();
            event.stopPropagation();
            onClose(tab.id);
        }} onPointerDown={(event) => {
            if (event.button !== 0)
                return;
            if ((event.target as HTMLElement | null)?.closest("[data-no-drag]")) {
                return;
            }
            if (canDrag)
                sortable.onItemPointerDown(tab.id, event);
        }}>
      {/* One element for both states, so a tab that gains or loses its title
          only changes width: the icon stays where it is and the title fades. */}
      <div className="relative h-7.5 w-full min-w-0 self-center">
        <button type="button" aria-label={accessibleLabel} aria-current={active ? "true" : undefined} data-tab-variant={variant} data-tauri-drag-region="false" onClick={() => {
            if (sortable.consumeClick())
                return;
            onSelect(tab.id);
        }} className={`tab-surface relative flex h-full w-full min-w-0 cursor-default items-center gap-1.5 overflow-hidden rounded-md pl-[11px] text-left ${variant === "icon" ? "pr-[11px]" : tab.descendantCount ? "pr-14" : closable ? "pr-7" : "pr-2.5"} ${active
            ? "text-content"
            : tab.pinned
                ? "bg-content/[0.06] text-content/70 hover:bg-content/10 hover:text-content"
                : "text-content/50 hover:bg-content/5 hover:text-content"}`}>
          {variant === "icon" ? (<TabGlyph tab={tab} dimmed={!active}/>) : (<>
            {tab.paneKind === "canvas" ? <ExcalidrawIcon className="size-3.5 shrink-0"/> : null}
            {tab.paneKind === "file" ? <span className="shrink-0"><FileTypeIcon name={tab.title} isDir={false} size={14}/></span> : null}
            {tab.paneKind === "document" ? <StickyNote className="size-3.5 shrink-0" strokeWidth={1.75}/> : null}
            {tab.harnesses.length > 0 ? (<TabHarnesses harnesses={tab.harnesses} busyHarnesses={tab.busyHarnesses} doneHarnesses={tab.doneHarnesses ?? []} dimmed={!active} approval={tab.status === "approval"}/>) : null}
          </>)}
          {/* Keep two-line tabs compact while leaving room for descenders. */}
          <span className={`tab-title flex min-w-0 flex-1 flex-col justify-center ${variant === "icon" ? "opacity-0" : ""}`}>
            <span className="flex min-w-0 items-center gap-1">
              <TabLabel className={`leading-tight  ${meta
            ? "text-[13px] @min-[11rem]:text-[10px] @min-[11rem]:font-medium"
            : "text-[13px]"}`}>
                {headline}
              </TabLabel>

            </span>
            {meta ? (<TabLabel className="hidden text-[10px] leading-tight text-content/45 @min-[11rem]:block">
                {meta}
              </TabLabel>) : null}
          </span>
        </button>
        {tab.descendantCount && onToggleFamily ? (<FamilyChip tab={tab} expanded={expanded} onToggle={onToggleFamily} corner={variant === "icon"}/>) : null}
        {closable && variant === "full" ? (<button type="button" title="Close Tab" aria-label={`Close ${headline}`} data-no-drag data-tauri-drag-region="false" onPointerDown={(event) => event.stopPropagation()} onClick={(e) => {
                e.stopPropagation();
                onClose(tab.id);
            }} className="absolute right-1 top-1/2 grid size-5 -translate-y-1/2 place-items-center rounded text-content/50 opacity-0 hover:bg-content/10 hover:text-content group-hover:opacity-100">
            <X className="size-3" strokeWidth={1.75}/>
          </button>) : null}
      </div>
    </div>);
}
/** Opens the tab switcher; wears a dot when a tab out of sight wants the user. */
function TabSwitcherButton({ count, attention, onClick, }: {
    count: number;
    attention: "approval" | "done" | null;
    onClick: () => void;
}) {
    return (<IconButton label={`Switch tabs (${MOD}P)`} onClick={onClick}>
      <span className="relative flex items-center gap-1 px-0.5" data-tab-switcher>
        <span className="text-[11px] font-medium leading-none tabular-nums">{count}</span>
        <ChevronDown className="size-3" strokeWidth={1.75}/>
        {attention ? (<span aria-hidden className={`absolute -right-0.5 -top-1 size-[7px] rounded-full ring-[1.5px] ring-background-base ${attention === "approval" ? "bg-amber-400" : "bg-teal-400"}`}/>) : null}
      </span>
    </IconButton>);
}
function TabStripChevron({ side, onClick, }: {
    side: "left" | "right";
    onClick: () => void;
}) {
    const label = side === "left" ? "Scroll tabs left" : "Scroll tabs right";
    const Icon = side === "left" ? ChevronLeft : ChevronRight;
    return (<button type="button" title={label} aria-label={label} data-tauri-drag-region="false" onPointerDown={(event) => event.stopPropagation()} onClick={onClick} className={`absolute top-1/2 z-40 grid size-6.5 -translate-y-1/2 place-items-center rounded-md bg-content/10 backdrop-blur-xl text-content/70 hover:bg-content/15 hover:text-content ${side === "left" ? "left-1" : "right-1"}`}>
      <Icon className="size-3.5" strokeWidth={1.75}/>
    </button>);
}
export function IconButton({ label, active, accent, disabled, onClick, onOpenContextMenu, children, }: {
    label: string;
    active?: boolean;
    accent?: boolean;
    disabled?: boolean;
    onClick?: () => void;
    onOpenContextMenu?: (x: number, y: number) => void;
    children: ReactNode;
}) {
    return (<button type="button" title={label} aria-label={label} aria-pressed={active || accent} aria-disabled={disabled} data-tauri-drag-region="false" onClick={() => {
            if (disabled)
                return;
            onClick?.();
        }} onContextMenu={onOpenContextMenu
            ? (event) => {
                event.preventDefault();
                event.stopPropagation();
                if (disabled)
                    return;
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
                if (disabled)
                    return;
                event.currentTarget.focus();
                const rect = event.currentTarget.getBoundingClientRect();
                onOpenContextMenu(rect.left, rect.bottom);
            }
            : undefined} className={`grid size-6.5 place-items-center rounded-md ${disabled
            ? "text-content/25"
            : accent
                ? "text-accent hover:bg-content/10"
                : active
                    ? "text-content hover:bg-content/10"
                    : "text-content/50 hover:bg-content/10 hover:text-content"}`}>
      {children}
    </button>);
}
export function DevModeLabel() {
    if (!import.meta.env.DEV)
        return null;
    return (<span title="Development build" className="mr-1 min-w-0 truncate rounded-md bg-skill/15 px-1.5 py-0.5 text-[10px] font-medium tracking-wide text-skill">
      Development
    </span>);
}
/** Flex spacer that keeps the Development badge next to the visit arrows. */
export function DevModeSlot() {
    return (<div className="flex min-w-0 flex-1 items-center justify-end">
      <DevModeLabel />
    </div>);
}
export function TabVisitNav({ canGoBack = false, canGoForward = false, onGoBack, onGoForward, onTogglePanel, panelActive = false, panelLabel = "Toggle Projects", }: {
    canGoBack?: boolean;
    canGoForward?: boolean;
    onGoBack?: () => void;
    onGoForward?: () => void;
    onTogglePanel?: () => void;
    panelActive?: boolean;
    panelLabel?: string;
}) {
    return (<div className="flex shrink-0 items-center">
      <IconButton label={`Back (${MOD}[)`} disabled={!canGoBack} onClick={onGoBack}>
        <ChevronLeft className="size-3.5" strokeWidth={1.75}/>
      </IconButton>
      <IconButton label={`Forward (${MOD}])`} disabled={!canGoForward} onClick={onGoForward}>
        <ChevronRight className="size-3.5" strokeWidth={1.75}/>
      </IconButton>
      {onTogglePanel ? (<IconButton label={panelLabel} active={panelActive} onClick={onTogglePanel}>
          <PanelLeft className="size-3.5" strokeWidth={1.75}/>
        </IconButton>) : null}
    </div>);
}
/** Back + rail toggle for overlay surfaces when the project rail is closed. */
export function OverlayNav({ onBack, onToggleSidebar, }: {
    onBack?: () => void;
    onToggleSidebar?: () => void;
}) {
    if (!onBack && !onToggleSidebar)
        return null;
    return (<div className="flex shrink-0 items-center px-1.5">
      {onBack ? (<IconButton label={`Back (${MOD}[)`} onClick={onBack}>
          <ChevronLeft className="size-3.5" strokeWidth={1.75}/>
        </IconButton>) : null}
      {onToggleSidebar ? (<IconButton label={`Toggle Sidebar (${MOD}B)`} onClick={onToggleSidebar}>
          <PanelLeft className="size-3.5" strokeWidth={1.75}/>
        </IconButton>) : null}
    </div>);
}
function TitleBarComponent({ tabs, activeId, cwd, projectRailOpen = true, sessionSidebarOpen = true, compactRail = false, canGoBack = false, canGoForward = false, onGoBack, onGoForward, onToggleSidebar, onToggleSessionSidebar, onSelect, onOpenSettings, onOpenNotes, onClose, onCloseMany, onArchiveTab, onDeleteTab, onReorder, onPin, recent = [], idleTabCount = 0, onCloseIdle, onOpenSwitcher, onPlaceOnPane, recents = [], onSelectProject, }: Props) {
    // A parent can fold away the tabs it started; the strip lays out what is left.
    const [unfolded, setUnfolded] = useState<ReadonlySet<string>>(() => new Set());
    const toggleFamily = useCallback((id: string) => setUnfolded((current) => {
        const next = new Set(current);
        if (next.has(id))
            next.delete(id);
        else
            next.add(id);
        return next;
    }), []);
    const folded = useMemo(() => foldFamilies(tabs, unfolded, activeId), [tabs, unfolded, activeId]);
    const stripTabs = useMemo(() => folded.map((entry) => entry.tab), [folded]);
    const depthOf = useMemo(() => new Map(folded.map((entry) => [entry.tab.id, entry.depth])), [folded]);
    const tabIds = stripTabs.map((tab) => tab.id);
    const { displayed, setTabNode, finishMotion } = useTabCloseMotion(stripTabs);
    const externalTabDrop = useMemo<ReorderExternalDrop<string> | undefined>(() => onPlaceOnPane
        ? {
            onMove: (tabId, event) => {
                if (tabId === activeId) {
                    setExternalPaneDrop(null);
                    return false;
                }
                const over = paneDropFromPoint(event.clientX, event.clientY);
                setExternalPaneDrop({
                    fromId: tabId,
                    overId: over?.id ?? null,
                    edge: over?.edge ?? "left",
                });
                return over != null;
            },
            onDrop: (tabId, event) => {
                if (tabId === activeId)
                    return false;
                const over = paneDropFromPoint(event.clientX, event.clientY);
                if (!over)
                    return false;
                onPlaceOnPane(tabId, over.id, over.edge);
                return true;
            },
            onEnd: () => setExternalPaneDrop(null),
        }
        : undefined, [activeId, onPlaceOnPane]);
    const sortable = useAnimatedReorder(tabIds, onReorder, "x", externalTabDrop);
    const paneToTabDrop = useExternalTitleTabDrop();
    const lockOverscroll = useLockOverscroll<HTMLDivElement>();
    const tabStripRef = useRef<HTMLDivElement | null>(null);
    const setTabStripRef = useCallback((el: HTMLDivElement | null) => {
        tabStripRef.current = el;
        lockOverscroll(el);
    }, [lockOverscroll]);
    const [tabOverflow, setTabOverflow] = useState({ left: false, right: false });
    const [stripWidth, setStripWidth] = useState(0);
    const [hovered, setHovered] = useState<{
        id: string;
        element: HTMLElement;
    } | null>(null);
    const hoverTimer = useRef(0);
    const lastHoverEnd = useRef(Number.NEGATIVE_INFINITY);
    // A card opens after a short rest on a tab, and the next one follows at once.
    const onTabHover = useCallback((id: string, element: HTMLElement | null) => {
        window.clearTimeout(hoverTimer.current);
        if (!element) {
            lastHoverEnd.current = performance.now();
            hoverTimer.current = window.setTimeout(() => setHovered((current) => current?.id === id ? null : current), 60);
            return;
        }
        const warm = performance.now() - lastHoverEnd.current < 500;
        hoverTimer.current = window.setTimeout(() => setHovered({ id, element }), warm ? 40 : 450);
    }, []);
    useEffect(() => () => window.clearTimeout(hoverTimer.current), []);
    const [tabMenu, setTabMenu] = useState<{
        tabId: string;
        x: number;
        y: number;
    } | null>(null);
    const syncTabOverflow = useCallback(() => {
        const el = tabStripRef.current;
        if (el) {
            setStripWidth((width) => width === el.clientWidth ? width : el.clientWidth);
        }
        const next = el
            ? tabStripOverflow(el.scrollLeft, el.clientWidth, el.scrollWidth)
            : { left: false, right: false };
        setTabOverflow((prev) => prev.left === next.left && prev.right === next.right ? prev : next);
    }, []);
    const scrollTabsBy = useCallback((direction: -1 | 1) => {
        const el = tabStripRef.current;
        if (!el)
            return;
        const amount = Math.max(el.clientWidth * 0.6, 112);
        el.scrollBy({ left: direction * amount, behavior: "smooth" });
    }, []);
    const activeTabRef = useRef<HTMLDivElement | null>(null);
    const canDrag = stripTabs.length > 1;
    useEffect(() => {
        if (sortable.draggingId)
            return;
        activeTabRef.current?.scrollIntoView({
            inline: "nearest",
            block: "nearest",
        });
    }, [activeId, sortable.draggingId]);
    useLayoutEffect(() => {
        const el = tabStripRef.current;
        if (!el)
            return;
        syncTabOverflow();
        el.addEventListener("scroll", syncTabOverflow, { passive: true });
        // Tabs glide between widths; what overflows mid-glide does not once they land.
        el.addEventListener("transitionend", syncTabOverflow);
        el.addEventListener("transitioncancel", syncTabOverflow);
        const ro = new ResizeObserver(syncTabOverflow);
        ro.observe(el);
        return () => {
            el.removeEventListener("scroll", syncTabOverflow);
            el.removeEventListener("transitionend", syncTabOverflow);
            el.removeEventListener("transitioncancel", syncTabOverflow);
            ro.disconnect();
        };
    }, [syncTabOverflow]);
    useLayoutEffect(() => {
        syncTabOverflow();
    }, [activeId, syncTabOverflow, tabs]);
    const activeTab = useMemo(() => tabs.find((t) => t.id === activeId), [activeId, tabs]);
    const systemTitle = useMemo(() => {
        const activeName = activeTab?.project ?? "";
        const project = cwd ? basename(cwd) : "";
        if (activeName && project && activeName !== project) {
            return `${activeName} — ${project} — Loci`;
        }
        if (project) {
            return `${project} — Loci`;
        }
        return "Loci";
    }, [activeTab, cwd]);
    useEffect(() => {
        document.title = systemTitle;
        try {
            void getCurrentWindow().setTitle(systemTitle);
        }
        catch { }
    }, [systemTitle]);
    const connectorCount = folded.filter((entry) => entry.depth > 0).length;
    const pinnedCount = stripTabs.filter((tab) => tab.pinned).length;
    // Padding on both sides of the strip is not tab space.
    const stripLayout = tabStripLayout({
        count: stripTabs.length,
        pinned: pinnedCount,
        available: stripWidth > 0 ? stripWidth - 16 - connectorCount * FAMILY_CONNECTOR_WIDTH : Number.POSITIVE_INFINITY,
        activeExtra: stripTabs.find((tab) => tab.id === activeId)?.descendantCount ? FAMILY_CHIP_WIDTH : 0,
    });
    // Widths glide for a moment after a change; look again once they have landed.
    useEffect(() => {
        const timer = window.setTimeout(syncTabOverflow, 280);
        return () => window.clearTimeout(timer);
    }, [syncTabOverflow, stripLayout.crowded, stripLayout.activeWidth, stripLayout.iconWidth, stripTabs.length, activeId]);
    // Which tabs keep their title when not all can: the one in view and the ones
    // used most recently, a choice that holds still while you move among them.
    const regularIds = stripTabs.filter((tab) => !tab.pinned).map((tab) => tab.id);
    const titledMemory = useRef<string[]>([]);
    const regularKey = regularIds.join("\0");
    const titledIds = useMemo(() => chooseTitled({
        ids: regularIds,
        activeId,
        recent,
        capacity: stripLayout.crowded ? stripLayout.titledCount : regularIds.length,
        previous: titledMemory.current,
    }), 
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [regularKey, activeId, recent, stripLayout.crowded, stripLayout.titledCount]);
    useLayoutEffect(() => {
        titledMemory.current = titledIds;
    }, [titledIds]);
    const titledSet = useMemo(() => new Set(titledIds), [titledIds]);
    const pillRef = useRef<HTMLDivElement | null>(null);
    useGlide({
        pill: pillRef,
        root: tabStripRef,
        target: () => activeTabRef.current,
        revision: `${activeId}|${stripWidth}|${stripLayout.crowded}|${stripLayout.iconWidth}|${stripLayout.titledWidth}|${stripLayout.activeWidth}|${titledIds.join(",")}|${stripTabs.length}|${pinnedCount}|${unfolded.size}`,
        live: !!sortable.draggingId,
    });
    const attention = tabs.some((tab) => tab.id !== activeId && tab.status === "approval")
        ? "approval"
        : tabs.some((tab) => tab.id !== activeId && tab.status === "done")
            ? "done"
            : null;
    const hoveredTab = hovered && !sortable.draggingId && !tabMenu
        ? tabs.find((tab) => tab.id === hovered.id)
        : undefined;
    const contextTab = tabMenu
        ? tabs.find((tab) => tab.id === tabMenu.tabId)
        : undefined;
    const contextCloseIds = contextTab
        ? {
            others: titleTabContextCloseIds(tabs, contextTab.id, "others"),
            right: titleTabContextCloseIds(tabs, contextTab.id, "right"),
            left: titleTabContextCloseIds(tabs, contextTab.id, "left"),
        }
        : null;
    const contextMenuItems: ContextMenuItem[] = contextTab
        ? [
            ...(contextTab.descendantCount
                ? [
                    {
                        kind: "item" as const,
                        id: "family",
                        label: `${unfolded.has(contextTab.id) ? "Hide" : "Show"} Started Tabs`,
                        description: `${contextTab.descendantCount} started from this tab`,
                    },
                ]
                : []),
            ...(onPin
                ? [
                    {
                        kind: "item" as const,
                        id: "pin",
                        label: contextTab.pinned ? "Unpin Tab" : "Pin Tab",
                        description: contextTab.pinned ? undefined : "Keep it at the left as an icon",
                    },
                    { kind: "sep" as const },
                ]
                : []),
            {
                kind: "item",
                id: "close",
                label: "Close Tab",
                shortcut: `${MOD}W`,
                disabled: !titleTabClosable(contextTab, tabs.length),
            },
            { kind: "sep" },
            {
                kind: "item",
                id: "others",
                label: "Close Other Tabs",
                disabled: contextCloseIds?.others.length === 0,
            },
            ...(onCloseIdle
                ? [
                    {
                        kind: "item" as const,
                        id: "idle",
                        label: "Close Idle Tabs",
                        description: idleTabCount > 0 ? `${idleTabCount} finished and quiet; Undo brings them back` : "None are idle right now",
                        disabled: idleTabCount === 0,
                    },
                ]
                : []),
            {
                kind: "item",
                id: "right",
                label: "Close Tabs to the Right",
                disabled: contextCloseIds?.right.length === 0,
            },
            {
                kind: "item",
                id: "left",
                label: "Close Tabs to the Left",
                disabled: contextCloseIds?.left.length === 0,
            },
            ...(contextTab.sessionCount > 0 && (onArchiveTab || onDeleteTab)
                ? [
                    { kind: "sep" as const },
                    ...(onArchiveTab
                        ? [
                            {
                                kind: "item" as const,
                                id: "archive",
                                label: "Archive",
                                description: contextTab.sessionCount > 1
                                    ? `All ${contextTab.sessionCount} conversations in this tab`
                                    : undefined,
                            },
                        ]
                        : []),
                    ...(onDeleteTab
                        ? [
                            {
                                kind: "item" as const,
                                id: "delete",
                                label: "Delete",
                                description: contextTab.sessionCount > 1
                                    ? `Permanently delete all ${contextTab.sessionCount} conversations in this tab`
                                    : undefined,
                                danger: true,
                            },
                        ]
                        : []),
                ]
                : []),
        ]
        : [];
    const onPickTabMenu = (id: string) => {
        if (!contextTab || !contextCloseIds)
            return;
        setTabMenu(null);
        if (id === "family") {
            toggleFamily(contextTab.id);
            return;
        }
        if (id === "idle") {
            onCloseIdle?.();
            return;
        }
        if (id === "pin") {
            onPin?.(contextTab.id, !contextTab.pinned);
            return;
        }
        if (id === "close") {
            onClose(contextTab.id);
            return;
        }
        if (id === "archive") {
            onArchiveTab?.(contextTab.id);
            return;
        }
        if (id === "delete") {
            onDeleteTab?.(contextTab.id);
            return;
        }
        if (id === "others" || id === "right" || id === "left") {
            onCloseMany(contextCloseIds[id], contextTab.id);
        }
    };
    const railClosed = !projectRailOpen;
    const showCurrentProject = looksLikeProject(cwd);
    // Until a project is picked, the rail and the sidebar hide, so nothing
    // project-scoped is actionable and the window controls need room.
    const projectless = !showCurrentProject;
    // An open project is labeled in the sidebar, above Sessions. Without a project that sidebar is gone, so the picker stays here.
    const showProjectButton = railClosed && Boolean(onSelectProject) && !showCurrentProject;
    const showTrailingActions = projectless &&
        railClosed &&
        Boolean(onOpenNotes || onOpenSettings);
    const trailingControls = showTrailingActions || !IS_MAC ? (<div className="flex h-full shrink-0 items-stretch">
        {showTrailingActions ? (<div className="flex items-center gap-0.5 px-2">

            {projectless && railClosed && onOpenNotes ? (<IconButton label="Notes" onClick={onOpenNotes}>
                <StickyNote className="size-3.5" strokeWidth={1.75}/>
              </IconButton>) : null}
            {!projectRailOpen && !showCurrentProject && onOpenSettings ? (<IconButton label={`Settings (${MOD},)`} onClick={onOpenSettings}>
                <Settings className="size-3.5" strokeWidth={1.75}/>
              </IconButton>) : null}
          </div>) : null}
        {!IS_MAC ? <WindowControls /> : null}
      </div>) : null;
    // "deep" drags from anywhere in the subtree. The bare attribute only drags
    // on a direct hit, which left every label and spacer dead. Tauri still
    // exempts buttons, links and inputs on its own.
    return (<header className={`flex h-10 shrink-0 select-none items-stretch border-b border-stroke${compactRail ? " body-glass" : ""}`} data-tauri-drag-region="deep">
      {compactRail ? (<div data-compact-title-nav className="flex shrink-0 items-center pl-[70px]">
          <TabVisitNav canGoBack={canGoBack} canGoForward={canGoForward} onGoBack={onGoBack} onGoForward={onGoForward}/>
        </div>) : null}
      {/* Both the rail and the sidebar step aside without a project, so the
              title bar takes over the traffic lights and the rail toggle. */}
      {projectless && railClosed && !compactRail ? (<>
          <div className="w-[78px] shrink-0"/>
          <div className="flex shrink-0 items-center px-1.5">
            <IconButton label={`Toggle Sidebar (${MOD}B)`} onClick={onToggleSidebar}>
              <PanelLeft className="size-3.5" strokeWidth={1.75}/>
            </IconButton>
          </div>
        </>) : null}
      {!sessionSidebarOpen && !projectless && onToggleSessionSidebar ? (<div className="flex shrink-0 items-center px-1.5">
          {IS_MAC && railClosed && !compactRail ? (<div className="w-[70px] shrink-0"/>) : null}
          <IconButton label={`Show workspace sidebar (${MOD}${SHIFT}B)`} onClick={onToggleSessionSidebar}>
            <SidebarLeft className="size-3.5" strokeWidth={1.75}/>
          </IconButton>
        </div>) : null}
      {showProjectButton && onSelectProject ? (<CwdPicker cwd={cwd} recents={recents} placement="below" onCwdChange={onSelectProject} buttonClassName="flex h-full min-w-0 max-w-64 shrink items-center gap-2 px-6 text-left text-sm font-medium leading-tight">
          <span className="min-w-0 truncate text-content/50">No project</span>
        </CwdPicker>) : null}

      <div className={`flex min-w-0 flex-1 items-stretch${showProjectButton ? " border-l border-stroke" : ""}`}>
        <div className="relative h-full min-w-0 flex-1 overflow-hidden" onWheel={(event) => {
            const el = tabStripRef.current;
            if (!el || el.scrollWidth <= el.clientWidth)
                return;
            if (event.deltaX === 0 && event.deltaY !== 0) {
                el.scrollLeft += event.deltaY;
            }
        }}>
          {tabOverflow.left ? (<TabStripChevron side="left" onClick={() => scrollTabsBy(-1)}/>) : null}
          {tabOverflow.right ? (<TabStripChevron side="right" onClick={() => scrollTabsBy(1)}/>) : null}
          <div ref={setTabStripRef} data-title-tab-strip className="scrollbar-none relative flex h-full min-w-0 cursor-default items-center gap-0.5 overflow-x-auto overflow-y-hidden overscroll-none pl-1.5 pr-2.5">
            <div ref={pillRef} aria-hidden data-tab-pill className="tab-pill" style={{ opacity: 0 }}/>
            {displayed.map((entry, index) => {
            const tab = entry.item;
            const active = !entry.closing && tab.id === activeId;
            const iconOnly = !!tab.pinned || (stripLayout.crowded && !titledSet.has(tab.id));
            // Past the point where titles stay readable the widths are explicit, so a tab can glide between icon and full.
            const explicitWidth = iconOnly ? stripLayout.iconWidth : stripLayout.crowded ? (active ? stripLayout.activeWidth : stripLayout.titledWidth) : undefined;
            const previous = displayed[index - 1]?.item;
            const dividerBefore = !tab.pinned && !!previous?.pinned;
            const depth = depthOf.get(tab.id) ?? 0;
            const shell = (<div ref={(el) => {
                    if (!entry.closing)
                        setTabNode(tab.id, el);
                }} style={!entry.closing && !entry.opening && explicitWidth !== undefined ? { width: explicitWidth } : undefined} className={entry.closing || entry.opening
                    ? "relative flex h-full w-full min-w-0 overflow-hidden items-center"
                    : explicitWidth !== undefined
                        ? "relative flex h-full shrink-0 cursor-default items-center transition-[width] duration-[260ms] ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none"
                        : "relative flex h-full w-56 min-w-32 shrink cursor-default items-center"} data-title-tab-id={entry.closing ? undefined : tab.id} data-tab-slot-id={entry.closing ? undefined : tab.id} data-tauri-drag-region="false">
                  {!entry.closing && paneToTabDrop?.targetTabId === tab.id ? (<span data-pane-tab-drop-hint className={`pointer-events-none absolute inset-y-1 z-50 w-0.5 rounded-full bg-accent shadow-[0_0_8px_var(--color-accent)] ${paneToTabDrop.position === "before"
                        ? "left-0"
                        : "right-0"}`}/>) : null}
                  <TitleTabItem tab={tab} active={active} variant={iconOnly ? "icon" : "full"} expanded={unfolded.has(tab.id) || (!!tab.descendantCount && stripTabs.some((other) => other.parentId === tab.id))} onToggleFamily={() => toggleFamily(tab.id)} closable={!entry.closing && titleTabClosable(tab, tabs.length)} canDrag={!entry.closing && canDrag} sortable={sortable} onSelect={(id) => {
                    setHovered(null);
                    onSelect(id);
                }} onClose={onClose} onHover={onTabHover} onContextMenu={(tabId, event) => {
                    setHovered(null);
                    setTabMenu({
                        tabId,
                        x: event.clientX,
                        y: event.clientY,
                    });
                }} itemRef={!entry.closing && tab.id === activeId
                    ? (el) => {
                        activeTabRef.current = el;
                    }
                    : undefined}/>
                </div>);
            const body = entry.closing || entry.opening ? (<TabWidthMotion key={tab.id} phase={entry.closing ? "closing" : "opening"} width={entry.width} onFinish={() => finishMotion(tab.id)}>
                    {shell}
                  </TabWidthMotion>) : (<div key={tab.id} className="contents">
                  {shell}
                </div>);
            return dividerBefore || depth > 0 ? (<div key={tab.id} className="contents">
                  {dividerBefore ? (<span aria-hidden data-pinned-divider className="mx-0.5 h-4 w-px shrink-0 bg-content/15"/>) : null}
                  {depth > 0 && !entry.closing ? (<span aria-hidden data-family-connector className="ml-0.5 h-3.5 w-px shrink-0 bg-content/30"/>) : null}
                  {body}
                </div>) : body;
        })}
          </div>
        </div>
        {onOpenSwitcher && tabs.length > 1 ? (<div className="flex shrink-0 items-center pr-1.5">
            <TabSwitcherButton count={tabs.length} attention={attention} onClick={() => {
                setHovered(null);
                onOpenSwitcher();
            }}/>
          </div>) : null}

        {!IS_MAC && !IS_WIN ? (<div className="flex min-w-0 flex-1 items-center justify-center px-4">
            <span className="pointer-events-none truncate text-[11.5px] font-medium text-content/40 select-none">
              {systemTitle}
            </span>
          </div>) : null}
        {trailingControls}
      </div>
      {hoveredTab && hovered ? (<TabHoverCard tab={hoveredTab} anchor={hovered.element} now={Date.now()}/>) : null}
      {tabMenu && contextTab ? (<ContextMenu x={tabMenu.x} y={tabMenu.y} width={244} items={contextMenuItems} ariaLabel={`Tab actions for ${tabCopy(contextTab).headline}`} onPick={onPickTabMenu} onClose={() => setTabMenu(null)}/>) : null}
    </header>);
}
export const TitleBar = memo(TitleBarComponent);
