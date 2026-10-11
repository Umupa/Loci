import { useEffect, useRef } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useFileSelection } from "../../files/hooks/useFileSelection";
import type { AgentDocument } from "../../sessions/model/cards";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import type { StoredDocument } from "../model/agentDocuments";
import { DocumentSelectionMenu } from "./DocumentSelectionMenu";

/** A library document as a reader shows it, with where it came from when it is a source. */
export function shownDocument(stored: StoredDocument & { body: string }): AgentDocument {
  return {
    id: stored.id,
    title: stored.title,
    body: stored.body,
    ...(stored.subject ? { subject: stored.subject } : {}),
    ...(stored.sourceUrl ? { sourceUrl: stored.sourceUrl } : {}),
    ...(stored.sourceVersion ? { sourceVersion: stored.sourceVersion } : {}),
    ...(stored.fetchedAt ? { fetchedAt: stored.fetchedAt } : {}),
  };
}

function hostOf(url: string): string {
  try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return url; }
}

const headingText = (text: string) => text.replace(/\s+/g, " ").trim().toLowerCase();

/** The heading a lesson starts at: the one named, or failing that the first that contains the name. */
export function findSection(root: HTMLElement, section: string): HTMLElement | undefined {
  const wanted = headingText(section.replace(/^#+\s*/, ""));
  if (!wanted) return undefined;
  const headings = [...root.querySelectorAll<HTMLElement>("h1, h2, h3, h4, h5, h6")];
  return headings.find((heading) => headingText(heading.textContent ?? "") === wanted)
    ?? headings.find((heading) => headingText(heading.textContent ?? "").includes(wanted));
}

type Props = {
  document: AgentDocument;
  /** The agent whose library it is in: selected text is put to that agent. */
  agentId?: string;
  /** A heading to start at. */
  section?: string;
};

/**
 * A document's text, for reading. A source says where it was published and
 * shows that page's pictures. Selecting text offers to ask about, comment on,
 * or quote the passage in the chat.
 */
export function DocumentBody({ document, agentId, section }: Props) {
  const topRef = useRef<HTMLDivElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const { selection, dismiss } = useFileSelection(bodyRef, true);

  useEffect(() => {
    const root = bodyRef.current;
    if (!root) return;
    if (!section) { topRef.current?.scrollIntoView?.({ block: "start" }); return; }
    // The text is laid out over a few frames; look again until the heading is there.
    let tries = 0;
    let frame = 0;
    const seek = () => {
      const heading = findSection(root, section);
      if (heading) heading.scrollIntoView?.({ block: "start" });
      else if (tries++ < 30) frame = requestAnimationFrame(seek);
    };
    seek();
    return () => cancelAnimationFrame(frame);
  }, [document.id, document.body, section]);

  const { sourceUrl } = document;
  return (
    <div ref={topRef}>
      {sourceUrl ? (
        <p data-document-source className="mb-3 flex flex-wrap items-baseline gap-x-2 border-b border-stroke pb-2 text-[11px] text-content/50">
          <span>Source</span>
          <a href={sourceUrl} title={sourceUrl} className="min-w-0 truncate text-content/70 hover:underline"
            onClick={(event) => { event.preventDefault(); void openUrl(sourceUrl).catch(() => undefined); }}>{hostOf(sourceUrl)}</a>
          {document.sourceVersion ? <span>{document.sourceVersion}</span> : null}
          {document.fetchedAt ? <span>saved {new Date(document.fetchedAt).toLocaleDateString()}</span> : null}
        </p>
      ) : null}
      <div ref={bodyRef} className="select-text">
        <AgentMarkdown text={document.body} wholeDocument sourceUrl={sourceUrl} />
      </div>
      <DocumentSelectionMenu document={document} agentId={agentId} selection={selection} onDismiss={dismiss} />
    </div>
  );
}
