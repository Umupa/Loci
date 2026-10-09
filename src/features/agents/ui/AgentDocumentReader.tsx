import { useEffect, useState } from "react";
import { Check, StickyNote, Trash2, X } from "../../../shared/ui/icons";
import { NOTES_CHANGED_EVENT, upsertNote } from "../../notes";
import type { AgentDocument } from "../../sessions/model/cards";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
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
  onClose: () => void;
};

const iconButton = "grid size-6 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content disabled:opacity-40";

/**
 * A document beside the chat, at reading width. It shows the library's copy,
 * so a revision the agent writes while it is open appears here.
 */
export function AgentDocumentReader({ agentId, document, onClose }: Props) {
  const [latest, setLatest] = useState<AgentDocument>(document);
  const [stored, setStored] = useState(false);
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    setLatest(document);
    setSaved(false);
    if (!agentId) return;
    let current = true;
    const load = () => void readAgentDocument(agentId, document.id).then((found) => {
      if (!current) return;
      setStored(!!found);
      if (found?.body != null) setLatest({ id: found.id, title: found.title, ...(found.subject ? { subject: found.subject } : {}), body: found.body });
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
    <aside aria-label={latest.title} className="flex w-[min(46rem,55%)] shrink-0 flex-col border-l border-stroke bg-background-base/70 backdrop-blur-xl">
      <header className="flex h-11 shrink-0 items-center gap-1.5 px-3">
        <div className="flex min-w-0 flex-1 items-baseline gap-2 px-1">
          <h2 className="truncate text-[13px] font-medium">{latest.title}</h2>
          {latest.subject ? <span className="shrink-0 text-xs text-content/45">{latest.subject}</span> : null}
        </div>
        <button type="button" title={saved ? "Saved to Notes" : "Save as a note"} aria-label="Save as a note" disabled={saved} onClick={() => void saveAsNote()} className={iconButton}>
          {saved ? <Check className="size-3.5" strokeWidth={2} /> : <StickyNote className="size-3.5" strokeWidth={1.75} />}
        </button>
        {agentId && stored ? (
          <button type="button" title="Remove from the library" aria-label="Remove from the library" className={iconButton}
            onClick={() => void deleteAgentDocument(agentId, latest.id).then(onClose)}>
            <Trash2 className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
        <button type="button" title="Close" aria-label="Close the document" onClick={onClose} className={iconButton}>
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-10 pt-2 text-[14px] leading-relaxed">
        <AgentMarkdown text={latest.body} wholeDocument />
      </div>
    </aside>
  );
}
