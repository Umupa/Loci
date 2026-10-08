import type { Block } from "../../sessions/model/session";

/** A quote shorter than this, counted in letters and digits, proves nothing. */
export const QUOTE_MIN = 6;

/** Only letters and digits take part, so an agent may copy with different spacing or punctuation. */
export function normalizeQuote(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
}

/**
 * What the learner typed in this session, one entry per message. Lines quoted
 * from a file (`> …`, as "Add to chat" writes them) are someone else's words.
 */
export function learnerTexts(blocks: readonly Block[], fromIndex = 0): string[] {
  return blocks.slice(fromIndex)
    .filter((block) => block.role === "user" && !block.draft)
    .map((block) => block.text.split("\n").filter((line) => !/^\s*>/.test(line)).join("\n"));
}

/** Whether `quote` is a passage of one message the learner typed, from `fromIndex` on. */
export function saidByLearner(blocks: readonly Block[], quote: string, fromIndex = 0): boolean {
  const wanted = normalizeQuote(quote);
  if (wanted.length < QUOTE_MIN) return false;
  return learnerTexts(blocks, fromIndex).some((text) => normalizeQuote(text).includes(wanted));
}

/** The longest edge label, in columns: a wide character such as a CJK one counts as two. */
export const EDGE_LABEL_COLUMNS = 28;

export function labelColumns(label: string): number {
  let width = 0;
  for (const char of label) width += /[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe30-\ufe4f\uff00-\uff60\uffe0-\uffe6]/.test(char) ? 2 : 1;
  return width;
}

/** An edge label is short, so it only has to be lifted from the learner's wording. */
export function wordedByLearner(blocks: readonly Block[], label: string): boolean {
  const wanted = normalizeQuote(label);
  return wanted.length >= 2 && learnerTexts(blocks).some((text) => normalizeQuote(text).includes(wanted));
}
