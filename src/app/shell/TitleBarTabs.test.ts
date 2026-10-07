// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TitleBar, titleTabContextCloseIds, type Tab } from "./TitleBar";

vi.mock("./WindowControls", () => ({ WindowControls: () => null }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ setTitle: async () => {} }) }));

let container: HTMLDivElement;
let root: Root;
let stripWidth = 0;

function tab(id: string, over: Partial<Tab> = {}): Tab {
  return { id, project: "loci", title: `Title ${id}`, more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], doneHarnesses: [], status: "idle", ...over };
}
const many = (count: number, over: (index: number) => Partial<Tab> = () => ({})) =>
  Array.from({ length: count }, (_, index) => tab(`t${index}`, over(index)));

function render(tabs: Tab[], props: Partial<ComponentProps<typeof TitleBar>> = {}) {
  act(() => root.render(createElement(TitleBar, {
    tabs, activeId: "t2", cwd: "/project",
    onToggleSidebar: vi.fn(), onSelect: vi.fn(), onClose: vi.fn(), onCloseMany: vi.fn(), onReorder: vi.fn(),
    ...props,
  })));
}
const variants = () => [...container.querySelectorAll<HTMLElement>("[data-tab-variant]")].map((el) => el.dataset.tabVariant);

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  stripWidth = 0;
  // The strip's width decides how crowded it is.
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockImplementation(function (this: HTMLElement) {
    return this.hasAttribute("data-title-tab-strip") ? stripWidth : 0;
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("tab strip density", () => {
  it("shows every title while they all fit", () => {
    stripWidth = 1400;
    render(many(6));
    expect(variants()).toEqual(Array(6).fill("full"));
  });

  it("folds idle tabs to icons, keeping the active tab's title, once titles would be slivers", () => {
    stripWidth = 700;
    render(many(12));
    const shown = variants();
    expect(shown.filter((variant) => variant === "full")).toHaveLength(1);
    expect(container.querySelector('[data-title-tab-id="t2"] [data-tab-variant="full"]')).not.toBeNull();
    expect(container.querySelector('[data-title-tab-id="t5"] [data-tab-variant="icon"]')).not.toBeNull();
  });

  it("keeps pinned tabs as icons ahead of a divider, whatever the room", () => {
    stripWidth = 1400;
    render(many(5, (index) => (index < 2 ? { pinned: true } : {})));
    expect(variants()).toEqual(["icon", "icon", "full", "full", "full"]);
    expect(container.querySelectorAll("[data-pinned-divider]")).toHaveLength(1);
  });

  it("describes an icon-only tab in words for assistive tech", () => {
    stripWidth = 700;
    render(many(12, (index) => (index === 5 ? { status: "approval" } : {})));
    expect(container.querySelector('[data-title-tab-id="t5"] button')?.getAttribute("aria-label")).toContain("Needs your approval");
  });
});

describe("pinning and bulk close", () => {
  it("offers Pin Tab and Unpin Tab from the tab menu", () => {
    const onPin = vi.fn();
    render([tab("a"), tab("b", { pinned: true })], { activeId: "a", onPin });
    for (const [id, label, pinned] of [["a", "Pin Tab", true], ["b", "Unpin Tab", false]] as const) {
      act(() => container.querySelector(`[data-title-tab-id="${id}"] .group`)!.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 10, clientY: 10 })));
      const item = [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((el) => el.textContent?.includes(label));
      expect(item).toBeDefined();
      act(() => item!.click());
      expect(onPin).toHaveBeenLastCalledWith(id, pinned);
    }
  });

  it("leaves pinned tabs out of Close Others, Close to the Right and Close to the Left", () => {
    const tabs = [tab("a"), tab("b", { pinned: true }), tab("c"), tab("d", { pinned: true }), tab("e")];
    expect(titleTabContextCloseIds(tabs, "c", "others")).toEqual(["a", "e"]);
    expect(titleTabContextCloseIds(tabs, "c", "right")).toEqual(["e"]);
    expect(titleTabContextCloseIds(tabs, "c", "left")).toEqual(["a"]);
  });
});

describe("Close Idle Tabs", () => {
  const openMenu = () => act(() => container.querySelector('[data-title-tab-id="a"] .group')!.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 10, clientY: 10 })));
  const item = () => [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((el) => el.textContent?.includes("Close Idle Tabs"));

  it("offers to close the quiet tabs, saying how many", () => {
    const onCloseIdle = vi.fn();
    render([tab("a"), tab("b")], { activeId: "a", idleTabCount: 3, onCloseIdle });
    openMenu();
    expect(item()?.textContent).toContain("3 finished and quiet");
    act(() => item()!.click());
    expect(onCloseIdle).toHaveBeenCalledOnce();
  });

  it("is disabled when nothing is idle", () => {
    render([tab("a"), tab("b")], { activeId: "a", idleTabCount: 0, onCloseIdle: vi.fn() });
    openMenu();
    expect((item() as HTMLButtonElement).disabled).toBe(true);
  });
});

