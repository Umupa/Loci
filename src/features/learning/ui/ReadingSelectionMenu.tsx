import { useCallback, useEffect, useRef, useState } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { copyText } from "../../../platform/tauri/clipboard";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Copy, Highlighter, MessageSquarePlus } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { quoteMarkdown, saveQuoteToNote } from "../model/quoteNote";
import { ToolbarButton, ToolbarDivider, useSaveToNote, type NoteShelf } from "./ReadingToolbar";

/** What a passage goes to the chat as: a question, a bare quote, or a comment on it. */
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
  /** Keep the passage highlighted; its own bar opens on it. Absent where nothing can be kept. */
  onMark?: (passage: FileSelection) => Promise<void>;
  /** The passage as Markdown, linked back to where it was read, for a note or the clipboard. */
  quote?: (passage: FileSelection) => Promise<string>;
  /** Where Save to note puts the passage. */
  notes?: NoteShelf;
  /** More actions after those, such as Definition and References in code. */
  actions?: readonly SelectionAction[];
};

/** An action on the selected passage, shown after the reading actions. */
export type SelectionAction = { label: string; title?: string; run: (passage: FileSelection) => Promise<void> | void };

const plainQuote = async (passage: FileSelection) => quoteMarkdown(passage.text);

/**
 * The bar on selected text in any reader: Highlight, Ask the mentor, Save to
 * note, Copy. Quote (⌘L) and Comment (⌥⌘M) stay as shortcuts. The passage is
 * held while focus moves into the comment field or the note picker, which
 * clears the native selection.
 */
