import { useCallback, useEffect, useRef, useState } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Popover } from "../../../shared/ui/Popover";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import "./ReadingSelectionMenu.css";

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
  /** Save a highlight; `note` opens it to write a note. Absent where nothing can be kept. */
  onMark?: (passage: FileSelection, note: boolean) => Promise<void>;
};

/**
 * The actions on selected text in any reader: Ask the mentor, Highlight, Note.
 * Quote (⌘L) and Comment (⌥⌘M) stay as shortcuts. The passage is kept while
 * focus moves to the comment field.
 */
export function ReadingSelectionMenu({ selection, onDismiss, resetKey, askLabel = "Ask", toChat, onMark }: Props) {
  const [commentSelection, setCommentSelection] = useState<FileSelection | null>(null);
  const [comment, setComment] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const commentRef = useRef<HTMLTextAreaElement>(null);
  const pendingRef = useRef(false);
  const actionRef = useRef(0);
  const previousKey = useRef(resetKey);
  const dismissRef = useRef(onDismiss);
  dismissRef.current = onDismiss;

  const close = useCallback(() => {
    actionRef.current += 1;
    pendingRef.current = false;
    setPending(false);
    setCommentSelection(null);
    setComment("");
    setError(null);
    window.getSelection()?.removeAllRanges();
    onDismiss();
  }, [onDismiss]);

  useEffect(() => {
    if (previousKey.current === resetKey) return;
    previousKey.current = resetKey;
    actionRef.current += 1;
    pendingRef.current = false;
    setPending(false);
    setCommentSelection(null);
    setComment("");
    setError(null);
    dismissRef.current();
  }, [resetKey]);

  useEffect(() => () => { actionRef.current += 1; }, []);

  useEffect(() => {
    if (commentSelection) commentRef.current?.focus({ preventScroll: true });
  }, [commentSelection]);

  useEffect(() => {
    if (!selection && !commentSelection) {
      actionRef.current += 1;
      pendingRef.current = false;
      setPending(false);
      setError(null);
    }
    if (!selection || commentSelection) return;
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    return () => {
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
    };
  }, [selection, commentSelection, close]);

  const run = async (action: (current: () => boolean) => Promise<void> | void, keepSelection = false) => {
    if (pendingRef.current) return;
    const turn = ++actionRef.current;
    const current = () => turn === actionRef.current;
    pendingRef.current = true;
    setPending(true);
    setError(null);
    try {
      await action(current);
      if (turn !== actionRef.current) return;
      if (keepSelection) {
        actionRef.current += 1;
        setCommentSelection(null);
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
  const send = (passage: FileSelection, intent: ChatIntent) => run((current) => toChat(passage, intent, current));
  const mark = (passage: FileSelection, note: boolean) => onMark ? run(() => onMark(passage, note), true) : undefined;

  useEffect(() => {
    if (!selection || commentSelection) return;
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
      if (isComment) { setError(null); setCommentSelection(selection); }
      else void send(selection, { kind: "quote" });
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  });

  const passage = commentSelection ?? selection;
  if (!passage) return null;
  const keep = (event: { preventDefault(): void }) => event.preventDefault();

  return (
    <Popover bare anchor={{ x: passage.rect.right, y: passage.rect.bottom }} side="bottom" align="start"
      onDismiss={close} role={commentSelection ? "dialog" : "toolbar"}
      aria-label={commentSelection ? "Comment on selected text" : "Selected text actions"}
      width={commentSelection ? 320 : undefined} className="document-selection-menu">
      {commentSelection ? (
        <form className="document-selection-menu__comment" onSubmit={(event) => {
          event.preventDefault();
          if (comment.trim()) void send(commentSelection, { kind: "comment", text: comment.trim() });
        }}>
          <blockquote>{commentSelection.text}</blockquote>
          <textarea ref={commentRef} aria-label="Comment" placeholder="Add a comment…" value={comment}
            disabled={pending} onChange={(event) => setComment(event.target.value)} />
          <footer>
            <button type="button" disabled={pending} onClick={close}>Cancel</button>
            <button type="submit" disabled={pending || !comment.trim()}>{pending ? "Adding…" : "Add to chat"}</button>
          </footer>
        </form>
      ) : (
        <div className="document-selection-menu__actions">
          <button type="button" disabled={pending} title={`Put this passage in a question, without sending it (Quote: ${IS_MAC ? "⌘L" : "Ctrl+L"}; Comment: ${IS_MAC ? "⌥⌘M" : "Ctrl+Alt+M"})`}
            onMouseDown={keep} onClick={() => void send(passage, { kind: "ask" })}>{askLabel}</button>
          {onMark ? <>
            <button type="button" disabled={pending} title="Keep this passage highlighted" onMouseDown={keep} onClick={() => void mark(passage, false)}>Highlight</button>
            <button type="button" disabled={pending} title="Highlight this passage and write a note on it" onMouseDown={keep} onClick={() => void mark(passage, true)}>Note</button>
          </> : null}
        </div>
      )}
      {error ? <p role="alert" className="document-selection-menu__error">Could not do that. {error}</p> : null}
    </Popover>
  );
}
