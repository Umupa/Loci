// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { QuestionForm } from "./QuestionForm";
import type {
  UserQuestionPrompt,
  UserQuestionReply,
} from "../model/userQuestion";

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

function prompt(multiSelect = false): UserQuestionPrompt {
  return {
    requestId: 7,
    questions: [
      {
        id: "colour",
        prompt: "Pick a colour",
        multiSelect,
        allowCustom: false,
        options: [
          { id: "red", label: "Red" },
          { id: "green", label: "Green" },
          { id: "blue", label: "Blue" },
        ],
      },
    ],
  };
}

function renderQuestion(
  onReply: (requestId: number, reply: UserQuestionReply) => void = vi.fn(),
  multiSelect = false,
) {
  act(() =>
    root.render(
      createElement(QuestionForm, {
        prompt: prompt(multiSelect),
        onReply,
      }),
    ),
  );
  return Array.from(
    container.querySelectorAll<HTMLButtonElement>("button[aria-pressed]"),
  );
}

function keyDown(target: Element, key: string) {
  act(() => {
    target.dispatchEvent(
      new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
    );
  });
}

function button(label: string): HTMLButtonElement {
  const match = Array.from(container.querySelectorAll("button")).find(
    (item) => item.textContent?.trim() === label,
  );
  if (!match) throw new Error(`No button labelled ${label}`);
  return match;
}

function multiSelectToggle(): HTMLInputElement {
  const toggle = container.querySelector<HTMLInputElement>('input[type="checkbox"]');
  if (!toggle) throw new Error("No multi-select toggle");
  return toggle;
}

function typeCustomAnswer(value: string) {
  const input = container.querySelector<HTMLInputElement>('input[placeholder="Type your answer"]')!;
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
}

describe("QuestionForm keyboard navigation", () => {
  it("moves the highlighted option with arrow keys and selects it with Enter", () => {
    const onReply = vi.fn();
    const options = renderQuestion(onReply);

    expect(options[0].tabIndex).toBe(0);
    expect(options[1].tabIndex).toBe(-1);
    act(() => options[0].focus());

    keyDown(options[0], "ArrowDown");
    expect(document.activeElement).toBe(options[1]);
    expect(options[1].dataset.highlighted).toBe("true");
    expect(options[1].tabIndex).toBe(0);

    keyDown(options[1], "Enter");
    expect(options[1].getAttribute("aria-pressed")).toBe("true");

    act(() =>
      container
        .querySelector<HTMLButtonElement>('button[type="submit"]')!
        .click(),
    );
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered",
      answers: { colour: ["green"] },
    });
  });

  it("wraps arrow navigation and supports Home and End", () => {
    const options = renderQuestion();
    act(() => options[0].focus());

    keyDown(options[0], "ArrowUp");
    expect(document.activeElement).toBe(options[2]);

    keyDown(options[2], "Home");
    expect(document.activeElement).toBe(options[0]);

    keyDown(options[0], "End");
    expect(document.activeElement).toBe(options[2]);
  });

  it("uses number keys to focus and select the matching option", () => {
    const options = renderQuestion();
    act(() => options[0].focus());

    keyDown(options[0], "3");

    expect(document.activeElement).toBe(options[2]);
    expect(options[2].getAttribute("aria-pressed")).toBe("true");
    expect(options[2].getAttribute("aria-keyshortcuts")).toBe("3");
  });

  it("toggles highlighted options for multi-select questions", () => {
    const options = renderQuestion(vi.fn(), true);
    act(() => options[0].focus());

    keyDown(options[0], "Enter");
    keyDown(options[0], "ArrowDown");
    keyDown(options[1], " ");

    expect(options[0].getAttribute("aria-pressed")).toBe("true");
    expect(options[1].getAttribute("aria-pressed")).toBe("true");

    keyDown(options[1], " ");
    expect(options[1].getAttribute("aria-pressed")).toBe("false");
  });
});

