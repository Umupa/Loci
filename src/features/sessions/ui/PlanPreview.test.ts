// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { PlanPreview } from "./PlanPreview";

let host: HTMLDivElement;
let root: Root;
const text = "# Weekly plan\n\nRead the guide, then try the exercise.";

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

function render(streaming = false, visible = true, revealOnMount = false) {
  act(() => root.render(createElement(PlanPreview, {
    text, streaming, visible, revealOnMount,
  })));
}

function card() {
  return host.querySelector<HTMLElement>("[data-plan-preview]")!;
}

it("shows historical plan content immediately without entry or ready motion", () => {
  render();
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("Read the guide");
  render(false, true, true);
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
});

it("briefly enters a newly arrived visible plan once while retaining its text", () => {
  render(false, true, true);
  const before = card();
  expect(card().hasAttribute("data-plan-entering")).toBe(true);
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("Read the guide");
  act(() => vi.advanceTimersByTime(220));
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
  render(false, true, true);
  expect(card()).toBe(before);
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
});

it("keeps the streaming icon in motion only while its pane is visible", () => {
  render(true);
  expect(card().hasAttribute("data-plan-streaming")).toBe(true);
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("Read the guide");
  render(true, false);
  expect(card().hasAttribute("data-plan-streaming")).toBe(false);
  render(true);
  expect(card().hasAttribute("data-plan-streaming")).toBe(true);
});

it("settles a visible stream ending once and clears its flag without animationend", () => {
  render(true);
  const before = card();
  render();
  expect(card()).toBe(before);
  expect(card().hasAttribute("data-plan-streaming")).toBe(false);
  expect(card().hasAttribute("data-plan-settling")).toBe(true);
  act(() => vi.advanceTimersByTime(700));
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("Read the guide");
  render();
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
});

it("does not replay a stream ending while hidden when the pane returns", () => {
  render(true);
  render(true, false);
  render(false, false);
  render();
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("Read the guide");
});

it("does not settle a hidden stream that ends as the pane becomes visible", () => {
  render(true, false);
  render();
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
});

it("ends entry and ready motion when hidden without replaying either", () => {
  render(true, true, true);
  expect(card().hasAttribute("data-plan-entering")).toBe(true);
  render(false, true, true);
  expect(card().hasAttribute("data-plan-settling")).toBe(true);
  render(false, false, true);
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
  render(false, true, true);
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
});

it("keeps a fresh plan arriving in a hidden pane static when reopened", () => {
  render(false, false, true);
  render(false, true, true);
  expect(card().hasAttribute("data-plan-entering")).toBe(false);
  expect(card().hasAttribute("data-plan-settling")).toBe(false);
});
