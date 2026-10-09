import type { Block } from "./session";
import {
  questionsFromUnknown,
  selectedAnswerLabels,
  type UserQuestion,
  type UserQuestionPrompt,
  type UserQuestionReply,
} from "./userQuestion";

/**
 * A standing question is one no provider request is waiting on: the agent
 * asked, ended its turn, and the answer is simply the user's next message.
 * It stays until it is answered, skipped, or the user writes something else,
 * so it never times out while they are away.
 *
 * Any agent can ask one, whether or not its CLI has a question tool, by
 * ending a reply with a fenced block the app turns into choices:
 *
 * ```loci-question
 * {"questions":[{"header":"Main job","question":"What should I look after?",
 *   "options":[{"label":"One project","description":"Keep its sessions moving"}]}]}
 * ```
 */
export const QUESTION_FENCE = "loci-question";

const BLOCK = new RegExp(
  "(?:^|\\n)[ \\t]*```" + QUESTION_FENCE + "[ \\t]*\\n([\\s\\S]*?)\\n[ \\t]*```[ \\t]*(?=\\n|$)",
  "g",
);

/** The questions an agent's reply asks through a question block, if it has one that reads. */
export function parseQuestionBlock(text: string): UserQuestion[] {
  if (!text.includes(QUESTION_FENCE)) return [];
  let last: string | undefined;
  for (const match of text.matchAll(BLOCK)) last = match[1];
  if (last == null) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(last);
  } catch {
    return [];
  }
  // One question may be written bare, without the list around it.
  const questions = questionsFromUnknown(
    Array.isArray(parsed) ||
      (parsed && typeof parsed === "object" && "questions" in parsed)
      ? parsed
      : { questions: [parsed] },
  );
  // A question nobody can answer by choosing or typing is not one.
  return questions.filter(
    (question) => question.options.length > 0 || question.allowCustom,
  );
}

/** The reply as the user reads it: the block is the form's, not the prose's. */
export function stripQuestionBlock(text: string): string {
  if (!text.includes(QUESTION_FENCE)) return text;
  return text.replace(BLOCK, "").replace(/\n{3,}/g, "\n\n").trimEnd();
}

/** A stable id for a block's question, clear of the ids providers hand out. */
function standingId(blockId: string): number {
  let hash = 0;
  for (let i = 0; i < blockId.length; i++) {
    hash = (hash * 31 + blockId.charCodeAt(i)) | 0;
  }
  return -(Math.abs(hash) + 1);
}

/**
 * The question the chat ends on, when its last reply asked one and the user
 * has not answered since. Derived from the transcript, so it is still there
 * after a restart.
 */
export function standingQuestionFromBlocks(
  blocks: readonly Block[],
): UserQuestionPrompt | undefined {
  for (let i = blocks.length - 1; i >= 0; i--) {
    const block = blocks[i];
    if (block.role === "user") return undefined;
    if (block.role !== "assistant" || block.tool || !block.text.trim()) continue;
    if (block.streaming) return undefined;
    const questions = parseQuestionBlock(block.text);
    if (!questions.length) return undefined;
    const first = questions[0];
    return {
      requestId: standingId(block.id),
      title: first.header || first.prompt,
      questions,
      standing: true,
    };
  }
  return undefined;
}

/**
 * The user's choices as the message they send. One question reads as its
 * answer alone; several keep each question beside its answer.
 */
export function questionReplyText(
  questions: readonly UserQuestion[],
  reply: UserQuestionReply,
): string {
  if (reply.kind === "skipped") return "";
  const answered = questions.flatMap((question) => {
    const answers = selectedAnswerLabels(question, reply);
    return answers.length ? [{ question, answers }] : [];
  });
  if (answered.length === 1) return answered[0].answers.join(", ");
  return answered
    .map(({ question, answers }) => `${question.header || question.prompt}: ${answers.join(", ")}`)
    .join("\n");
}
