import { useLayoutEffect, useRef, type RefObject } from "react";
import { boxOf, motionAllowed, type Box } from "../lib/ghostFly";

const KEY = "data-flip-key";

/**
 * Items that change place glide to it instead of jumping. Mark each item with
 * `data-flip-key`; whenever `revision` changes the items are measured again,
 * and any that moved are animated from where they were. One that is new rises
 * in from slightly small. Positions are taken relative to the container, so
 * scrolling it never reads as movement.
 */
export function useFlip(container: RefObject<HTMLElement | null>, revision: unknown, { duration = 340 }: { duration?: number } = {}) {
  const previous = useRef<Map<string, Box> | null>(null);
  const running = useRef(new Map<string, Animation>());

  useLayoutEffect(() => {
    const root = container.current;
    if (!root) return;
    // Finish what is moving first, so every measurement is of where things really are.
    for (const animation of running.current.values()) animation.cancel();
    running.current.clear();
    const origin = root.getBoundingClientRect();
    const items = [...root.querySelectorAll<HTMLElement>(`[${KEY}]`)];
    const next = new Map<string, Box>();
    for (const item of items) {
      const box = boxOf(item);
      next.set(item.getAttribute(KEY)!, { left: box.left - origin.left, top: box.top - origin.top, width: box.width, height: box.height });
    }
    const before = previous.current;
    previous.current = next;
    if (!before || !motionAllowed()) return;
    for (const item of items) {
      const key = item.getAttribute(KEY)!;
      const to = next.get(key)!;
      const from = before.get(key);
      let animation: Animation;
      if (from) {
        const dx = from.left - to.left;
        const dy = from.top - to.top;
        if (Math.abs(dx) < 1 && Math.abs(dy) < 1) continue;
        animation = item.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }], { duration, easing: "cubic-bezier(0.2, 0.9, 0.25, 1)" });
      } else {
        animation = item.animate([{ opacity: 0, transform: "scale(0.92)" }, { opacity: 1, transform: "none" }], { duration, easing: "cubic-bezier(0.2, 0.9, 0.25, 1)" });
      }
      running.current.set(key, animation);
      animation.finished.then(() => running.current.delete(key), () => running.current.delete(key));
    }
  }, [container, revision, duration]);
}
