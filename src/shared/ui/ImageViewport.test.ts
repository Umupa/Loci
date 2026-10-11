// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ImageViewport } from "./ImageViewport";
import { requestImageZoom } from "../lib/imageZoomCommands";

const native = vi.hoisted(() => ({ claims: [] as Array<(delta: number) => void> }));
vi.mock("../../platform/tauri/trackpadZoom", () => ({
  claimTrackpadMagnify: (callback: (delta: number) => void) => {
    native.claims.push(callback);
    return () => { native.claims.splice(native.claims.indexOf(callback), 1); };
  },
}));

let roots: Root[];
const resizeCallbacks = new Map<Element, ResizeObserverCallback>();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  roots = [];
  native.claims.length = 0;
  resizeCallbacks.clear();
  vi.stubGlobal("ResizeObserver", class {
    constructor(private callback: ResizeObserverCallback) {}
    observe(element: Element) { resizeCallbacks.set(element, this.callback); }
    disconnect() {
      for (const [element, callback] of resizeCallbacks) {
        if (callback === this.callback) resizeCallbacks.delete(element);
      }
    }
  });
});

afterEach(() => {
  act(() => roots.forEach((root) => root.unmount()));
  expect(native.claims).toHaveLength(0);
  document.body.replaceChildren();
  vi.unstubAllGlobals();
});

function mount(props: Partial<ComponentProps<typeof ImageViewport>> = {}) {
  const host = document.createElement("div");
  document.body.append(host);
  const root = createRoot(host);
  roots.push(root);
  const initial = { src: "image.png", alt: "Diagram", active: "focused" as const, ...props };
  act(() => root.render(createElement(ImageViewport, initial)));
  let width = 1048;
  let height = 548;
  const image = () => host.querySelector("img")!;
  const viewport = () => image().parentElement!;
  const load = () => {
    Object.defineProperties(viewport(), {
      clientWidth: { configurable: true, get: () => width },
      clientHeight: { configurable: true, get: () => height },
      getBoundingClientRect: { configurable: true, value: () => new DOMRect(20, 30, width, height) },
    });
    Object.defineProperties(image(), {
      naturalWidth: { configurable: true, value: 2000 },
      naturalHeight: { configurable: true, value: 1000 },
    });
    act(() => image().dispatchEvent(new Event("load")));
  };
  const click = (label: string) => act(() => host.querySelector<HTMLButtonElement>(`[aria-label="${label}"]`)!.click());
  const zoom = () => host.querySelector("output")!.textContent;
  return {
    host, root, image, viewport, load, click, zoom,
    resize(nextWidth: number, nextHeight: number) {
      width = nextWidth; height = nextHeight;
      act(() => resizeCallbacks.get(viewport())!([], {} as ResizeObserver));
    },
    source(src: string) { act(() => root.render(createElement(ImageViewport, { ...initial, src }))); },
  };
}

function wheel(element: Element, values: WheelEventInit) {
  const event = new WheelEvent("wheel", { bubbles: true, cancelable: true, clientX: 544, clientY: 304, ...values });
  // Happy DOM's WheelEvent does not inherit the MouseEvent coordinates/modifiers.
  Object.assign(event, { clientX: 544, clientY: 304, ctrlKey: false, metaKey: false, ...values });
  act(() => element.dispatchEvent(event));
  expect(event.defaultPrevented).toBe(true);
}

function pointer(element: Element, type: string, x: number, y: number) {
  act(() => element.dispatchEvent(new PointerEvent(type, {
    bubbles: true, pointerId: 1, isPrimary: true, button: 0, clientX: x, clientY: y,
  })));
}

function gesture(element: Element, type: string, scale = 1) {
  const event = Object.assign(new Event(type, { bubbles: true, cancelable: true }), { scale });
  act(() => element.dispatchEvent(event));
  expect(event.defaultPrevented).toBe(true);
}