describe("tabs an agent started", () => {
  const family = () => [
    tab("p", { descendantCount: 2, descendantStatus: "approval" }),
    tab("c1", { parentId: "p" }),
    tab("c2", { parentId: "p" }),
    tab("other"),
  ];
  const shown = () => [...container.querySelectorAll<HTMLElement>("[data-title-tab-id]")].map((el) => el.dataset.titleTabId);
  const chip = () => container.querySelector<HTMLButtonElement>("[data-family-toggle]");

  it("folds them under their parent, which says how many and how urgent", () => {
    stripWidth = 1400;
    render(family(), { activeId: "other" });
    expect(shown()).toEqual(["p", "other"]);
    expect(chip()?.textContent).toContain("2");
    expect(chip()?.className).toContain("text-amber-400");
    expect(chip()?.getAttribute("aria-expanded")).toBe("false");
    // The count button still counts everything, hidden or not.
    expect(container.querySelector("[data-tab-switcher]")).toBeNull();
    render(family(), { activeId: "other", onOpenSwitcher: vi.fn() });
    expect(container.querySelector("[data-tab-switcher]")?.textContent).toContain("4");
  });

  it("unfolds on the chip, with a connector before each child", () => {
    stripWidth = 1400;
    render(family(), { activeId: "other" });
    act(() => chip()!.click());
    expect(shown()).toEqual(["p", "c1", "c2", "other"]);
    expect(container.querySelectorAll("[data-family-connector]")).toHaveLength(2);
    expect(chip()?.getAttribute("aria-expanded")).toBe("true");
    act(() => chip()!.click());
    expect(shown()).toEqual(["p", "other"]);
  });

  it("never hides the tab in view, nor the parent it came from", () => {
    stripWidth = 1400;
    render(family(), { activeId: "c2" });
    expect(shown()).toEqual(["p", "c1", "c2", "other"]);
  });

  it("can be unfolded from the tab menu too", () => {
    stripWidth = 1400;
    render(family(), { activeId: "other" });
    act(() => container.querySelector('[data-title-tab-id="p"] .group')!.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true, clientX: 10, clientY: 10 })));
    const item = [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((el) => el.textContent?.includes("Show Started Tabs"));
    expect(item?.textContent).toContain("2 started from this tab");
    act(() => item!.click());
    expect(shown()).toEqual(["p", "c1", "c2", "other"]);
  });
});

describe("tab switcher button", () => {
  it("counts the tabs and opens the switcher", () => {
    const onOpenSwitcher = vi.fn();
    render(many(4), { onOpenSwitcher });
    const button = container.querySelector<HTMLButtonElement>("[data-tab-switcher]")!.closest("button")!;
    expect(button.textContent).toContain("4");
    act(() => button.click());
    expect(onOpenSwitcher).toHaveBeenCalledOnce();
  });

  it("wears a dot for a tab out of sight that needs the user, approvals first", () => {
    render(many(4, (index) => (index === 1 ? { status: "done" } : {})), { onOpenSwitcher: vi.fn() });
    const dot = () => container.querySelector("[data-tab-switcher] > span[aria-hidden]");
    expect(dot()?.className).toContain("bg-teal-400");
    render(many(4, (index) => (index === 1 ? { status: "done" } : index === 3 ? { status: "approval" } : {})), { onOpenSwitcher: vi.fn() });
    expect(dot()?.className).toContain("bg-amber-400");
    // The tab in view is not "out of sight".
    render(many(4, (index) => (index === 2 ? { status: "approval" } : {})), { onOpenSwitcher: vi.fn() });
    expect(dot()).toBeNull();
  });

  it("is absent with a single tab", () => {
    render(many(1), { activeId: "t0", onOpenSwitcher: vi.fn() });
    expect(container.querySelector("[data-tab-switcher]")).toBeNull();
  });
});

describe("tab hover card", () => {
  it("unfolds after a short rest with the full title, status and last words", () => {
    vi.useFakeTimers();
    stripWidth = 700;
    render(many(12, (index) => (index === 5 ? { title: "A very long conversation title that never fit", status: "approval", preview: "May I run the migration?" } : {})));
    const item = container.querySelector('[data-title-tab-id="t5"] .group')!;
    act(() => { item.dispatchEvent(new MouseEvent("pointerover", { bubbles: true })); vi.advanceTimersByTime(200); });
    expect(document.querySelector('[role="tooltip"]')).toBeNull();
    act(() => { vi.advanceTimersByTime(300); });
    const card = document.querySelector('[role="tooltip"]');
    expect(card?.textContent).toContain("A very long conversation title that never fit");
    expect(card?.textContent).toContain("Needs your approval");
    expect(card?.textContent).toContain("May I run the migration?");
    act(() => { item.dispatchEvent(new MouseEvent("pointerout", { bubbles: true })); vi.advanceTimersByTime(100); });
    expect(document.querySelector('[role="tooltip"]')).toBeNull();
  });
});
