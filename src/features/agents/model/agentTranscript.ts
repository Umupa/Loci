import { invoke } from "@tauri-apps/api/core";
import {
  sessionConversationPage,
  type SessionReadOptions,
} from "../../agent-app/model/sessionConversation";
import {
  hydrateStoredBlocks,
  sanitizeSessionForPersist,
} from "../../sessions/data/sessionStore";
import {
  hasPendingApproval,
  type Block,
  type Session,
} from "../../sessions/model/session";

/**
 * An agent's chat never ends, so its transcript would grow without bound and
 * every save and render with it. Past this many turns the oldest are moved to
 * pages in the store (see `src-tauri/src/agent_transcript.rs`), leaving a
 * recent window in the session itself.
 */
export const LIVE_TURNS_MAX = 60;
/** How many turns stay after archiving, so it happens in batches. */
export const LIVE_TURNS_KEPT = 40;

/** Where each turn starts: at a message the user, or the app for them, sent. */
function turnStarts(blocks: readonly Block[]): number[] {
  const starts: number[] = [];
  blocks.forEach((block, index) => {
    if (block.role === "user" && !block.draft) starts.push(index);
  });
  return starts;
}

/** The whole turns to move out, oldest first, and what stays; nothing while the chat is short. */
export function planArchive(
  blocks: readonly Block[],
): { archived: Block[]; kept: Block[] } | undefined {
  const starts = turnStarts(blocks);
  if (starts.length <= LIVE_TURNS_MAX) return undefined;
  const cut = starts[starts.length - LIVE_TURNS_KEPT];
  return { archived: blocks.slice(0, cut), kept: blocks.slice(cut) };
}

/** Whether nothing in the chat is in motion, so its older turns can be moved. */
export function canArchive(
  session: Pick<Session, "busy" | "blocks" | "pendingQuestion" | "queuedMessages">,
): boolean {
  return (
    !session.busy &&
    !session.pendingQuestion &&
    !session.queuedMessages?.length &&
    !hasPendingApproval(session.blocks)
  );
}

/**
 * Moves the chat's oldest turns to a page and returns what stays, or nothing
 * when there is nothing to move. The page is written first, keyed by its
 * first block, so a crash before the session is saved archives nothing twice.
 */
export async function archiveOlderTurns(
  session: Session,
): Promise<Block[] | undefined> {
  const plan = planArchive(session.blocks);
  if (!plan) return undefined;
  const blocks = sanitizeSessionForPersist({
    ...session,
    blocks: plan.archived,
  }).blocks;
  if (!blocks.length) return plan.kept;
  await invoke("agent_transcript_append", {
    sessionId: session.id,
    firstBlockId: blocks[0].id,
    blocksJson: JSON.stringify(blocks),
  });
  return plan.kept;
}

export type TranscriptPage = {
  /** Pass as `before` for the page older than this one. */
  seq: number;
  blocks: Block[];
  hasOlder: boolean;
};

/** The newest archived page older than `before`, or the newest of all. */
export async function loadTranscriptPage(
  sessionId: string,
  before?: number,
): Promise<TranscriptPage | undefined> {
  const page = await invoke<{
    seq: number;
    blocksJson: string;
    hasOlder: boolean;
  } | null>("agent_transcript_page", { sessionId, before: before ?? null });
  if (!page) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(page.blocksJson);
  } catch {
    parsed = [];
  }
  return {
    seq: page.seq,
    blocks: hydrateStoredBlocks(parsed),
    hasOlder: page.hasOlder,
  };
}

/**
 * The agent reads its own chat through the app CLI. The live window answers
 * first; archived pages are read only as far back as the request reaches.
 */
export async function readAgentConversation(
  session: Session,
  options: SessionReadOptions,
  loadPage: typeof loadTranscriptPage = loadTranscriptPage,
) {
  // Validate limits before fetching anything.
  sessionConversationPage({ ...session, blocks: [] }, { ...options, before: undefined });
  let blocks = session.blocks;
  let cursor: number | undefined;
  let exhausted = false;
  const older = async () => {
    if (exhausted) return false;
    const page = await loadPage(session.id, cursor);
    if (!page) {
      exhausted = true;
      return false;
    }
    blocks = [...page.blocks, ...blocks];
    cursor = page.seq;
    exhausted = !page.hasOlder;
    return true;
  };
  const before = options.before;
  while (before && !blocks.some((block) => block.id === before)) {
    if (!(await older())) break;
  }
  let result = sessionConversationPage({ ...session, blocks }, options);
  // A page boundary can leave fewer exchanges than asked for.
  while (result.turns.length < (options.limit ?? 3) && (await older())) {
    result = sessionConversationPage({ ...session, blocks }, options);
  }
  if (!result.nextBefore && result.turns.length && !exhausted) {
    // More remains in pages not read yet.
    if ((await loadPage(session.id, cursor)) != null)
      result.nextBefore = result.turns[0].turnId;
  }
  return result;
}
