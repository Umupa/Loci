import { useSyncExternalStore } from "react";

/** Where in a library document a reader is asked to go: a heading, a quoted passage, a highlight. */
export type DocumentPlace = { section?: string; quote?: string; annotationId?: string };
/** `token` tells two requests for the same place apart. */
export type DocumentPlaceRequest = DocumentPlace & { token: number };

const requests = new Map<string, DocumentPlaceRequest>();
const listeners = new Set<() => void>();
let counter = 0;

const key = (agentId: string, documentId: string) => `${agentId}\n${documentId}`;
function notify() { for (const listener of listeners) listener(); }

/** Ask the reader showing this document, now or once it opens, to show a place in it. */
export function requestDocumentPlace(agentId: string, documentId: string, place: DocumentPlace): void {
  requests.set(key(agentId, documentId), { ...place, token: ++counter });
  notify();
}

/** The reader has shown the place; the request does not outlive the opening that made it. */
export function consumeDocumentPlace(agentId: string, documentId: string, token: number): void {
  if (requests.get(key(agentId, documentId))?.token !== token) return;
  requests.delete(key(agentId, documentId));
  notify();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

export function useDocumentPlace(agentId: string | undefined, documentId: string): DocumentPlaceRequest | undefined {
  return useSyncExternalStore(subscribe, () => agentId ? requests.get(key(agentId, documentId)) : undefined, () => undefined);
}
