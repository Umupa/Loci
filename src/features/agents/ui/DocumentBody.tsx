import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { openUrl } from "@tauri-apps/plugin-opener";
import { PenLine } from "../../../shared/ui/icons";
import { sectionHeadingIndex } from "../../../shared/lib/markdown/markdownSection";
import { useFileSelection } from "../../files/hooks/useFileSelection";
import type { AgentDocument } from "../../sessions/model/cards";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import type { StoredDocument } from "../model/agentDocuments";
import { ReadingSelectionMenu } from "../../learning/ui/ReadingSelectionMenu";
import { useReadingMarks, type MarksListRequest } from "../../learning/ui/useReadingMarks";
import { documentMarkSpec } from "../model/documentMarks";
import { inLesson } from "../../learning/model/annotationCounts";
import { consumeDocumentPlace, useDocumentPlace } from "../model/documentPlace";
import { quoteInText, rangeAt, textIndex } from "../../learning/model/textAnchor";
import { flashRange } from "../../learning/ui/useTextHighlights";
import "./DocumentBody.css";

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

/** The heading a lesson starts at: the one named, or failing that the first that contains the name. */
export function findSection(root: HTMLElement, section: string): HTMLElement | undefined {
  const headings = [...root.querySelectorAll<HTMLElement>("h1, h2, h3, h4, h5, h6")]
    .filter((heading) => !heading.closest("blockquote, li, [data-footnotes]"));
  return headings[sectionHeadingIndex(headings.map((heading) => heading.textContent ?? ""), section)];
}

type Props = {
  document: AgentDocument;
  /** The agent whose library it is in: selected text is put to that agent. */
  agentId?: string;
  /** A heading to focus on, with an option to read the full document. */
  section?: string;
  /**
   * Only the text: no section breadcrumb or source line. A course lesson is
   * read this way; its course already says where the reader is.
   */
  bare?: boolean;
  /** Show the list of highlights and notes, dropping from this anchor. */
  marksList?: MarksListRequest;
  /** How many highlights the document has, for a menu to say. */
  onMarks?: (count: number) => void;
};

/**
 * A document's text, for reading. A source says where it was published and
 * shows that page's pictures. Selecting text offers to ask about, highlight or
 * note the passage; its highlights are painted on the text.
 */
