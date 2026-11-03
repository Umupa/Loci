import { useEffect, useRef, useState } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Highlighter, MessageSquarePlus } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import { ToolbarButton } from "../../learning/ui/ReadingToolbar";
import { type TranscriptSelection } from "../model/transcriptSelection";

type Props = {
  selection: TranscriptSelection | null;
  /** Ask: the passage goes into the reply being written, quoted. */
  onAddToChat?: (text: string, blockId?: string) => void;
  /** Highlight: the passage is kept in the mentor's highlights, without asking where. */
  onKeep?: (text: string) => void | Promise<unknown>;
  onDismiss: () => void;
};

/**
 * The bar on text selected in a conversation: the reader's own two actions,
 * Highlight (H) and Ask (⌘L). Nothing asks which note.
 */
export function TranscriptSelectionMenu({ selection, onAddToChat, onKeep, onDismiss }: Props) {
  const onDismissRef = useRef(onDismiss);
  onDismissRef.current = onDismiss;
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setError(null); }, [selection]);

  // Scrolling or resizing moves the text out from under the menu, so the
  // selection it acts on is gone; drop it rather than chase the range.
  useEffect(() => {
    if (!selection) return;
    const dismiss = () => onDismissRef.current();
    window.addEventListener("scroll", dismiss, true);
    window.addEventListener("resize", dismiss);
    return () => {
      window.removeEventListener("scroll", dismiss, true);
      window.removeEventListener("resize", dismiss);
    };
  }, [selection]);

  const run = async (action: () => unknown) => {
    if (pending) return;
    setPending(true);
    setError(null);
    try {
      await action();
      window.getSelection()?.removeAllRanges();
      onDismissRef.current();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setPending(false);
    }
  };
  const keep = selection && onKeep ? () => void run(() => onKeep(selection.text)) : undefined;
  const ask = selection && onAddToChat ? () => void run(() => onAddToChat(selection.text, selection.blockId)) : undefined;
  const keys = useRef({ keep, ask });
  keys.current = { keep, ask };

  useEffect(() => {
    if (!selection) return;
    const key = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.repeat || isImeComposition(event)) return;
      if (event.target instanceof Element && event.target.closest('input, textarea, select, [contenteditable="true"]')) return;
      const mod = IS_MAC ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
      const plain = !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
      const action = plain && event.code === "KeyH" ? keys.current.keep
        : mod && !event.altKey && !event.shiftKey && event.code === "KeyL" ? keys.current.ask : undefined;
      if (!action) return;
      event.preventDefault();
      event.stopPropagation();
      action();
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, [selection]);

  if (!selection || (!keep && !ask)) return null;
  return (
    <Popover anchor={selection.rect} side="top" align="center" bare
      onDismiss={(reason) => {
        if (reason === "escape") window.getSelection()?.removeAllRanges();
        onDismiss();
      }}
      role="toolbar" aria-label="Selected text actions" className="reading-toolbar">
      <div className="reading-toolbar__actions">
        {keep ? <ToolbarButton icon={<Highlighter className="size-3.5" />} label="Highlight" title="Keep in this mentor's highlights (H)"
          disabled={pending} onClick={keep} /> : null}
        {ask ? <ToolbarButton icon={<MessageSquarePlus className="size-3.5" />} label="Ask" title={`Quote in your reply (${IS_MAC ? "⌘L" : "Ctrl+L"})`}
          disabled={pending} onClick={ask} /> : null}
      </div>
      {error ? <p role="alert" className="reading-toolbar__error">Could not do that. {error}</p> : null}
    </Popover>
  );
}
