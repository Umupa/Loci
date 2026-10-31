import { useCallback, useEffect, useState, type ReactNode, type RefObject } from "react";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { Popover, type PopoverAnchor } from "../../../shared/ui/Popover";
import { findAgent } from "../../agents/model/agent";
import { appendSelectionQuote, requestAddToChat } from "../../sessions/model/quoteDraft";
import { deleteAnnotation, listAnnotations, registerLearningSource, subscribeLearningChanges, upsertAnnotation } from "../model/learningStore";
import { describeRange } from "../model/textAnchor";
import type { Annotation, AnnotationTarget, LearningSource, TextAnchor } from "../model/types";
import { AnnotationList, AnnotationPopover } from "./PdfAnnotations";
import type { ChatIntent } from "./ReadingSelectionMenu";
import { flashRange, useTextHighlights } from "./useTextHighlights";

export const ASK_PROMPT = "Explain this passage.";

export type MarkSpec = {
  /** What highlights are kept on. Without it the reader offers Ask only. */
  target?: AnnotationTarget;
  /** How a passage is cited; without it a passage goes to the chat as a quote. */
  source?: (anchor: TextAnchor, quote: string, annotationId?: string) => LearningSource;
  /** A selection's lines, in a text file. */
  lines?: (range: Range) => [number, number] | undefined;
};

type Options = {
  /** The mentor beside the reader: Ask goes to its conversation. */
  agentId?: string;
  /** False while the text is not shown as text. */
  enabled?: boolean;
};

const targetKey = (target?: AnnotationTarget) => target ? JSON.stringify(target) : "";

/** The draft a passage becomes: a question, a quote or a comment, with its source when it has one. */
export function chatDraft(intent: ChatIntent, text: string, source?: LearningSource): [string, "plain" | "quote"] {
  if (source) return [intent.kind === "ask" ? ASK_PROMPT : intent.kind === "comment" ? intent.text : "", "plain"];
  if (intent.kind === "quote") return [text, "quote"];
  return [appendSelectionQuote("", text) + (intent.kind === "ask" ? ASK_PROMPT : intent.text), "plain"];
}

/**
 * Highlights, notes and questions on one reader's text: what the selection
 * menu does, the marks painted on the text, the open mark and the list.
 */
export function useReadingMarks(root: RefObject<HTMLElement | null>, spec: MarkSpec, { agentId, enabled = true }: Options = {}) {
  const { target, source: cite, lines } = spec;
  const key = targetKey(target);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [open, setOpen] = useState<{ id: string; at: DOMRect; note: boolean } | null>(null);
  const agent = agentId ? findAgent(agentId) : undefined;
  const askLabel = agent?.name ? `Ask ${agent.name}` : "Ask";
  const chatTarget = agent?.sessionId ? { targetSessionId: agent.sessionId } : {};

  useEffect(() => {
    setAnnotations([]);
    setOpen(null);
    if (!target) return;
    let current = true;
    const load = () => void listAnnotations(target).then((found) => { if (current) setAnnotations(found); }, () => {});
    load();
    const stop = subscribeLearningChanges(load);
    return () => { current = false; stop(); };
  }, [key]);

  const { orphans, rangeOf } = useTextHighlights(root, annotations, {
    selectedId: open?.id, enabled,
    onOpen: (annotation, at) => setOpen({ id: annotation.id, at, note: false }),
  });

  const anchorOf = useCallback((passage: FileSelection): TextAnchor | null => {
    const element = root.current;
    if (!element || !element.contains(passage.range.commonAncestorContainer)) return null;
    const found = lines?.(passage.range);
    return describeRange(element, passage.range, found ? { lines: found } : {});
  }, [root, lines]);

  const toChat = useCallback(async (passage: FileSelection, intent: ChatIntent, current: () => boolean = () => true) => {
    const anchor = cite ? anchorOf(passage) ?? { exact: passage.text, prefix: "", suffix: "", start: 0, end: 0 } : null;
    const source = cite && anchor ? cite(anchor, passage.text) : undefined;
    if (source) await registerLearningSource(source);
    if (!current()) return;
    const [text, mode] = chatDraft(intent, passage.text, source);
    requestAddToChat(text, mode, { ...(source ? { sources: [source] } : {}), ...chatTarget });
  }, [cite, anchorOf, agent?.sessionId]);

  const onMark = useCallback(async (passage: FileSelection, note: boolean) => {
    if (!target || !cite) return;
    const anchor = anchorOf(passage);
    if (!anchor) throw new Error("This selection has no readable text.");
    const id = crypto.randomUUID();
    const now = Date.now();
    const saved = await upsertAnnotation({ id, documentId: "", target, anchor, source: cite(anchor, anchor.exact, id),
      anchors: [], note: "", discussions: [], createdAt: now, updatedAt: now });
    setAnnotations((current) => [...current.filter((entry) => entry.id !== saved.id), saved]);
    setOpen({ id: saved.id, at: passage.rect, note });
  }, [key, cite, anchorOf]);

  const select = useCallback((annotation: Annotation) => {
    const range = rangeOf(annotation.id);
    if (range) flashRange(range);
    const rect = range?.getBoundingClientRect();
    setOpen({ id: annotation.id, at: rect && (rect.width || rect.height) ? rect : new DOMRect(window.innerWidth / 2, 120, 1, 1), note: false });
  }, [rangeOf]);

  const shown = open ? annotations.find((entry) => entry.id === open.id) : undefined;
  const popover: ReactNode = shown && open ? <AnnotationPopover key={shown.id} annotation={shown} anchor={open.at} askLabel={askLabel} focusNote={open.note}
    onDismiss={() => setOpen(null)}
    onAsk={(annotation) => {
      requestAddToChat(annotation.note ? `${ASK_PROMPT}\n\nMy note: ${annotation.note}` : ASK_PROMPT, "plain", { sources: [annotation.source], ...chatTarget });
      setOpen(null);
    }}
    onSave={async (annotation, note) => {
      const updated = await upsertAnnotation({ ...annotation, note, updatedAt: Date.now() });
      setAnnotations((current) => current.map((entry) => entry.id === updated.id ? updated : entry));
    }}
    onDelete={async (annotation) => {
      await deleteAnnotation(annotation.id);
      setAnnotations((current) => current.filter((entry) => entry.id !== annotation.id));
    }} /> : null;

  const list = (onClose: () => void, title?: string): ReactNode =>
    <AnnotationList annotations={annotations} orphans={orphans} selectedId={open?.id} title={title} onSelect={select} onClose={onClose} />;

  /** The list as a panel dropping from a reader's menu button. */
  const listPopover = (anchor: PopoverAnchor, onClose: () => void, title?: string): ReactNode =>
    <Popover bare anchor={anchor} side="bottom" align="end" width={300} maxHeight={460} onDismiss={onClose} className="pdf-annotations--floating">
      {list(onClose, title)}
    </Popover>;

  return { annotations, orphans, askLabel, popover, list, listPopover, select, rangeOf, toChat, onMark: target && cite ? onMark : undefined };
}
