import { useCallback, useEffect, useRef, useState } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Popover } from "../../../shared/ui/Popover";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { registerLearningSource } from "../../learning/model/learningStore";
import type { AgentDocument } from "../../sessions/model/cards";
import { appendSelectionQuote, requestAddToChat } from "../../sessions/model/quoteDraft";
import { findAgent } from "../model/agent";
import "./DocumentSelectionMenu.css";

type Props = {
  document: AgentDocument;
  agentId?: string;
  selection: FileSelection | null;
  onDismiss: () => void;
};

/** Keep a passage available while focus moves from the document to its comment. */
export function DocumentSelectionMenu({ document, agentId, selection, onDismiss }: Props) {
  const [commentSelection, setCommentSelection] = useState<FileSelection | null>(null);
  const [comment, setComment] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const commentRef = useRef<HTMLTextAreaElement>(null);
  const pendingRef = useRef(false);
  const actionRef = useRef(0);
  const previousContext = useRef({ document, agentId });
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
    const previous = previousContext.current;
    previousContext.current = { document, agentId };
    if (previous.document.id === document.id && previous.document.body === document.body
      && previous.document.title === document.title && previous.document.sourceUrl === document.sourceUrl
      && previous.agentId === agentId) return;
    actionRef.current += 1;
    pendingRef.current = false;
    setPending(false);
    setCommentSelection(null);
    setComment("");
    setError(null);
    dismissRef.current();
  }, [document.id, document.body, document.title, document.sourceUrl, agentId]);

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

  const addToChat = async (passage: FileSelection, followUp?: string) => {
    if (pendingRef.current) return;
    const action = ++actionRef.current;
    pendingRef.current = true;
    setPending(true);
    setError(null);
    try {
      const targetSessionId = agentId ? findAgent(agentId)?.sessionId : undefined;
      const target = targetSessionId ? { targetSessionId } : undefined;
      if (document.sourceUrl) {
        const source = { id: crypto.randomUUID(), kind: "web" as const, url: document.sourceUrl, title: document.title, quote: passage.text };
        await registerLearningSource(source);
        if (action !== actionRef.current) return;
        requestAddToChat(followUp ?? "", "plain", { sources: [source], ...target });
      } else if (followUp !== undefined) {
        requestAddToChat(appendSelectionQuote("", passage.text) + followUp, "plain", target);
      } else {
        requestAddToChat(passage.text, "quote", target);
      }
      close();
    } catch (cause) {
      if (action === actionRef.current) setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      if (action === actionRef.current) {
        pendingRef.current = false;
        setPending(false);
      }
    }
  };

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
      else void addToChat(selection);
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  });

  const passage = commentSelection ?? selection;
  if (!passage) return null;

  return (
    <Popover bare anchor={{ x: passage.rect.right, y: passage.rect.bottom }} side="bottom" align="start"
      onDismiss={close} role={commentSelection ? "dialog" : "toolbar"}
      aria-label={commentSelection ? "Comment on selected text" : "Selected document text actions"}
      width={commentSelection ? 320 : undefined} className="document-selection-menu">
      {commentSelection ? (
        <form className="document-selection-menu__comment" onSubmit={(event) => {
          event.preventDefault();
          if (comment.trim()) void addToChat(commentSelection, comment.trim());
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
          <button type="button" disabled={pending} title="Ask about this passage"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => void addToChat(passage, "请解释这段内容。")}>Ask</button>
          <button type="button" disabled={pending} aria-keyshortcuts={IS_MAC ? "Alt+Meta+M" : "Alt+Control+M"}
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => { setError(null); setCommentSelection(selection); }}>
            <span>Comment</span><kbd>{IS_MAC ? "⌥ ⌘ M" : "Ctrl+Alt+M"}</kbd>
          </button>
          <button type="button" disabled={pending} aria-keyshortcuts={IS_MAC ? "Meta+L" : "Control+L"}
            onMouseDown={(event) => event.preventDefault()} onClick={() => void addToChat(passage)}>
            <span>Quote</span><kbd>{IS_MAC ? "⌘ L" : "Ctrl+L"}</kbd>
          </button>
        </div>
      )}
      {error ? <p role="alert" className="document-selection-menu__error">Could not add to chat. {error}</p> : null}
    </Popover>
  );
}
