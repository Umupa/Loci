import { useLayoutEffect, type RefObject } from "react";

type Glide = { x: number; w: number; vx: number; vw: number; ready: boolean };

/** How stiff the highlight is. Critically damped, so it arrives without overshooting. */
const STIFFNESS = 520;
const DAMPING = 2 * Math.sqrt(STIFFNESS);
const SETTLED_DISTANCE = 0.25;
const SETTLED_FRAMES = 4;

function reducedMotion(): boolean {
  return typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * A highlight that follows a target element with a spring, instead of cutting
 * from tab to tab. The target is read every frame, so it keeps up with a tab
 * that is itself still growing or shrinking. It rests once it has arrived.
 *
 * `revision` is anything whose change may have moved the target.
 */
export function useGlide({ pill, root, target, revision, live = false }: {
  pill: RefObject<HTMLElement | null>;
  /** The scroller the pill lives in; positions are measured against its content. */
  root: RefObject<HTMLElement | null>;
  target: () => HTMLElement | null;
  revision: unknown;
  /** Keep following even once arrived, for as long as the target may be moved by hand. */
  live?: boolean;
}) {
  useLayoutEffect(() => {
    const el = pill.current;
    const scroller = root.current;
    if (!el || !scroller) return;
    const state: Glide = (el as unknown as { __glide?: Glide }).__glide ?? { x: 0, w: 0, vx: 0, vw: 0, ready: false };
    (el as unknown as { __glide?: Glide }).__glide = state;
    const instant = reducedMotion();
    let frame = 0;
    let last = performance.now();
    let calm = 0;

    const measure = () => {
      const node = target();
      if (!node) return null;
      const box = node.getBoundingClientRect();
      const base = scroller.getBoundingClientRect();
      return { x: box.left - base.left + scroller.scrollLeft, w: box.width };
    };
    const paint = () => {
      el.style.transform = `translateX(${state.x}px)`;
      el.style.width = `${Math.max(0, state.w)}px`;
    };
    const step = (now: number) => {
      const goal = measure();
      if (!goal) {
        // With nothing to follow it hides, and reappears in place rather than flying in from where it was.
        el.style.opacity = "0";
        state.ready = false;
        return;
      }
      if (!state.ready || instant) {
        Object.assign(state, { x: goal.x, w: goal.w, vx: 0, vw: 0, ready: true });
        el.style.opacity = "1";
        paint();
        if (instant) return;
      }
      const dt = Math.min(0.032, (now - last) / 1000);
      last = now;
      state.vx += ((goal.x - state.x) * STIFFNESS - state.vx * DAMPING) * dt;
      state.vw += ((goal.w - state.w) * STIFFNESS - state.vw * DAMPING) * dt;
      state.x += state.vx * dt;
      state.w += state.vw * dt;
      paint();
      const arrived = Math.abs(goal.x - state.x) < SETTLED_DISTANCE && Math.abs(goal.w - state.w) < SETTLED_DISTANCE
        && Math.abs(state.vx) < 1 && Math.abs(state.vw) < 1;
      calm = arrived ? calm + 1 : 0;
      if (calm >= SETTLED_FRAMES && !live) {
        Object.assign(state, { x: goal.x, w: goal.w, vx: 0, vw: 0 });
        paint();
        return;
      }
      frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
    // The refs and the target reader are stable by construction; only `revision` moves the target.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [revision, live]);
}
