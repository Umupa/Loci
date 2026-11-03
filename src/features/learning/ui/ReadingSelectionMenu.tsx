import { useCallback, useEffect, useRef, useState } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Highlighter, MessageSquarePlus } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { ToolbarButton, ToolbarDivider } from "./ReadingToolbar";

/** What a passage goes to the chat as: a question, a bare quote, or a comment on it (the reader's own note). */
export type ChatIntent = { kind: "ask" } | { kind: "quote" } | { kind: "comment"; text: string };

type Props = {
  selection: FileSelection | null;
  onDismiss: () => void;
  /** Changes when the text being read changes: a captured passage no longer belongs to it. */
  resetKey: string;
  /** "Ask Kern", for the mentor beside the reader. */
  askLabel?: string;
  /**
   * Put the passage in the composer's draft. Nothing is sent. `current` turns
   * false once the menu was dismissed or its text changed: then nothing is added.
   */
  toChat: (passage: FileSelection, intent: ChatIntent, current: () => boolean) => Promise<void> | void;
  /** Keep the passage highlighted, which is keeping it in the course's excerpts. Absent where nothing can be kept. */
  onMark?: (passage: FileSelection) => Promise<void>;
  /** More actions after those, such as Definition and References in code. */
  actions?: readonly SelectionAction[];
};

/** An action on the selected passage, shown after the reading actions. */
export type SelectionAction = { label: string; title?: string; run: (passage: FileSelection) => Promise<void> | void };

/**
 * The bar on selected text in any reader, and the same as in a conversation:
 * Highlight (H) keeps it, Ask (⌘L) quotes it in the chat for a question. A
 * highlight is the note: its own bar takes a thought on it. Copy is ⌘C.
 */
export function ReadingSelectionMenu({ selection, onDismiss, resetKey, askLabel = "Ask", toChat, onMark, actions }: Props) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pendingRef = useRef(false);
  const actionRef = useRef(0);
  const previousKey = useRef(resetKey);
  const dismissRef = useRef(onDismiss);
  dismissRef.current = onDismiss;

  const reset = () => {
    actionRef.current += 1;
    pendingRef.current = false;
    setPending(false);
    setError(null);
  };

  const close = useCallback(() => {
    reset();
    window.getSelection()?.removeAllRanges();
    onDismiss();
  }, [onDismiss]);

  useEffect(() => {
    if (previousKey.current === resetKey) return;
    previousKey.current = resetKey;
    reset();
    dismissRef.current();
  }, [resetKey]);

  useEffect(() => () => { actionRef.current += 1; }, []);

  useEffect(() => {
    if (!selection) { reset(); return; }
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    return () => {
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
    };
  }, [selection, close]);

  const run = async (action: (current: () => boolean) => Promise<unknown> | unknown) => {
    if (pendingRef.current) return;
    const turn = ++actionRef.current;
    const current = () => turn === actionRef.current;
    pendingRef.current = true;
    setPending(true);
    setError(null);
    try {
      await action(current);
      if (turn === actionRef.current) close();
    } catch (cause) {
      if (turn === actionRef.current) setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      if (turn === actionRef.current) {
        pendingRef.current = false;
        setPending(false);
      }
    }
  };
  const ask = (shown: FileSelection) => run((current) => toChat(shown, { kind: "ask" }, current));
  const mark = onMark ? (shown: FileSelection) => run(() => onMark(shown)) : undefined;

  useEffect(() => {
    if (!selection) return;
    const key = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.repeat || isImeComposition(event) || pendingRef.current) return;
      if (window.document.querySelector('[data-shortcut-recorder-active="true"]')) return;
      if (event.target instanceof Element && event.target.closest('input, textarea, select, [contenteditable="true"]')) return;
      const mod = IS_MAC ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
      const plain = !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
      const isMark = plain && event.code === "KeyH" && !!mark;
      const isAsk = mod && !event.altKey && !event.shiftKey && event.code === "KeyL";
      if (!isMark && !isAsk) return;
      event.preventDefault();
      event.stopPropagation();
      if (isMark) void mark!(selection);
      else void ask(selection);
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  });

  if (!selection) return null;

  return (
    <Popover bare anchor={{ x: selection.rect.right, y: selection.rect.bottom }} side="bottom" align="start"
      onDismiss={close} role="toolbar" aria-label="Selected text actions" className="reading-toolbar">
      <div className="reading-toolbar__actions">
        {mark ? <ToolbarButton icon={<Highlighter className="size-3.5" />} label="Highlight" title="Keep this passage (H)"
          disabled={pending} onClick={() => void mark(selection)} /> : null}
        <ToolbarButton icon={<MessageSquarePlus className="size-3.5" />} label={askLabel} disabled={pending}
          title={`Quote this passage in the chat and write your question (${IS_MAC ? "⌘L" : "Ctrl+L"})`}
          onClick={() => void ask(selection)} />
        {actions?.length ? <ToolbarDivider /> : null}
        {actions?.map((action) => <button key={action.label} type="button" className="reading-toolbar__button" disabled={pending} title={action.title}
          onMouseDown={(event) => event.preventDefault()} onClick={() => void run(() => action.run(selection))}>{action.label}</button>)}
      </div>
      {error ? <p role="alert" className="reading-toolbar__error">Could not do that. {error}</p> : null}
    </Popover>
  );
}