export function ReadingSelectionMenu({ selection, onDismiss, resetKey, askLabel = "Ask", toChat, onMark, quote = plainQuote, notes, actions }: Props) {
  const [held, setHeld] = useState<{ passage: FileSelection; for: "comment" | "note" } | null>(null);
  const [comment, setComment] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const commentRef = useRef<HTMLTextAreaElement>(null);
  const pendingRef = useRef(false);
  const actionRef = useRef(0);
  const previousKey = useRef(resetKey);
  const dismissRef = useRef(onDismiss);
  dismissRef.current = onDismiss;
  const passage = held?.passage ?? selection;
  const passageRef = useRef(passage);
  passageRef.current = passage;
  const saving = useSaveToNote(notes, async (target) => {
    const shown = passageRef.current;
    if (!shown) throw new Error("The passage is no longer selected.");
    return saveQuoteToNote(await quote(shown), shown.text, target, notes?.agentId);
  });
  const savingRef = useRef(saving);
  savingRef.current = saving;

  const reset = () => {
    actionRef.current += 1;
    pendingRef.current = false;
    setPending(false);
    setHeld(null);
    setComment("");
    setError(null);
    savingRef.current.cancel();
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
    if (held?.for === "comment") commentRef.current?.focus({ preventScroll: true });
  }, [held]);

  // The picker holds the passage while it is open (it takes focus, which clears
  // the selection); closed with Back, the bar is on the selection again, or gone.
  useEffect(() => {
    if (saving.picking && !held && selection) setHeld({ passage: selection, for: "note" });
    if (held?.for === "note" && !saving.picking) setHeld(null);
  }, [held, selection, saving.picking]);

  useEffect(() => {
    if (!selection && !held) {
      actionRef.current += 1;
      pendingRef.current = false;
      setPending(false);
      setError(null);
    }
    if (!selection || held) return;
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    return () => {
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
    };
  }, [selection, held, close]);

  /**
   * `then`: what follows a finished action; a highlight leaves the passage to
   * its own bar. An action that resolves `false` moved on to another step.
   */
  const run = async (action: (current: () => boolean) => Promise<unknown> | unknown, then: "close" | "release" = "close") => {
    if (pendingRef.current) return;
    const turn = ++actionRef.current;
    const current = () => turn === actionRef.current;
    pendingRef.current = true;
    setPending(true);
    setError(null);
    try {
      const result = await action(current);
      if (turn !== actionRef.current || result === false) return;
      if (then === "release") {
        actionRef.current += 1;
        setHeld(null);
        window.getSelection()?.removeAllRanges();
        onDismiss();
      } else close();
    } catch (cause) {
      if (turn === actionRef.current) setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      if (turn === actionRef.current) {
        pendingRef.current = false;
        setPending(false);
      }
    }
  };
  const send = (shown: FileSelection, intent: ChatIntent) => run((current) => toChat(shown, intent, current));
  // When it asks which note instead, the picker takes over the bar.
  const saveToNote = () => run(async () => await savingRef.current.run() ? undefined : false);

  useEffect(() => {
    if (!selection || held) return;
    const key = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.repeat || isImeComposition(event) || pendingRef.current) return;
      if (window.document.querySelector('[data-shortcut-recorder-active="true"]')) return;
      if (event.target instanceof Element && event.target.closest('input, textarea, select, [contenteditable="true"]')) return;
      const mod = IS_MAC ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
      if (!mod || event.shiftKey) return;
      const isComment = event.altKey && event.code === "KeyM";
      const isQuote = !event.altKey && event.code === "KeyL";
      if (!isComment && !isQuote) return;
      event.preventDefault();
      event.stopPropagation();
      if (isComment) { setError(null); setHeld({ passage: selection, for: "comment" }); }
      else void send(selection, { kind: "quote" });
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  });

  if (!passage) return null;
  const commenting = held?.for === "comment";
  const picker = saving.picker(close);

  return (
    <Popover bare anchor={{ x: passage.rect.right, y: passage.rect.bottom }} side="bottom" align="start"
      onDismiss={close} role={commenting ? "dialog" : "toolbar"}
      aria-label={commenting ? "Comment on selected text" : "Selected text actions"}
      width={commenting ? 320 : undefined} className="reading-toolbar">
      {commenting ? (
        <form className="reading-toolbar__comment" onSubmit={(event) => {
          event.preventDefault();
          if (comment.trim()) void send(passage, { kind: "comment", text: comment.trim() });
        }}>
          <blockquote>{passage.text}</blockquote>
          <textarea ref={commentRef} aria-label="Comment" placeholder="Add a comment…" value={comment}
            disabled={pending} onChange={(event) => setComment(event.target.value)} />
          <footer>
            <button type="button" disabled={pending} onClick={close}>Cancel</button>
            <button type="submit" disabled={pending || !comment.trim()}>{pending ? "Adding…" : "Add to chat"}</button>
          </footer>
        </form>
      ) : picker ? <div className="reading-toolbar__picker">{picker}</div> : (
        <div className="reading-toolbar__actions">
          {onMark ? <ToolbarButton icon={<Highlighter className="size-3.5" />} label="Highlight" title="Keep this passage highlighted"
            disabled={pending} onClick={() => void run(() => onMark(passage), "release")} /> : null}
          <ToolbarButton icon={<MessageSquarePlus className="size-3.5" />} label={askLabel} disabled={pending}
            title={`Quote this passage in the chat and write your question (Quote: ${IS_MAC ? "⌘L" : "Ctrl+L"}; Comment: ${IS_MAC ? "⌥⌘M" : "Ctrl+Alt+M"})`}
            onClick={() => void send(passage, { kind: "ask" })} />
          {saving.button(() => void saveToNote(), pending)}
          <ToolbarButton icon={<Copy className="size-3.5" />} label="Copy quote" iconOnly disabled={pending}
            title="Copy as a Markdown quote, with a link back here" onClick={() => void run(async () => copyText(await quote(passage)))} />
          {actions?.length ? <ToolbarDivider /> : null}
          {actions?.map((action) => <button key={action.label} type="button" className="reading-toolbar__button" disabled={pending} title={action.title}
            onMouseDown={(event) => event.preventDefault()} onClick={() => void run(() => action.run(passage))}>{action.label}</button>)}
        </div>
      )}
      {error ? <p role="alert" className="reading-toolbar__error">Could not do that. {error}</p> : null}
    </Popover>
  );
}
