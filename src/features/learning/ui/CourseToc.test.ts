// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { CourseToc } from "./CourseToc";

const highlighter = vi.hoisted(() => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "light" }));

let container: HTMLDivElement, scroll: HTMLElement, host: HTMLDivElement, root: Root;
let width: number, height: number, contentHeight: number, reducedMotion: boolean;
let frameId: number, frames: Map<number, FrameRequestCallback>;
let observers: Array<{ callback: ResizeObserverCallback; observe: ReturnType<typeof vi.fn>; unobserve: ReturnType<typeof vi.fn>; disconnect: ReturnType<typeof vi.fn> }>;
const scrollRef = { current: null as HTMLElement | null };

const reading = (body: string) => `<article class="course-pane__reading"><div class="agent-markdown">${body}</div></article>`;
const items = () => [...host.querySelectorAll<HTMLButtonElement>(".course-toc__item")];
const toggle = () => host.querySelector<HTMLButtonElement>(".course-toc__toggle")!;
const panel = () => host.querySelector<HTMLElement>("nav")!;
const activeItem = () => host.querySelector<HTMLButtonElement>('[aria-current="location"]')!;
const active = () => host.querySelector<HTMLButtonElement>('[aria-current="location"]')?.textContent;
const flushFrames = () => {
  const pending = [...frames.values()];
  frames.clear();
  for (const callback of pending) callback(0);
};
const settle = async () => {
  await act(async () => {
    // MutationObserver delivers asynchronously, as library document loads do.
    await new Promise((resolve) => setTimeout(resolve, 0));
    flushFrames();
  });
};
const mount = async (body = "") => {
  scroll.innerHTML = body;
  await act(async () => root.render(createElement(CourseToc, { scrollRef })));
  act(flushFrames);
};
const positionHeadings = (offsets: number[]) => {
  const headings = [...scroll.querySelectorAll<HTMLElement>(".agent-markdown :is(h1, h2, h3, h4, h5, h6)")];
  headings.forEach((heading, index) => {
    vi.spyOn(heading, "getBoundingClientRect").mockImplementation(() => new DOMRect(0, 100 + offsets[index] - scroll.scrollTop, 300, 30));
  });
  return headings;
};
const trackScroll = (top: number) => {
  act(() => {
    scroll.scrollTop = top;
    scroll.dispatchEvent(new Event("scroll"));
    flushFrames();
  });
};
const pointer = (type: "pointerover" | "pointerout", target: HTMLElement, pointerType = "mouse", relatedTarget: EventTarget | null = null) => {
  act(() => target.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerType, relatedTarget })));
};
const escape = () => act(() => activeItem().dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));

beforeEach(() => {
  width = 1000; height = 400; contentHeight = 1800; reducedMotion = false;
  frameId = 0; frames = new Map(); observers = [];
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { frames.set(++frameId, callback); return frameId; });
  vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
  vi.stubGlobal("ResizeObserver", class {
    observe = vi.fn(); unobserve = vi.fn(); disconnect = vi.fn();
    constructor(readonly callback: ResizeObserverCallback) { observers.push(this); }
  });
  vi.spyOn(window, "matchMedia").mockImplementation((query) => ({ matches: reducedMotion && query === "(prefers-reduced-motion: reduce)" } as MediaQueryList));
  container = document.createElement("div");
  scroll = document.createElement("main");
  scroll.className = "course-pane__main";
  host = document.createElement("div");
  container.append(scroll, host); document.body.append(container);
  Object.defineProperties(scroll, {
    clientWidth: { get: () => width }, clientHeight: { get: () => height }, scrollHeight: { get: () => contentHeight },
  });
  vi.spyOn(scroll, "getBoundingClientRect").mockImplementation(() => new DOMRect(0, 100, width, height));
  vi.spyOn(scroll, "scrollTo").mockImplementation(() => undefined);
  scrollRef.current = scroll;
  root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount()); container.remove(); scrollRef.current = null;
  vi.restoreAllMocks(); vi.unstubAllGlobals();
});

it("uses the real rendered Markdown headings, including formatting, Setext, and repeated Chinese titles", async () => {
  const markdown = renderToStaticMarkup(createElement(AgentMarkdown, { wholeDocument: true, text: [
    "# 多租户", "", "## 用例 **kubectl**", "", "术语", "---", "", "### 租户", "",
    "```text", "# This is code", "```", "", "### 租户", "", "A note[^1]", "", "[^1]: Footnote text.",
  ].join("\n") }));
  await mount(`<h2>Outside article</h2><article class="course-pane__reading">${markdown}<div class="agent-markdown"><h4> </h4></div></article>`);

  expect(items().map((button) => button.textContent)).toEqual(["多租户", "用例 kubectl", "术语", "租户", "租户"]);
  const insets = items().map((button) => parseFloat(button.style.paddingInlineStart));
  expect(insets.map((inset) => inset - insets[0])).toEqual([0, 12, 12, 24, 24]);
  expect(panel().getAttribute("aria-label")).toBe("Table of contents");
  expect(toggle().getAttribute("aria-controls")).toBe(panel().id);
  expect(toggle().getAttribute("aria-expanded")).toBe("false");
  expect(panel().hidden).toBe(true);
  expect(host.querySelector(".course-toc__header, .course-toc__close")).toBeNull();
});

