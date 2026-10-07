// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { boxOf, flyGhost, motionAllowed } from "./ghostFly";

let calls: { keyframes: Keyframe[]; options: KeyframeAnimationOptions }[];
let finish: () => void;

beforeEach(() => {
  calls = [];
  vi.stubGlobal("matchMedia", (query: string) => ({ matches: false, media: query, addEventListener() {}, removeEventListener() {} }));
  Element.prototype.animate = function (keyframes: Keyframe[] | PropertyIndexedKeyframes | null, options?: number | KeyframeAnimationOptions) {
    calls.push({ keyframes: keyframes as Keyframe[], options: options as KeyframeAnimationOptions });
    return { finished: new Promise<void>((resolve) => { finish = resolve; }) } as unknown as Animation;
  } as typeof Element.prototype.animate;
});
afterEach(() => {
  document.body.replaceChildren();
  vi.unstubAllGlobals();
});

function card(): HTMLElement {
  const el = document.createElement("div");
  el.id = "card";
  el.setAttribute("data-overview-tab", "a");
  el.innerHTML = '<button data-x="1">Close</button>';
  document.body.append(el);
  return el;
}
const base = { left: 100, top: 200, width: 300, height: 150 };

describe("flyGhost", () => {
  it("starts where it came from, as a squeezed copy, and ends in place", () => {
    flyGhost({ source: card(), base, from: { left: 20, top: 10, width: 60, height: 30 }, to: base, fadeIn: true });
    const [first, ...rest] = calls[0].keyframes;
    expect(first.transform).toBe("translate(-80px, -190px) scale(0.2, 0.2)");
    expect(first.opacity).toBe(0);
    expect(rest.at(-1)).toMatchObject({ transform: "translate(0px, 0px) scale(1, 1)", opacity: 1 });
  });

  it("is a harmless copy: positioned on top, inert, and carrying none of the original's data", () => {
    const original = card();
    flyGhost({ source: original, base, from: base, to: base });
    const ghost = [...document.body.children].find((el) => el !== original) as HTMLElement;
    expect(ghost.style.position).toBe("fixed");
    expect(ghost.style.pointerEvents).toBe("none");
    expect(ghost.getAttribute("aria-hidden")).toBe("true");
    expect(ghost.id).toBe("");
    expect(ghost.hasAttribute("data-overview-tab")).toBe(false);
    expect(ghost.querySelector("[data-x]")).toBeNull();
    expect(document.querySelectorAll("[data-overview-tab]")).toHaveLength(1);
  });

  it("can fade out on the way, and removes itself and says so when it lands", async () => {
    const onDone = vi.fn();
    const original = card();
    flyGhost({ source: original, base, from: base, to: { left: 0, top: 0, width: 900, height: 600 }, fadeOut: true, onDone });
    expect(calls[0].keyframes.at(-1)).toMatchObject({ opacity: 0, transform: "translate(-100px, -200px) scale(3, 4)" });
    finish();
    await Promise.resolve();
    await Promise.resolve();
    expect(onDone).toHaveBeenCalledOnce();
    expect(document.body.children).toHaveLength(1);
  });

  it("does nothing, but still reports done, when the user asks for reduced motion", () => {
    vi.stubGlobal("matchMedia", (query: string) => ({ matches: true, media: query, addEventListener() {}, removeEventListener() {} }));
    const onDone = vi.fn();
    expect(motionAllowed()).toBe(false);
    expect(flyGhost({ source: card(), base, from: base, to: base, onDone })).toBeNull();
    expect(onDone).toHaveBeenCalledOnce();
    expect(calls).toHaveLength(0);
    expect(document.body.children).toHaveLength(1);
  });

  it("measures an element", () => {
    const el = card();
    el.getBoundingClientRect = () => ({ left: 5, top: 6, width: 7, height: 8, right: 12, bottom: 14, x: 5, y: 6, toJSON() {} });
    expect(boxOf(el)).toEqual({ left: 5, top: 6, width: 7, height: 8 });
  });
});
