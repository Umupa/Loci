// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Tab } from "../../features/workspace/model/tabSummary";
import { TabOverview } from "./TabOverview";

let container: HTMLDivElement;
let root: Root;

function tab(id: string, title: string, over: Partial<Tab> = {}): Tab {
  return { id, title, project: "loci", projectPath: "/p/loci", more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], status: "idle", preview: `About ${title}`, ...over };
}
const tabs = [
  tab("a", "Fix the tab bar"),
  tab("b", "Write release notes", { status: "approval", preview: "Run npm test?" }),
  tab("c", "Survey", { project: "papers", projectPath: "/p/papers" }),
  tab("d", "Refactor sessions", { status: "busy", busySince: Date.now() - 90_000 }),
];

function handlers() {
  return { onActivate: vi.fn(), onCloseTabs: vi.fn(), onParkTabs: vi.fn(), onPinTabs: vi.fn(), onDismiss: vi.fn() };
}
function render(props: ReturnType<typeof handlers> & Partial<ComponentProps<typeof TabOverview>>) {
  act(() => root.render(createElement(TabOverview, { tabs, activeId: "a", projectPath: "/p/loci", recent: ["a"], ...props })));
}
const input = () => document.querySelector<HTMLInputElement>('input[aria-label="Search tabs"]')!;
const cards = () => [...document.querySelectorAll<HTMLElement>("[data-overview-tab]")];
const order = () => cards().map((card) => card.dataset.overviewTab);
const cursorId = () => document.querySelector<HTMLElement>("[data-cursor='true']")?.dataset.overviewTab;
function key(name: string, init: KeyboardEventInit = {}) {
  act(() => { input().dispatchEvent(new KeyboardEvent("keydown", { key: name, bubbles: true, cancelable: true, ...init })); });
}
function type(text: string) {
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input(), text);
    input().dispatchEvent(new Event("input", { bubbles: true }));
  });
}
/** Closing waits a moment for the cards to leave. */
const settle = () => act(async () => { await new Promise((resolve) => setTimeout(resolve, 260)); });
const check = (id: string) => document.querySelector<HTMLElement>(`[data-overview-tab="${id}"] [role="checkbox"]`)!;

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

describe("TabOverview", () => {
  it("opens on this project, what wants you first, saying how many need you or work", () => {
    render(handlers());
    expect(order()).toEqual(["b", "d", "a"]);
    expect(document.body.textContent).toContain("3 tabs");
    expect(document.body.textContent).toContain("1 need you");
    expect(document.body.textContent).toContain("1 working");
    expect(document.querySelector('[data-overview-tab="a"]')?.textContent).toContain("Current");
  });

  it("can look across every project", () => {
    render(handlers());
    act(() => [...document.querySelectorAll<HTMLElement>('[role="tab"]')].find((el) => el.textContent === "All projects")!.click());
    expect(order()).toContain("c");
    expect(document.querySelector('[data-overview-tab="c"]')?.textContent).toContain("papers");
  });

  it("starts on the first tab that is not the current one, and moves with the arrows", () => {
    render(handlers());
    expect(cursorId()).toBe("b");
    key("ArrowRight");
    expect(cursorId()).toBe("d");
    key("ArrowLeft");
    expect(cursorId()).toBe("b");
  });

  it("opens the card under the cursor on Enter, and on click", () => {
    const h = handlers();
    render(h);
    key("Enter");
    expect(h.onActivate).toHaveBeenCalledWith("b");
    expect(h.onDismiss).toHaveBeenCalled();
    act(() => document.querySelector<HTMLElement>('[data-overview-tab="d"]')!.click());
    expect(h.onActivate).toHaveBeenLastCalledWith("d");
  });

  it("filters while you type, and keeps typed arrows for the caret", () => {
    render(handlers());
    type("release");
    expect(order()).toEqual(["b"]);
    type("zzzz");
    expect(document.body.textContent).toContain("No tab matches “zzzz”");
  });

  it("selects with the checkbox, space or a modified click, and acts on all of them at once", async () => {
    const h = handlers();
    render(h);
    act(() => check("b").click());
    key("ArrowRight");
    key(" ");
    act(() => document.querySelector<HTMLElement>('[data-overview-tab="a"]')!.dispatchEvent(new MouseEvent("click", { bubbles: true, ctrlKey: true })));
    expect(document.querySelector("[data-bulk-bar]")?.textContent).toContain("3 selected");
    expect(h.onActivate).not.toHaveBeenCalled();
    const bar = () => document.querySelector("[data-bulk-bar]")!;
    const press = (label: string) => act(() => [...bar().querySelectorAll("button")].find((el) => el.textContent?.includes(label))!.click());
    press("Park");
    await settle();
    expect(h.onParkTabs).toHaveBeenCalledWith(expect.arrayContaining(["a", "b", "d"]));
    expect(document.querySelector("[data-bulk-bar]")).toBeNull();
  });

  it("pins a selection, then offers to unpin when all of it is pinned", () => {
    const h = handlers();
    render(h);
    act(() => check("d").click());
    act(() => [...document.querySelectorAll<HTMLElement>("[data-bulk-bar] button")].find((el) => el.textContent?.includes("Pin"))!.click());
    expect(h.onPinTabs).toHaveBeenCalledWith(["d"], true);
    render({ ...h, tabs: tabs.map((t) => (t.id === "d" ? { ...t, pinned: true } : t)) });
    act(() => check("d").click());
    expect(document.querySelector("[data-bulk-bar]")?.textContent).toContain("Unpin");
  });

  it("closes the selection, or the card under the cursor, with the shortcut", async () => {
    const h = handlers();
    render(h);
    key("Backspace", { ctrlKey: true });
    await settle();
    expect(h.onCloseTabs).toHaveBeenLastCalledWith(["b"]);
    act(() => check("a").click());
    act(() => check("d").click());
    key("Backspace", { metaKey: true });
    await settle();
    expect(h.onCloseTabs).toHaveBeenLastCalledWith(expect.arrayContaining(["a", "d"]));
  });

  it("closes a single card from its own button, letting it leave first, without opening it", async () => {
    const h = handlers();
    render(h);
    act(() => document.querySelector<HTMLElement>('[data-overview-tab="d"] button[aria-label="Close tab"]')!.click());
    // The card fades and shrinks while its tab is still open; the others stay put.
    expect(h.onCloseTabs).not.toHaveBeenCalled();
    expect(document.querySelector('[data-overview-tab="d"]')?.className).toContain("opacity-0");
    expect(document.querySelector('[data-overview-tab="b"]')?.className).not.toContain("opacity-0");
    await settle();
    expect(h.onCloseTabs).toHaveBeenCalledWith(["d"]);
    expect(h.onActivate).not.toHaveBeenCalled();
  });

  it("forgets a selected tab once it is gone", () => {
    const h = handlers();
    render(h);
    act(() => check("b").click());
    expect(document.querySelector("[data-bulk-bar]")).not.toBeNull();
    render({ ...h, tabs: tabs.filter((t) => t.id !== "b") });
    expect(document.querySelector("[data-bulk-bar]")).toBeNull();
  });
});
