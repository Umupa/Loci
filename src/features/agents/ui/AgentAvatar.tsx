import { useId, useLayoutEffect, useMemo, useRef, type Ref } from "react";
import { agentAvatar } from "../model/agentAvatars";
import "./AgentAvatar.css";

type Props = {
  /** Avatar name; see `agentAvatars`. */
  name: string;
  /** The agent's color, which paints its head. */
  color: string;
  className?: string;
};

function AvatarGraphic({ name, color, className, bust, ref }: Props & { bust?: boolean; ref?: Ref<SVGSVGElement> }) {
  const avatar = agentAvatar(name);
  const instanceId = `loci-avatar-${useId().replace(/:/g, "")}`;
  // Masks and clip paths cannot share IDs, even for the same face in two colors.
  const markup = useMemo(
    () => avatar.markup.replace(/__LOCI_AVATAR_ID__/g, instanceId),
    [avatar.markup, instanceId],
  );
  return (
    <svg ref={ref} aria-hidden data-agent-avatar={avatar.name} viewBox={bust ? avatar.viewBox : avatar.faceViewBox} className={`agent-avatar ${className ?? ""}`}
      style={{ color }} dangerouslySetInnerHTML={{ __html: markup }} />
  );
}

/** Small avatars show the face alone: local SVGs with no timers or visibility observers. */
export function AgentAvatar({ name, color, className = "size-5 shrink-0" }: Props) {
  return <AvatarGraphic name={name} color={color} className={className} />;
}

/**
 * The Details preview animates the eyes when it first appears and when the
 * pointer is over it; fixed expressions stay still. It never runs a timer for
 * an idle blink.
 */
export function AgentAvatarPreview({ name, color, className = "size-16" }: Props) {
  const avatar = agentAvatar(name);
  const rootRef = useRef<SVGSVGElement>(null);
  const shownNameRef = useRef(name);
  const selectionBlinkRef = useRef<((canBlink: boolean) => void) | null>(null);

  useLayoutEffect(() => {
    const root = rootRef.current!;
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let blinkable = avatar.canBlink;
    let visible = false;
    let disposed = false;
    let timer: number | undefined;

    const allowed = () => !disposed && blinkable && visible && !document.hidden && !reducedMotion.matches;
    const stop = () => {
      window.clearTimeout(timer);
      timer = undefined;
      root.removeAttribute("data-blinking");
    };
    function blink() {
      window.clearTimeout(timer);
      timer = undefined;
      if (!allowed()) return;
      root.setAttribute("data-blinking", "true");
      // One timer at a time, and no React updates between CSS animation frames.
      timer = window.setTimeout(() => {
        root.removeAttribute("data-blinking");
        timer = undefined;
      }, 160);
    }
    // Losing the viewport, the window or the motion preference cuts a blink short.
    const settle = () => {
      if (!allowed()) stop();
    };
    selectionBlinkRef.current = (canBlink) => {
      blinkable = canBlink;
      stop();
      blink();
    };
    const observer = new IntersectionObserver(([entry]) => {
      if (disposed) return;
      if (entry.isIntersecting === visible) return;
      visible = entry.isIntersecting;
      if (visible) blink();
      else stop();
    });
    observer.observe(root);
    const onPointerEnter = () => blink();
    root.addEventListener("pointerenter", onPointerEnter);
    document.addEventListener("visibilitychange", settle);
    reducedMotion.addEventListener("change", settle);
    return () => {
      disposed = true;
      selectionBlinkRef.current = null;
      stop();
      observer.disconnect();
      root.removeEventListener("pointerenter", onPointerEnter);
      document.removeEventListener("visibilitychange", settle);
      reducedMotion.removeEventListener("change", settle);
    };
  }, []);

  useLayoutEffect(() => {
    if (shownNameRef.current === name) return;
    shownNameRef.current = name;
    selectionBlinkRef.current?.(avatar.canBlink);
  }, [name, avatar.canBlink]);

  return (
    <AvatarGraphic ref={rootRef} name={name} color={color} bust className={`agent-avatar-preview ${className}`} />
  );
}
