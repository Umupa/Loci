import { useCallback, useEffect, useState, type ReactNode, type RefObject } from "react";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { Popover, type PopoverAnchor } from "../../../shared/ui/Popover";
import { findAgent } from "../../agents/model/agent";
import { appendSelectionQuote, requestAddToChat } from "../../sessions/model/quoteDraft";
import { deleteAnnotation, listAnnotations, registerLearningSource, subscribeLearningChanges, upsertAnnotation } from "../model/learningStore";
import { describeRange } from "../model/textAnchor";
import type { Annotation, AnnotationTarget, LearningSource, TextAnchor } from "../model/types";
import { blockAnchor, blockAt, blockLabel, type ReadingBlock } from "../model/blockAnchor";
import { quoteMarkdown, saveQuoteToNote } from "../model/quoteNote";
import { BlockHandle, BlockToolbar } from "./BlockToolbar";
import { AnnotationList, AnnotationToolbar } from "./PdfAnnotations";
import type { ChatIntent } from "./ReadingSelectionMenu";
import { useNoteShelf } from "./ReadingToolbar";
import { flashRange, useTextHighlights } from "./useTextHighlights";

/** Show a reader's list of highlights, dropping from this anchor. */
export type MarksListRequest = { anchor: PopoverAnchor; onClose: () => void; title?: string };

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

/**
 * Ask: the passage quoted at the end of the draft, with the reader's note on
 * it, and the cursor after them for the question.
 */
export function askDraft(quote: string, note = ""): string {
  return appendSelectionQuote("", quote) + (note.trim() ? `My note: ${note.trim()}\n\n` : "");
}

/** The draft a passage becomes: a question, a quote or a comment, with its source when it has one. */
export function chatDraft(intent: ChatIntent, text: string, source?: LearningSource): [string, "plain" | "quote" | "prompt"] {
  if (intent.kind === "ask") return [askDraft(text), "prompt"];
  if (source) return [intent.kind === "comment" ? intent.text : "", "plain"];
  if (intent.kind === "quote") return [text, "quote"];
  return [appendSelectionQuote("", text) + intent.text, "plain"];
}

/**
 * Highlights, notes and questions on one reader's text: what the selection
 * menu does, the marks painted on the text, the open mark and the list.
 */
