import "@excalidraw/excalidraw/index.css";
import { CaptureUpdateAction, convertToExcalidrawElements, Excalidraw, getSceneVersion, hashElementsVersion, restore } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI, ExcalidrawProps } from "@excalidraw/excalidraw/types";
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { GripVertical, ExternalLink, MessageSquarePlus, ExcalidrawIcon, X, Maximize2, Minimize2 } from "../../../shared/ui/icons";
import type { Canvas, CanvasSceneReplacement } from "../canvas";
import { CANVAS_SCENE_ACCESS_EVENT, CANVAS_SCENE_REPLACED_EVENT, canvasSceneDrafts as sceneDrafts, canvasElementsToText, updateCanvas } from "../canvas";
import { registerCanvasRenderer } from "../renderScheduling";
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
  onOpenInWorkspace?: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  onAddToChat: (text: string) => void;
  onTitleChange: (id: string, title: string) => void;
  onRegisterAppend?: (canvasId: string, fn: ((text: string) => void) | null) => void;
};

function CanvasPaneComponent({ canvas, focused, onFocus, onClose, onOpenInWorkspace, onPaneDragStart, onAddToChat, onTitleChange, onRegisterAppend }: Props) {
  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);
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
  const latestDataRef = useRef<Scene | null>(null);
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
    void updateCanvas(canvasRef.current.id, { dataJson }).then(() => {
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
    const scene = { elements, appState, files };
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
      sceneDrafts.delete(canvas.id);
      applyingSceneRef.current = true;
      try {
        api.addFiles(Object.values(data.files));
        const documentState = {
          viewBackgroundColor: data.appState.viewBackgroundColor,
          currentItemFontFamily: data.appState.currentItemFontFamily,
        };
        api.updateScene({ elements: data.elements, appState: documentState, captureUpdate: CaptureUpdateAction.IMMEDIATELY });
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

  const appendText = useCallback((text: string) => {
    const api = apiRef.current;
    if (!api) return;
    const existing = api.getSceneElements();
    const maxY = existing.reduce((acc, el) => Math.max(acc, el.y + el.height), 0);
    const added = convertToExcalidrawElements([{ type: "text", x: 40, y: maxY + 40, text, fontSize: 16, width: 500 }]);
    api.updateScene({ elements: [...existing, ...added] });
  }, []);
  const registerRef = useRef(onRegisterAppend);
  registerRef.current = onRegisterAppend;
  const registerApi = useCallback((api: ExcalidrawImperativeAPI) => {
    apiRef.current = api;
    registerRef.current?.(canvas.id, appendText);
    const replacement = pendingReplacementRef.current;
    if (replacement) {
      pendingReplacementRef.current = null;
      window.dispatchEvent(new CustomEvent(CANVAS_SCENE_REPLACED_EVENT, { detail: replacement }));
    }
  }, [canvas.id, appendText]);
  useEffect(() => () => { registerRef.current?.(canvas.id, null); }, [canvas.id]);

  const handleAddToChat = useCallback(() => {
    const api = apiRef.current;
    if (!api) return;
    const all = api.getSceneElements();
    const selectedIds = api.getAppState().selectedElementIds;
    const selected = all.filter((el) => selectedIds[el.id]);
    onAddToChat(canvasElementsToText(canvas.title, JSON.stringify(selected.length ? selected : all, null, 2), canvas.id));
  }, [canvas.id, canvas.title, onAddToChat]);

  const commitTitle = () => {
    setEditingTitle(false);
    const title = titleDraft.trim() || "Untitled drawing";
    if (title !== canvas.title) { save(); onTitleChange(canvas.id, title); }
  };

  return (
    <div ref={containerRef} className="loci-canvas flex h-full min-h-0 min-w-0 flex-col text-content" onPointerDown={() => { if (!focused) onFocus(); }}>
      <div className={`flex h-9 shrink-0 select-none items-center gap-1.5 border-b border-stroke px-2 ${onPaneDragStart ? "cursor-grab active:cursor-grabbing touch-none" : ""}`}
        onPointerDown={(event) => {
          if (!(event.target as HTMLElement).closest("[data-no-drag]")) onPaneDragStart?.(event);
        }}>
        {onPaneDragStart ? <GripVertical className="size-3.5 shrink-0 text-content/35" /> : <ExcalidrawIcon className="size-3.5 shrink-0 text-content/45" />}
        <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} />
        {editingTitle ? (
          <input data-no-drag autoFocus aria-label="Drawing title" className="min-w-0 flex-1 bg-transparent text-xs text-content outline-none" value={titleDraft}
            onChange={(event) => setTitleDraft(event.target.value)} onBlur={commitTitle}
            onKeyDown={(event) => {
              if (event.key === "Enter") event.currentTarget.blur();
              if (event.key === "Escape") { event.preventDefault(); setEditingTitle(false); }
            }} />
        ) : <span className="min-w-0 flex-1 truncate text-xs" title="Double-click to rename" onDoubleClick={() => { setTitleDraft(canvas.title); setEditingTitle(true); }}>{canvas.title}</span>}
        {saveError ? <button data-no-drag className="text-xs text-red-400" onClick={save}>Retry save</button> : null}
        <button type="button" data-no-drag aria-label="Add drawing to chat" title="Add selected elements or drawing to chat" onClick={handleAddToChat}
          className="flex h-6 shrink-0 items-center gap-1 rounded px-1.5 text-xs text-content/55 hover:bg-content/10 hover:text-content">
          <MessageSquarePlus className="size-3.5" /><span>Add to chat</span>
        </button>
        <button type="button" data-no-drag aria-label={isFullscreen ? "Exit fullscreen" : "Enter fullscreen"} title={isFullscreen ? "Exit fullscreen" : "Fullscreen"} onClick={toggleFullscreen} className="grid size-6 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content">
          {isFullscreen ? <Minimize2 className="size-3.5" /> : <Maximize2 className="size-3.5" />}
        </button>
        {onOpenInWorkspace ? <button type="button" data-no-drag aria-label="Open drawing in workspace" title="Open in workspace" onClick={onOpenInWorkspace} className="grid size-6 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"><ExternalLink className="size-3.5" /></button> : null}
        {onClose ? <button type="button" data-no-drag aria-label="Close pane" title="Close pane" onClick={onClose}
          className="grid size-5 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"><X className="size-3" /></button> : null}
      </div>
      <div className="min-h-0 min-w-0 flex-1">
        <Excalidraw excalidrawAPI={registerApi} initialData={initialData} onChange={handleChange} theme={isDark ? "dark" : "light"}
          UIOptions={{ canvasActions: { saveAsImage: false, loadScene: false, export: false, toggleTheme: false } }} />
      </div>
    </div>
  );
}
export const CanvasPane = memo(CanvasPaneComponent);
