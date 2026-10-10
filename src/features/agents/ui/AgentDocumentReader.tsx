import { useEffect, useState, type PointerEvent as ReactPointerEvent } from "react";
import { Check, GripVertical, StickyNote, Trash2, X } from "../../../shared/ui/icons";
import { NOTES_CHANGED_EVENT, upsertNote } from "../../notes";
import type { AgentDocument } from "../../sessions/model/cards";
import { DocumentBody, shownDocument } from "./DocumentBody";
import {
  deleteAgentDocument,
  readAgentDocument,
  subscribeAgentDocuments,
} from "../model/agentDocuments";

type Props = {
  /** The agent whose library it is in, when it was opened from one. */
  agentId?: string;
  /** The document as the chat or the library handed it over. */
  document: AgentDocument;
  focused: boolean;
  onFocus: () => void;
  onClose: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
};

const iconButton = "grid size-6 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content disabled:opacity-40";

/**
 * A workspace document pane. It shows the library's copy, so a revision the
 * agent writes while it is open appears here, and a source shows as a source
 * however the pane was opened.
 */
export function AgentDocumentReader({ agentId, document, focused, onFocus, onClose, onPaneDragStart }: Props) {
  const [latest, setLatest] = useState<AgentDocument>(document);
  const [stored, setStored] = useState(false);
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    setLatest(document);
    setStored(false);
    setSaved(false);
    if (!agentId) return;
    let current = true;
    const load = () => void readAgentDocument(agentId, document.id).then((found) => {
      if (!current) return;
      setStored(!!found);
      if (found?.body != null) setLatest(shownDocument({ ...found, body: found.body }));
    }, () => undefined);
    load();
    const stop = subscribeAgentDocuments(load);
    return () => {
      current = false;
      stop();
    };
  }, [agentId, document]);

  const saveAsNote = async () => {
    await upsertNote({ id: crypto.randomUUID(), title: latest.title, body: latest.body, tags: latest.subject ? [latest.subject] : [] });
    window.dispatchEvent(new Event(NOTES_CHANGED_EVENT));
    setSaved(true);
  };

  return (
    <aside aria-label={latest.title} className="flex h-full min-h-0 min-w-0 w-full flex-col text-content" onPointerDown={() => { if (!focused) onFocus(); }}>
      <header className={`flex h-9 shrink-0 select-none items-center gap-1.5 border-b border-stroke px-2 ${onPaneDragStart ? "cursor-grab active:cursor-grabbing touch-none" : ""}`}
        onPointerDown={(event) => {
          if (!(event.target as HTMLElement).closest("[data-no-drag]")) onPaneDragStart?.(event);
        }}>
        {onPaneDragStart ? <GripVertical className="size-3.5 shrink-0 text-content/35" /> : null}
        <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} />
        <div className="flex min-w-0 flex-1 items-baseline gap-2">
          <h2 className="min-w-0 truncate text-xs">{latest.title}</h2>
          {latest.subject ? <span className="min-w-0 truncate text-[11px] text-content/45">{latest.subject}</span> : null}
        </div>
        <button type="button" data-no-drag title={saved ? "Saved to Notes" : "Save as a note"} aria-label="Save as a note" disabled={saved} onClick={() => void saveAsNote()} className={iconButton}>
          {saved ? <Check className="size-3.5" strokeWidth={2} /> : <StickyNote className="size-3.5" strokeWidth={1.75} />}
        </button>
        {agentId && stored ? (
          <button type="button" data-no-drag title="Remove from the library" aria-label="Remove from the library" className={iconButton}
            onClick={() => void deleteAgentDocument(agentId, latest.id).then(onClose)}>
            <Trash2 className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
        <button type="button" data-no-drag title="Close" aria-label="Close the document" onClick={onClose} className={iconButton}>
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </header>
      <div className="min-h-0 min-w-0 flex-1 overflow-y-auto px-6 pb-10 pt-2 text-[14px] leading-relaxed">
        <DocumentBody document={latest} agentId={agentId} />
      </div>
    </aside>
  );
}
