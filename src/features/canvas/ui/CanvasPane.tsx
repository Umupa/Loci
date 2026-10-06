import "@excalidraw/excalidraw/index.css";
import { Excalidraw } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI, ExcalidrawProps } from "@excalidraw/excalidraw/types";
type OnChangeCb = NonNullable<ExcalidrawProps["onChange"]>;
type ExcalidrawElements = Parameters<OnChangeCb>[0];
type AppState = Parameters<OnChangeCb>[1];
type BinaryFiles = Parameters<OnChangeCb>[2];
import {
  memo,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import type { Canvas } from "../canvas";
import { canvasElementsToText, upsertCanvas } from "../canvas";

const SAVE_DEBOUNCE_MS = 1500;

type Props = {
  canvas: Canvas;
  focused: boolean;
  onFocus: () => void;
  onAddToChat: (text: string) => void;
  onTitleChange: (id: string, title: string) => void;
  onRegisterAppend?: (canvasId: string, fn: (text: string) => void) => void;
};

function CanvasPaneComponent({ canvas, focused, onFocus, onAddToChat, onTitleChange, onRegisterAppend }: Props) {
  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latestDataRef = useRef<{ elements: ExcalidrawElements; appState: AppState; files: BinaryFiles } | null>(null);
  const [isDark, setIsDark] = useState(
    () => !document.documentElement.classList.contains("theme-light"),
  );
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState(canvas.title);

  // Track theme changes
  useEffect(() => {
    const observer = new MutationObserver(() => {
      setIsDark(!document.documentElement.classList.contains("theme-light"));
    });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    return () => observer.disconnect();
  }, []);

  const scheduleSave = useCallback(() => {
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      const data = latestDataRef.current;
      if (!data) return;
      const dataJson = JSON.stringify({
        elements: data.elements,
        appState: {
          viewBackgroundColor: data.appState.viewBackgroundColor,
          currentItemFontFamily: data.appState.currentItemFontFamily,
        },
        files: data.files,
      });
      upsertCanvas({ id: canvas.id, title: canvas.title, dataJson, tags: canvas.tags, cwd: canvas.cwd });
    }, SAVE_DEBOUNCE_MS);
  }, [canvas.id, canvas.title, canvas.tags, canvas.cwd]);

  const handleChange = useCallback(
    (elements: ExcalidrawElements, appState: AppState, files: BinaryFiles) => {
      latestDataRef.current = { elements, appState, files };
      scheduleSave();
    },
    [scheduleSave],
  );

  const onRegisterAppendRef = useRef(onRegisterAppend);
  onRegisterAppendRef.current = onRegisterAppend;

  const appendText = useCallback((text: string) => {
    const api = apiRef.current;
    if (!api) return;
    const existing = api.getSceneElements();
    const maxY = existing.reduce((acc, el) => Math.max(acc, el.y + el.height), 0);
    const newEl = {
      type: "text",
      id: crypto.randomUUID(),
      x: 40,
      y: maxY + 40,
      width: 500,
      height: 100,
      angle: 0,
      strokeColor: "#1e1e1e",
      backgroundColor: "transparent",
      fillStyle: "solid" as const,
      strokeWidth: 1,
      strokeStyle: "solid" as const,
      roughness: 1,
      opacity: 100,
      groupIds: [],
      frameId: null,
      roundness: null,
      seed: Math.floor(Math.random() * 100000),
      version: 1,
      versionNonce: Math.floor(Math.random() * 100000),
      index: null,
      isDeleted: false,
      boundElements: null,
      updated: Date.now(),
      link: null,
      locked: false,
      text,
      originalText: text,
      fontSize: 16,
      fontFamily: 1,
      textAlign: "left" as const,
      verticalAlign: "top" as const,
      containerId: null,
      autoResize: true,
      lineHeight: 1.25,
    };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    api.updateScene({ elements: [...existing, newEl as any] });
  }, []);

  useEffect(() => {
    if (!onRegisterAppendRef.current) return;
    const waitForApi = setInterval(() => {
      if (!apiRef.current) return;
      clearInterval(waitForApi);
      onRegisterAppendRef.current?.(canvas.id, appendText);
    }, 100);
    return () => clearInterval(waitForApi);
  }, [canvas.id, appendText]);

  const handleAddToChat = useCallback(() => {
    const api = apiRef.current;
    if (!api) return;
    const allElements = api.getSceneElements();
    const appState = api.getAppState();
    const selectedIds = appState.selectedElementIds ?? {};
    const selected = Object.keys(selectedIds);
    const target = selected.length > 0
      ? allElements.filter((el) => selectedIds[el.id])
      : allElements;
    const text = canvasElementsToText(canvas.title, JSON.stringify(target, null, 2));
    onAddToChat(text);
  }, [canvas.title, onAddToChat]);

  const handleTitleBlur = useCallback(() => {
    setEditingTitle(false);
    const trimmed = titleDraft.trim() || "Untitled Canvas";
    if (trimmed !== canvas.title) {
      onTitleChange(canvas.id, trimmed);
    }
  }, [canvas.id, canvas.title, titleDraft, onTitleChange]);

  const parsedData = (() => {
    try {
      return JSON.parse(canvas.dataJson);
    } catch {
      return { elements: [], appState: {}, files: {} };
    }
  })();

  return (
    <div
      className="flex h-full min-h-0 min-w-0 flex-col"
      onPointerDown={() => !focused && onFocus()}
    >
      {/* Toolbar */}
      <div className="flex h-10 shrink-0 items-center gap-2 border-b border-[--border] px-3">
        {editingTitle ? (
          <input
            autoFocus
            className="min-w-0 flex-1 bg-transparent text-sm font-medium text-[--text-1] outline-none"
            value={titleDraft}
            onChange={(e) => setTitleDraft(e.target.value)}
            onBlur={handleTitleBlur}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === "Escape") e.currentTarget.blur();
            }}
          />
        ) : (
          <button
            className="min-w-0 flex-1 truncate text-left text-sm font-medium text-[--text-1] hover:text-[--text-2]"
            onDoubleClick={() => {
              setTitleDraft(canvas.title);
              setEditingTitle(true);
            }}
            title="Double-click to rename"
          >
            {canvas.title}
          </button>
        )}
        <button
          className="shrink-0 rounded px-2 py-1 text-xs text-[--text-3] hover:bg-[--bg-2] hover:text-[--text-1]"
          onClick={handleAddToChat}
          title="Add canvas to chat"
        >
          Add to Chat
        </button>
      </div>

      {/* Canvas */}
      <div className="min-h-0 flex-1">
        <Excalidraw
          key={canvas.id}
          excalidrawAPI={(api) => { apiRef.current = api; }}
          initialData={parsedData}
          onChange={handleChange}
          theme={isDark ? "dark" : "light"}
          UIOptions={{
            canvasActions: {
              saveAsImage: false,
              loadScene: false,
            },
          }}
        />
      </div>
    </div>
  );
}

export const CanvasPane = memo(CanvasPaneComponent);
