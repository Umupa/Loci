import type { MarkSpec } from "../../learning/ui/useReadingMarks";
import type { AgentDocument } from "../../sessions/model/cards";

/** What a document's passages are kept on and cited as: its library entry, or the page it was taken from. */
export function documentMarkSpec(document: AgentDocument, agentId?: string): MarkSpec {
  if (agentId) return {
    target: { kind: "document", agentId, documentId: document.id },
    source: (anchor, quote, annotationId) => {
      const section = anchor.headings?.[anchor.headings.length - 1];
      return { id: crypto.randomUUID(), kind: "document", agentId, documentId: document.id, title: document.title, quote,
        ...(document.sourceUrl ? { url: document.sourceUrl } : {}), ...(section ? { section } : {}), anchor, ...(annotationId ? { annotationId } : {}) };
    },
  };
  if (document.sourceUrl) {
    const url = document.sourceUrl;
    return { source: (_anchor, quote) => ({ id: crypto.randomUUID(), kind: "web", url, title: document.title, quote }) };
  }
  return {};
}
