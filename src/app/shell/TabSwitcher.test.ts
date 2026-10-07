// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ClosedTab } from "../../features/workspace/model/closedTabs";
import type { Tab } from "../../features/workspace/model/tabSummary";
import { TabSwitcher } from "./TabSwitcher";

let container: HTMLDivElement;
let root: Root;

function tab(id: string, title: string, over: Partial<Tab> = {}): Tab {
  return { id, title, project: "loci", projectPath: "/p/loci", more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], status: "idle", ...over };
}
const tabs = [
  tab("a", "Fix the tab bar", { preview: "Done with the strip" }),
  tab("b", "Write release notes", { status: "approval", preview: "Run npm test?" }),
  tab("c", "Survey", { project: "papers", projectPath: "/p/papers" }),
  tab("d", "Refactor sessions"),
];
const closed: ClosedTab[] = [{ layout: { type: "leaf", id: "x" }, focusedId: "x", title: "Old chat", project: "loci", closedAt: Date.now() - 120_000, batch: 9 }];

function handlers() {
  return { onActivate: vi.fn(), onCloseTab: vi.fn(), onPin: vi.fn(), onReopen: vi.fn(), onDismiss: vi.fn() };
}
function render(props: Partial<ComponentProps<typeof TabSwitcher>> & ReturnType<typeof handlers>) {
  act(() => root.render(createElement(TabSwitcher, { tabs, activeId: "a", projectPath: "/p/loci", recent: ["a", "d"], closed, ...props })));
}
const input = () => document.querySelector<HTMLInputElement>('input[aria-label="Search open tabs"]')!;
const rows = () => [...document.querySelectorAll<HTMLElement>('[role="option"]')];
const selectedText = () => document.querySelector('[role="option"][aria-selected="true"]')?.textContent ?? "";
function press(key: string, init: KeyboardEventInit = {}) {
  act(() => { input().dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, ...init })); });
}
function type(text: string) {
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input(), text);
    input().dispatchEvent(new Event("input", { bubbles: true }));
  });
}

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

describe("TabSwitcher", () => {
  it("lists what needs the user first, then this project, other projects, and what was closed", () => {
    render(handlers());
    expect([...document.querySelectorAll("section h3")].map((el) => el.textContent?.replace(/\d+$/, ""))).toEqual(["Needs you", "This project", "papers", "Recently closed"]);
    expect(rows().map((row) => row.textContent)).toEqual(expect.arrayContaining([expect.stringContaining("Run npm test?"), expect.stringContaining("Old chat")]));
    expect(rows().find((row) => row.textContent?.includes("Fix the tab bar"))?.textContent).toContain("Current");
  });

  it("starts on the tab to flip back to, not the one already in view", () => {
    render(handlers());
    // "Needs you" comes first, so the highlight lands on the approval.
    expect(selectedText()).toContain("Write release notes");
  });

  it("opens the highlighted tab on Enter, moving with the arrows", () => {
    const h = handlers();
    render(h);
    press("ArrowDown");
    expect(selectedText()).toContain("Fix the tab bar");
    press("ArrowDown");
    expect(selectedText()).toContain("Refactor sessions");
    press("Enter");
    expect(h.onActivate).toHaveBeenCalledWith("d");
    expect(h.onDismiss).toHaveBeenCalled();
  });

  it("wraps from the first row to the last", () => {
    render(handlers());
    press("ArrowUp");
    expect(selectedText()).toContain("Old chat");
    press("ArrowDown");
    expect(selectedText()).toContain("Write release notes");
  });

  it("filters as you type and highlights the match", () => {
    const h = handlers();
    render(h);
    type("surv");
    expect(rows().map((row) => row.textContent)).toEqual([expect.stringContaining("Survey")]);
    expect(rows()[0].textContent).toContain("papers");
    press("Enter");
    expect(h.onActivate).toHaveBeenCalledWith("c");
  });

  it("says so when nothing matches", () => {
    render(handlers());
    type("zzzz");
    expect(document.body.textContent).toContain("No tab matches “zzzz”");
  });

  it("reopens a closed tab's whole batch from its row", () => {
    const h = handlers();
    render(h);
    const row = rows().find((el) => el.textContent?.includes("Old chat"))!;
    act(() => row.click());
    expect(h.onReopen).toHaveBeenCalledWith(9);
  });

  it("closes the highlighted tab with the shortcut and keeps the list open", () => {
    const h = handlers();
    render(h);
    press("Backspace", { ctrlKey: true });
    expect(h.onCloseTab).toHaveBeenCalledWith("b");
    expect(h.onDismiss).not.toHaveBeenCalled();
  });

  it("pins and closes from a row's own buttons without opening it", () => {
    const h = handlers();
    render(h);
    const row = rows().find((el) => el.textContent?.includes("Refactor sessions"))!;
    act(() => row.dispatchEvent(new MouseEvent("mousemove", { bubbles: true })));
    act(() => row.querySelector<HTMLElement>('button[aria-label="Pin tab"]')!.click());
    expect(h.onPin).toHaveBeenCalledWith("d", true);
    act(() => row.querySelector<HTMLElement>('button[aria-label="Close tab"]')!.click());
    expect(h.onCloseTab).toHaveBeenCalledWith("d");
    expect(h.onActivate).not.toHaveBeenCalled();
  });
});
