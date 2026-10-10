// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { WidgetToolbar } from "./WidgetCard";
import { askAboutWidget } from "../model/widgetContext";
import { retainWidget } from "../model/widgetRuntime";
import { openWidget } from "../model/widgets";
import type { StoredWidget } from "../model/types";

vi.mock("../model/widgetContext", () => ({ askAboutWidget: vi.fn().mockResolvedValue(undefined) }));
vi.mock("../model/widgetRuntime", () => ({ retainWidget: vi.fn().mockResolvedValue(undefined), useWidget: vi.fn() }));
vi.mock("../model/widgets", async (original) => ({ ...await original<typeof import("../model/widgets")>(), openWidget: vi.fn() }));
vi.mock("../model/learningStore", () => ({ getLearningSource: vi.fn() }));

const widget: StoredWidget = { owner: { kind: "session", id: "session-a" }, id: "queue", title: "Queue mechanics", subject: "Concurrency", html: "<p>Queue</p>", sourceIds: [], sourceSessionId: "session-a", sourceBlockId: "reply-a", revision: 2, saved: true, state: { capacity: 4, items: [1, 2, 3] }, createdAt: 1, updatedAt: 2 };
let container: HTMLDivElement;
let root: Root;
const button = (name: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.getAttribute("aria-label") === name || item.textContent === name)!;
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("keeps Ask, retention and expansion available with accessible icon names", async () => {
  await act(async () => root.render(createElement(WidgetToolbar, { widget })));
  expect(askAboutWidget).not.toHaveBeenCalled();
  expect(button("Ask").getAttribute("aria-label")).toBe("Ask");
  expect(button("Saved · Remove").getAttribute("aria-pressed")).toBe("true");
  await act(async () => button("Ask").click());
  expect(askAboutWidget).toHaveBeenCalledWith(widget, expect.any(String));
  await act(async () => button("Saved · Remove").click());
  expect(retainWidget).toHaveBeenCalledWith({ owner: widget.owner, id: widget.id }, false);
  act(() => button("Expand").click());
  expect(openWidget).toHaveBeenCalledWith({ owner: widget.owner, id: widget.id }, widget.sourceSessionId, widget.title);
});

it("opens secondary actions outside the card and prepares an article only after selection", async () => {
  await act(async () => root.render(createElement(WidgetToolbar, { widget })));
  expect(document.querySelector('[role="menu"]')).toBeNull();
  await act(async () => button("Explanation actions").click());
  const menu = document.querySelector('[role="menu"]')!;
  expect(container.contains(menu)).toBe(false);
  expect(document.activeElement).toBe(menu);
  expect(menu.textContent).toContain("HTML");
  expect(askAboutWidget).not.toHaveBeenCalled();
  await act(async () => {
    menu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
  });
  await act(async () => {
    menu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
  });
  await act(async () => {
    menu.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  });
  expect(askAboutWidget).toHaveBeenCalledWith(widget, expect.stringContaining("博客草稿"));
  expect(document.querySelector('[role="menu"]')).toBeNull();
});

it("keeps source inspection local and closes the actions menu with Escape", async () => {
  await act(async () => root.render(createElement(WidgetToolbar, { widget, expanded: true })));
  expect(button("Expand")).toBeUndefined();
  expect(container.textContent).not.toContain(widget.title);
  await act(async () => button("Explanation actions").click());
  await act(async () => button("HTML").click());
  expect(container.querySelector("pre")?.textContent).toBe(widget.html);
  expect(askAboutWidget).not.toHaveBeenCalled();
  await act(async () => button("Explanation actions").click());
  act(() => window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })));
  expect(document.querySelector('[role="menu"]')).toBeNull();
});
