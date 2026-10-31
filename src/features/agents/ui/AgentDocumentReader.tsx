import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { Check, Copy, MoreHorizontal, StickyNote, Trash2, X } from "../../../shared/ui/icons";
import { copyMessage } from "../../../platform/tauri/clipboard";
import { Popover } from "../../../shared/ui/Popover";
import { ResourceHeader, RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { upsertNote } from "../../notes";
import type { AgentDocument } from "../../sessions/model/cards";
import { DocumentBody, shownDocument } from "./DocumentBody";
import {
  deleteAgentDocument,
  readAgentDocument,
  subscribeAgentDocuments,
} from "../model/agentDocuments";
import { consumeDocumentSection, useDocumentSection } from "../model/documentPlace";
import { findHeading, headingPlace } from "../../files/model/filePlace";

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
  const [error, setError] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [reload, setReload] = useState(0);
  const [menu, setMenu] = useState(false);
  const [copied, setCopied] = useState(false);
  const more = useRef<HTMLButtonElement>(null);
  const [loading, setLoading] = useState(!!agentId);
  const bodyRef = useRef<HTMLDivElement>(null);
  // A section asked for from outside (a command, a link): scroll to its heading once the text is in.
  const sectionRequest = useDocumentSection(agentId, document.id);
  useEffect(() => {
    if (!sectionRequest || !agentId || loading) return;
    const place = headingPlace(sectionRequest.section);
    let timer = 0;
    const show = (tries: number) => {
      const heading = place && bodyRef.current ? findHeading(bodyRef.current, place) : null;
      if (!heading && tries > 0) { timer = window.setTimeout(() => show(tries - 1), 50); return; }
      heading?.scrollIntoView?.({ block: "start" });
      consumeDocumentSection(agentId, document.id, sectionRequest.token);
    };
    show(20);
    return () => window.clearTimeout(timer);
  }, [sectionRequest, agentId, document.id, loading, latest]);
  useEffect(() => {
    setLatest(document);
    setStored(false);
    setSaved(false);
    setCopied(false);
    setMenu(false);
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
        setError(found?.body != null ? undefined : "This document is no longer in the library.");
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

  const saveAsNote = async () => {
    try {
      await upsertNote({ id: crypto.randomUUID(), title: latest.title, body: latest.body, tags: latest.subject ? [latest.subject] : [], ...(agentId ? { agentId } : {}) });
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
            onClick={() => void deleteAgentDocument(agentId, latest.id).then(onBack ?? onClose).catch((cause) => setActionError(String(cause)))}>
            <Trash2 className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
        <button type="button" data-no-drag title="Close" aria-label="Close the document" onClick={onClose} className={iconButton}>
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </PaneHeader>}
      {menu ? <Popover anchor={more} side="bottom" align="end" width={204} role="menu" aria-label="Document actions" onDismiss={() => setMenu(false)} className="p-1 font-sans">
        <button type="button" role="menuitem" disabled={loading || !!error} onClick={() => { setMenu(false); void copyMessage(latest.body).then(() => { setCopied(true); setActionError(undefined); }, (cause) => setActionError(`Could not copy document: ${String(cause)}`)); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs hover:bg-content/6 disabled:opacity-40">{copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}{copied ? "Copied" : "Copy document"}</button>
        <button type="button" role="menuitem" disabled={saved || loading || !!error} onClick={() => { setMenu(false); void saveAsNote(); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs hover:bg-content/6 disabled:opacity-40"><StickyNote className="size-3.5" />{saved ? "Saved to Notes" : "Save as a note"}</button>
        {agentId && stored ? <button type="button" role="menuitem" onClick={() => { setMenu(false); void deleteAgentDocument(agentId, latest.id).then(onBack ?? onClose).catch((cause) => setActionError(String(cause))); }} className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-xs text-red-400 hover:bg-content/6"><Trash2 className="size-3.5" />Remove from the library</button> : null}
      </Popover> : null}
      <div ref={bodyRef} className={`min-h-0 min-w-0 flex-1 overflow-y-auto ${embedded ? "px-7 py-6" : "px-6 pb-10 pt-2"} text-[14px] leading-relaxed`}>
        {loading ? <p role="status" className="py-4 text-xs text-content/50">Opening document…</p> : error ? <div role="alert" className="py-4 text-xs text-content/60"><p>{error}</p><button type="button" className="mt-2 underline" onClick={() => setReload((value) => value + 1)}>Retry</button></div> : <DocumentBody document={latest} agentId={agentId} />}
        {actionError ? <p role="alert" className="mt-3 text-xs text-red-400">{actionError}</p> : null}
      </div>
    </aside>
  );
}
