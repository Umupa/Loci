import { useEffect, useRef, useState, type RefObject } from "react";
import { createPortal } from "react-dom";
import { copyText } from "../../../platform/tauri/clipboard";
import { Copy, Highlighter, MessageSquarePlus } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import type { Note } from "../../notes/notes";
import type { NoteTarget } from "../../notes/noteTarget";
import { BLOCK_SELECTOR } from "../model/blockAnchor";
import { ToolbarButton, useSaveToNote, type NoteShelf } from "./ReadingToolbar";

/*
 * A whole block (a table, a diagram, a code block, a picture, an area drawn
 * on a PDF page) has the selection's bar: Highlight · Ask · Save to note ·
 * Copy. What each action takes from the block is the reader's to say.
 */

type Props = {
  anchor: DOMRect;
  /** "Table actions": what the bar is for, to a screen reader. */
  label: string;
  askLabel?: string;
  notes?: NoteShelf;
  onDismiss: () => void;
  /** Keep the block highlighted; its own bar opens on it. Absent where nothing can be kept. */
  onMark?: () => Promise<void>;
  /** Put the block in the composer's draft. */
  onAsk: () => Promise<void> | void;
  /** Add the block to a note, or start one with it. */
  save: (target: NoteTarget) => Promise<Note>;
  /** The block as Markdown, for the clipboard. */
  copy: () => Promise<string>;
};

export function BlockToolbar({ anchor, label, askLabel = "Ask", notes, onDismiss, onMark, onAsk, save, copy }: Props) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const saving = useSaveToNote(notes, save);
  const run = async (action: () => Promise<unknown> | unknown) => {
    setPending(true); setError(null);
    try {
      // An action that resolves `false` moved on to another step (the note picker).
      if (await action() !== false) onDismiss();
    } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setPending(false); }
  };
  const picker = saving.picker(onDismiss);
  return <Popover bare anchor={anchor} side="bottom" align="start" onDismiss={onDismiss} role="toolbar" aria-label={label} className="reading-toolbar">
    {picker ? <div className="reading-toolbar__picker">{picker}</div> : <div className="reading-toolbar__actions">
      {onMark ? <ToolbarButton icon={<Highlighter className="size-3.5" />} label="Highlight" title="Keep this block highlighted"
        disabled={pending} onClick={() => void run(onMark)} /> : null}
      <ToolbarButton icon={<MessageSquarePlus className="size-3.5" />} label={askLabel} disabled={pending}
        title="Put this block in the chat, as written, and write your question" onClick={() => void run(onAsk)} />
      {saving.button(() => void run(async () => await saving.run() ? undefined : false), pending)}
      <ToolbarButton icon={<Copy className="size-3.5" />} label="Copy as Markdown" iconOnly disabled={pending}
        title="Copy as Markdown, with a link back here" onClick={() => void run(async () => copyText(await copy()))} />
    </div>}
    {error ? <p role="alert" className="reading-toolbar__error">Could not do that. {error}</p> : null}
  </Popover>;
}

const HANDLE = 22;
const GAP = 6;
const HIDE_AFTER_MS = 220;

/**
 * The small handle a block shows while the pointer is on it: in the margin to
 * its left when there is room, else just inside its top-left corner. It stays
 * at the top of a tall block scrolled part way out of view.
 */
export function BlockHandle({ root, enabled = true, marked, onOpen }: {
  root: RefObject<HTMLElement | null>;
  enabled?: boolean;
  /** Whether the block already has a highlight: the handle says so. */
  marked: (block: Element) => boolean;
  onOpen: (block: HTMLElement, at: DOMRect) => void;
}) {
  const [shown, setShown] = useState<{ block: HTMLElement; x: number; y: number } | null>(null);
  const hideTimer = useRef(0);
  const shownRef = useRef(shown);
  shownRef.current = shown;

  useEffect(() => {
    const element = root.current;
    setShown(null);
    if (!element || !enabled) return;
    const place = (block: HTMLElement) => {
      if (!block.isConnected) return null;
      const rect = block.getBoundingClientRect();
      const bound = (block.closest("[data-reading-scroll]") ?? element).getBoundingClientRect();
      const outside = rect.left - HANDLE - GAP >= bound.left + 2;
      const top = Math.max(rect.top + (outside ? 2 : GAP), bound.top + GAP);
      if (top > rect.bottom - HANDLE || top > bound.bottom - HANDLE) return null;
      return { block, x: outside ? rect.left - HANDLE - GAP : rect.left + GAP, y: top };
    };
    const over = (event: PointerEvent) => {
      const target = event.target instanceof Element ? event.target : null;
      const block = target?.closest<HTMLElement>(BLOCK_SELECTOR);
      if (!block || !element.contains(block)) return;
      window.clearTimeout(hideTimer.current);
      if (shownRef.current?.block !== block) setShown(place(block));
    };
    const out = (event: PointerEvent) => {
      const next = event.relatedTarget instanceof Element ? event.relatedTarget : null;
      if (next?.closest("[data-block-handle]")) return;
      const block = shownRef.current?.block;
      if (block && next && block.contains(next)) return;
      window.clearTimeout(hideTimer.current);
      hideTimer.current = window.setTimeout(() => setShown(null), HIDE_AFTER_MS);
    };
    const follow = () => setShown((current) => current ? place(current.block) : current);
    element.addEventListener("pointerover", over);
    element.addEventListener("pointerout", out);
    window.addEventListener("scroll", follow, true);
    window.addEventListener("resize", follow);
    return () => {
      window.clearTimeout(hideTimer.current);
      element.removeEventListener("pointerover", over);
      element.removeEventListener("pointerout", out);
      window.removeEventListener("scroll", follow, true);
      window.removeEventListener("resize", follow);
    };
  }, [root, enabled]);

  if (!shown) return null;
  const isMarked = marked(shown.block);
  return createPortal(<button type="button" data-block-handle className="block-handle" data-marked={isMarked ? "" : undefined}
    style={{ left: shown.x, top: shown.y }}
    aria-label={isMarked ? "Highlight actions" : "Block actions"} title={isMarked ? "This block is highlighted: note, ask, save or delete" : "Highlight, ask about or save this block"}
    onPointerEnter={() => window.clearTimeout(hideTimer.current)}
    onPointerLeave={(event) => {
      if (event.relatedTarget instanceof Node && shown.block.contains(event.relatedTarget)) return;
      hideTimer.current = window.setTimeout(() => setShown(null), HIDE_AFTER_MS);
    }}
    onMouseDown={(event) => event.preventDefault()}
    onClick={(event) => onOpen(shown.block, event.currentTarget.getBoundingClientRect())}>
    <Highlighter className="size-3.5" />
  </button>, document.body);
}
