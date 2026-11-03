import type { Block } from "../../sessions/model/session";
import { loadTranscriptPage, type TranscriptPage } from "./agentTranscript";

/** Archived turns read back for one conversation, and where the next read starts. */
export type EarlierPages = {
  blocks: Block[];
  /** The newest page, read ahead but not shown yet. */
  next?: TranscriptPage;
  /** Pass as `before` for the page older than `blocks`. */
  before?: number;
};

/** Whether older turns remain to read or show. */
export function hasEarlierPages(shown: EarlierPages | undefined): boolean {
  return !!shown?.next || shown?.before !== undefined;
}

/**
 * Reads the next archived page for a conversation. `append` false only looks
 * ahead at the newest page, so a pane can tell whether history exists; true
 * moves that page, or the next older one, into `blocks`.
 */
export async function readEarlierPage(
  sessionId: string,
  shown: EarlierPages | undefined,
  append: boolean,
  load: (sessionId: string, before?: number) => Promise<TranscriptPage | undefined> = loadTranscriptPage,
): Promise<EarlierPages> {
  if (shown && (!append || !hasEarlierPages(shown))) return shown;
  const page = shown?.next ?? await load(sessionId, shown?.before);
  if (!shown) return { blocks: [], next: page };
  // The cursor ran past the oldest page: what is shown stays, and no cursor is kept.
  if (!page) return { blocks: shown.blocks };
  return { blocks: [...page.blocks, ...shown.blocks], ...(page.hasOlder ? { before: page.seq } : {}) };
}

/** Archived blocks not also in the live transcript, to show before it. */
export function earlierBlocks(shown: EarlierPages | undefined, live: readonly Block[]): Block[] | undefined {
  const blocks = shown?.blocks;
  if (!blocks?.length) return blocks;
  const liveIds = new Set(live.map((block) => block.id));
  return blocks.filter((block) => !liveIds.has(block.id));
}
