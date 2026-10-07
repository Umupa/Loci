// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { closedTabs } from "../../features/workspace/model/closedTabs";
import { ClosedTabToast } from "./ClosedTabToast";

let container: HTMLDivElement;
let root: Root;
const record = (title: string) => ({ layout: { type: "leaf" as const, id: title }, focusedId: title, title, project: "loci" });
const toast = () => document.querySelector("[data-closed-tab-toast]");

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  closedTabs.take("latest");
  while (closedTabs.history().length) closedTabs.take("latest");
  closedTabs.dismissNotice();
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("ClosedTabToast", () => {
  it("names the tab that closed and undoes the whole batch", () => {
    const onUndo = vi.fn();
    act(() => root.render(createElement(ClosedTabToast, { onUndo })));
    expect(toast()).toBeNull();
    act(() => closedTabs.record([record("Fix the tab bar")]));
    expect(toast()?.textContent).toContain("Closed “Fix the tab bar”");
    act(() => toast()!.querySelector<HTMLButtonElement>("button")!.click());
    expect(onUndo).toHaveBeenCalledWith(closedTabs.history()[0].batch);
  });

  it("counts tabs closed together, and truncates a long title", () => {
    act(() => root.render(createElement(ClosedTabToast, { onUndo: vi.fn() })));
    act(() => closedTabs.record([record("one"), record("two"), record("three")]));
    expect(toast()?.textContent).toContain("Closed 3 tabs");
    act(() => closedTabs.record([record("x".repeat(80))]));
    expect(toast()?.textContent).toContain("…");
  });

  it("goes away on its own, and on dismiss", () => {
    act(() => root.render(createElement(ClosedTabToast, { onUndo: vi.fn() })));
    act(() => closedTabs.record([record("a")]));
    act(() => { vi.advanceTimersByTime(8100); });
    expect(toast()).toBeNull();
    act(() => closedTabs.record([record("b")]));
    act(() => toast()!.querySelector<HTMLButtonElement>('button[aria-label="Dismiss"]')!.click());
    expect(toast()).toBeNull();
  });

  it("waits while the pointer rests on it", () => {
    act(() => root.render(createElement(ClosedTabToast, { onUndo: vi.fn() })));
    act(() => closedTabs.record([record("a")]));
    act(() => { toast()!.dispatchEvent(new MouseEvent("pointerover", { bubbles: true })); });
    act(() => { vi.advanceTimersByTime(8100); });
    expect(toast()).not.toBeNull();
    act(() => { toast()!.dispatchEvent(new MouseEvent("pointerout", { bubbles: true })); vi.advanceTimersByTime(1600); });
    expect(toast()).toBeNull();
  });

  it("clears once the closed tabs are taken back", () => {
    act(() => root.render(createElement(ClosedTabToast, { onUndo: vi.fn() })));
    act(() => closedTabs.record([record("a")]));
    act(() => { closedTabs.take("latest"); });
    expect(toast()).toBeNull();
  });
});
