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

function AvatarGraphic({ name, color, className, ref }: Props & { ref?: Ref<SVGSVGElement> }) {
  const avatar = agentAvatar(name);
  const instanceId = `loci-avatar-${useId().replace(/:/g, "")}`;
  // Masks and clip paths cannot share IDs, even for the same face in two colors.
  const markup = useMemo(
    () => avatar.markup.replace(/__LOCI_AVATAR_ID__/g, instanceId),
    [avatar.markup, instanceId],
  );
  return (
    <svg ref={ref} aria-hidden data-agent-avatar={avatar.name} viewBox={avatar.viewBox} className={className}
      style={{ color }} dangerouslySetInnerHTML={{ __html: markup }} />
  );
}

/** Small avatars are local SVGs with no timers or visibility observers. */
export function AgentAvatar({ name, color, className = "size-5 shrink-0" }: Props) {
  return <AvatarGraphic name={name} color={color} className={className} />;
}

/** Only the visible Details preview animates the eyes; fixed expressions stay still. */
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
    const schedule = (delay: number) => {
      timer = window.setTimeout(blink, delay);
    };
    const idleDelay = () => 6000 + Math.random() * 3000;
    function blink() {
      timer = undefined;
      if (!allowed()) return;
      root.setAttribute("data-blinking", "true");
      // One timer at a time, and no React updates between CSS animation frames.
      timer = window.setTimeout(() => {
        root.removeAttribute("data-blinking");
        timer = undefined;
        if (allowed()) schedule(idleDelay());
      }, 160);
    }
    const sync = () => {
      stop();
      if (allowed()) schedule(idleDelay());
    };
    selectionBlinkRef.current = (canBlink) => {
      blinkable = canBlink;
      stop();
      if (allowed()) schedule(180);
    };
    const observer = new IntersectionObserver(([entry]) => {
      if (disposed) return;
      if (entry.isIntersecting === visible) return;
      visible = entry.isIntersecting;
      sync();
    });
    observer.observe(root);
    document.addEventListener("visibilitychange", sync);
    reducedMotion.addEventListener("change", sync);
    return () => {
      disposed = true;
      selectionBlinkRef.current = null;
      stop();
      observer.disconnect();
      document.removeEventListener("visibilitychange", sync);
      reducedMotion.removeEventListener("change", sync);
    };
  }, []);

  useLayoutEffect(() => {
    if (shownNameRef.current === name) return;
    shownNameRef.current = name;
    selectionBlinkRef.current?.(avatar.canBlink);
  }, [name, avatar.canBlink]);

  return (
    <AvatarGraphic ref={rootRef} name={name} color={color} className={`agent-avatar-preview ${className}`} />
  );
}
