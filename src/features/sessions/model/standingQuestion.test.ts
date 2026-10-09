import { describe, expect, it } from "vitest";
import type { Block } from "./session";
import {
  parseQuestionBlock,
  questionReplyText,
  standingQuestionFromBlocks,
  stripQuestionBlock,
} from "./standingQuestion";

const reply = `Let's settle your main job first.

\`\`\`loci-question
{"questions":[{"header":"Main job","question":"What should I look after?","options":[{"label":"One project","description":"Keep its sessions moving"},{"label":"A regular check"}]}]}
\`\`\``;

describe("question blocks", () => {
  it("turns a reply's block into questions with choices and room for the user's own answer", () => {
    const [question] = parseQuestionBlock(reply);
    expect(question).toMatchObject({ header: "Main job", prompt: "What should I look after?", multiSelect: false });
    expect(question.options.map((option) => option.label)).toEqual(["One project", "A regular check"]);
    expect(question.options[0].description).toBe("Keep its sessions moving");
  });

  it("reads a single question written bare, and several at once", () => {
    expect(parseQuestionBlock('```loci-question\n{"question":"Which?","options":["A","B"]}\n```')).toHaveLength(1);
    expect(parseQuestionBlock('```loci-question\n[{"question":"One?","options":["A"]},{"question":"Two?","multiSelect":true,"options":["B","C"]}]\n```')
      .map((question) => question.multiSelect)).toEqual([false, true]);
  });

  it("asks nothing when the block does not read, or is not there", () => {
    expect(parseQuestionBlock("Just an answer.")).toEqual([]);
    expect(parseQuestionBlock("```loci-question\nnot json\n```")).toEqual([]);
    expect(parseQuestionBlock("```json\n{}\n```")).toEqual([]);
    // Mentioned in prose, not asked.
    expect(parseQuestionBlock("Use a loci-question block for that.")).toEqual([]);
  });

  it("keeps the block out of what the user reads", () => {
    expect(stripQuestionBlock(reply)).toBe("Let's settle your main job first.");
    expect(stripQuestionBlock("No question here.")).toBe("No question here.");
    expect(stripQuestionBlock('```loci-question\n{"question":"Which?","options":["A"]}\n```')).toBe("");
  });
});

describe("standing questions", () => {
  const blocks = (...list: Partial<Block>[]) => list.map((block, index) => ({ id: `b${index}`, text: "", ...block })) as Block[];

  it("is the question the chat ends on, with an id that stays the same", () => {
    const chat = blocks({ role: "user", text: "hi" }, { role: "tool", tool: { title: "Read" } as Block["tool"] }, { role: "assistant", text: reply });
    const question = standingQuestionFromBlocks(chat)!;
    expect(question).toMatchObject({ standing: true, title: "Main job" });
    expect(question.requestId).toBeLessThan(0);
    expect(standingQuestionFromBlocks(chat)!.requestId).toBe(question.requestId);
  });

  it("is gone once the user has written, while a reply is still arriving, or when the last reply asked nothing", () => {
    expect(standingQuestionFromBlocks(blocks({ role: "assistant", text: reply }, { role: "user", text: "One project" }))).toBeUndefined();
    expect(standingQuestionFromBlocks(blocks({ role: "assistant", text: reply, streaming: true }))).toBeUndefined();
    expect(standingQuestionFromBlocks(blocks({ role: "assistant", text: reply }, { role: "assistant", text: "Never mind." }))).toBeUndefined();
    expect(standingQuestionFromBlocks([])).toBeUndefined();
  });

  it("sends one answer as itself, and several beside what they answer", () => {
    const [one] = parseQuestionBlock(reply);
    expect(questionReplyText([one], { kind: "answered", answers: { [one.id]: [one.options[1].id] } })).toBe("A regular check");
    expect(questionReplyText([one], { kind: "answered", answers: {}, custom: { [one.id]: "Watch my inbox" } })).toBe("Watch my inbox");
    expect(questionReplyText([one], { kind: "skipped" })).toBe("");
    const two = parseQuestionBlock('```loci-question\n[{"header":"Job","question":"One?","options":["A"]},{"question":"Two?","multiSelect":true,"options":["B","C"]}]\n```');
    expect(questionReplyText(two, { kind: "answered", answers: { [two[0].id]: [two[0].options[0].id], [two[1].id]: two[1].options.map((option) => option.id) } }))
      .toBe("Job: A\nTwo?: B, C");
  });
});
