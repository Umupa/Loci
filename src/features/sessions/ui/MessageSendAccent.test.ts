// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { MessageSendAccent } from "./MessageSendAccent";

let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(100_000);
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

function render(blockId: string, startedAt?: number) {
  act(() => root.render(createElement(MessageSendAccent, { blockId, startedAt })));
}

it("acknowledges a fresh send briefly and releases its decoration", () => {
  render("accent-new", 99_500);
  expect(container.querySelector("[data-message-send-accent]")).not.toBeNull();
  act(() => vi.advanceTimersByTime(850));
  expect(container.querySelector("[data-message-send-accent]")).toBeNull();
  expect(vi.getTimerCount()).toBe(0);
});

it("keeps historical messages quiet", () => {
  render("accent-history", 90_000);
  expect(container.querySelector("[data-message-send-accent]")).toBeNull();
  expect(vi.getTimerCount()).toBe(0);
});

it("does not replay when a fresh message remounts after a tab switch", () => {
  render("accent-remount", 99_500);
  expect(container.querySelector("[data-message-send-accent]")).not.toBeNull();
  act(() => root.render(null));
  expect(vi.getTimerCount()).toBe(0);
  render("accent-remount", 99_500);
  expect(container.querySelector("[data-message-send-accent]")).toBeNull();
});
