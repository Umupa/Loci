import { transport } from "../../../platform/transport";
import type { Block } from "../../sessions/model/session";
import type { TextAnchor } from "./types";

/**
 * A message the learner sent while a lesson was open: a question on the
 * lesson, or on a passage of it (`passage`), maybe following up an earlier
 * one (`threadId`, that question's message id). Its answer is the mentor's
 * reply, kept as it read when the turn ended.
 */
export type LessonQuestion = {
  courseId: string; lessonId: string; sessionId: string; messageId: string; text: string; askedAt: number;
  anchor?: string; threadId?: string; answerId?: string; answer?: string;
};

/** Fired on `window` when a question is recorded on a lesson, or answered. */
export const LESSON_QUESTIONS_EVENT = "loci:lesson-questions";

/** The question's one line: its first line of words, without the quoted passage it may start with. */
export function questionLine(text: string): string {
  const lines = text.replace(/\r\n?/g, "\n").split("\n").map((line) => line.trim());
  const own = lines.find((line) => line && !line.startsWith(">")) ?? lines.find(Boolean) ?? "";
  return own.replace(/\s+/g, " ").slice(0, 300);
}

/** Where a question asked from the lesson itself belongs: its passage and the thread it follows up. */
export type LessonAskPlace = { passage?: TextAnchor; threadId?: string };

/** The next message to a session is asked from the lesson, at this place. */
const pendingAsks = new Map<string, LessonAskPlace>();
export function queueLessonAsk(sessionId: string, place: LessonAskPlace): void { pendingAsks.set(sessionId, place); }
export function takeLessonAsk(sessionId: string): LessonAskPlace | undefined {
  const place = pendingAsks.get(sessionId);
  pendingAsks.delete(sessionId);
  return place;
}

/** Questions waiting for their answer to be kept, by message id. */
const awaiting = new Map<string, { agentId: string; sessionId: string; courseId: string; lessonId: string }>();

function changed(agentId: string, courseId: string, lessonId: string) {
  if (typeof window !== "undefined")
    window.dispatchEvent(new CustomEvent(LESSON_QUESTIONS_EVENT, { detail: { agentId, courseId, lessonId } }));
}

/** Keeps a message as asked on a lesson. A failure is not the message's: it is only left unrecorded. */
export async function recordLessonQuestion(agentId: string, lesson: { courseId: string; lessonId: string }, sessionId: string, messageId: string, text: string, place: LessonAskPlace = {}): Promise<void> {
  const line = questionLine(text);
  if (!line) return;
  await transport.call("lesson_question_add", {
    agentId, courseId: lesson.courseId, lessonId: lesson.lessonId, sessionId, messageId, text: line,
    anchor: place.passage ? JSON.stringify(place.passage) : null, threadId: place.threadId ?? null,
  });
  awaiting.set(messageId, { agentId, sessionId, ...lesson });
  changed(agentId, lesson.courseId, lesson.lessonId);
}

/** Questions on a mentor's lessons, newest first: one lesson's, one course's, or all. */
export function loadLessonQuestions(agentId: string, where: { courseId?: string; lessonId?: string; limit?: number } = {}): Promise<LessonQuestion[]> {
  return transport.call<LessonQuestion[]>("lesson_questions_list", {
    agentId, courseId: where.courseId ?? null, lessonId: where.lessonId ?? null, limit: where.limit ?? null,
  });
}

/**
 * The mentor's reply to the message `messageId`: its prose after that
 * message, up to the next one the learner sent. `streaming` while it is still
 * being written; undefined while the message is not in these blocks.
 */
export function answerAfter(blocks: readonly Block[], messageId: string): { id?: string; text: string; streaming: boolean } | undefined {
  const at = blocks.findIndex((block) => block.id === messageId);
  if (at < 0) return undefined;
  const parts: Block[] = [];
  for (const block of blocks.slice(at + 1)) {
    if (block.role === "user" && !block.agentSessionCompletion) break;
    if (block.role === "assistant" && block.text.trim()) parts.push(block);
  }
  return {
    ...(parts.length ? { id: parts[parts.length - 1].id } : {}),
    text: parts.map((block) => block.text.trim()).join("\n\n"),
    streaming: parts.some((block) => block.streaming),
  };
}

