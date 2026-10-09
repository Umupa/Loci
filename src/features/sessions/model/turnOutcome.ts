import type { Block } from "./session";

/** How a turn ended, for a caller that started it and waits on its result. */
export type TurnOutcome = {
  status: "completed" | "failed" | "cancelled";
  /** The turn's answer: the last thing the agent said in it. */
  text: string;
  error?: string;
};

/** The last prose of the latest turn; earlier prose was narration. */
export function latestTurnReply(blocks: readonly Block[]): string {
  for (let i = blocks.length - 1; i >= 0; i--) {
    const block = blocks[i];
    if (block.role === "user") break;
    if (block.role === "assistant" && !block.tool && block.text.trim())
      return block.text;
  }
  return "";
}

/** The outcome of a turn that has just ended, from the chat as it stands. */
export function turnOutcome(
  blocks: readonly Block[],
  status: TurnOutcome["status"],
  error?: string,
): TurnOutcome {
  return {
    status,
    text: latestTurnReply(blocks),
    ...(status === "failed"
      ? { error: error?.trim() || "The turn did not finish." }
      : {}),
  };
}
