import type { OpenFileFn } from "../../files/model/filePlace";
import { lazy, memo, Suspense, useCallback, useEffect, useReducer, useRef, useState, type ComponentProps, type ReactNode, type CSSProperties, type PointerEvent as ReactPointerEvent, } from "react";
import { setGrabbing, suppressTextSelection } from "../../../shared/lib/drag";
import { paneDropFromPoint, setExternalTitleTabDrop, titleTabDropFromPoint, useExternalPaneDrop, type TitleTabDropPosition, } from "../model/paneDrop";
import type { ApprovalDecision, UserQuestionReply, } from "../../../integrations/harness";
import { filePanePath, layoutLeaves, layoutSashes, setSplitRatio, type LayoutLeaf, type LayoutNode, type LayoutSash, type PaneEdge, } from "../model/layout";
import { type RecentProject, } from "../../projects/model/recents";
import { type Attachment, type Block, type HarnessId, type RuntimeMode, type Session, type ComposerTurnOptions, } from "../../sessions/model/session";
import type { LearningMessageContext } from "../../learning/model/types";
import { SessionPane } from "../../sessions/ui/SessionPane";
import type { TranscriptPool } from "../../sessions/ui/TranscriptPool";
import type { SessionFolderTarget } from "../../sessions/model/sessionFolders";
import type { Canvas } from "../../canvas/canvas";
const FilePane = lazy(() => import("../../files/ui/FilePane").then((m) => ({ default: m.FilePane })));
const CoursePane = lazy(() => import("../../learning/ui/CoursePane").then((m) => ({ default: m.CoursePane })));
const AgentDocumentReader = lazy(() => import("../../agents/ui/AgentDocumentReader").then((m) => ({ default: m.AgentDocumentReader })));
const CanvasPane = lazy(() => import("../../canvas/ui/CanvasPane").then((m) => ({ default: m.CanvasPane })));
type Shared = {
    visible: boolean;
    sessions: Session[];
    focusedId: string;
    composerFocused: boolean;
    composerFocusToken?: number;
    recents: RecentProject[];
    hideProjectPicker?: boolean;
    onOpenFile: OpenFileFn;
    onFocus: (paneId: string) => void;
    onClose: (sessionId: string) => void;
    onRatio: (splitId: string, index: number, ratio: number) => void;
    onCwdChange: (sessionId: string, cwd: string) => void;
    onModelChange: (sessionId: string, harness: HarnessId, model: string) => void;
    onModelSettingsChange: (sessionId: string, settings: Record<string, string>) => void;
    onRuntimeModeChange: (sessionId: string, mode: RuntimeMode) => void;
    onSubmit: (sessionId: string, text: string, attachments: Attachment[], options?: ComposerTurnOptions) => boolean | void;
    onSaveDraft: (sessionId: string, text: string, attachments: Attachment[], context?: LearningMessageContext) => boolean | void;
    onRemoveDraft: (sessionId: string, draftBlockId: string) => boolean | void;
    onStop: (sessionId: string) => void;
    onCompactContext: (sessionId: string) => boolean;
    onPlaceSessionInFolder: (sessionId: string, target: SessionFolderTarget) => void;
    onDeleteQueuedMessage: (sessionId: string, messageId: string) => void;
    onEditQueuedMessage: (sessionId: string, messageId: string, text: string) => void;
    onQueuedMessageEditingChange: (sessionId: string, messageId?: string) => void;
    onSteerQueuedMessage: (sessionId: string, messageId: string) => void;
    onResumeQueue: (sessionId: string) => void;
    onUsageLimitResume: (sessionId: string) => void;
    onUsageLimitResumeAtReset: (sessionId: string, enabled: boolean) => void;
    onUsageLimitDismiss: (sessionId: string) => void;
    onNoteCardDismiss?: (sessionId: string) => void;
    onApproval: (sessionId: string, requestId: number, decision: ApprovalDecision) => void;
    onQuestionReply: (sessionId: string, requestId: number, reply: UserQuestionReply) => void;
    onQuestionInteraction?: (sessionId: string, requestId: number) => void;
    onBtwSubmit?: (sessionId: string, turn: Block[], threadId: string, messageId: string, text: string, model?: string, modelSettings?: Record<string, string>) => boolean | void;
    onBtwRetry?: (sessionId: string, turn: Block[], threadId: string) => void;
    onBtwDelete?: (sessionId: string, turn: Block[], threadId: string) => void;
    onBtwStop?: (sessionId: string, turn: Block[], threadId: string) => void;
    onBtwModelChange?: (sessionId: string, turn: Block[], threadId: string, model: string, modelSettings: Record<string, string>) => void;
    onMovePane: (fromId: string, toId: string, edge: PaneEdge) => void;
    onDetachPane?: (paneId: string, targetTabId: string, position: TitleTabDropPosition) => void;
    transcriptPool?: TranscriptPool;
    canvases?: Canvas[];
    /** Agent conversations use the same layout, with their own header and details. */
    renderSession?: (props: ComponentProps<typeof SessionPane>) => ReactNode;
    onCanvasFocus?: (canvasId: string) => void;
    onCanvasAddToChat?: (text: string) => void;
    canvasChatTarget?: "chat" | "agent";
    canvasChatIcon?: ReactNode;
    onCanvasTitleChange?: (canvasId: string, title: string) => void;
    onSaveToCanvas?: (text: string, anchor?: HTMLElement | null) => void | Promise<void>;
    /** Project folder that file panes show their paths relative to. */
    projectCwd?: string;
    onFilePaneFocus?: (paneId: string) => void;
    onFilePanePin?: (path: string) => void;
    onOpenProjectFile?: OpenFileFn;
};
type Props = Shared & {
    layout: LayoutNode;
};
type PaneDrag = {
    fromId: string;
    overId: string | null;
    edge: PaneEdge;
};
const DRAG_THRESHOLD = 5;
function PaneTreeComponent({ visible, layout, sessions, focusedId, composerFocused, composerFocusToken, recents, hideProjectPicker, onOpenFile, onFocus, onClose, onRatio, onCwdChange, onModelChange, onModelSettingsChange, onRuntimeModeChange, onSaveDraft, onRemoveDraft, onSubmit, onStop, onCompactContext, onPlaceSessionInFolder, onDeleteQueuedMessage, onEditQueuedMessage, onQueuedMessageEditingChange, onSteerQueuedMessage, onResumeQueue, onUsageLimitResume, onUsageLimitResumeAtReset, onUsageLimitDismiss, onNoteCardDismiss, onApproval, onQuestionReply, onQuestionInteraction, onBtwSubmit, onBtwRetry, onBtwDelete, onBtwStop, onBtwModelChange, onMovePane, onDetachPane, transcriptPool, canvases, renderSession, onCanvasFocus, onCanvasAddToChat, canvasChatTarget, canvasChatIcon, onCanvasTitleChange, onSaveToCanvas, projectCwd, onFilePaneFocus, onFilePanePin, onOpenProjectFile, }: Props) {
    const treeRef = useRef<HTMLDivElement>(null);
    const layoutRef = useRef(layout);
    layoutRef.current = layout;
    const [draft, setDraft] = useState<LayoutNode | null>(null);
    const [paneDrag, setPaneDrag] = useState<PaneDrag | null>(null);
    const externalDrop = useExternalPaneDrop(visible);
    const drop = paneDrag ?? externalDrop;
    const onMovePaneRef = useRef(onMovePane);
    onMovePaneRef.current = onMovePane;
    const onDetachPaneRef = useRef(onDetachPane);
    onDetachPaneRef.current = onDetachPane;
    const onFocusRef = useRef(onFocus);
    onFocusRef.current = onFocus;
    useEffect(() => {
        setDraft(null);
    }, [layout]);
    // A sash drag re-renders this tree every frame. `SessionPane` compares props
    // shallowly, so handing it a fresh drag handler each frame would re-render
    // the whole session subtree (transcript, composer, picker) per frame.
    const dragHandlers = useRef(new Map<string, (event: ReactPointerEvent<HTMLElement>) => void>());
    const paneDragStartFor = (paneId: string) => {
        const cached = dragHandlers.current.get(paneId);
        if (cached)
            return cached;
        const handler = (event: ReactPointerEvent<HTMLElement>) => startPaneDrag(paneId, event);
        dragHandlers.current.set(paneId, handler);
        return handler;
    };
    const tree = draft ?? layout;
    const leaves = layoutLeaves(tree);
    // "Add to chat" from a file or drawing pane goes to the chat beside it: the
    // focused chat, else the tab's first. A hidden tab has no focus and no target.
    const chatTargetId = !focusedId ? undefined
        : leaves.find((entry) => entry.id === focusedId && entry.kind === "session")?.id
            ?? leaves.find((entry) => entry.kind === "session")?.id;
    const sashes = layoutSashes(tree);
    const inSplit = leaves.length > 1;
    // A pane split into an existing layout slides in from the edge it was added
    // on, using the existing pane transition. The neighbours reflow once up front;
    // only the new pane's content moves, so nothing rewraps mid-animation.
    // Panes present when the tree mounts, or swapped in place, just appear.
    const knownLeafIds = useRef<ReadonlySet<string> | null>(null);
    const enteringPanes = useRef(new Map<string, PaneEnterFrom>());
    const [, rerender] = useReducer((tick: number) => tick + 1, 0);
    if (knownLeafIds.current && leaves.length > knownLeafIds.current.size) {
        for (const leaf of leaves) {
            if (knownLeafIds.current.has(leaf.id))
                continue;
            enteringPanes.current.set(leaf.id, paneEnterFrom(leaf));
        }
    }
    knownLeafIds.current = new Set(leaves.map((leaf) => leaf.id));
    const startPaneDrag = useCallback((fromId: string, event: ReactPointerEvent<HTMLElement>) => {
        if (event.button !== 0)
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
                if (Math.hypot(ev.clientX - startX, ev.clientY - startY) <
                    DRAG_THRESHOLD) {
                    return;
                }
                active = true;
                setGrabbing(true);
                onFocusRef.current(fromId);
                setPaneDrag({ fromId, overId: null, edge: "left" });
            }
            const titleTab = onDetachPaneRef.current ? titleTabDropFromPoint(ev.clientX, ev.clientY) : null;
            setExternalTitleTabDrop(titleTab ? { fromId, ...titleTab } : null);
            if (titleTab) {
                setPaneDrag({ fromId, overId: null, edge: "left" });
                return;
            }
            const over = paneDropFromPoint(ev.clientX, ev.clientY);
            if (!over || over.id === fromId) {
                setPaneDrag({
                    fromId,
                    overId: over?.id === fromId ? fromId : null,
                    edge: over?.edge ?? "left",
                });
                return;
            }
            setPaneDrag({ fromId, overId: over.id, edge: over.edge });
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
            setGrabbing(false);
            setPaneDrag(null);
            setExternalTitleTabDrop(null);
            try {
                handle.releasePointerCapture(pointerId);
            }
            catch {
                /* already released */
            }
            if (!active || !commit)
                return;
            const titleTab = onDetachPaneRef.current ? titleTabDropFromPoint(lastX, lastY) : null;
            if (titleTab) {
                onDetachPaneRef.current?.(fromId, titleTab.targetTabId, titleTab.position);
                return;
            }
            const over = paneDropFromPoint(lastX, lastY);
            if (over && over.id !== fromId) {
                onMovePaneRef.current(fromId, over.id, over.edge);
            }
        }
        window.addEventListener("pointermove", onMove);
        window.addEventListener("pointerup", onUp);
        window.addEventListener("pointercancel", onUp);
        window.addEventListener("keydown", onKey);
    }, []);
    return (<div ref={treeRef} className="relative h-full min-h-0 min-w-0">
      {leaves.map((leaf) => {
            const isCanvas = leaf.kind === "canvas";
            const filePath = leaf.kind === "file" ? filePanePath(leaf.id) : undefined;
            const session = leaf.kind === "session" ? sessions.find((entry) => entry.id === leaf.id) : undefined;
            const canvas = isCanvas ? canvases?.find((c) => c.id === leaf.id) : undefined;
            const dragging = drop?.fromId === leaf.id;
            const onPaneDragStart = inSplit ? paneDragStartFor(leaf.id) : undefined;
            const sessionPaneProps: ComponentProps<typeof SessionPane> | undefined = session ? {
                onOpenFile: onOpenFile,
                addToChatTarget: chatTargetId === session.id,
                session: session,
                visible: visible,
                focused: focusedId === session.id,
                inSplit: inSplit,
                composerFocused: composerFocused,
                composerFocusToken: composerFocusToken,
                recents: recents,
                hideProjectPicker: hideProjectPicker,
                onFocus: onFocus,
                onClose: onClose,
                onCwdChange: onCwdChange,
                onModelChange: onModelChange,
                onModelSettingsChange: onModelSettingsChange,
                onRuntimeModeChange: onRuntimeModeChange,
                onSaveDraft: onSaveDraft,
                onRemoveDraft: onRemoveDraft,
                onSubmit: onSubmit,
                onStop: onStop,
                onCompactContext: onCompactContext,
                onPlaceSessionInFolder: onPlaceSessionInFolder,
                onDeleteQueuedMessage: onDeleteQueuedMessage,
                onEditQueuedMessage: onEditQueuedMessage,
                onQueuedMessageEditingChange: onQueuedMessageEditingChange,
                onSteerQueuedMessage: onSteerQueuedMessage,
                onResumeQueue: onResumeQueue,
                onUsageLimitResume: onUsageLimitResume,
                onUsageLimitResumeAtReset: onUsageLimitResumeAtReset,
                onUsageLimitDismiss: onUsageLimitDismiss,
                onNoteCardDismiss: onNoteCardDismiss,
                onSaveToCanvas: onSaveToCanvas,
                onApproval: onApproval,
                onQuestionReply: onQuestionReply,
                onQuestionInteraction: onQuestionInteraction,
                onBtwSubmit: onBtwSubmit,
                onBtwRetry: onBtwRetry,
                onBtwDelete: onBtwDelete,
                onBtwStop: onBtwStop,
                onBtwModelChange: onBtwModelChange,
                onPaneDragStart: onPaneDragStart,
                transcriptPool: transcriptPool
            } : undefined;
            const backgroundStyle = {
                "--chat-background-left": `${(-leaf.rect.x / leaf.rect.w) * 100}%`,
                "--chat-background-top": `${(-leaf.rect.y / leaf.rect.h) * 100}%`,
                "--chat-background-width": `${100 / leaf.rect.w}%`,
                "--chat-background-height": `${100 / leaf.rect.h}%`,
            } as CSSProperties;
            return (<div key={leaf.id} data-pane-id={leaf.id} className={`absolute flex min-h-0 min-w-0 flex-col overflow-hidden ${dragging ? "opacity-40" : ""}`}
            // The new pane focuses its composer while it is still
            // offscreen, and focus scrolls this clip box to reveal it, which
            // fights the slide. Scroll events land before paint, so undoing
            // it here never shows.
            onScroll={(event) => {
                    if (!enteringPanes.current.has(leaf.id))
                        return;
                    event.currentTarget.scrollLeft = 0;
                    event.currentTarget.scrollTop = 0;
                }} style={{
                    left: `${leaf.rect.x * 100}%`,
                    top: `${leaf.rect.y * 100}%`,
                    width: `${leaf.rect.w * 100}%`,
                    height: `${leaf.rect.h * 100}%`,
                    ...backgroundStyle,
                }}>
            {drop && drop.overId === leaf.id && drop.fromId !== leaf.id ? (<PaneDropHint edge={drop.edge}/>) : null}
            <div data-pane-enter={enteringPanes.current.get(leaf.id)} onAnimationEnd={(event) => {
                    if (event.animationName !== "pane-enter")
                        return;
                    enteringPanes.current.delete(leaf.id);
                    rerender();
                }} className="flex min-h-0 min-w-0 flex-1 flex-col">
              {leaf.kind === "course" && leaf.course ? (visible ? <Suspense fallback={null}><CoursePane {...leaf.course} focused={focusedId === leaf.id} onFocus={() => onFocus(leaf.id)} onClose={() => onClose(leaf.id)} onPaneDragStart={onPaneDragStart}/></Suspense> : null) : leaf.kind === "document" && leaf.document ? (visible ? <Suspense fallback={null}><AgentDocumentReader document={leaf.document} agentId={leaf.agentId} focused={focusedId === leaf.id} onFocus={() => onFocus(leaf.id)} onClose={() => onClose(leaf.id)} onPaneDragStart={onPaneDragStart}/></Suspense> : null) : filePath !== undefined ? (visible ? <Suspense fallback={null}><FilePane path={filePath} cwd={projectCwd ?? ""} preview={!!leaf.preview} focused={focusedId === leaf.id} onFocus={() => onFilePaneFocus?.(leaf.id)} onPin={() => onFilePanePin?.(filePath)} onClose={() => onClose(leaf.id)} onOpenFile={onOpenProjectFile ?? onOpenFile} onPaneDragStart={onPaneDragStart}/></Suspense> : null) : canvas ? (visible ? <Suspense fallback={null}><CanvasPane canvas={canvas} focused={focusedId === canvas.id} onFocus={() => onCanvasFocus?.(canvas.id)} onAddToChat={(text) => onCanvasAddToChat?.(text)} chatTarget={canvasChatTarget} chatIcon={canvasChatIcon} onTitleChange={(id, title) => onCanvasTitleChange?.(id, title)} onClose={() => onClose(canvas.id)} onPaneDragStart={onPaneDragStart}/></Suspense> : null) : sessionPaneProps ? (renderSession?.(sessionPaneProps) ?? <SessionPane {...sessionPaneProps}/>) : isCanvas ? (<div className="flex h-full flex-col items-center justify-center gap-2 text-sm text-content/60"><p>Drawing is no longer available.</p><button type="button" className="rounded px-3 py-1 hover:bg-content/10" onClick={() => onClose(leaf.id)}>Close pane</button></div>) : null}
            </div>
          </div>);
        })}
      {sashes.map((sash) => (<Sash key={`${sash.splitId}:${sash.index}`} sash={sash} containerRef={treeRef} onPreview={(ratio) => setDraft(setSplitRatio(layoutRef.current, sash.splitId, sash.index, ratio))} onCommit={(ratio) => {
                setDraft(null);
                onRatio(sash.splitId, sash.index, ratio);
            }} onCancel={() => setDraft(null)}/>))}
    </div>);
}
export const PaneTree = memo(PaneTreeComponent, (previous, next) => !previous.visible && !next.visible);
type PaneEnterFrom = "left" | "right" | "top" | "bottom" | "fade";
function paneEnterFrom({ rect, axis }: LayoutLeaf): PaneEnterFrom {
    const edge = 0.001;
    if (axis === "x") {
        if (rect.x + rect.w >= 1 - edge)
            return "right";
        if (rect.x <= edge)
            return "left";
    }
    else {
        if (rect.y + rect.h >= 1 - edge)
            return "bottom";
        if (rect.y <= edge)
            return "top";
    }
    return "fade";
}
function PaneDropHint({ edge }: {
    edge: PaneEdge;
}) {
    const wash = edge === "left"
        ? "absolute inset-y-0 left-0 w-1/2 bg-accent/15"
        : edge === "right"
            ? "absolute inset-y-0 right-0 w-1/2 bg-accent/15"
            : edge === "top"
                ? "absolute inset-x-0 top-0 h-1/2 bg-accent/15"
                : "absolute inset-x-0 bottom-0 h-1/2 bg-accent/15";
    const line = edge === "left"
        ? "absolute inset-y-0 left-0 w-0.5 bg-accent"
        : edge === "right"
            ? "absolute inset-y-0 right-0 w-0.5 bg-accent"
            : edge === "top"
                ? "absolute inset-x-0 top-0 h-0.5 bg-accent"
                : "absolute inset-x-0 bottom-0 h-0.5 bg-accent";
    return (<div className="pointer-events-none absolute inset-0 z-20">
      <div className={wash}/>
      <div className={line}/>
    </div>);
}
function Sash({ sash, containerRef, onPreview, onCommit, onCancel, }: {
    sash: LayoutSash;
    containerRef: {
        current: HTMLDivElement | null;
    };
    onPreview: (ratio: number) => void;
    onCommit: (ratio: number) => void;
    onCancel: () => void;
}) {
    const row = sash.dir === "right";
    const boundary = sash.sizes
        .slice(0, sash.index + 1)
        .reduce((sum, size) => sum + size, 0);
    const group = sash.group;
    return (<div role="separator" aria-orientation={row ? "vertical" : "horizontal"} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(boundary * 100)} className={row ? "absolute z-10 w-px bg-stroke" : "absolute z-10 h-px bg-stroke"} style={row
            ? {
                left: `${(group.x + boundary * group.w) * 100}%`,
                top: `${group.y * 100}%`,
                height: `${group.h * 100}%`,
            }
            : {
                left: `${group.x * 100}%`,
                top: `${(group.y + boundary * group.h) * 100}%`,
                width: `${group.w * 100}%`,
            }}>
      <div className={row
            ? "absolute inset-y-0 -left-1.5 -right-1.5 cursor-col-resize touch-none"
            : "absolute inset-x-0 -top-1.5 -bottom-1.5 cursor-row-resize touch-none"} onPointerDown={(e) => {
            e.preventDefault();
            e.stopPropagation();
            const handle = e.currentTarget;
            const parent = containerRef.current;
            if (!parent)
                return;
            handle.setPointerCapture(e.pointerId);
            const rect = parent.getBoundingClientRect();
            const restoreSelection = suppressTextSelection();
            const previousCursor = document.body.style.cursor;
            document.body.style.cursor = row ? "col-resize" : "row-resize";
            const origin = row
                ? rect.left + group.x * rect.width
                : rect.top + group.y * rect.height;
            const span = row ? group.w * rect.width : group.h * rect.height;
            let nextBoundary = boundary;
            let moved = false;
            let frame: number | null = null;
            const move = (ev: PointerEvent) => {
                const pos = row ? ev.clientX : ev.clientY;
                if (span <= 0)
                    return;
                moved = true;
                nextBoundary = (pos - origin) / span;
                if (frame != null)
                    return;
                frame = requestAnimationFrame(() => {
                    frame = null;
                    onPreview(nextBoundary);
                });
            };
            const finish = (commit: boolean) => {
                if (frame != null) {
                    cancelAnimationFrame(frame);
                    frame = null;
                }
                if (handle.hasPointerCapture(e.pointerId)) {
                    handle.releasePointerCapture(e.pointerId);
                }
                handle.removeEventListener("pointermove", move);
                handle.removeEventListener("pointerup", up);
                handle.removeEventListener("pointercancel", cancel);
                window.removeEventListener("keydown", keydown);
                restoreSelection();
                document.body.style.cursor = previousCursor;
                if (!moved)
                    return;
                if (commit)
                    onCommit(nextBoundary);
                else
                    onCancel();
            };
            const up = () => finish(true);
            const cancel = () => finish(false);
            const keydown = (event: KeyboardEvent) => {
                if (event.key !== "Escape")
                    return;
                event.preventDefault();
                finish(false);
            };
            handle.addEventListener("pointermove", move);
            handle.addEventListener("pointerup", up);
            handle.addEventListener("pointercancel", cancel);
            window.addEventListener("keydown", keydown);
        }}/>
    </div>);
}
