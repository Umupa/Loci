import { useTurnCelebration } from "./turnCelebration";
import "./MessageSendAccent.css";

const SEND_ACCENT_MS = 850;

/** A short receipt for a fresh send, independent of the agent's progress. */
export function MessageSendAccent({ blockId, startedAt }: {
  blockId: string;
  startedAt?: number;
}) {
  const active = useTurnCelebration(blockId, startedAt, SEND_ACCENT_MS);
  return active ? <span data-message-send-accent aria-hidden className="message-send-accent" /> : null;
}
