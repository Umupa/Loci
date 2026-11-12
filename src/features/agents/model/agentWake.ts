/**
 * What a hidden run needs: an agent's heartbeat works in a session of its
 * own, so the work never piles up in the agent's conversation; only what it
 * decides to tell the user is posted to the chat.
 */

/** Its reply when it has nothing worth posting. */
export const QUIET_MARKER = "NOTHING_TO_REPORT";
/** Working time before a run is stopped. */
export const WAKE_RUN_TIMEOUT_MS = 60 * 60 * 1000;
/** How long a run waits for the user to answer an approval it asked for. */
export const WAKE_APPROVAL_WAIT_MS = 12 * 60 * 60 * 1000;

/** What to post, or nothing when the run chose to stay quiet. */
export function wakeReport(text: string): string | undefined {
  const trimmed = text.trim();
  if (!trimmed) return undefined;
  if (trimmed.replace(/[`*.\s]/g, "") === QUIET_MARKER) return undefined;
  // A run that narrated before deciding to stay quiet ends on the marker.
  if (trimmed.endsWith(QUIET_MARKER) && trimmed.length < 400) return undefined;
  return trimmed.replace(new RegExp(`\\s*${QUIET_MARKER}\\s*$`), "").trim();
}

/**
 * Hidden runs in flight, to the agent each belongs to. Their sessions are
 * ephemeral, so this is all there is.
 */
const runs = new Map<string, string>();

export function markWakeRun(sessionId: string, agentId: string): void {
  runs.set(sessionId, agentId);
}

/** The agent a hidden run works for. */
export function wakeRunAgent(sessionId: string): string | undefined {
  return runs.get(sessionId);
}

export function clearWakeRun(sessionId: string): void {
  runs.delete(sessionId);
}

/**
 * An approval a hidden run asked for, put to the user in the agent's chat
 * under an id of its own: the run's request ids would collide with the
 * agent's. In memory only; a relay outlives neither its run nor the app.
 */
export type ApprovalRelay = {
  /** The agent's conversation the question is put in. */
  chatId: string;
  runId: string;
  requestId: number;
  blockId: string;
};

const relays = new Map<number, ApprovalRelay>();
let nextRelayId = 1_000_000_000;

export function relayApproval(relay: ApprovalRelay): number {
  const id = nextRelayId++;
  relays.set(id, relay);
  return id;
}

/** The relay behind a request in the agent's chat, removed once answered. */
export function takeRelayedApproval(chatId: string, requestId: number): ApprovalRelay | undefined {
  const relay = relays.get(requestId);
  if (!relay || relay.chatId !== chatId) return undefined;
  relays.delete(requestId);
  return relay;
}

/** Whether a run's request has already been put to the user. */
export function isRelayed(runId: string, requestId: number): boolean {
  for (const relay of relays.values())
    if (relay.runId === runId && relay.requestId === requestId) return true;
  return false;
}

/** Relays still open when their run ended, to withdraw from the chat. */
export function dropRelays(runId: string): ApprovalRelay[] {
  const dropped: ApprovalRelay[] = [];
  for (const [id, relay] of relays)
    if (relay.runId === runId) {
      relays.delete(id);
      dropped.push(relay);
    }
  return dropped;
}
