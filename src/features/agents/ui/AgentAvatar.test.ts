// @vitest-environment happy-dom
import { act, createElement, Fragment, Profiler, StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AGENT_AVATARS } from "../model/agentAvatars";
import { AgentAvatar, AgentAvatarPreview } from "./AgentAvatar";

let root: Root;
let container: HTMLDivElement;
let hidden: boolean;
let hiddenDescriptor: PropertyDescriptor | undefined;
let observers: TestIntersectionObserver[];
let media: MediaQueryList;
let mediaEvents: EventTarget;
let matchMedia: ReturnType<typeof vi.fn>;
let requestFrame: ReturnType<typeof vi.fn>;
let setInterval: ReturnType<typeof vi.spyOn>;

class TestIntersectionObserver {
  callback: IntersectionObserverCallback;
  targets = new Set<Element>();
  observe = vi.fn((target: Element) => this.targets.add(target));
  disconnect = vi.fn(() => this.targets.clear());

  constructor(callback: IntersectionObserverCallback) {
    this.callback = callback;
    observers.push(this);
  }

  intersect(visible: boolean) {
    this.callback(
      [...this.targets].map((target) => ({ target, isIntersecting: visible }) as IntersectionObserverEntry),
      this as unknown as IntersectionObserver,
    );
  }
}

function preview(name = "dew", color = "#428fff") {
  act(() => root.render(createElement(AgentAvatarPreview, { name, color })));
}

function intersect(visible: boolean) {
  act(() => observers.at(-1)!.intersect(visible));
}

function visibility(isHidden: boolean) {
  hidden = isHidden;
  act(() => document.dispatchEvent(new Event("visibilitychange")));
}

function reduced(matches: boolean) {
  Object.defineProperty(media, "matches", { configurable: true, value: matches });
  act(() => mediaEvents.dispatchEvent(Object.assign(new Event("change"), { matches })));
}

function advance(milliseconds: number) {
  act(() => vi.advanceTimersByTime(milliseconds));
}

function hover() {
  act(() => svg().dispatchEvent(new Event("pointerenter")));
}

function svg() {
  return container.querySelector<SVGSVGElement>("svg")!;
}

