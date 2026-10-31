import { useSyncExternalStore } from "react";

/** A section a reader was asked to show in a library document; `token` tells two requests apart. */
export type DocumentSectionRequest = { section: string; token: number };

const requests = new Map<string, DocumentSectionRequest>();
const listeners = new Set<() => void>();
let counter = 0;

const key = (agentId: string, documentId: string) => `${agentId}\n${documentId}`;
function notify() { for (const listener of listeners) listener(); }

/** Ask the reader showing this document, now or once it opens, to scroll to a section. */
export function requestDocumentSection(agentId: string, documentId: string, section: string): void {
  requests.set(key(agentId, documentId), { section, token: ++counter });
  notify();
}

/** The reader has shown the section; the request does not outlive the opening that made it. */
export function consumeDocumentSection(agentId: string, documentId: string, token: number): void {
  if (requests.get(key(agentId, documentId))?.token !== token) return;
  requests.delete(key(agentId, documentId));
  notify();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

export function useDocumentSection(agentId: string | undefined, documentId: string): DocumentSectionRequest | undefined {
  return useSyncExternalStore(subscribe, () => agentId ? requests.get(key(agentId, documentId)) : undefined, () => undefined);
}
