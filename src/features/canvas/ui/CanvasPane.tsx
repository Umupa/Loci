import "@excalidraw/excalidraw/index.css";
import { CaptureUpdateAction, convertToExcalidrawElements, Excalidraw, getSceneVersion, hashElementsVersion, restore } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI, ExcalidrawProps } from "@excalidraw/excalidraw/types";
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { MessageSquarePlus, ExcalidrawIcon, X, Maximize2, Minimize2 } from "../../../shared/ui/icons";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { ResourceHeader, RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import type { Canvas, CanvasSceneReplacement } from "../canvas";
import { CANVAS_SCENE_ACCESS_EVENT, CANVAS_SCENE_REPLACED_EVENT, canvasSceneDrafts as sceneDrafts, canvasElementsToText, updateCanvas } from "../canvas";
import { registerCanvasRenderer } from "../renderScheduling";
import { parseAppResourceUrl, requestOpenAppResource } from "../../../shared/lib/appResourceLinks";
import "./canvas.css";

type OnChange = NonNullable<ExcalidrawProps["onChange"]>;
type Scene = {
  elements: Parameters<OnChange>[0];
  appState: Parameters<OnChange>[1];
  files: Parameters<OnChange>[2];
};
// Retain edits synchronously across list switches and workspace reparenting.
const SAVE_DEBOUNCE_MS = 1500;
type SceneRevision = {
  version: number;
  hash: number;
  count: number;
  background: Scene["appState"]["viewBackgroundColor"];
  font: Scene["appState"]["currentItemFontFamily"];
  files: Scene["files"];
};

type Props = {
  canvas: Canvas;
  focused: boolean;
  onFocus: () => void;
  onClose?: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  onAddToChat: (text: string) => void;
  chatTarget?: "chat" | "agent";
  /** The mentor the drawing goes to, when it is read beside one: "Add to Ada". */
  chatName?: string;
  chatIcon?: ReactNode;
  onTitleChange: (id: string, title: string) => void;
  /** Shown as the window's one reader: a reader header with Close, no pane chrome. */
  reader?: boolean;
};

function CanvasPaneComponent({ canvas, focused, onFocus, onClose, onPaneDragStart, onAddToChat, chatTarget = "chat", chatName, chatIcon, onTitleChange, reader = false }: Props) {
  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);
  const pointerUpRef = useRef<Parameters<NonNullable<ExcalidrawProps["onPointerUp"]>>[1] | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef(canvas);
  canvasRef.current = canvas;
  const [isFullscreen, setIsFullscreen] = useState(false);
  useEffect(() => {
    const handler = () => setIsFullscreen(document.fullscreenElement === containerRef.current);
    document.addEventListener("fullscreenchange", handler);
    return () => document.removeEventListener("fullscreenchange", handler);
  }, []);
  const toggleFullscreen = () => {
    if (isFullscreen) void document.exitFullscreen();
    else void containerRef.current?.requestFullscreen();
  };
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latestDataRef = useRef<(Scene & { baseDataJson?: string }) | null>(null);
  const savedDataRef = useRef(sceneDrafts.get(canvas.id)?.baseDataJson ?? canvas.dataJson);
  const revisionRef = useRef<SceneRevision | null>(null);
  const applyingSceneRef = useRef(false);
  const fittedRef = useRef(false);
  const pendingReplacementRef = useRef<Canvas | null>(null);
  const [saveError, setSaveError] = useState(false);
  const [isDark, setIsDark] = useState(() => !document.documentElement.classList.contains("theme-light"));
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState(canvas.title);
  const initialData = useMemo(() => {
    const draft = sceneDrafts.get(canvas.id);
    if (draft) return { elements: draft.elements, files: draft.files, appState: { viewBackgroundColor: draft.appState.viewBackgroundColor, currentItemFontFamily: draft.appState.currentItemFontFamily } };
    try { return JSON.parse(canvas.dataJson); }
    catch { return { elements: [], appState: {}, files: {} }; }
  }, [canvas.id]);

  useLayoutEffect(registerCanvasRenderer, []);

  useEffect(() => {
    const observer = new MutationObserver(() => setIsDark(!document.documentElement.classList.contains("theme-light")));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    return () => observer.disconnect();
  }, []);

  const save = useCallback(() => {
    const data = latestDataRef.current;
    if (!data) return;
    latestDataRef.current = null;
    const dataJson = JSON.stringify({ elements: data.elements, appState: {
      viewBackgroundColor: data.appState.viewBackgroundColor,
      currentItemFontFamily: data.appState.currentItemFontFamily,
    }, files: data.files });
    void updateCanvas(canvasRef.current.id, { dataJson }, { baseDataJson: data.baseDataJson ?? savedDataRef.current }).then(() => {
      savedDataRef.current = dataJson;
      if (sceneDrafts.get(canvasRef.current.id) === data) sceneDrafts.delete(canvasRef.current.id);
      setSaveError(false);
    }).catch(() => {
      if (!latestDataRef.current) latestDataRef.current = data;
      setSaveError(true);
    });
  }, []);

  const handleChange = useCallback<OnChange>((elements, appState, files) => {
    if (!fittedRef.current) {
      // The viewport is not saved, and a pane opened beside a chat is narrow:
      // start with the whole drawing in view, never enlarged.
      fittedRef.current = true;
      if (elements.some((element) => !element.isDeleted))
        requestAnimationFrame(() => apiRef.current?.scrollToContent(undefined, { fitToViewport: true, viewportZoomFactor: 0.9, maxZoom: 1 }));
    }
    const restoringDraft = revisionRef.current === null && sceneDrafts.has(canvasRef.current.id);
    const revision: SceneRevision = {
      version: getSceneVersion(elements),
      hash: hashElementsVersion(elements),
      count: elements.length,
      background: appState.viewBackgroundColor,
      font: appState.currentItemFontFamily,
      files,
    };
    // Excalidraw also emits onChange for zoom, pan, selection and tool changes.
    // Compare element versions, not object identity: edits can mutate elements
    // in place. Only these appState fields are part of our persisted document.
    const previous = revisionRef.current ?? {
      version: getSceneVersion(initialData.elements ?? []),
      hash: hashElementsVersion(initialData.elements ?? []),
      count: initialData.elements?.length ?? 0,
      background: initialData.appState?.viewBackgroundColor ?? revision.background,
      font: initialData.appState?.currentItemFontFamily ?? revision.font,
      files,
    };
    revisionRef.current = revision;
    if (applyingSceneRef.current) return;
    // A restored draft is still dirty, even if hydration did not change it.
    if (!restoringDraft &&
      previous.version === revision.version && previous.hash === revision.hash && previous.count === revision.count &&
      previous.background === revision.background && previous.font === revision.font && previous.files === files) return;
    const scene = { elements, appState, files, baseDataJson: savedDataRef.current };
    latestDataRef.current = scene;
    sceneDrafts.set(canvasRef.current.id, scene);
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(save, SAVE_DEBOUNCE_MS);
  }, [save, initialData]);

  useEffect(() => () => {
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    save();
  }, [save]);

  useEffect(() => {
    const flush = (event: Event) => {
      if ((event as CustomEvent<string>).detail !== canvas.id) return;
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      save();
    };
    const replace = (event: Event) => {
      const saved = (event as CustomEvent<CanvasSceneReplacement>).detail;
      const api = apiRef.current;
      if (saved.id !== canvas.id) return;
      if (!api) { pendingReplacementRef.current = saved; return; }
      const data = restore(JSON.parse(saved.dataJson), null, null);
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      latestDataRef.current = null;
      savedDataRef.current = saved.dataJson;
      sceneDrafts.delete(canvas.id);
      applyingSceneRef.current = true;
      try {
        api.addFiles(Object.values(data.files));
        const documentState = {
          viewBackgroundColor: data.appState.viewBackgroundColor,
          currentItemFontFamily: data.appState.currentItemFontFamily,
        };
        api.updateScene({ elements: data.elements, appState: documentState, captureUpdate: saved.silent ? CaptureUpdateAction.NEVER : CaptureUpdateAction.IMMEDIATELY });
        revisionRef.current = {
          version: getSceneVersion(data.elements), hash: hashElementsVersion(data.elements), count: data.elements.length,
          background: documentState.viewBackgroundColor, font: documentState.currentItemFontFamily, files: api.getFiles(),
        };
        setSaveError(false);
      } finally { applyingSceneRef.current = false; }
      // Follow the agent's last camera, as the official Excalidraw widget does.
      if (saved.viewport) api.scrollToContent(convertToExcalidrawElements([{ type: "rectangle", ...saved.viewport }]),
        { fitToViewport: true, viewportZoomFactor: 1, maxZoom: 1, animate: true, duration: 300 });
    };
    window.addEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
    window.addEventListener(CANVAS_SCENE_REPLACED_EVENT, replace);
    return () => {
      window.removeEventListener(CANVAS_SCENE_ACCESS_EVENT, flush);
      window.removeEventListener(CANVAS_SCENE_REPLACED_EVENT, replace);
    };
  }, [canvas.id, save]);

  const registerApi = useCallback((api: ExcalidrawImperativeAPI) => {
    apiRef.current = api;
    const replacement = pendingReplacementRef.current;
    if (replacement) {
      pendingReplacementRef.current = null;
      window.dispatchEvent(new CustomEvent(CANVAS_SCENE_REPLACED_EVENT, { detail: replacement }));
    }
  }, []);

  const handleAddToChat = useCallback(() => {
    const api = apiRef.current;
    if (!api) return;
    const all = api.getSceneElements();
    const selectedIds = api.getAppState().selectedElementIds;
    const selected = all.filter((el) => selectedIds[el.id]);
    onAddToChat(canvasElementsToText(canvas.title, JSON.stringify(selected.length ? selected : all, null, 2), canvas.id));
  }, [canvas.id, canvas.title, onAddToChat]);

  // Links to notes, canvases, sessions and files open inside Loci; other links keep Excalidraw's behavior.
  const openLink = useCallback<NonNullable<ExcalidrawProps["onLinkOpen"]>>((element, event) => {
    const resource = element.link ? parseAppResourceUrl(element.link) : undefined;
    if (!resource) return;
    event.preventDefault();
    requestOpenAppResource(resource);
  }, []);

  const rememberPointerUp = useCallback<NonNullable<ExcalidrawProps["onPointerUp"]>>((activeTool, state) => {
    pointerUpRef.current = activeTool.type === "selection" && !state.drag.hasOccurred &&
      !state.resize.isResizing && !state.boxSelection.hasOccurred && !state.scrollbars.isOverEither ? state : null;
  }, []);

  const navigateConcept = useCallback((event: ReactMouseEvent<HTMLDivElement>) => {
    const pointer = pointerUpRef.current;
    pointerUpRef.current = null;
    if (!pointer || !(event.target instanceof HTMLCanvasElement) || event.button !== 0 ||
      event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
    // Use Excalidraw's actual hit, which accounts for pan, zoom, rotation and
    // stacking. Searching concept bounding boxes would select obscured nodes.
    const elements = apiRef.current?.getSceneElements();
    let element = elements?.find((candidate) => candidate.id === pointer.hit.element?.id);
    const containerId = element?.type === "text" ? element.containerId : null;
    if (containerId) element = elements?.find((candidate) => candidate.id === containerId);
    const data = element?.customData;
    if (!element || element.isDeleted || data?.type !== "concept" ||
      typeof data.courseId !== "string" || !data.courseId.trim() ||
      typeof data.conceptId !== "string" || !data.conceptId.trim()) return;
    event.preventDefault();
    event.stopPropagation();
    window.dispatchEvent(new CustomEvent("loci:navigate-concept", { detail: {
      courseId: data.courseId, conceptId: data.conceptId, canvasId: canvasRef.current.id,
      ...(typeof data.agentId === "string" && data.agentId ? { agentId: data.agentId } : {}),
    } }));
  }, []);

  const commitTitle = () => {
    setEditingTitle(false);
    const title = titleDraft.trim() || "Untitled drawing";
    if (title !== canvas.title) { save(); onTitleChange(canvas.id, title); }
  };
  const chatNameOrTarget = chatName ?? chatTarget;
  const chatLabel = chatName ? `Add to ${chatName}` : chatTarget === "agent" ? "Add to agent" : "Add to chat";
  const titleField = editingTitle ? (
    <input autoFocus aria-label="Drawing title" className={reader ? "w-full min-w-0 bg-transparent text-[13px] font-medium text-content outline-none" : "min-w-0 flex-1 bg-transparent text-xs text-content outline-none"} value={titleDraft}
      onChange={(event) => setTitleDraft(event.target.value)} onBlur={commitTitle}
      onKeyDown={(event) => {
        if (event.key === "Enter") event.currentTarget.blur();
        if (event.key === "Escape") { event.preventDefault(); setEditingTitle(false); }
      }} />
  ) : <span className={`block min-w-0 truncate ${reader ? "" : "flex-1 text-xs"}`} title="Double-click to rename" onDoubleClick={() => { setTitleDraft(canvas.title); setEditingTitle(true); }}>{canvas.title}</span>;
  const addButton = (
    <button type="button" data-no-drag data-tauri-drag-region="false" aria-label={`Add drawing to ${chatNameOrTarget}`} title={`Add selected elements or drawing to ${chatNameOrTarget}`} onClick={handleAddToChat}
      className={`flex shrink-0 items-center gap-1 text-content/55 hover:bg-content/10 hover:text-content ${reader ? "h-6 rounded-md px-1.5 text-xs" : "h-6 rounded px-1.5 text-xs"}`}>
      {chatIcon ?? <MessageSquarePlus className="size-3.5" />}<span>{chatLabel}</span>
    </button>
  );
  const fullscreenButton = (
    <button type="button" data-no-drag data-tauri-drag-region="false" aria-label={isFullscreen ? "Exit fullscreen" : "Enter fullscreen"} title={isFullscreen ? "Exit fullscreen" : "Fullscreen"} onClick={toggleFullscreen}
      className={reader ? RESOURCE_ACTION : "grid size-6 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"}>
      {isFullscreen ? <Minimize2 className="size-3.5" /> : <Maximize2 className="size-3.5" />}
    </button>
  );

  return (
    <div ref={containerRef} className="loci-canvas flex h-full min-h-0 min-w-0 flex-col text-content" onPointerDown={() => { if (!focused) onFocus(); }}>
      {reader && onClose ? <ResourceHeader title={canvas.title} titleContent={titleField} onClose={onClose}>
        {saveError ? <button type="button" data-tauri-drag-region="false" className="text-xs text-red-400" onClick={save}>Retry save</button> : null}
        {addButton}
        {fullscreenButton}
      </ResourceHeader> : <PaneHeader onPaneDragStart={onPaneDragStart}>
        {!onPaneDragStart ? <ExcalidrawIcon className="size-3.5 shrink-0 text-content/45" /> : null}
        <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} />
        {titleField}
        {saveError ? <button data-no-drag className="text-xs text-red-400" onClick={save}>Retry save</button> : null}
        {addButton}
        {fullscreenButton}
        {onClose ? <button type="button" data-no-drag aria-label="Close pane" title="Close pane" onClick={onClose}
          className="grid size-5 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"><X className="size-3" /></button> : null}
      </PaneHeader>}
      <div className="relative min-h-0 min-w-0 flex-1" onPointerDownCapture={() => { pointerUpRef.current = null; }} onDoubleClickCapture={navigateConcept}>
        <Excalidraw excalidrawAPI={registerApi} initialData={initialData} onChange={handleChange} onLinkOpen={openLink} theme={isDark ? "dark" : "light"}
          onPointerUp={rememberPointerUp}
          UIOptions={{ canvasActions: { saveAsImage: false, loadScene: false, export: false, toggleTheme: false } }} />
      </div>
    </div>
  );
}
export const CanvasPane = memo(CanvasPaneComponent);