function isBlinking() {
  return svg().getAttribute("data-blinking") === "true";
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
  vi.spyOn(Math, "random").mockReturnValue(0);
  hidden = false;
  hiddenDescriptor = Object.getOwnPropertyDescriptor(document, "hidden");
  Object.defineProperty(document, "hidden", { configurable: true, get: () => hidden });
  observers = [];
  vi.stubGlobal("IntersectionObserver", TestIntersectionObserver);
  mediaEvents = new EventTarget();
  media = {
    matches: false,
    media: "(prefers-reduced-motion: reduce)",
    onchange: null,
    addEventListener: vi.fn(mediaEvents.addEventListener.bind(mediaEvents)),
    removeEventListener: vi.fn(mediaEvents.removeEventListener.bind(mediaEvents)),
    dispatchEvent: mediaEvents.dispatchEvent.bind(mediaEvents),
  } as unknown as MediaQueryList;
  matchMedia = vi.fn(() => media);
  vi.stubGlobal("matchMedia", matchMedia);
  requestFrame = vi.fn();
  vi.stubGlobal("requestAnimationFrame", requestFrame);
  setInterval = vi.spyOn(globalThis, "setInterval");
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  if (hiddenDescriptor) Object.defineProperty(document, "hidden", hiddenDescriptor);
  else Reflect.deleteProperty(document, "hidden");
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("AgentAvatar", () => {
  it("keeps a large list of small avatars free of animation resources and SVG ID collisions", () => {
    act(() => root.render(createElement(
      Fragment,
      null,
      ...Array.from({ length: 100 }, (_, key) => createElement(AgentAvatar, {
        key,
        name: AGENT_AVATARS[key % AGENT_AVATARS.length].name,
        color: "#428fff",
      })),
    )));

    expect(container.querySelectorAll("svg")).toHaveLength(100);
    expect(vi.getTimerCount()).toBe(0);
    expect(observers).toHaveLength(0);
    expect(matchMedia).not.toHaveBeenCalled();
    expect(requestFrame).not.toHaveBeenCalled();
    expect(setInterval).not.toHaveBeenCalled();
    const ids = [...container.querySelectorAll("[id]")].map((element) => element.id);
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
    expect(container.innerHTML).not.toContain("__LOCI_AVATAR_ID__");
    for (const face of container.querySelectorAll("svg")) {
      const localIds = new Set([...face.querySelectorAll("[id]")].map((element) => element.id));
      for (const element of face.querySelectorAll("*")) {
        const href = element.getAttribute("href");
        if (href) expect(localIds.has(href.slice(1))).toBe(true);
        for (const attribute of element.attributes) {
          for (const [, id] of attribute.value.matchAll(/url\(#([^)]*)\)/g)) {
            expect(localIds.has(id)).toBe(true);
          }
        }
      }
    }
    advance(30_000);
    expect(container.querySelector("[data-blinking]")).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it.each([
    ["dew", "0 0 180 180"],
    ["neutral-dew", "0 0 120 120"],
  ])("updates %s's chosen color while preserving its native canvas, eye colors, and artwork", (name, viewBox) => {
    act(() => root.render(createElement(AgentAvatar, {
      name,
      color: "hsl(45 90% 55%)",
    })));
    expect(svg().getAttribute("viewBox")).toBe(viewBox);
    expect(svg().getAttribute("shape-rendering")).not.toBe("crispEdges");
    expect(svg().style.color).toBe("hsl(45 90% 55%)");
    expect(svg().querySelector('[fill="currentColor"]')).not.toBeNull();
    const artwork = svg().innerHTML;
    const eyeColors = [...svg().querySelectorAll(".agent-avatar-eyes [fill]")].map((eye) => eye.getAttribute("fill"));
    expect(eyeColors.length).toBeGreaterThan(0);

    act(() => root.render(createElement(AgentAvatar, { name, color: "#428fff" })));
    expect(svg().style.color).toBe("#428fff");
    expect(svg().innerHTML).toBe(artwork);
    expect([...svg().querySelectorAll(".agent-avatar-eyes [fill]")].map((eye) => eye.getAttribute("fill"))).toEqual(eyeColors);
  });
});

describe("AgentAvatarPreview", () => {
  it.each(["ember", "wisp", "pebble", "neutral-ember", "neutral-wisp", "neutral-pebble"])("keeps %s's fixed eye expression free of blink timers", (name) => {
    preview(name);
    intersect(true);
    expect(vi.getTimerCount()).toBe(0);
    advance(30_000);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("blinks once when it appears, then stays still until the pointer is over it", () => {
    preview();
    expect(vi.getTimerCount()).toBe(0);
    intersect(true);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    advance(160);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    advance(30_000);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);

    hover();
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    advance(160);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("stops blinking for a fixed expression and blinks when selecting an animated face", () => {
    preview();
    intersect(true);
    expect(isBlinking()).toBe(true);
    const observerCount = observers.length;

    preview("wisp");
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    advance(20_000);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);

    preview("moss");
    expect(observers).toHaveLength(observerCount);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    advance(160);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it.each(["dew", "neutral-dew"])("blinks %s once on appearance without animation frames or React commits", (name) => {
    const onRender = vi.fn();
    act(() => root.render(createElement(
      Profiler,
      { id: "preview", onRender },
      createElement(AgentAvatarPreview, { name, color: "#428fff" }),
    )));
    expect(vi.getTimerCount()).toBe(0);
    expect(isBlinking()).toBe(false);
    intersect(true);
    const commits = onRender.mock.calls.length;
    const artwork = svg().innerHTML;
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    advance(159);
    expect(isBlinking()).toBe(true);
    advance(1);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    expect(svg().innerHTML).toBe(artwork);
    expect(onRender).toHaveBeenCalledTimes(commits);
    expect(requestFrame).not.toHaveBeenCalled();
    expect(setInterval).not.toHaveBeenCalled();
  });

  it("only reacts to the latest face selection and does not restart for color changes", () => {
    const addListener = vi.spyOn(document, "addEventListener");
    preview();
    intersect(true);
    advance(160);
    const observerCount = observers.length;
    const mediaCount = matchMedia.mock.calls.length;
    const visibilityListeners = () => addListener.mock.calls.filter(([type]) => type === "visibilitychange").length;
    const listenerCount = visibilityListeners();

    preview("moss");
    expect(isBlinking()).toBe(true);
    advance(100);
    preview("dew");
    expect(isBlinking()).toBe(true);
    expect(svg().dataset.agentAvatar).toBe("dew");
    // Changing a face does not change its visibility or require another IO notification.
    expect(observers).toHaveLength(observerCount);
    expect(matchMedia).toHaveBeenCalledTimes(mediaCount);
    expect(visibilityListeners()).toBe(listenerCount);
    expect(vi.getTimerCount()).toBe(1);

    advance(160);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    const artwork = svg().innerHTML;
    preview("dew", "hsl(45 90% 55%)");
    expect(observers).toHaveLength(observerCount);
    expect(vi.getTimerCount()).toBe(0);
    expect(isBlinking()).toBe(false);
    expect(svg().innerHTML).toBe(artwork);
  });

  it("switches series without adding animation resources or losing the chosen color", () => {
    preview();
    intersect(true);
    advance(160);
    const originalArtwork = svg().innerHTML;
    const observerCount = observers.length;
    const mediaCount = matchMedia.mock.calls.length;

    preview("neutral-dew");
    expect(svg().dataset.agentAvatar).toBe("neutral-dew");
    expect(svg().getAttribute("viewBox")).toBe("0 0 120 120");
    expect(svg().style.color).toBe("#428fff");
    expect(svg().innerHTML).not.toBe(originalArtwork);
    expect(observers).toHaveLength(observerCount);
    expect(matchMedia).toHaveBeenCalledTimes(mediaCount);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    advance(160);
    expect(isBlinking()).toBe(false);

    preview("neutral-wisp");
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);

    preview("dew");
    expect(svg().getAttribute("viewBox")).toBe("0 0 180 180");
    expect(svg().style.color).toBe("#428fff");
    expect(observers).toHaveLength(observerCount);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
  });

  it("does no scheduled work outside the viewport and blinks once on re-entering", () => {
    preview();
    intersect(false);
    expect(vi.getTimerCount()).toBe(0);
    advance(20_000);
    expect(isBlinking()).toBe(false);
    intersect(true);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    advance(160);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    intersect(false);
    expect(vi.getTimerCount()).toBe(0);
    preview("moss");
    expect(vi.getTimerCount()).toBe(0);
    intersect(true);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
  });

  it("stops an in-progress blink when the document is hidden", () => {
    preview();
    intersect(true);
    expect(isBlinking()).toBe(true);
    visibility(true);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    advance(20_000);
    visibility(false);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
    hover();
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
  });

  it("honors reduced motion at mount and when the preference changes", () => {
    reduced(true);
    preview();
    intersect(true);
    expect(vi.getTimerCount()).toBe(0);
    advance(20_000);
    expect(isBlinking()).toBe(false);

    reduced(false);
    hover();
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    reduced(true);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("blinks only when viewport, document visibility, and motion preference all permit it", () => {
    preview();
    intersect(false);
    visibility(true);
    hover();
    intersect(true);
    expect(vi.getTimerCount()).toBe(0);
    expect(isBlinking()).toBe(false);

    reduced(true);
    visibility(false);
    reduced(false);
    expect(vi.getTimerCount()).toBe(0);
    intersect(false);
    intersect(true);
    expect(isBlinking()).toBe(true);
    visibility(true);
    expect(isBlinking()).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("cleans up timers, observers, and listeners across StrictMode effects and unmount", () => {
    const addListener = vi.spyOn(document, "addEventListener");
    const removeListener = vi.spyOn(document, "removeEventListener");
    act(() => root.render(createElement(
      StrictMode,
      null,
      createElement(AgentAvatarPreview, { name: "dew", color: "#428fff" }),
    )));
    expect(observers.filter((observer) => observer.targets.size > 0)).toHaveLength(1);
    expect(observers[0].disconnect).toHaveBeenCalled();
    intersect(true);
    expect(isBlinking()).toBe(true);
    expect(vi.getTimerCount()).toBe(1);
    const target = svg();

    act(() => root.unmount());
    expect(vi.getTimerCount()).toBe(0);
    expect(target.hasAttribute("data-blinking")).toBe(false);
    for (const observer of observers) expect(observer.disconnect).toHaveBeenCalled();
    expect(media.removeEventListener).toHaveBeenCalledTimes(vi.mocked(media.addEventListener).mock.calls.length);
    const addedVisibilityListeners = addListener.mock.calls.filter(([type]) => type === "visibilitychange");
    const removedVisibilityListeners = removeListener.mock.calls.filter(([type]) => type === "visibilitychange");
    expect(removedVisibilityListeners).toHaveLength(addedVisibilityListeners.length);
    // A notification queued before disconnect can still reach an old callback.
    act(() => {
      for (const observer of observers) {
        observer.callback(
          [{ target, isIntersecting: true } as IntersectionObserverEntry],
          observer as unknown as IntersectionObserver,
        );
      }
    });
    expect(vi.getTimerCount()).toBe(0);
    visibility(false);
    reduced(false);
    advance(20_000);
    expect(vi.getTimerCount()).toBe(0);
  });
});
