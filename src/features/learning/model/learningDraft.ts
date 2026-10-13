import type { AddToChatRequest, QuoteRequest } from "../../sessions/model/quoteDraft";
import type { LearningMessageContext } from "./types";

const contexts = new Map<string, LearningMessageContext>();
const pending = new Map<string, QuoteRequest[]>();
const listeners = new Set<() => void>();
let nextId = 0;

/** Composer state follows its conversation when a pane is moved or remounted. */
export function getLearningDraftContext(sessionId: string): LearningMessageContext {
  return contexts.get(sessionId) ?? {};
}
export function setLearningDraftContext(sessionId: string, context: LearningMessageContext) {
  if (context.sources?.length) contexts.set(sessionId, context);
  else contexts.delete(sessionId);
}

/** Targeted requests wait for the owning session, rather than another visible composer. */
export function queueLearningDraft(sessionId: string, request: AddToChatRequest) {
  const { targetSessionId: _target, ...detail } = request;
  pending.set(sessionId, [...(pending.get(sessionId) ?? []), { ...detail, id: ++nextId }]);
  for (const listener of listeners) listener();
}
export function peekLearningDraft(sessionId: string): QuoteRequest | undefined {
  return pending.get(sessionId)?.[0];
}
export function consumeLearningDraft(sessionId: string, id: number) {
  const requests = pending.get(sessionId);
  if (requests?.[0]?.id !== id) return;
  if (requests.length > 1) pending.set(sessionId, requests.slice(1));
  else pending.delete(sessionId);
  for (const listener of listeners) listener();
}
export function subscribeLearningDraft(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
