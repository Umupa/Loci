import { useRef, useState } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { copyText } from "../../../platform/tauri/clipboard";
import { Popover } from "../../../shared/ui/Popover";
import { ChevronRight, Copy, MessageSquare, MessageSquarePlus, PenLine, Trash2, X } from "../../../shared/ui/icons";
import { registerLearningSource } from "../model/learningStore";
import { openLearningDiscussion } from "../model/navigation";
import { quoteMarkdown, savePictureQuoteToNote, saveQuoteToNote } from "../model/quoteNote";
import { blockLabel } from "../model/blockAnchor";
import { ToolbarButton, ToolbarDivider, useSaveToNote, type NoteShelf } from "./ReadingToolbar";
import type { Annotation } from "../model/types";
import { annotationPlace } from "../model/annotationPlace";

export { annotationPlace };
import "./PdfAnnotations.css";

type Actions = {
  onAsk: (annotation: Annotation) => void;
  onSave: (annotation: Annotation, note: string) => Promise<void>;
  onDelete: (annotation: Annotation) => Promise<void>;
};

/** Reading order: PDF marks by page and height, text marks by where they start. */
function readingOrder(a: Annotation, b: Annotation): number {
  const pdf = (entry: Annotation) => entry.anchors[0] ? [entry.anchors[0].page, entry.anchors[0].rects[0]?.y ?? 0] : null;
  const [pa, pb] = [pdf(a), pdf(b)];
  if (pa && pb) return pa[0] - pb[0] || pa[1] - pb[1] || a.createdAt - b.createdAt;
  return (a.anchor?.start ?? 0) - (b.anchor?.start ?? 0) || a.createdAt - b.createdAt;
}

/** The highlights and notes of what the reader shows, beside it. */
export function AnnotationList({ annotations, selectedId, orphans, title = "Highlights & notes", onSelect, onClose }: {
  annotations: Annotation[]; selectedId?: string;
  /** Marks whose words are no longer in the text. They are kept, and said so. */
  orphans?: ReadonlySet<string>;
  title?: string;
  onSelect: (annotation: Annotation) => void; onClose: () => void;
}) {
  const ordered = [...annotations].sort(readingOrder);
  return <aside aria-label={title} className="pdf-annotations">
    <header className="pdf-annotations__header">
      <h2>{title}</h2>
      {annotations.length ? <span className="pdf-annotations__count">{annotations.length}</span> : null}
      <button type="button" title="Close annotations" aria-label="Close annotations" onClick={onClose} className="pdf-annotations__icon-button"><X className="size-3.5" /></button>
    </header>
    <div className="pdf-annotations__list">
      {annotations.length === 0 ? <p className="pdf-annotations__empty">Select text to highlight it</p> : null}
      {ordered.map((annotation) => <button key={annotation.id} type="button" onClick={() => onSelect(annotation)}
        aria-pressed={selectedId === annotation.id} className="pdf-annotations__entry">
        <span className="pdf-annotations__entry-meta">
          <span className="pdf-annotations__page"><span className="pdf-annotations__marker" />{annotationPlace(annotation, orphans?.has(annotation.id))}</span>
          <ChevronRight className="size-3" />
        </span>
        <span className="pdf-annotations__entry-quote line-clamp-3">{annotation.source.quote || (annotation.anchor?.block ? blockLabel(annotation.anchor.block.kind) : "")}</span>
        {annotation.note ? <span className="pdf-annotations__entry-note line-clamp-2">{annotation.note}</span> : null}
        {annotation.discussions.length ? <span className="pdf-annotations__entry-discussions"><MessageSquare className="size-3" />{annotation.discussions.length} discussion{annotation.discussions.length === 1 ? "" : "s"}</span> : null}
      </button>)}
    </div>
  </aside>;
}

/**
 * A highlight's bar, the same as a selection's with its own two added: Note,
 * which opens a small field for a note on it, and Delete. A note already
 * written shows as a line under the bar.
 */
