// @vitest-environment happy-dom
import { act, createElement, useRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useGlide } from "./useGlide";

let root: Root;
let container: HTMLDivElement;
let goal: { left: number; width: number };
let frames: FrameRequestCallback[];
let clock: number;
let reduced = false;

function Strip({ revision, live = false, missing = false }: { revision: string; live?: boolean; missing?: boolean }) {
  const pill = useRef<HTMLDivElement>(null);
  const scroller = useRef<HTMLDivElement>(null);
  const target = useRef<HTMLDivElement>(null);
  useGlide({ pill, root: scroller, target: () => (missing ? null : target.current), revision, live });
  return createElement("div", { ref: scroller }, createElement("div", { ref: pill, "data-pill": true }), createElement("div", { ref: target, "data-target": true }));
}
const pill = () => container.querySelector<HTMLElement>("[data-pill]")!;
const x = () => Number(/translateX\((-?[\d.]+)px\)/.exec(pill().style.transform)?.[1] ?? NaN);
const width = () => parseFloat(pill().style.width);
/** Run animation frames, 16ms apart. */
function run(count: number) {
  for (let i = 0; i < count; i += 1) {
    clock += 16;
    const due = frames.splice(0);
    act(() => due.forEach((frame) => frame(clock)));
  }
}
const render = (revision: string, live = false, missing = false) => act(() => root.render(createElement(Strip, { revision, live, missing })));

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  goal = { left: 40, width: 120 };
  frames = [];
  clock = 1000;
  reduced = false;
  vi.stubGlobal("matchMedia", (query: string) => ({ matches: reduced, media: query, addEventListener() {}, removeEventListener() {} }));
  vi.stubGlobal("requestAnimationFrame", (cb: FrameRequestCallback) => { frames.push(cb); return frames.length; });
  vi.stubGlobal("cancelAnimationFrame", () => { frames.length = 0; });
  vi.spyOn(performance, "now").mockImplementation(() => clock);
  Element.prototype.getBoundingClientRect = function (this: Element) {
    const target = this.hasAttribute("data-target");
    const left = target ? goal.left : 0;
    const w = target ? goal.width : 800;
    return { left, top: 0, width: w, height: 30, right: left + w, bottom: 30, x: left, y: 0, toJSON() {} };
  };
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("useGlide", () => {
  it("starts on its target, without gliding in from nowhere", () => {
    render("a");
    run(1);
    expect(x()).toBe(40);
    expect(width()).toBe(120);
  });

  it("glides to a new target over several frames, never overshooting, and then rests", () => {
    render("a");
    run(2);
    goal = { left: 300, width: 80 };
    render("b");
    run(1);
    expect(x()).toBeGreaterThan(40);
    expect(x()).toBeLessThan(300);
    let furthest = 0;
    for (let i = 0; i < 90; i += 1) {
      run(1);
      furthest = Math.max(furthest, x());
    }
    expect(furthest).toBeLessThanOrEqual(300.5);
    expect(x()).toBe(300);
    expect(width()).toBe(80);
    expect(frames).toHaveLength(0);
  });

  it("keeps up with a target that is still moving, such as a tab still changing width", () => {
    render("a");
    run(2);
    render("b");
    for (let i = 0; i < 20; i += 1) {
      goal = { left: 40 + i * 5, width: 120 + i * 2 };
      run(1);
    }
    expect(x()).toBeGreaterThan(80);
    expect(Math.abs(x() - goal.left)).toBeLessThan(40);
  });

  it("jumps straight there when the user asked for reduced motion", () => {
    reduced = true;
    render("a");
    run(1);
    goal = { left: 500, width: 90 };
    render("b");
    run(1);
    expect(x()).toBe(500);
    expect(width()).toBe(90);
  });

  it("hides when there is nothing to follow, and comes back when there is", () => {
    render("a");
    run(1);
    expect(pill().style.opacity).toBe("1");
    render("b", false, true);
    run(1);
    expect(pill().style.opacity).toBe("0");
    render("c");
    run(2);
    expect(pill().style.opacity).toBe("1");
  });

  it("keeps following for as long as it is told the target may be dragged", () => {
    render("a", true);
    run(2);
    run(30);
    expect(frames.length).toBeGreaterThan(0);
    goal = { left: 200, width: 120 };
    run(80);
    expect(x()).toBeCloseTo(200, 0);
  });
});
