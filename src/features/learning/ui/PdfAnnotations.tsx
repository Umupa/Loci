import { useState } from "react";
import { Popover } from "../../../shared/ui/Popover";
import { ChevronRight, Pencil, MessageSquare, MessageSquarePlus, Trash2, X } from "../../../shared/ui/icons";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { openLearningDiscussion } from "../model/navigation";
import type { PdfAnnotation } from "../model/types";
import "./PdfAnnotations.css";

type Actions = {
  onAsk: (annotation: PdfAnnotation) => void;
  onSave: (annotation: PdfAnnotation, note: string) => Promise<void>;
  onDelete: (annotation: PdfAnnotation) => Promise<void>;
};

export function PdfAnnotationsList({ annotations, selectedId, onSelect, onClose }: {
  annotations: PdfAnnotation[]; selectedId?: string;
  onSelect: (annotation: PdfAnnotation) => void; onClose: () => void;
}) {
  const ordered = [...annotations].sort((a, b) =>
    a.anchors[0].page - b.anchors[0].page
    || a.anchors[0].rects[0].y - b.anchors[0].rects[0].y
    || a.createdAt - b.createdAt);
  return <aside aria-label="PDF annotations" className="pdf-annotations">
    <header className="pdf-annotations__header">
      <h2>Annotations</h2>
      <span className="pdf-annotations__count">{annotations.length}</span>
      <button type="button" title="Close annotations" aria-label="Close annotations" onClick={onClose} className="pdf-annotations__icon-button"><X className="size-3.5" /></button>
    </header>
    <div className="pdf-annotations__list">
      {annotations.length === 0 ? <div className="pdf-annotations__empty">
        <span className="pdf-annotations__empty-icon"><Pencil className="size-4" /></span>
        <p className="pdf-annotations__empty-title">No annotations yet</p>
        <p>Select text in the PDF and choose Highlight to keep a passage here.</p>
      </div> : null}
      {ordered.map((annotation) => <button key={annotation.id} type="button" onClick={() => onSelect(annotation)}
        aria-pressed={selectedId === annotation.id} className="pdf-annotations__entry">
        <span className="pdf-annotations__entry-meta">
          <span className="pdf-annotations__page"><span className="pdf-annotations__marker" />Page {annotation.anchors.map((anchor) => anchor.page).join(", ")}</span>
          <ChevronRight className="size-3" />
        </span>
        <span className="pdf-annotations__entry-quote line-clamp-3">{annotation.source.quote}</span>
        {annotation.note ? <span className="pdf-annotations__entry-note line-clamp-2">{annotation.note}</span> : null}
        {annotation.discussions.length ? <span className="pdf-annotations__entry-discussions"><MessageSquare className="size-3" />{annotation.discussions.length} discussion{annotation.discussions.length === 1 ? "" : "s"}</span> : null}
      </button>)}
    </div>
  </aside>;
}

export function PdfSelectionMenu({ selection, onAsk, onHighlight, onDismiss }: {
  selection: FileSelection; onAsk: () => Promise<void>; onHighlight: () => Promise<void>; onDismiss: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = async (action: () => Promise<void>) => {
    setPending(true); setError(null);
    try { await action(); window.getSelection()?.removeAllRanges(); onDismiss(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setPending(false); }
  };
  return <Popover bare anchor={selection.rect} side="top" align="center" onDismiss={onDismiss} role="toolbar" aria-label="Selected PDF text actions" className="pdf-selection-menu">
    <div className="pdf-selection-menu__actions">
      <button type="button" disabled={pending} onMouseDown={(event) => event.preventDefault()} onClick={() => void run(onAsk)}
        className="pdf-selection-menu__action"><MessageSquarePlus className="size-3.5" />Ask agent</button>
      <button type="button" disabled={pending} onMouseDown={(event) => event.preventDefault()} onClick={() => void run(onHighlight)}
        className="pdf-selection-menu__action"><Pencil className="pdf-annotations__highlight-icon size-3.5" />Highlight</button>
    </div>
    {error ? <p role="alert" className="pdf-annotations__error">{error}</p> : null}
  </Popover>;
}

export function PdfAnnotationPopover({ annotation, anchor, onDismiss, onAsk, onSave, onDelete }: Actions & {
  annotation: PdfAnnotation; anchor: DOMRect; onDismiss: () => void;
}) {
  const [note, setNote] = useState(annotation.note);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = async (action: () => Promise<void>) => {
    setPending(true); setError(null);
    try { await action(); } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setPending(false); }
  };
  return <Popover bare anchor={anchor} side="right" width={320} onDismiss={onDismiss} role="dialog" aria-label="PDF annotation" className="pdf-annotation-popover">
    <header className="pdf-annotation-popover__header">
      <span className="pdf-annotation-popover__badge"><Pencil className="size-3.5" /></span>
      <div className="pdf-annotation-popover__heading">
        <h2>Highlight</h2>
        <p>Page {annotation.anchors.map((entry) => entry.page).join(", ")}</p>
      </div>
      <button type="button" title="Close annotation" aria-label="Close annotation" onClick={onDismiss} className="pdf-annotations__icon-button"><X className="size-3.5" /></button>
    </header>
    <div className="pdf-annotation-popover__body">
      <blockquote className="pdf-annotation-popover__quote">{annotation.source.quote}</blockquote>
      <div className="pdf-annotation-popover__note-header">
        <span>Note</span>
        <button type="button" disabled={pending || note === annotation.note} onClick={() => void run(() => onSave(annotation, note))}
          className="pdf-annotation-popover__save">Save note</button>
      </div>
      <textarea aria-label="Annotation note" placeholder="Add your thoughts or a question…" value={note} onChange={(event) => setNote(event.target.value)}
        className="pdf-annotation-popover__note" />
      {annotation.discussions.length ? <div className="pdf-annotation-popover__discussions">
        <p className="pdf-annotation-popover__section-title">Discussions <span>{annotation.discussions.length}</span></p>
        <div className="pdf-annotation-popover__discussion-list">
          {annotation.discussions.map((discussion, index) => <button key={`${discussion.sessionId}:${discussion.blockId}`} type="button"
            onClick={() => openLearningDiscussion(discussion)} className="pdf-annotation-popover__discussion"><MessageSquare className="size-3.5" /><span>Open discussion {index + 1}</span><ChevronRight className="size-3" /></button>)}
        </div>
      </div> : null}
      {error ? <p role="alert" className="pdf-annotations__error">{error}</p> : null}
    </div>
    <footer className="pdf-annotation-popover__footer">
      <button type="button" onClick={() => onAsk(annotation)} className="pdf-annotation-popover__ask"><MessageSquarePlus className="size-3.5" />Ask agent</button>
      <button type="button" title="Delete annotation" aria-label="Delete annotation" disabled={pending} onClick={() => void run(async () => { await onDelete(annotation); onDismiss(); })}
        className="pdf-annotations__icon-button pdf-annotations__delete"><Trash2 className="size-3.5" /></button>
    </footer>
  </Popover>;
}