export function AnnotationToolbar({ annotation, anchor, onDismiss, onAsk, onSave, onDelete, askLabel = "Ask", notes, picture }: Actions & {
  annotation: Annotation; anchor: DOMRect; onDismiss: () => void;
  /** A picture of what is marked (an area of a PDF page), kept with the note above the passage. */
  picture?: () => Promise<File | null>;
  /** "Ask Kern": the mentor the question goes to. */
  askLabel?: string;
  /** Where Save to note puts the passage. */
  notes?: NoteShelf;
}) {
  const [note, setNote] = useState(annotation.note);
  const [editing, setEditing] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const noteRef = useRef(note);
  noteRef.current = note;
  const markdown = async () => {
    await registerLearningSource(annotation.source);
    return quoteMarkdown(annotation.source.quote, annotation.source, noteRef.current);
  };
  const title = annotation.source.quote || (annotation.anchor?.block ? `${blockLabel(annotation.anchor.block.kind)} · ${annotation.source.title}` : annotation.source.title);
  const saving = useSaveToNote(notes, async (target) => picture
    ? savePictureQuoteToNote(await picture(), await markdown(), title, target, notes?.agentId)
    : saveQuoteToNote(await markdown(), title, target, notes?.agentId));
  const run = async (action: () => Promise<unknown>) => {
    setPending(true); setError(null);
    try { await action(); } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setPending(false); }
  };
  // Text written into the note is worth keeping: dismissing, asking or saving it elsewhere keeps it.
  const savePending = async () => {
    if (note === annotation.note) return;
    await onSave(annotation, note);
  };
  const saveAndDismiss = async () => { await savePending(); onDismiss(); };
  const discussion = annotation.discussions[annotation.discussions.length - 1];
  const picker = saving.picker(onDismiss);
  return <Popover bare anchor={anchor} side="bottom" align="start" onDismiss={() => void run(saveAndDismiss)}
    role="toolbar" aria-label="Highlight actions" className="reading-toolbar">
    {picker ? <div className="reading-toolbar__picker">{picker}</div> : <>
      <div className="reading-toolbar__actions">
        <ToolbarButton icon={<PenLine className="size-3.5" />} label="Note" title={annotation.note ? "Edit the note on this highlight" : "Write a note on this highlight"}
          pressed={editing} disabled={pending} onClick={() => setEditing((open) => !open)} />
        <ToolbarButton icon={<MessageSquarePlus className="size-3.5" />} label={askLabel} title="Quote this passage in the chat and write your question" disabled={pending}
          onClick={() => void run(async () => { await savePending(); onAsk({ ...annotation, note }); })} />
        {saving.button(() => void run(async () => { await savePending(); if (await saving.run()) onDismiss(); }), pending)}
        <ToolbarButton icon={<Copy className="size-3.5" />} label="Copy quote" iconOnly title="Copy as a Markdown quote, with a link back here" disabled={pending}
          onClick={() => void run(async () => copyText(await markdown()))} />
        <ToolbarDivider />
        {discussion ? <ToolbarButton icon={<MessageSquare className="size-3.5" />} label="Open discussion" iconOnly disabled={pending}
          title={annotation.discussions.length === 1 ? "Open the conversation about this passage" : `Open the latest of ${annotation.discussions.length} conversations about this passage`}
          onClick={() => openLearningDiscussion(discussion)} /> : null}
        <ToolbarButton icon={<Trash2 className="size-3.5" />} label="Delete highlight" iconOnly danger disabled={pending} onClick={() => {
          if (!annotation.note || window.confirm("Delete this highlight and its note?")) void run(async () => { await onDelete(annotation); onDismiss(); });
        }} />
      </div>
      {editing ? <form className="reading-toolbar__note-form" onSubmit={(event) => {
        event.preventDefault();
        void run(async () => { await savePending(); setEditing(false); });
      }}>
        <textarea aria-label="Note" autoFocus placeholder="Write a note on this passage…" value={note} disabled={pending}
          onChange={(event) => setNote(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) { event.preventDefault(); event.currentTarget.form?.requestSubmit(); } }} />
        <footer>
          <span>{IS_MAC ? "⌘↩" : "Ctrl+Enter"} to save</span>
          <button type="button" disabled={pending} onClick={() => { setNote(annotation.note); setEditing(false); }}>Cancel</button>
          <button type="submit" disabled={pending || note === annotation.note}>Save</button>
        </footer>
      </form> : annotation.note ? <button type="button" className="reading-toolbar__note" title="Edit the note" onClick={() => setEditing(true)}>{annotation.note}</button> : null}
    </>}
    {error ? <p role="alert" className="reading-toolbar__error">Could not do that. {error}</p> : null}
  </Popover>;
}