describe("QuestionForm user-selected multi-select", () => {
  it("lets a single-choice question collect multiple answers with the keyboard", () => {
    const onReply = vi.fn();
    const options = renderQuestion(onReply);
    expect(multiSelectToggle().checked).toBe(false);

    act(() => multiSelectToggle().click());
    expect(container.textContent).toContain("Select all that apply");
    keyDown(options[0], "Enter");
    keyDown(options[0], "ArrowDown");
    keyDown(options[1], " ");

    expect(options[0].getAttribute("aria-pressed")).toBe("true");
    expect(options[1].getAttribute("aria-pressed")).toBe("true");
    expect(onReply).not.toHaveBeenCalled();
    act(() => button("Continue").click());
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered",
      answers: { colour: ["red", "green"] },
    });
  });

  it("keeps the first selected answer when multi-select is disabled", () => {
    const onReply = vi.fn();
    renderQuestion(onReply);
    act(() => multiSelectToggle().click());
    act(() => button("Green").click());
    act(() => button("Red").click());

    act(() => multiSelectToggle().click());

    expect(multiSelectToggle().checked).toBe(false);
    expect(button("Green").getAttribute("aria-pressed")).toBe("true");
    expect(button("Red").getAttribute("aria-pressed")).toBe("false");
    expect(onReply).not.toHaveBeenCalled();
    act(() => button("Continue").click());
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered",
      answers: { colour: ["green"] },
    });
  });

  it("keeps custom-answer validation when Other is the first selected answer", () => {
    const onReply = vi.fn();
    const withCustom = prompt();
    withCustom.questions[0].allowCustom = true;
    act(() => root.render(createElement(QuestionForm, { prompt: withCustom, onReply })));
    act(() => multiSelectToggle().click());
    act(() => button("Other").click());
    act(() => button("Red").click());
    expect(button("Continue").disabled).toBe(true);

    act(() => multiSelectToggle().click());
    expect(button("Other").getAttribute("aria-pressed")).toBe("true");
    expect(button("Red").getAttribute("aria-pressed")).toBe("false");
    expect(button("Continue").disabled).toBe(true);
    typeCustomAnswer("Purple");
    expect(button("Continue").disabled).toBe(false);
    act(() => button("Continue").click());
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered",
      answers: { colour: ["__custom__"] },
      custom: { colour: "Purple" },
    });
  });

  it.each(["deselected during multi-select", "replaced before enabling multi-select"])(
    "does not submit a hidden custom draft %s",
    (transition) => {
      const onReply = vi.fn();
      const withCustom = prompt();
      withCustom.questions[0].allowCustom = true;
      act(() => root.render(createElement(QuestionForm, { prompt: withCustom, onReply })));
      const enabledFirst = transition === "deselected during multi-select";
      if (enabledFirst) act(() => multiSelectToggle().click());
      act(() => button("Other").click());
      typeCustomAnswer("Purple");

      if (enabledFirst) act(() => button("Other").click());
      act(() => button("Red").click());
      if (!enabledFirst) act(() => multiSelectToggle().click());
      expect(container.querySelector('input[placeholder="Type your answer"]')).toBeNull();

      act(() => button("Other").click());
      expect(container.querySelector<HTMLInputElement>('input[placeholder="Type your answer"]')!.value).toBe("Purple");
      act(() => button("Other").click());
      act(() => button("Continue").click());
      expect(onReply).toHaveBeenCalledWith(7, {
        kind: "answered",
        answers: { colour: ["red"] },
      });
    },
  );

  it("resets the selection mode and answers for a new request", () => {
    renderQuestion();
    act(() => multiSelectToggle().click());
    act(() => button("Red").click());
    act(() => button("Green").click());

    act(() => root.render(createElement(QuestionForm, {
      prompt: { ...prompt(), requestId: 8 },
      onReply: vi.fn(),
    })));

    expect(multiSelectToggle().checked).toBe(false);
    expect(button("Red").getAttribute("aria-pressed")).toBe("false");
    expect(button("Green").getAttribute("aria-pressed")).toBe("false");
    expect(button("Continue").disabled).toBe(true);
  });

  it("counts changing the mode as an interaction with an optional question", () => {
    const onInteraction = vi.fn();
    act(() => root.render(createElement(QuestionForm, {
      prompt: { ...prompt(), autoResolveAt: Date.now() + 60_000 },
      onReply: vi.fn(),
      onInteraction,
    })));

    act(() => multiSelectToggle().click());

    expect(onInteraction).toHaveBeenCalledWith(7);
  });

  it("does not offer the toggle for declared multi-select or fewer than two normal options", () => {
    renderQuestion(vi.fn(), true);
    expect(container.querySelector('input[type="checkbox"]')).toBeNull();
    expect(container.textContent).toContain("Select all that apply");

    const oneOption = prompt();
    oneOption.questions[0].options = [
      { id: "red", label: "Red" },
      { id: "other", label: "Other" },
    ];
    oneOption.questions[0].allowCustom = true;
    act(() => root.render(createElement(QuestionForm, { prompt: oneOption, onReply: vi.fn() })));
    expect(container.querySelector('input[type="checkbox"]')).toBeNull();
  });

  it("does not offer multi-select when the provider requires one original option", () => {
    const currentPrompt = prompt();
    currentPrompt.questions[0].allowMultiSelect = false;
    const onReply = vi.fn();
    act(() => root.render(createElement(QuestionForm, { prompt: currentPrompt, onReply })));
    expect(container.querySelector('input[type="checkbox"]')).toBeNull();
    act(() => button("Red").click());
    act(() => button("Green").click());
    act(() => button("Continue").click());
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered", answers: { colour: ["green"] },
    });
  });
});