it("jumps to the chosen repeated heading within the article scroller", async () => {
  await mount(reading("<h2>租户</h2><h3>租户</h3><h3>租户</h3>"));
  positionHeadings([20, 500, 1050]);
  scroll.scrollTop = 200;
  const windowScroll = vi.spyOn(window, "scrollTo");
  act(() => toggle().click());

  act(() => items()[1].click());
  expect(scroll.scrollTo).toHaveBeenLastCalledWith({ top: 476, behavior: "smooth" });
  expect(panel().hidden).toBe(true);
  expect(document.activeElement).toBe(toggle());
  act(() => toggle().click());
  act(() => items()[2].click());
  expect(scroll.scrollTo).toHaveBeenLastCalledWith({ top: 1026, behavior: "smooth" });
  expect(windowScroll).not.toHaveBeenCalled();
  expect(toggle().getAttribute("aria-expanded")).toBe("false");
  expect(document.activeElement).toBe(toggle());
});

it("follows an initial section position, scroll events, and a short final section at the bottom", async () => {
  scroll.scrollTop = 520;
  await mount(reading("<h2>Start</h2><h2>Selected section</h2><h2>Short ending</h2>"));
  positionHeadings([20, 500, 1650]);
  trackScroll(520);
  expect(active()).toBe("Selected section");
  trackScroll(0);
  expect(active()).toBe("Start");
  trackScroll(contentHeight - height);
  expect(active()).toBe("Short ending");

  trackScroll(600);
  expect(active()).toBe("Selected section");
  height = 0;
  vi.mocked(scroll.getBoundingClientRect).mockReturnValue(new DOMRect());
  for (const heading of scroll.querySelectorAll<HTMLElement>("h2")) vi.mocked(heading.getBoundingClientRect).mockReturnValue(new DOMRect());
  act(() => { observers[0].callback([], {} as ResizeObserver); flushFrames(); });
  expect(active()).toBe("Selected section");
});

it("collects asynchronous documents and revisions, retaining the explicit visibility choice", async () => {
  await mount("Opening…");
  expect(host.querySelector(".course-toc")).toBeNull();
  scroll.innerHTML = reading("<h2>Original</h2><h3>Details</h3>");
  await settle();
  expect(items().map((button) => button.textContent)).toEqual(["Original", "Details"]);
  expect(panel().hidden).toBe(true);
  act(() => toggle().click());
  escape();

  scroll.querySelector("h3")!.firstChild!.textContent = "Revised details";
  await settle();
  expect(items()[1].textContent).toBe("Revised details");
  expect(panel().hidden).toBe(true);

  scroll.innerHTML = reading("<h2>Another document</h2>");
  await settle();
  expect(items().map((button) => button.textContent)).toEqual(["Another document"]);
  expect(toggle().getAttribute("aria-expanded")).toBe("false");
  expect(observers[0].unobserve).toHaveBeenCalled();

  act(() => toggle().click());
  scroll.innerHTML = reading("<p>The revised document has no headings.</p>");
  await settle();
  expect(host.querySelector(".course-toc")).toBeNull();
  scroll.innerHTML = reading("<h2>Restored heading</h2>");
  await settle();
  expect(items().map((button) => button.textContent)).toEqual(["Restored heading"]);
  expect(panel().hidden).toBe(true);

  scroll.innerHTML = "<article><h2>File lesson</h2><button>Open to read</button></article>";
  await settle();
  expect(host.querySelector(".course-toc")).toBeNull();
});

it("stays collapsed across width changes and keeps keyboard dismissal reachable", async () => {
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  expect(toggle().getAttribute("aria-expanded")).toBe("false");
  expect(panel().hidden).toBe(true);
  for (const nextWidth of [500, 1100, 500]) {
    width = nextWidth;
    act(() => { observers[0].callback([], {} as ResizeObserver); flushFrames(); });
    expect(panel().hidden).toBe(true);
  }
  act(() => toggle().focus());
  expect(panel().hidden).toBe(true);
  act(() => toggle().click());
  expect(panel().hidden).toBe(false);
  expect(document.activeElement).toBe(activeItem());
  act(() => {
    items()[1].focus();
    items()[1].dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
  });
  expect(panel().hidden).toBe(true);
  expect(document.activeElement).toBe(toggle());
  width = 1100;
  act(() => { observers[0].callback([], {} as ResizeObserver); flushFrames(); });
  expect(panel().hidden).toBe(true);
});

