import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { Check, Copy, MoreHorizontal, Pencil, StickyNote, Trash2, X } from "../../../shared/ui/icons";
import { copyMessage } from "../../../platform/tauri/clipboard";
import { Popover } from "../../../shared/ui/Popover";
import { ResourceHeader, RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { upsertNote } from "../../notes";
import { requestOpenAppResource } from "../../../shared/lib/appResourceLinks";
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
  onBack?: () => void;
  /** Shown as the window's one reader: a reader header with Close, no pane chrome. */
  reader?: boolean;
};

const iconButton = "grid size-6 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content disabled:opacity-40";

/**
 * A workspace document pane. It shows the library's copy, so a revision the
 * agent writes while it is open appears here, and a source shows as a source
 * however the pane was opened.
 */
export function AgentDocumentReader({ agentId, document, focused, onFocus, onClose, onPaneDragStart, onBack, reader = false }: Props) {
  const embedded = reader || !!onBack;
  const [latest, setLatest] = useState<AgentDocument>(document);
  const [stored, setStored] = useState(false);
  const [saved, setSaved] = useState(false);
  const [savedNoteId, setSavedNoteId] = useState<string>();
  /** The library no longer has it; the copy the conversation handed over still reads. */
  const [missing, setMissing] = useState(false);
  const [error, setError] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [reload, setReload] = useState(0);
  const [menu, setMenu] = useState(false);
  const [copied, setCopied] = useState(false);
  const [marksOpen, setMarksOpen] = useState(false);
  const [marks, setMarks] = useState(0);
  const more = useRef<HTMLButtonElement>(null);
  const [loading, setLoading] = useState(!!agentId);
  useEffect(() => {
    setLatest(document);
    setStored(false);
    setSaved(false);
    setSavedNoteId(undefined);
    setCopied(false);
    setMenu(false);
    setMissing(false);
    setError(undefined);
    setActionError(undefined);
    setLoading(!!agentId);
    if (!agentId) return;
    let current = true;
    let request = 0;
    const load = () => {
      const turn = ++request;
      void readAgentDocument(agentId, document.id).then((found) => {
        if (!current || turn !== request) return;
        setStored(!!found);
        setLoading(false);
        // A reply's copy is still worth reading when the library no longer has its document.
        setMissing(!found);
        setError(undefined);
        if (found?.body != null) setLatest(shownDocument({ ...found, body: found.body }));
      }, (cause) => {
        if (current && turn === request) { setLoading(false); setError(String(cause)); }
      });
    };
    load();
    const stop = subscribeAgentDocuments(load);
    return () => {
      current = false;
      stop();
    };
  }, [agentId, document, reload]);

  /** Gone for good, with the highlights and notes written in it: ask first. */
  const removeFromLibrary = () => {
    if (!agentId || !window.confirm(`Remove “${latest.title}” from the library? Its highlights and notes will no longer be reachable.`)) return;
    void deleteAgentDocument(agentId, latest.id).then(onBack ?? onClose).catch((cause) => setActionError(String(cause)));
  };

  const saveAsNote = async () => {
    try {
      const note = await upsertNote({ id: crypto.randomUUID(), title: latest.title, body: latest.body, tags: latest.subject ? [latest.subject] : [], ...(agentId ? { agentId } : {}) });
      setSavedNoteId(note?.id);
      setSaved(true);
    } catch (cause) { setActionError(`Could not save note: ${String(cause)}`); }
  };

  return (
    <aside aria-label={latest.title} className="flex h-full min-h-0 min-w-0 w-full flex-col text-content" onPointerDown={() => { if (!focused) onFocus(); }}>
      {embedded ? <ResourceHeader title={latest.title} backLabel="Back to documents" onBack={onBack} onClose={onClose}>
        <button ref={more} type="button" title="Document actions" aria-label="Document actions" aria-expanded={menu} aria-haspopup="menu" className={RESOURCE_ACTION} onClick={() => setMenu((open) => !open)}><MoreHorizontal className="size-3.5" /></button>
      </ResourceHeader> : <PaneHeader onPaneDragStart={onPaneDragStart}>
        {!embedded ? <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} /> : null}
        <div className="flex min-w-0 flex-1 items-baseline gap-2">
          <h2 className="min-w-0 truncate text-xs" title={latest.title}>{latest.title}</h2>
          {latest.subject ? <span className="pane-header-secondary min-w-0 truncate text-[11px] text-content/45">{latest.subject}</span> : null}
        </div>
        <button type="button" data-no-drag title={saved ? "Saved to Notes" : "Save as a note"} aria-label="Save as a note" disabled={saved || loading || !!error} onClick={() => void saveAsNote()} className={iconButton}>
          {saved ? <Check className="size-3.5" strokeWidth={2} /> : <StickyNote className="size-3.5" strokeWidth={1.75} />}
        </button>
        {agentId && stored ? (
          <button type="button" data-no-drag title="Remove from the library" aria-label="Remove from the library" className={iconButton}
            onClick={removeFromLibrary}>
            <Trash2 className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
        <button type="button" data-no-drag title="Close" aria-label="Close the document" onClick={onClose} className={iconButton}>
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </PaneHeader>}
      {menu ? <Popover anchor={more} side="bottom" align="end" width={204} role="menu" aria-label="Document actions" onDismiss={() => setMenu(false)} className="p-1 font-sans">
        <button type="button" role="menuitem" disabled={loading || !!error} onClick={() => { setMenu(false); void copyMessage(latest.body).then(() => { setCopied(true); setActionError(undefined); }, (cause) => setActionError(`Could not copy document: ${String(cause)}`)); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs hover:bg-content/6 disabled:opacity-40">{copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}{copied ? "Copied" : "Copy document"}</button>
        {agentId ? <button type="button" role="menuitem" disabled={loading || !!error} onClick={() => { setMenu(false); setMarksOpen(true); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs hover:bg-content/6 disabled:opacity-40"><Pencil className="size-3.5" />Highlights &amp; notes{marks ? ` (${marks})` : ""}</button> : null}
        <button type="button" role="menuitem" disabled={saved || loading || !!error} onClick={() => { setMenu(false); void saveAsNote(); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs hover:bg-content/6 disabled:opacity-40"><StickyNote className="size-3.5" />{saved ? "Saved to Notes" : "Save as a note"}</button>
        {agentId && stored ? <button type="button" role="menuitem" onClick={() => { setMenu(false); removeFromLibrary(); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs text-red-400 hover:bg-content/6"><Trash2 className="size-3.5" />Remove from the library</button> : null}
      </Popover> : null}
      {saved && savedNoteId ? <div role="status" className="flex shrink-0 items-center gap-2 border-b border-stroke px-6 py-1.5 text-[12px] text-content/60">
        <span>Saved to Notes.</span>
        <button type="button" onClick={() => requestOpenAppResource({ kind: "note", id: savedNoteId })} className="underline hover:text-content">Open</button>
      </div> : null}
      <div className={`min-h-0 min-w-0 flex-1 overflow-y-auto ${embedded ? "px-7 py-6" : "px-6 pb-10 pt-2"} text-[14px] leading-relaxed`}>
        {loading ? <p role="status" className="py-4 text-xs text-content/50">Opening document…</p> : error ? <div role="alert" className="py-4 text-xs text-content/60"><p>{error}</p><button type="button" className="mt-2 underline" onClick={() => setReload((value) => value + 1)}>Retry</button></div> : <>
          {missing ? <p role="status" className="document-section-notice">This document is no longer in the library. Showing the copy from this conversation.</p> : null}
          <DocumentBody document={latest} agentId={agentId} onMarks={setMarks}
            marksList={marksOpen ? { anchor: more, onClose: () => setMarksOpen(false) } : undefined} />
        </>}
        {actionError ? <p role="alert" className="mt-3 text-xs text-red-400">{actionError}</p> : null}
      </div>
    </aside>
  );
}
