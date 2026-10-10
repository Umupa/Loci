// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { WorkFoldLine, type WorkFoldState } from "./WorkFoldLine";

let container: HTMLDivElement;
let root: Root;
const onToggle = vi.fn();

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  onToggle.mockClear();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

function render(
  state: WorkFoldState,
  visible = true,
  title = "Thinking · 2s",
  open = false,
) {
  act(() => root.render(createElement(WorkFoldLine, {
    title,
    state,
    visible,
    expandable: true,
    open,
    onToggle,
  })));
}

function line() {
  return container.querySelector<HTMLElement>("[data-work-fold]")!;
}

it.each(["thinking", "working", "responding", "waiting"] as const)(
  "briefly celebrates a visible %s turn finishing without moving its root",
  (state) => {
    render(state);
    const before = line();
    render("done", true, "Thought for 2s");
    expect(line()).toBe(before);
    expect(line().hasAttribute("data-work-completing")).toBe(true);

    act(() => vi.advanceTimersByTime(699));
    expect(line().hasAttribute("data-work-completing")).toBe(true);
    act(() => vi.advanceTimersByTime(1));
    expect(line().hasAttribute("data-work-completing")).toBe(false);
  },
);

it("keeps a historical completed turn still on mount and subsequent renders", () => {
  render("done");
  expect(line().hasAttribute("data-work-completing")).toBe(false);
  render("done", true, "Thought for 9s");
  expect(line().hasAttribute("data-work-completing")).toBe(false);
});

it("does not replay a turn that completed while its pane was hidden", () => {
  render("working");
  render("working", false);
  expect(line().hasAttribute("data-work-animated")).toBe(false);
  render("done", false);
  render("done");
  expect(line().hasAttribute("data-work-completing")).toBe(false);
});

it("does not celebrate a completion arriving as a hidden pane becomes visible", () => {
  render("working", false);
  render("done");
  expect(line().hasAttribute("data-work-completing")).toBe(false);
});

it("ends the completion motion when hidden and stays still when reopened", () => {
  render("responding");
  render("done");
  expect(line().hasAttribute("data-work-completing")).toBe(true);
  render("done", false);
  expect(line().hasAttribute("data-work-completing")).toBe(false);
  render("done");
  expect(line().hasAttribute("data-work-completing")).toBe(false);
});

it.each(["error", "interrupted"] as const)("keeps %s terminal states out of completion motion", (state) => {
  render("working");
  render(state);
  expect(line().dataset.workState).toBe(state);
  expect(line().hasAttribute("data-work-completing")).toBe(false);
  expect(line().hasAttribute("data-work-animated")).toBe(false);
});

it("announces state changes without putting ticking title text in the live region", () => {
  render("thinking", true, "Thinking · 2s");
  const announcement = container.querySelector("[data-work-announcement]")!;
  expect(line().hasAttribute("aria-live")).toBe(false);
  expect(announcement.textContent).toBe("Thinking");

  render("thinking", true, "Thinking · 3s");
  expect(container.querySelector("[data-work-announcement]")).toBe(announcement);
  expect(announcement.textContent).toBe("Thinking");

  render("responding", true, "Responding · 4s");
  expect(announcement.textContent).toBe("Responding");
});

it("keeps the expansion control and its chevron present across turn states", () => {
  render("thinking");
  expect(line().getAttribute("aria-expanded")).toBe("false");
  expect(line().getAttribute("aria-label")).toBe("Show the work");
  expect(line().querySelector("[data-work-chevron]")).not.toBeNull();
  act(() => line().click());
  expect(onToggle).toHaveBeenCalledOnce();

  render("done", true, "Thought for 2s", true);
  expect(line().getAttribute("aria-expanded")).toBe("true");
  expect(line().getAttribute("aria-label")).toBe("Hide the work");
  expect(line().querySelector("[data-work-chevron]")?.classList.contains("rotate-90")).toBe(true);
});