it.each([500, 1100])("uses an instant jump for reduced motion and closes after selection at width %i", async (paneWidth) => {
  width = paneWidth; reducedMotion = true;
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  positionHeadings([20, 500]);
  act(() => toggle().click());
  act(() => items()[1].click());
  expect(scroll.scrollTo).toHaveBeenCalledWith({ top: 476, behavior: "instant" });
  expect(panel().hidden).toBe(true);
  expect(document.activeElement).toBe(toggle());
});

it("remeasures section positions after layout changes and releases observers when closed", async () => {
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  const headings = positionHeadings([20, 500]);
  trackScroll(520);
  expect(active()).toBe("Second");
  vi.mocked(headings[1].getBoundingClientRect).mockImplementation(() => new DOMRect(0, 700 - scroll.scrollTop, 300, 30));
  act(() => { observers[0].callback([], {} as ResizeObserver); flushFrames(); });
  expect(active()).toBe("First");
  act(() => scroll.dispatchEvent(new Event("scroll")));
  expect(frames.size).toBe(1);
  act(() => root.render(null));
  expect(observers[0].disconnect).toHaveBeenCalledOnce();
  expect(frames.size).toBe(0);
  act(() => scroll.dispatchEvent(new Event("scroll")));
  expect(frames.size).toBe(0);
});

it("opens on mouse hover, stays open across its panel, and closes after leaving or selecting", async () => {
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  const outline = host.querySelector<HTMLElement>(".course-toc")!;
  pointer("pointerover", toggle());
  expect(panel().hidden).toBe(false);
  pointer("pointerout", toggle(), "mouse", panel());
  expect(panel().hidden).toBe(false);
  pointer("pointerout", outline, "mouse", document.body);
  expect(panel().hidden).toBe(true);

  pointer("pointerover", toggle());
  positionHeadings([20, 500]);
  act(() => items()[1].click());
  expect(scroll.scrollTo).toHaveBeenCalledWith({ top: 476, behavior: "smooth" });
  expect(panel().hidden).toBe(true);
  expect(document.activeElement).toBe(toggle());
});

it("keeps hover open when hiding a focused rail triggers a native blur", async () => {
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  const outline = host.querySelector<HTMLElement>(".course-toc")!;
  act(() => toggle().focus());
  pointer("pointerover", toggle());
  expect(panel().hidden).toBe(false);
  // A display:none trigger loses focus without another element taking it.
  act(() => toggle().dispatchEvent(new FocusEvent("focusout", { bubbles: true, relatedTarget: null })));
  expect(panel().hidden).toBe(false);
  pointer("pointerout", outline, "mouse", document.body);
  expect(panel().hidden).toBe(true);
});

it("opens touch users by click and holds keyboard focus until it leaves the popup", async () => {
  width = 500;
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  const outline = host.querySelector<HTMLElement>(".course-toc")!;
  pointer("pointerover", toggle(), "touch");
  expect(panel().hidden).toBe(true);
  act(() => toggle().click());
  expect(panel().hidden).toBe(false);
  expect(document.activeElement).toBe(activeItem());
  pointer("pointerout", outline, "mouse", document.body);
  expect(panel().hidden).toBe(false);
  escape();

  const outside = document.createElement("button"); container.append(outside);
  act(() => outside.focus());
  pointer("pointerover", toggle());
  expect(document.activeElement).toBe(outside);
  act(() => items()[1].focus());
  pointer("pointerout", outline, "mouse", document.body);
  expect(panel().hidden).toBe(false);
  act(() => outside.focus());
  expect(panel().hidden).toBe(true);
});

it("dismisses an outside pointer press without stealing the outside control's focus", async () => {
  await mount(reading("<h2>First</h2><h2>Second</h2>"));
  const outside = document.createElement("button"); container.append(outside);
  act(() => toggle().click());
  expect(document.activeElement).toBe(activeItem());
  act(() => scroll.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerType: "mouse" })));
  expect(panel().hidden).toBe(true);
  act(() => toggle().click());
  act(() => {
    outside.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerType: "mouse" }));
    outside.focus();
  });
  expect(panel().hidden).toBe(true);
  expect(document.activeElement).toBe(outside);
});

it("keeps a section beyond the first twelve represented in the compact rail", async () => {
  width = 500; contentHeight = 9000;
  await mount(reading(Array.from({ length: 25 }, (_, index) => `<h2>Section ${index + 1}</h2>`).join("")));
  positionHeadings(Array.from({ length: 25 }, (_, index) => 20 + index * 300));
  trackScroll(20 + 19 * 300);
  expect(active()).toBe("Section 20");
  expect(toggle().querySelectorAll(".course-toc__line")).toHaveLength(12);
  expect(toggle().querySelectorAll("[data-current]")).toHaveLength(1);
  expect(panel().hidden).toBe(true);
  act(() => toggle().click());
  expect(items()).toHaveLength(25);
  expect(active()).toBe("Section 20");
  expect(document.activeElement).toBe(items()[19]);
});
