import { memo, useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import type { Note } from "../notes";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { Globe, GripVertical, X } from "../../../shared/ui/icons";

type Props = {
  note: Note;
  focused: boolean;
  onFocus: () => void;
  onClose: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  onAddToChat: (text: string) => void;
};

function SourcePaneComponent({ note, focused, onFocus, onClose, onPaneDragStart, onAddToChat }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [selection, setSelection] = useState<{ text: string; x: number; y: number } | null>(null);

  const handleAddAllToChat = useCallback(() => {
    const text = note.body.trim();
    if (text) onAddToChat(`[Source: "${note.title}"]\n\n${text}`);
  }, [note.body, note.title, onAddToChat]);

  useEffect(() => {
    const handleMouseUp = () => {
      const sel = window.getSelection();
      const text = sel?.toString().trim();
      if (!text || !sel?.rangeCount) { setSelection(null); return; }
      const container = containerRef.current;
      if (!container) { setSelection(null); return; }
      const anchorNode = sel.anchorNode;
      if (!anchorNode || !container.contains(anchorNode)) { setSelection(null); return; }
      const range = sel.getRangeAt(0);
      const rect = range.getBoundingClientRect();
      const parentRect = container.getBoundingClientRect();
      setSelection({
        text,
        x: rect.left + rect.width / 2 - parentRect.left,
        y: rect.top - parentRect.top - 8,
      });
    };
    document.addEventListener("mouseup", handleMouseUp);
    return () => document.removeEventListener("mouseup", handleMouseUp);
  }, []);

  const handleSelectionAddToChat = useCallback(() => {
    if (!selection) return;
    onAddToChat(`[Source: "${note.title}"]\n\n${selection.text}`);
    window.getSelection()?.removeAllRanges();
    setSelection(null);
  }, [note.title, onAddToChat, selection]);

  return (
    <div
      ref={containerRef}
      className="relative flex h-full min-h-0 min-w-0 flex-col"
      onPointerDown={() => !focused && onFocus()}
    >
      {/* Toolbar */}
      <div className={`flex h-9 shrink-0 select-none items-center gap-1.5 border-b border-stroke px-2 ${onPaneDragStart ? "cursor-grab active:cursor-grabbing touch-none" : ""}`} onPointerDown={(event) => { if (!(event.target as HTMLElement).closest("[data-no-drag]")) onPaneDragStart?.(event); }}>
        {onPaneDragStart ? <GripVertical className="size-3.5 text-content/35" /> : <Globe className="size-3.5 text-content/45" />}
        <span className="min-w-0 flex-1 truncate text-xs text-content">
          {note.title}
        </span>
        {note.sourceUrl ? (
          <a
            data-no-drag
            href={note.sourceUrl}
            target="_blank"
            rel="noreferrer"
            className="shrink-0 rounded p-1 text-content/40 hover:bg-content/10 hover:text-content"
            title={note.sourceUrl}
          >
            <Globe className="size-3.5" strokeWidth={1.75} />
          </a>
        ) : null}
        <button
          data-no-drag
          className="shrink-0 rounded px-2 py-1 text-xs text-content/55 hover:bg-content/10 hover:text-content"
          onClick={handleAddAllToChat}
          title="Add full source to chat"
        >
          Add to Chat
        </button>
        <button type="button" data-no-drag aria-label="Close pane" title="Close pane" onClick={onClose} className="grid size-5 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"><X className="size-3" /></button>
      </div>

      {/* Content */}
      <div className="min-h-0 flex-1 overflow-y-auto px-6 py-4">
        <AgentMarkdown text={note.body} />
      </div>

      {/* Selection mini-toolbar */}
      {selection ? (
        <div
          className="pointer-events-auto absolute z-50 -translate-x-1/2 -translate-y-full"
          style={{ left: selection.x, top: selection.y }}
        >
          <div className="flex items-center gap-1 rounded-md border border-stroke bg-background-base px-1 py-0.5 shadow-md">
            <button
              className="rounded px-2 py-0.5 text-xs text-content hover:bg-content/10"
              onMouseDown={(e) => e.preventDefault()}
              onClick={handleSelectionAddToChat}
            >
              Add to Chat
            </button>
            <button
              className="rounded p-0.5 text-content/40 hover:text-content"
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => setSelection(null)}
            >
              <X className="size-3" strokeWidth={2} />
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

export const SourcePane = memo(SourcePaneComponent);
