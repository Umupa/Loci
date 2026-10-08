import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { SidebarLeft } from "../../shared/ui/icons";
import { MOD, SHIFT } from "../../platform/tauri/platform";
import {
  loadSecondarySidebarOpen,
  saveSecondarySidebarOpen,
  type SecondarySidebarId,
} from "../../features/settings/model/appearance";
import { IconButton } from "./TitleBar";

/** The toggle shortcut reaches whichever list page is showing through this event. */
export const TOGGLE_SECONDARY_SIDEBAR_EVENT = "loci:toggle-secondary-sidebar";

const SLIDE_MS = 150;

/** The one control that opens and closes a page's second column, wherever it is. */
export function SecondarySidebarToggle({ open, onToggle, name }: {
  open: boolean;
  onToggle: () => void;
  /** What the column holds, for the tooltip: "workspace sidebar", "notes list". */
  name: string;
}) {
  return (
    <IconButton label={`${open ? "Hide" : "Show"} ${name} (${MOD}${SHIFT}B)`} active={open} onClick={onToggle}>
      <SidebarLeft className="size-3.5" strokeWidth={1.75} />
    </IconButton>
  );
}

/** Open state of a list page's column: remembered, and flipped by the shortcut. */
export function useSecondarySidebar(id: SecondarySidebarId): [boolean, () => void] {
  const [open, setOpen] = useState(() => loadSecondarySidebarOpen(id));
  const toggle = useCallback(() => {
    setOpen((current) => {
      saveSecondarySidebarOpen(id, !current);
      return !current;
    });
  }, [id]);
  useEffect(() => {
    window.addEventListener(TOGGLE_SECONDARY_SIDEBAR_EVENT, toggle);
    return () => window.removeEventListener(TOGGLE_SECONDARY_SIDEBAR_EVENT, toggle);
  }, [toggle]);
  return [open, toggle];
}

function prefersReducedMotion(): boolean {
  return typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * A column that slides shut to nothing: no border, no handle, no strip left
 * behind. Its content stays mounted while it closes and is inert once it has.
 * The column keeps its own width, so a width the user dragged survives.
 */
export function CollapsiblePane({ open, children }: { open: boolean; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [mounted, setMounted] = useState(open);
  const shown = useRef(open);
  const animation = useRef<Animation | null>(null);

  if (open && !mounted) setMounted(true);

  useLayoutEffect(() => {
    if (open === shown.current) return;
    shown.current = open;
    const el = ref.current;
    animation.current?.cancel();
    animation.current = null;
    const instant = prefersReducedMotion() || typeof el?.animate !== "function";
    if (!el || instant) {
      if (!open) setMounted(false);
      return;
    }
    // Clipping only lasts while moving: the resize handle hangs over the edge.
    el.style.overflow = "hidden";
    const target = el.scrollWidth;
    const frames = open
      ? [{ width: "0px" }, { width: `${target}px` }]
      : [{ width: `${el.getBoundingClientRect().width}px` }, { width: "0px" }];
    const run = el.animate(frames, { duration: SLIDE_MS, easing: "ease-out", fill: open ? "none" : "forwards" });
    animation.current = run;
    const done = () => {
      if (animation.current !== run) return;
      animation.current = null;
      window.clearTimeout(fallback);
      el.style.overflow = "";
      if (!open) setMounted(false);
    };
    run.onfinish = done;
    // A stalled animation must never leave a closed column standing.
    const fallback = window.setTimeout(done, SLIDE_MS + 100);
  }, [open]);

  if (!mounted) return null;
  return (
    <div ref={ref} inert={!open || undefined} aria-hidden={!open || undefined} className="flex h-full min-h-0 shrink-0">
      {children}
    </div>
  );
}