export function useReadingMarks(root: RefObject<HTMLElement | null>, spec: MarkSpec, { agentId, enabled = true }: Options = {}) {
  const { target, source: cite, lines } = spec;
  const key = targetKey(target);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [open, setOpen] = useState<{ id: string; at: DOMRect } | null>(null);
  const [openBlock, setOpenBlock] = useState<{ block: ReadingBlock; at: DOMRect } | null>(null);
  const agent = agentId ? findAgent(agentId) : undefined;
  const askLabel = agent?.name ? `Ask ${agent.name}` : "Ask";
  const chatTarget = agent?.sessionId ? { targetSessionId: agent.sessionId } : {};

  useEffect(() => {
    setAnnotations([]);
    setOpen(null);
    setOpenBlock(null);
    if (!target) return;
    let current = true;
    const load = () => void listAnnotations(target).then((found) => { if (current) setAnnotations(found); }, () => {});
    load();
    const stop = subscribeLearningChanges(load);
    return () => { current = false; stop(); };
  }, [key]);

  const { orphans, rangeOf, blockMark } = useTextHighlights(root, annotations, {
    selectedId: open?.id, enabled,
    onOpen: (annotation, at) => setOpen({ id: annotation.id, at }),
  });

  const anchorOf = useCallback((passage: FileSelection): TextAnchor | null => {
    const element = root.current;
    if (!element || !element.contains(passage.range.commonAncestorContainer)) return null;
    const found = lines?.(passage.range);
    return describeRange(element, passage.range, found ? { lines: found } : {});
  }, [root, lines]);

  /** The passage's source, saved so a link or a chat can name it. */
  const sourceOf = useCallback(async (passage: FileSelection) => {
    const anchor = cite ? anchorOf(passage) ?? { exact: passage.text, prefix: "", suffix: "", start: 0, end: 0 } : null;
    const source = cite && anchor ? cite(anchor, passage.text) : undefined;
    if (source) await registerLearningSource(source);
    return source;
  }, [cite, anchorOf]);

  const toChat = useCallback(async (passage: FileSelection, intent: ChatIntent, current: () => boolean = () => true) => {
    const source = await sourceOf(passage);
    if (!current()) return;
    const [text, mode] = chatDraft(intent, passage.text, source);
    requestAddToChat(text, mode, { ...(source ? { sources: [source] } : {}), ...chatTarget });
  }, [sourceOf, agent?.sessionId]);

  const quote = useCallback(async (passage: FileSelection) => quoteMarkdown(passage.text, await sourceOf(passage)), [sourceOf]);
  const notes = useNoteShelf(agentId);

  const onMark = useCallback(async (passage: FileSelection) => {
    if (!target || !cite) return;
    const anchor = anchorOf(passage);
    if (!anchor) throw new Error("This selection has no readable text.");
    const id = crypto.randomUUID();
    const now = Date.now();
    const saved = await upsertAnnotation({ id, documentId: "", target, anchor, source: cite(anchor, anchor.exact, id),
      anchors: [], note: "", discussions: [], createdAt: now, updatedAt: now });
    setAnnotations((current) => [...current.filter((entry) => entry.id !== saved.id), saved]);
    setOpen({ id: saved.id, at: passage.rect });
  }, [key, cite, anchorOf]);

  /** A whole block's anchor and its source, saved so a link or a chat can name it. The block's Markdown is the quote. */
  const blockSource = async (block: ReadingBlock, annotationId?: string) => {
    const element = root.current;
    const anchor = element ? blockAnchor(element, block) : null;
    const source = cite && anchor ? cite(anchor, block.source, annotationId) : undefined;
    if (source && !annotationId) await registerLearningSource(source);
    return { anchor, source };
  };

  const markBlock = async (block: ReadingBlock, at: DOMRect) => {
    if (!target || !cite) return;
    const id = crypto.randomUUID();
    const { anchor, source } = await blockSource(block, id);
    if (!anchor || !source) throw new Error("This block can no longer be found.");
    const now = Date.now();
    const saved = await upsertAnnotation({ id, documentId: "", target, anchor, source,
      anchors: [], note: "", discussions: [], createdAt: now, updatedAt: now });
    setAnnotations((current) => [...current.filter((entry) => entry.id !== saved.id), saved]);
    setOpen({ id: saved.id, at });
  };

  /** The handle on a block: its highlight's bar when it has one, else the block's own. */
  const onBlock = (element: HTMLElement, at: DOMRect) => {
    const id = blockMark(element);
    if (id) { setOpenBlock(null); setOpen({ id, at }); return; }
    const block = root.current ? blockAt(root.current, element) : null;
    if (block) { setOpen(null); setOpenBlock({ block, at }); }
  };

  const select = useCallback((annotation: Annotation) => {
    const range = rangeOf(annotation.id);
    if (range) flashRange(range);
    const rect = range?.getBoundingClientRect();
    setOpen({ id: annotation.id, at: rect && (rect.width || rect.height) ? rect : new DOMRect(window.innerWidth / 2, 120, 1, 1) });
  }, [rangeOf]);

  const shown = open ? annotations.find((entry) => entry.id === open.id) : undefined;
  const shownBlock = openBlock?.block;
  const blockBar: ReactNode = shownBlock && openBlock ? <BlockToolbar key={shownBlock.source} anchor={openBlock.at} label={`${blockLabel(shownBlock.kind)} actions`}
    askLabel={askLabel} notes={notes} onDismiss={() => setOpenBlock(null)}
    onMark={target && cite ? () => markBlock(shownBlock, openBlock.at) : undefined}
    onAsk={async () => {
      const { source } = await blockSource(shownBlock);
      requestAddToChat(askDraft(shownBlock.source), "prompt", { ...(source ? { sources: [source] } : {}), ...chatTarget });
    }}
    save={async (to) => {
      const { anchor, source } = await blockSource(shownBlock);
      return saveQuoteToNote(quoteMarkdown(shownBlock.source, source), anchor?.block?.lead || blockLabel(shownBlock.kind), to, agentId);
    }}
    copy={async () => quoteMarkdown(shownBlock.source, (await blockSource(shownBlock)).source)} /> : null;
  const handle: ReactNode = <BlockHandle root={root} enabled={enabled} marked={(block) => !!blockMark(block)} onOpen={onBlock} />;
  const toolbar: ReactNode = shown && open ? <AnnotationToolbar key={shown.id} annotation={shown} anchor={open.at} askLabel={askLabel} notes={notes}
    onDismiss={() => setOpen(null)}
    onAsk={(annotation) => {
      requestAddToChat(askDraft(annotation.source.quote, annotation.note), "prompt", { sources: [annotation.source], ...chatTarget });
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
  const popover: ReactNode = <>{handle}{blockBar}{toolbar}</>;

  const list = (onClose: () => void, title?: string, only: readonly Annotation[] = annotations): ReactNode =>
    <AnnotationList annotations={[...only]} orphans={orphans} selectedId={open?.id} title={title} onSelect={select} onClose={onClose} />;

  /** The list as a panel dropping from a reader's menu button. */
  const listPopover = (anchor: PopoverAnchor, onClose: () => void, title?: string, only?: readonly Annotation[]): ReactNode =>
    <Popover bare anchor={anchor} side="bottom" align="end" width={300} maxHeight={460} onDismiss={onClose} className="pdf-annotations--floating">
      {list(onClose, title, only)}
    </Popover>;

  return { annotations, orphans, askLabel, chatTarget, popover, list, listPopover, select, rangeOf, toChat, quote, notes, onMark: target && cite ? onMark : undefined };
}