describe("image viewport interactions", () => {
  it("starts at the actual fitted scale and changes zoom relative to what is visible", () => {
    const view = mount();
    expect(view.host.querySelector<HTMLButtonElement>('[aria-label="Zoom in"]')!.disabled).toBe(true);
    expect(requestImageZoom("zoom-in")).toBe(true);
    view.load();
    expect(view.zoom()).toBe("50%");
    expect(view.image().style.width).toBe("1000px");
    expect(view.image().style.height).toBe("500px");
    view.click("Zoom out");
    expect(view.zoom()).toBe("40%");
    expect(view.image().style.width).toBe("800px");
    view.click("Zoom in");
    expect(view.zoom()).toBe("50%");
    view.click("Actual size");
    expect(view.zoom()).toBe("100%");
    expect(view.image().style.width).toBe("2000px");
    view.click("Fit to window");
    expect(view.zoom()).toBe("50%");
  });

  it("zooms around the wheel pointer, pans ordinary scrolling, and keeps image edges reachable", () => {
    const view = mount();
    view.load();
    wheel(view.viewport(), { ctrlKey: true, deltaY: -Math.log(2) / 0.01, clientX: 644, clientY: 354 });
    expect(view.zoom()).toBe("100%");
    // The same image pixel remains 100px right and 50px below viewport center.
    expect(view.image().style.transform).toContain("translate(-100px, -50px)");
    wheel(view.viewport(), { deltaX: 30, deltaY: 40 });
    expect(view.zoom()).toBe("100%");
    expect(view.image().style.transform).toContain("translate(-130px, -90px)");
    wheel(view.viewport(), { deltaX: -5000, deltaY: 5000 });
    expect(view.image().style.transform).toContain("translate(500px, -250px)");
    wheel(view.viewport(), { ctrlKey: true, deltaY: -10000 });
    expect(view.zoom()).toBe("1600%");
    wheel(view.viewport(), { ctrlKey: true, deltaY: 10000 });
    expect(view.zoom()).toBe("5%");
    expect(view.image().style.transform).toContain("translate(0px, 0px)");
  });

  it("uses WebKit gesture scale cumulatively and ignores duplicate wheel events during a pinch", () => {
    const view = mount();
    view.load();
    gesture(view.viewport(), "gesturestart");
    gesture(view.viewport(), "gesturechange", 1.2);
    expect(view.zoom()).toBe("60%");
    gesture(view.viewport(), "gesturechange", 1.3);
    expect(view.zoom()).toBe("65%");
    wheel(view.viewport(), { ctrlKey: true, deltaY: -100 });
    expect(view.zoom()).toBe("65%");
    gesture(view.viewport(), "gestureend");
    wheel(view.viewport(), { ctrlKey: true, deltaY: -Math.log(2) / 0.01 });
    expect(view.zoom()).toBe("130%");
  });

  it("applies native magnification only to the active image and releases claims on unmount", () => {
    const focused = mount();
    focused.load();
    const modal = mount({ active: "modal" });
    modal.load();
    // A background pane mounting/loading later must not steal the modal's pinch.
    const background = mount();
    background.load();
    act(() => native.claims.at(-1)!(0.2));
    expect(focused.zoom()).toBe("50%");
    expect(modal.zoom()).toBe("60%");
    expect(background.zoom()).toBe("50%");
    act(() => background.root.unmount());
    act(() => modal.root.unmount());
    expect(native.claims).toHaveLength(1);
    const dialog = document.createElement("div");
    dialog.setAttribute("role", "dialog");
    document.body.append(dialog);
    act(() => native.claims[0](0.2));
    expect(focused.zoom()).toBe("50%");
    dialog.remove();
    pointer(focused.viewport(), "pointermove", 644, 354);
    act(() => native.claims[0](1));
    expect(focused.zoom()).toBe("100%");
    expect(focused.image().style.transform).toContain("translate(-100px, -50px)");
    const inactive = mount({ active: undefined });
    inactive.load();
    expect(native.claims).toHaveLength(1);
  });

  it("distinguishes a backdrop click from panning or a cancelled pointer gesture", () => {
    const close = vi.fn();
    const view = mount({ active: "modal", onBackgroundClick: close });
    view.load();
    view.click("Actual size");
    pointer(view.viewport(), "pointerdown", 544, 304);
    pointer(view.viewport(), "pointermove", 644, 354);
    pointer(view.viewport(), "pointerup", 644, 354);
    expect(view.image().style.transform).toContain("translate(100px, 50px)");
    expect(close).not.toHaveBeenCalled();
    pointer(view.viewport(), "pointerdown", 544, 304);
    pointer(view.viewport(), "pointercancel", 544, 304);
    pointer(view.viewport(), "pointerup", 544, 304);
    expect(close).not.toHaveBeenCalled();
    pointer(view.image(), "pointerdown", 544, 304);
    pointer(view.image(), "pointerup", 544, 304);
    expect(close).not.toHaveBeenCalled();
    pointer(view.viewport(), "pointerdown", 44, 54);
    pointer(view.viewport(), "pointerup", 44, 54);
    expect(close).toHaveBeenCalledOnce();
  });

  it("recomputes Fit on resize, preserves manual scale, and resets for a new source", () => {
    const view = mount();
    view.load();
    view.resize(848, 448);
    expect(view.zoom()).toBe("40%");
    view.click("Actual size");
    wheel(view.viewport(), { deltaX: -10000, deltaY: -10000 });
    view.resize(1648, 848);
    expect(view.zoom()).toBe("100%");
    expect(view.image().style.transform).toContain("translate(200px, 100px)");
    view.source("another.png");
    expect(view.image().style.visibility).toBe("hidden");
    expect(native.claims).toHaveLength(1);
    expect(requestImageZoom("zoom-in")).toBe(true);
    view.load();
    expect(view.zoom()).toBe("80%");
    expect(view.image().style.transform).toContain("translate(0px, 0px)");
    expect(view.host.querySelector('[aria-label="Fit to window"]')?.getAttribute("aria-pressed")).toBe("true");
  });
});
