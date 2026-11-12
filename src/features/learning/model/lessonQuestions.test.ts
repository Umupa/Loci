import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Block } from "../../sessions/model/session";
import { answerAfter, lessonAskText, lessonThreads, queueLessonAsk, recordLessonQuestion, settleLessonAnswers, takeLessonAsk, type LessonQuestion } from "./lessonQuestions";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));

const passage = { exact: "kubelet watches", prefix: "", suffix: "", start: 10, end: 25 };
const question = (messageId: string, askedAt: number, extra: Partial<LessonQuestion> = {}): LessonQuestion =>
  ({ courseId: "c", lessonId: "l", sessionId: "s", messageId, text: messageId, askedAt, ...extra });
const blocks = (streaming = false) => [
  { id: "q1", role: "user", text: "Why?" },
  { id: "t", role: "tool", text: "" },
  { id: "a1", role: "assistant", text: "Because it lists again." },
  { id: "a2", role: "assistant", text: "Then compares.", streaming },
  { id: "q2", role: "user", text: "And?" },
] as unknown as Block[];

beforeEach(() => vi.mocked(invoke).mockClear());

describe("questions asked on a lesson", () => {
  it("reads the mentor's reply after a message, up to the next one", () => {
    expect(answerAfter(blocks(), "q1")).toEqual({ id: "a2", text: "Because it lists again.\n\nThen compares.", streaming: false });
    expect(answerAfter(blocks(true), "q1")?.streaming).toBe(true);
    expect(answerAfter(blocks(), "q2")).toEqual({ text: "", streaming: false });
    expect(answerAfter(blocks(), "gone")).toBeUndefined();
  });

  it("groups follow-ups under the question they follow, on its passage", () => {
    const threads = lessonThreads([
      question("q3", 3, { threadId: "q1" }),
      question("q1", 1, { anchor: JSON.stringify(passage) }),
      question("q2", 2),
      question("q4", 4, { threadId: "missing" }),
    ]);
    expect(threads.map((thread) => [thread.id, thread.questions.map((entry) => entry.messageId), !!thread.passage])).toEqual([
      ["q1", ["q1", "q3"], true], ["q2", ["q2"], false], ["q4", ["q4"], false],
    ]);
  });

  it("quotes the passage on the first question only", () => {
    expect(lessonAskText({ question: " Why? ", passage })).toBe("> kubelet watches\n\nWhy?");
    expect(lessonAskText({ question: "And then?", passage, threadId: "q1" })).toBe("And then?");
    expect(lessonAskText({ question: "On the lesson" })).toBe("On the lesson");
  });

  it("records the place an ask came from, and keeps the answer once the turn ends", async () => {
    queueLessonAsk("s", { passage, threadId: "q0" });
    const place = takeLessonAsk("s");
    expect(takeLessonAsk("s")).toBeUndefined();
    await recordLessonQuestion("a", { courseId: "c", lessonId: "l" }, "s", "q1", "> kubelet watches\n\nWhy?", place);
    expect(invoke).toHaveBeenCalledWith("lesson_question_add", expect.objectContaining({ messageId: "q1", text: "Why?", anchor: JSON.stringify(passage), threadId: "q0" }));
    settleLessonAnswers([{ id: "s", busy: true, blocks: blocks() }]);
    // Idle before the reply has landed: still waiting for it.
    settleLessonAnswers([{ id: "s", busy: false, blocks: blocks().slice(0, 2) }]);
    expect(invoke).not.toHaveBeenCalledWith("lesson_question_answer", expect.anything());
    settleLessonAnswers([{ id: "s", busy: false, blocks: blocks() }]);
    expect(invoke).toHaveBeenCalledWith("lesson_question_answer", { agentId: "a", messageId: "q1", answerId: "a2", answer: "Because it lists again.\n\nThen compares." });
    vi.mocked(invoke).mockClear();
    settleLessonAnswers([{ id: "s", busy: false, blocks: blocks() }]);
    expect(invoke).not.toHaveBeenCalled();
  });
});
