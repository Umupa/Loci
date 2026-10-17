import { describe,expect,it } from "vitest";
import {
CUSTOM_OPTION_ID,
buildQuestionReply,
questionAnswersComplete,
questionIsComplete,
questionPromptTitle,
questionsFromUnknown,
selectedAnswerLabels,
} from "./userQuestion";

describe("questionsFromUnknown", () => {
  it("parses Claude-style AskUserQuestion input", () => {
    const questions = questionsFromUnknown({
      questions: [
        {
          header: "Format",
          question: "How should I format the output?",
          multiSelect: false,
          options: [
            { label: "Summary", description: "Brief overview" },
            { label: "Detailed", description: "Full explanation" },
          ],
        },
        {
          header: "Sections",
          question: "Which sections should I include?",
          multiSelect: true,
          options: [
            { label: "Introduction" },
            { label: "Conclusion" },
          ],
        },
      ],
    });
    expect(questions).toHaveLength(2);
    expect(questions[0]).toMatchObject({
      prompt: "How should I format the output?",
      header: "Format",
      multiSelect: false,
      allowCustom: true,
    });
    expect(questions[1]?.multiSelect).toBe(true);
    expect(questionPromptTitle(questions)).toBe("Format");
  });

  it("parses prompt-shaped ask_question params without adding Other", () => {
    const questions = questionsFromUnknown({
      title: "Need input",
      questions: [
        {
          id: "q1",
          prompt: "Which mode should I use?",
          allowMultiple: true,
          options: [
            { id: "agent", label: "Agent" },
            { id: "plan", label: "Plan" },
          ],
        },
      ],
    });
    expect(questions[0]).toMatchObject({
      id: "q1",
      prompt: "Which mode should I use?",
      multiSelect: true,
      allowCustom: false,
    });
    expect(questions[0]?.options.map((option) => option.id)).toEqual([
      "agent",
      "plan",
    ]);
  });

  it("honors custom/multiple flags", () => {
    const questions = questionsFromUnknown({
      questions: [
        {
          question: "Pick a name",
          multiple: false,
          custom: false,
          options: [{ label: "Alpha" }],
        },
      ],
    });
    expect(questions[0]).toMatchObject({
      prompt: "Pick a name",
      multiSelect: false,
      allowCustom: false,
    });
  });
});

describe("question answers", () => {
  const questions = questionsFromUnknown({
    questions: [
      {
        question: "Which file?",
        options: [{ label: "a.ts" }, { label: "b.ts" }],
      },
    ],
  });
  const question = questions[0]!;

  it("requires a selection before continue", () => {
    expect(questionAnswersComplete(questions, {}, {})).toBe(false);
    expect(
      questionAnswersComplete(questions, { [question.id]: ["a.ts"] }, {}),
    ).toBe(true);
  });

  it("requires custom text when Other is selected", () => {
    expect(
      questionAnswersComplete(
        questions,
        { [question.id]: [CUSTOM_OPTION_ID] },
        {},
      ),
    ).toBe(false);
    expect(
      questionAnswersComplete(
        questions,
        { [question.id]: [CUSTOM_OPTION_ID] },
        { [question.id]: "c.ts" },
      ),
    ).toBe(true);
  });

  it("maps selected ids back to labels and custom text", () => {
    expect(
      selectedAnswerLabels(question, {
        kind: "answered",
        answers: { [question.id]: ["b.ts"] },
      }),
    ).toEqual(["b.ts"]);
    expect(
      selectedAnswerLabels(question, {
        kind: "answered",
        answers: { [question.id]: [CUSTOM_OPTION_ID] },
        custom: { [question.id]: "c.ts" },
      }),
    ).toEqual(["c.ts"]);
  });

  it("preserves supplemental custom text when the UI enabled multiple answers", () => {
    expect(
      selectedAnswerLabels(question, {
        kind: "answered",
        answers: { [question.id]: ["a.ts", "b.ts"] },
        custom: { [question.id]: "  c.ts  " },
      }),
    ).toEqual(["a.ts", "b.ts", "c.ts"]);
  });

  it("includes explicit Other text once among multiple answers", () => {
    const explicitOther = {
      ...question,
      options: [...question.options, { id: "other", label: "Other" }],
    };
    expect(
      selectedAnswerLabels(explicitOther, {
        kind: "answered",
        answers: { [question.id]: ["a.ts", "other", "b.ts"] },
        custom: { [question.id]: "c.ts" },
      }),
    ).toEqual(["a.ts", "c.ts", "b.ts"]);
  });

  it("ignores supplemental custom text when custom answers are disabled", () => {
    expect(
      selectedAnswerLabels({ ...question, allowCustom: false }, {
        kind: "answered",
        answers: { [question.id]: ["a.ts"] },
        custom: { [question.id]: "c.ts" },
      }),
    ).toEqual(["a.ts"]);
  });
});

describe("buildQuestionReply", () => {
  const questions = questionsFromUnknown({
    questions: [
      {
        question: "Language?",
        header: "Language",
        options: [{ label: "TypeScript" }, { label: "JavaScript" }],
      },
      {
        question: "Which files?",
        header: "Files",
        multiSelect: true,
        options: [{ label: "a.ts" }, { label: "b.ts" }],
      },
    ],
  });
  const language = questions[0]!;
  const files = questions[1]!;

  it("skips the whole prompt when no question was answered", () => {
    expect(buildQuestionReply(questions, {}, {})).toEqual({ kind: "skipped" });
    expect(questionIsComplete(language, {}, {})).toBe(false);
  });

  it("keeps answers for questions that were filled and drops skipped ones", () => {
    expect(
      buildQuestionReply(
        questions,
        { [files.id]: ["a.ts", "b.ts"] },
        {},
      ),
    ).toEqual({
      kind: "answered",
      answers: { [files.id]: ["a.ts", "b.ts"] },
    });
  });

  it("includes every completed question", () => {
    expect(
      buildQuestionReply(
        questions,
        {
          [language.id]: [CUSTOM_OPTION_ID],
          [files.id]: ["a.ts"],
        },
        { [language.id]: "Python" },
      ),
    ).toEqual({
      kind: "answered",
      answers: {
        [language.id]: [CUSTOM_OPTION_ID],
        [files.id]: ["a.ts"],
      },
      custom: { [language.id]: "Python" },
    });
  });

  it("accepts a local multi-select override without changing the original question", () => {
    const answers = { [language.id]: ["TypeScript", "JavaScript"] };
    const custom = { [language.id]: "  Python  " };
    expect(buildQuestionReply([language], answers, custom)).toEqual({
      kind: "skipped",
    });
    expect(
      buildQuestionReply([{ ...language, multiSelect: true }], answers, custom),
    ).toEqual({
      kind: "answered",
      answers,
      custom: { [language.id]: "Python" },
    });
    expect(language.multiSelect).toBe(false);
  });

  it("drops a draft custom answer when a single option replaces it", () => {
    const reply = buildQuestionReply(
      [language],
      { [language.id]: ["TypeScript"] },
      { [language.id]: "Python" },
    );
    expect(reply).toEqual({
      kind: "answered",
      answers: { [language.id]: ["TypeScript"] },
    });
  });
});
