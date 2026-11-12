import { transport } from "../../../platform/transport";

/** A message the learner sent while a lesson was open beside the chat. */
export type LessonQuestion = { courseId: string; lessonId: string; sessionId: string; messageId: string; text: string; askedAt: number };

/** Fired on `window` when a question is recorded on a lesson. */
export const LESSON_QUESTIONS_EVENT = "loci:lesson-questions";

/** The question's one line: its first line of words, without the quoted passage it may start with. */
export function questionLine(text: string): string {
  const lines = text.replace(/\r\n?/g, "\n").split("\n").map((line) => line.trim());
  const own = lines.find((line) => line && !line.startsWith(">")) ?? lines.find(Boolean) ?? "";
  return own.replace(/\s+/g, " ").slice(0, 300);
}

/** Keeps a message as asked on a lesson. A failure is not the message's: it is only left unrecorded. */
export async function recordLessonQuestion(agentId: string, lesson: { courseId: string; lessonId: string }, sessionId: string, messageId: string, text: string): Promise<void> {
  const line = questionLine(text);
  if (!line) return;
  await transport.call("lesson_question_add", { agentId, courseId: lesson.courseId, lessonId: lesson.lessonId, sessionId, messageId, text: line });
  if (typeof window !== "undefined")
    window.dispatchEvent(new CustomEvent(LESSON_QUESTIONS_EVENT, { detail: { agentId, courseId: lesson.courseId, lessonId: lesson.lessonId } }));
}

/** Questions on a mentor's lessons, newest first: one lesson's, one course's, or all. */
export function loadLessonQuestions(agentId: string, where: { courseId?: string; lessonId?: string; limit?: number } = {}): Promise<LessonQuestion[]> {
  return transport.call<LessonQuestion[]>("lesson_questions_list", {
    agentId, courseId: where.courseId ?? null, lessonId: where.lessonId ?? null, limit: where.limit ?? null,
  });
}
