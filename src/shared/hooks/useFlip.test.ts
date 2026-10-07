// @vitest-environment happy-dom
import { act, createElement, useRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useFlip } from "./useFlip";

let root: Root;
let container: HTMLDivElement;
let positions: Record<string, { left: number; top: number }>;
let animations: { key: string | null; keyframes: Keyframe[]; cancelled: boolean }[];

function Grid({ keys }: { keys: string[] }) {
  const ref = useRef<HTMLDivElement>(null);
  useFlip(ref, keys.join(","));
  return createElement("div", { ref }, keys.map((key) => createElement("div", { key, "data-flip-key": key })));
}
const render = (keys: string[]) => act(() => root.render(createElement(Grid, { keys })));

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  positions = {};
  animations = [];
  vi.stubGlobal("matchMedia", (query: string) => ({ matches: false, media: query, addEventListener() {}, removeEventListener() {} }));
  Element.prototype.getBoundingClientRect = function (this: Element) {
    const key = this.getAttribute("data-flip-key");
    const at = key ? positions[key] ?? { left: 0, top: 0 } : { left: 0, top: 0 };
    return { left: at.left, top: at.top, width: 100, height: 50, right: at.left + 100, bottom: at.top + 50, x: at.left, y: at.top, toJSON() {} };
  };
  Element.prototype.animate = function (this: Element, keyframes: Keyframe[] | PropertyIndexedKeyframes | null) {
    const record = { key: this.getAttribute("data-flip-key"), keyframes: keyframes as Keyframe[], cancelled: false };
    animations.push(record);
    return { finished: new Promise(() => {}), cancel() { record.cancelled = true; } } as unknown as Animation;
  } as typeof Element.prototype.animate;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

describe("useFlip", () => {
  it("does not animate the first layout", () => {
    positions = { a: { left: 0, top: 0 }, b: { left: 100, top: 0 } };
    render(["a", "b"]);
    expect(animations).toHaveLength(0);
  });

  it("slides an item from where it was to where it is now", () => {
    positions = { a: { left: 0, top: 0 }, b: { left: 100, top: 0 }, c: { left: 200, top: 0 } };
    render(["a", "b", "c"]);
    // a is closed: b and c close up around the gap.
    positions = { b: { left: 0, top: 0 }, c: { left: 100, top: 0 } };
    render(["b", "c"]);
    expect(animations.map((a) => [a.key, a.keyframes[0].transform])).toEqual([["b", "translate(100px, 0px)"], ["c", "translate(100px, 0px)"]]);
  });

  it("brings in an item that was not there before, small and faded", () => {
    positions = { a: { left: 0, top: 0 } };
    render(["a"]);
    positions = { a: { left: 0, top: 0 }, b: { left: 100, top: 0 } };
    render(["a", "b"]);
    expect(animations).toHaveLength(1);
    expect(animations[0]).toMatchObject({ key: "b" });
    expect(animations[0].keyframes[0]).toMatchObject({ opacity: 0, transform: "scale(0.92)" });
  });

  it("leaves items that stayed alone", () => {
    positions = { a: { left: 0, top: 0 }, b: { left: 100, top: 0 } };
    render(["a", "b"]);
    render(["a", "b", "b"].slice(0, 2).reverse().reverse());
    expect(animations).toHaveLength(0);
  });

  it("does not move anything for a user who asked for reduced motion", () => {
    vi.stubGlobal("matchMedia", (query: string) => ({ matches: true, media: query, addEventListener() {}, removeEventListener() {} }));
    positions = { a: { left: 0, top: 0 }, b: { left: 100, top: 0 } };
    render(["a", "b"]);
    positions = { b: { left: 0, top: 0 } };
    render(["b"]);
    expect(animations).toHaveLength(0);
  });
});
