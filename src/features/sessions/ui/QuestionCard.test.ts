// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { UserQuestionPrompt } from "../model/userQuestion";
import { QuestionCard } from "./QuestionCard";

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
    questions: [{
      id: "colour",
      prompt: "Which colours?",
      multiSelect,
      allowCustom: true,
      options: [{ id: "red", label: "Red" }, { id: "green", label: "Green" }],
    }],
  };
}

function button(label: string): HTMLButtonElement {
  const match = Array.from(container.querySelectorAll("button")).find(
    (element) => element.textContent?.trim() === label,
  );
  if (!match) throw new Error(`No button labelled ${label}`);
  return match;
}

function option(id: string): HTMLButtonElement {
  const options = Array.from(container.querySelectorAll<HTMLButtonElement>("button[aria-checked]"));
  const match = options.find((element) => element.textContent?.includes(id));
  if (!match) throw new Error(`No option labelled ${id}`);
  return match;
}

function toggle(): HTMLInputElement {
  return container.querySelector<HTMLInputElement>('input[aria-label="Multi-select"]')!;
}

function click(element: HTMLElement) {
  act(() => element.click());
}

function render(currentPrompt = prompt(), onReply = vi.fn(), onInteraction = vi.fn()) {
  act(() => root.render(createElement(QuestionCard, { prompt: currentPrompt, onReply, onInteraction })));
  return { onReply, onInteraction };
}

describe("QuestionCard selections", () => {
  it("keeps the single-select one-click reply", () => {
    const { onReply } = render();
    click(option("Red"));
    expect(onReply).toHaveBeenCalledWith(7, { kind: "answered", answers: { colour: ["red"] } });
  });

  it("keeps provider-enforced single-choice questions single-select", () => {
    const currentPrompt = prompt();
    currentPrompt.questions[0].allowMultiSelect = false;
    const { onReply } = render(currentPrompt);
    expect(toggle()).toBeNull();
    click(option("Green"));
    expect(onReply).toHaveBeenCalledWith(7, { kind: "answered", answers: { colour: ["green"] } });
  });

  it("lets users enable multi-select and waits for confirmation", () => {
    const { onReply } = render();
    click(toggle());
    expect(container.textContent).toContain("Pick any that apply");
    expect(button("Send").disabled).toBe(true);

    click(option("Red"));
    click(option("Green"));
    expect(option("Red").getAttribute("role")).toBe("checkbox");
    expect(option("Red").getAttribute("aria-checked")).toBe("true");
    expect(option("Green").getAttribute("aria-checked")).toBe("true");
    expect(onReply).not.toHaveBeenCalled();

    click(button("Send"));
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered", answers: { colour: ["red", "green"] },
    });
  });

  it("allows deselection and disables sending an empty multi-select answer", () => {
    const { onReply } = render(prompt(true));
    expect(toggle()).toBeNull();
    click(option("Red"));
    click(option("Green"));
    click(option("Red"));
    expect(option("Red").getAttribute("aria-checked")).toBe("false");
    click(option("Green"));
    expect(button("Send").disabled).toBe(true);
    click(button("Send"));
    expect(onReply).not.toHaveBeenCalled();
  });

  it("keeps only the first choice when returning to single-select without sending", () => {
    const { onReply } = render();
    click(toggle());
    click(option("Green"));
    click(option("Red"));
    click(toggle());
    expect(option("Green").getAttribute("role")).toBe("radio");
    expect(option("Green").getAttribute("aria-checked")).toBe("true");
    expect(option("Red").getAttribute("aria-checked")).toBe("false");
    expect(onReply).not.toHaveBeenCalled();
    click(button("Send"));
    expect(onReply).toHaveBeenCalledWith(7, { kind: "answered", answers: { colour: ["green"] } });
  });

  it("preserves all choices across questions and keeps selection mode local to each question", () => {
    const currentPrompt = prompt();
    currentPrompt.questions.push({
      id: "size", prompt: "Which size?", multiSelect: false, allowCustom: false,
      options: [{ id: "small", label: "Small" }, { id: "large", label: "Large" }],
    });
    const { onReply } = render(currentPrompt);
    click(toggle());
    click(option("Red"));
    click(option("Green"));
    expect(container.textContent).toContain("1 of 2");
    expect(onReply).not.toHaveBeenCalled();
    click(button("Next"));
    expect(container.textContent).toContain("2 of 2");
    expect(toggle().checked).toBe(false);
    click(option("Large"));
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered", answers: { colour: ["red", "green"], size: ["large"] },
    });
  });

  it("includes a typed supplement alongside multi-select choices", () => {
    const { onReply } = render();
    click(toggle());
    click(option("Red"));
    const input = container.querySelector<HTMLInputElement>('input[aria-label="Your own answer"]')!;
    act(() => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "  Blue too  ");
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    click(button("Send"));
    expect(onReply).toHaveBeenCalledWith(7, {
      kind: "answered", answers: { colour: ["red"] }, custom: { colour: "Blue too" },
    });
  });

  it("resets the mode and choices for a new request and treats toggling as interaction", () => {
    const currentPrompt = { ...prompt(), autoResolveAt: Date.now() + 30_000 };
    const { onReply, onInteraction } = render(currentPrompt);
    click(toggle());
    expect(onInteraction).toHaveBeenCalledWith(7);
    click(option("Red"));
    render({ ...currentPrompt, requestId: 8 }, onReply, onInteraction);
    expect(toggle().checked).toBe(false);
    expect(option("Red").getAttribute("aria-checked")).toBe("false");
    expect(container.textContent).not.toContain("Send");
  });
});