export function DocumentBody({ document, agentId, section, bare, marksList, onMarks }: Props) {
  const requestedSection = section?.trim() || undefined;
  const scope = JSON.stringify([document.id, requestedSection]);
  const [view, setView] = useState({ scope, full: false });
  if (view.scope !== scope) setView({ scope, full: false });
  const fullDocument = view.scope === scope && view.full;
  const [matchedTitle, setMatchedTitle] = useState<string>();
  const topRef = useRef<HTMLDivElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const { selection, dismiss } = useFileSelection(bodyRef, true);
  const spec = useMemo(() => documentMarkSpec(document, agentId), [document, agentId]);
  const marks = useReadingMarks(bodyRef, spec, { agentId });
  // A lesson reading one section lists and counts that section's marks, as its outline does.
  const shownMarks = useMemo(() => bare && requestedSection
    ? marks.annotations.filter((annotation) => inLesson({ id: "", title: "", document: document.id, section: requestedSection }, annotation))
    : marks.annotations, [marks.annotations, bare, requestedSection, document.id]);
  const count = shownMarks.length;
  useEffect(() => { onMarks?.(count); }, [onMarks, count]);

  useLayoutEffect(() => {
    const root = bodyRef.current;
    if (!root) return;
    // Saved documents render synchronously in Streamdown's static mode.
    const heading = requestedSection ? findSection(root, requestedSection) : undefined;
    setMatchedTitle(heading?.textContent ?? undefined);
    if (heading) heading.setAttribute("data-section-target", "");
    const frame = requestAnimationFrame(() => {
      if (fullDocument && heading) {
        heading.scrollIntoView?.({ block: "center", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
      } else topRef.current?.scrollIntoView?.({ block: "start", behavior: "instant" });
    });
    return () => { cancelAnimationFrame(frame); heading?.removeAttribute("data-section-target"); };
  }, [document.id, document.body, requestedSection, fullDocument]);

  // A place asked for from outside (a mentor's link, a command): the quoted passage, flashed,
  // else its section. A lesson showing one section widens to the whole document when the
  // passage lies outside it.
  const placeRequest = useDocumentPlace(agentId, document.id);
  const [notice, setNotice] = useState<{ scope: string; text: string }>();
  const { annotations, select } = marks;
  useEffect(() => {
    if (!placeRequest || !agentId) return;
    let timer = 0;
    const show = (tries: number) => {
      const root = bodyRef.current;
      if (!root) { if (tries > 0) timer = window.setTimeout(() => show(tries - 1), 50); return; }
      const mark = placeRequest.annotationId ? annotations.find((entry) => entry.id === placeRequest.annotationId) : undefined;
      if (mark && marks.rangeOf(mark.id)) { select(mark); consumeDocumentPlace(agentId, document.id, placeRequest.token); return; }
      const heading = placeRequest.section ? findSection(root, placeRequest.section) : undefined;
      let range: Range | null = null;
      if (placeRequest.quote) {
        const index = textIndex(root);
        const near = heading ? index.pieces.find((piece) => heading.contains(piece.node))?.start ?? 0 : 0;
        const found = quoteInText(index.text, placeRequest.quote, near);
        range = found ? rangeAt(index, found.start, found.end) : null;
      }
      const wanted = placeRequest.quote ? !!range : placeRequest.section ? !!heading : true;
      if (!wanted && tries > 0) { timer = window.setTimeout(() => show(tries - 1), 50); return; }
      if (!wanted && requestedSection && !fullDocument) { setView({ scope, full: true }); return; }
      if (range) flashRange(range);
      else heading?.scrollIntoView?.({ block: "start" });
      if (placeRequest.quote && !range) setNotice({ scope, text: heading ? "That passage has changed; showing its section." : "That passage is no longer in this document." });
      consumeDocumentPlace(agentId, document.id, placeRequest.token);
    };
    // After the layout effect has put the document at its start.
    timer = window.setTimeout(() => show(20), 60);
    return () => window.clearTimeout(timer);
  }, [placeRequest, agentId, document.id, document.body, fullDocument, annotations]); // eslint-disable-line react-hooks/exhaustive-deps

  const { sourceUrl } = document;
  return (
    <div ref={topRef}>
      {requestedSection && !bare ? <div className="document-section-bar">
        <nav aria-label="Document section" className="document-section-path"><span>{document.title}</span><span aria-hidden="true">/</span><span aria-current="location">{matchedTitle ?? requestedSection}</span></nav>
        {matchedTitle ? <button type="button" className="document-section-toggle" onClick={() => { dismiss(); setView({ scope, full: !fullDocument }); }}>{fullDocument ? "Only this section" : "View full document"}</button> : null}
      </div> : null}
      {requestedSection && !matchedTitle && !bare ? <p role="status" className="document-section-notice">Section “{requestedSection}” was not found. Showing the full document.</p> : null}
      {notice?.scope === scope ? <p role="status" className="document-section-notice">{notice.text}</p> : null}
      {sourceUrl && !bare ? (
        <p data-document-source className="mb-3 flex flex-wrap items-baseline gap-x-2 border-b border-stroke pb-2 text-[11px] text-content/50">
          <span>Source</span>
          <a href={sourceUrl} title={sourceUrl} className="min-w-0 truncate text-content/70 hover:underline"
            onClick={(event) => { event.preventDefault(); void openUrl(sourceUrl).catch(() => undefined); }}>{hostOf(sourceUrl)}</a>
          {document.sourceVersion ? <span>{document.sourceVersion}</span> : null}
          {document.fetchedAt ? <span>saved {new Date(document.fetchedAt).toLocaleDateString()}</span> : null}
        </p>
      ) : agentId && !sourceUrl ? (
        // The mentor's own writing is never mistaken for what someone else published.
        <p data-document-guide className="document-guide-label">
          <PenLine aria-hidden className="size-3 shrink-0" />
          <span>Mentor's guide</span>
          <span className="document-guide-note">written by your mentor, not a first-hand source</span>
        </p>
      ) : null}
      <div ref={bodyRef} className="select-text" data-reading-text>
        <AgentMarkdown text={document.body} wholeDocument sourceUrl={sourceUrl} section={fullDocument ? undefined : requestedSection} />
      </div>
      <ReadingSelectionMenu selection={selection} onDismiss={dismiss} askLabel={marks.askLabel} toChat={marks.toChat} onMark={marks.onMark}
        resetKey={JSON.stringify([document.id, document.body, document.title, document.sourceUrl, agentId])} />
      {marks.popover}
      {marksList ? marks.listPopover(marksList.anchor, marksList.onClose, marksList.title, shownMarks) as ReactNode : null}
    </div>
  );
}
