import { LAYER } from "./layers";

export type Box = { left: number; top: number; width: number; height: number };

const EASE = "cubic-bezier(0.2, 0.9, 0.25, 1)";

export function motionAllowed(): boolean {
  return typeof Element !== "undefined"
    && typeof Element.prototype.animate === "function"
    && !(typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
}

export function boxOf(element: Element): Box {
  const { left, top, width, height } = element.getBoundingClientRect();
  return { left, top, width, height };
}

/** The transform that makes something laid out as `base` look like `box`. */
function transformFor(box: Box, base: Box): string {
  return `translate(${box.left - base.left}px, ${box.top - base.top}px) scale(${box.width / Math.max(1, base.width)}, ${box.height / Math.max(1, base.height)})`;
}

/**
 * A copy of an element that moves from one place to another above everything
 * and then removes itself. It is laid out as `base`; `from` and `to` are where
 * it appears to start and end, so it can leave the bounds of whatever clips the
 * real element (a scroller, a dialog) and cross the app on the way.
 */
export function flyGhost({ source, base, from, to, duration = 460, delay = 0, fadeIn = false, fadeOut = false, onDone }: {
  source: HTMLElement;
  base: Box;
  from: Box;
  to: Box;
  duration?: number;
  delay?: number;
  fadeIn?: boolean;
  fadeOut?: boolean;
  onDone?: () => void;
}): Animation | null {
  if (!motionAllowed()) {
    onDone?.();
    return null;
  }
  const ghost = source.cloneNode(true) as HTMLElement;
  // The copy must not be mistaken for the original by anything that looks cards up.
  for (const node of [ghost, ...ghost.querySelectorAll<HTMLElement>("*")]) {
    for (const name of node.getAttributeNames()) if (name.startsWith("data-")) node.removeAttribute(name);
    node.removeAttribute("id");
  }
  Object.assign(ghost.style, {
    position: "fixed",
    left: `${base.left}px`,
    top: `${base.top}px`,
    width: `${base.width}px`,
    height: `${base.height}px`,
    margin: "0",
    pointerEvents: "none",
    zIndex: String(LAYER.toast + 1),
    transformOrigin: "0 0",
    transition: "none",
    visibility: "visible",
  });
  ghost.setAttribute("aria-hidden", "true");
  document.body.append(ghost);
  const frames: Keyframe[] = [
    { transform: transformFor(from, base), opacity: fadeIn ? 0 : 1, offset: 0 },
    ...(fadeIn ? [{ opacity: 1, offset: 0.35 }] : []),
    ...(fadeOut ? [{ opacity: 1, offset: 0.55 }] : []),
    { transform: transformFor(to, base), opacity: fadeOut ? 0 : 1, offset: 1 },
  ];
  const animation = ghost.animate(frames, { duration, delay, easing: EASE, fill: "both" });
  const finish = () => {
    ghost.remove();
    onDone?.();
  };
  animation.finished.then(finish, finish);
  return animation;
}