/**
 * Keeps the answers of questions whose turn has ended, read from the
 * sessions as they are now. A turn that ended with nothing to say leaves the
 * question unanswered.
 */
export function settleLessonAnswers(sessions: readonly { id: string; busy?: boolean; blocks: readonly Block[] }[]): void {
  for (const [messageId, entry] of awaiting) {
    const session = sessions.find((candidate) => candidate.id === entry.sessionId);
    if (!session || session.busy) continue;
    const answer = answerAfter(session.blocks, messageId);
    if (!answer || answer.streaming) continue;
    if (!answer.id || !answer.text) {
      // The turn may end a moment before its reply lands; only a later message settles that there is none.
      const at = session.blocks.findIndex((block) => block.id === messageId);
      if (session.blocks.slice(at + 1).some((block) => block.role === "user" && !block.agentSessionCompletion)) awaiting.delete(messageId);
      continue;
    }
    awaiting.delete(messageId);
    keepLessonAnswer(entry, messageId, answer.id, answer.text);
  }
}

const kept = new Set<string>();
/**
 * Saves a question's answer once. The reader calls it too, for an answer it
 * shows that was never kept (its turn ended while the app was elsewhere).
 */
export function keepLessonAnswer(where: { agentId: string; courseId: string; lessonId: string }, messageId: string, answerId: string, answer: string): void {
  if (kept.has(messageId)) return;
  kept.add(messageId);
  void transport.call("lesson_question_answer", { agentId: where.agentId, messageId, answerId, answer })
    .then(() => changed(where.agentId, where.courseId, where.lessonId), () => { kept.delete(messageId); });
}

/** A question and those that follow it up, oldest first, on one passage or on the lesson as a whole. */
export type LessonThread = { id: string; passage?: TextAnchor; questions: LessonQuestion[] };

function parsePassage(anchor: string | undefined): TextAnchor | undefined {
  if (!anchor) return undefined;
  try {
    const value = JSON.parse(anchor) as TextAnchor;
    return value && typeof value === "object" && typeof value.exact === "string" ? value : undefined;
  } catch { return undefined; }
}

/** Questions (in any order) as threads, oldest first; a follow-up whose first question is gone starts its own. */
export function lessonThreads(questions: readonly LessonQuestion[]): LessonThread[] {
  const ordered = [...questions].sort((a, b) => a.askedAt - b.askedAt || a.messageId.localeCompare(b.messageId));
  const threads = new Map<string, LessonThread>();
  for (const question of ordered) {
    const parent = question.threadId && threads.get(question.threadId);
    if (parent) { parent.questions.push(question); continue; }
    const passage = parsePassage(question.anchor);
    threads.set(question.messageId, { id: question.messageId, ...(passage ? { passage } : {}), questions: [question] });
  }
  return [...threads.values()];
}

/** Asking from a lesson, sent straight to its mentor: on a passage, following up a thread, or on the lesson as a whole. */
export type LessonAsk = { agentId: string; sessionId: string; question: string; passage?: TextAnchor; threadId?: string };
export const LESSON_ASK_EVENT = "loci:lesson-ask";

/** The message a lesson ask sends: the passage quoted first, when it is the first question on it. */
export function lessonAskText(ask: Pick<LessonAsk, "question" | "passage" | "threadId">): string {
  const question = ask.question.trim();
  if (!ask.passage || ask.threadId) return question;
  const quote = ask.passage.exact.trim().replace(/\s+/g, " ").slice(0, 600);
  return `> ${quote}\n\n${question}`;
}

export function askOnLesson(ask: LessonAsk): void {
  if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent<LessonAsk>(LESSON_ASK_EVENT, { detail: ask }));
}