describe("QuestionForm steps", () => {
  function twoQuestions(): UserQuestionPrompt {
    return {
      requestId: 9,
      questions: [
        {
          id: "colour",
          prompt: "Pick a colour",
          multiSelect: false,
          allowCustom: false,
          options: [
            { id: "red", label: "Red" },
            { id: "green", label: "Green" },
          ],
        },
        {
          id: "size",
          prompt: "Pick a size",
          multiSelect: false,
          allowCustom: false,
          options: [
            { id: "small", label: "Small" },
            { id: "large", label: "Large" },
          ],
        },
      ],
    };
  }

  it("returns to the previous question with its answer and submits the change", () => {
    const onReply = vi.fn();
    act(() =>
      root.render(createElement(QuestionForm, { prompt: twoQuestions(), onReply })),
    );
    expect(container.textContent).not.toContain("Back");

    act(() => button("Red").click());
    act(() => button("Continue").click());
    expect(container.textContent).toContain("Pick a size");

    act(() => button("Back").click());
    expect(container.textContent).toContain("Pick a colour");
    expect(button("Red").getAttribute("aria-pressed")).toBe("true");

    act(() => button("Green").click());
    act(() => button("Continue").click());
    act(() => button("Large").click());
    act(() => button("Continue").click());

    expect(onReply).toHaveBeenCalledWith(9, {
      kind: "answered",
      answers: { colour: ["green"], size: ["large"] },
    });
  });

  it("preserves each question's selection mode and answers across steps", () => {
    const onReply = vi.fn();
    act(() => root.render(createElement(QuestionForm, { prompt: twoQuestions(), onReply })));
    act(() => multiSelectToggle().click());
    act(() => button("Red").click());
    act(() => button("Green").click());
    act(() => button("Continue").click());
    expect(multiSelectToggle().checked).toBe(false);
    act(() => button("Large").click());

    act(() => button("Back").click());
    expect(multiSelectToggle().checked).toBe(true);
    expect(button("Red").getAttribute("aria-pressed")).toBe("true");
    expect(button("Green").getAttribute("aria-pressed")).toBe("true");
    act(() => button("Continue").click());
    expect(multiSelectToggle().checked).toBe(false);
    expect(button("Large").getAttribute("aria-pressed")).toBe("true");
    act(() => button("Continue").click());

    expect(onReply).toHaveBeenCalledWith(9, {
      kind: "answered",
      answers: { colour: ["red", "green"], size: ["large"] },
    });
  });
});
