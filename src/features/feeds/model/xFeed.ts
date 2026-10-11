import { invoke } from "@tauri-apps/api/core";
import type { XCapture } from "./feedContext";

/** Overlay rectangle in logical window px, relative to the content area. */
export type XFeedBounds = { x: number; y: number; width: number; height: number };

export type XShortcut = { id: string; label: string; description: string; path: string };

export const X_SHORTCUTS: readonly XShortcut[] = [
  { id: "home", label: "Home", description: "Your timeline", path: "/home" },
  { id: "explore", label: "Explore", description: "Trends and search", path: "/explore" },
  { id: "notifications", label: "Notifications", description: "Mentions, replies and likes", path: "/notifications" },
  { id: "bookmarks", label: "Bookmarks", description: "Posts you saved", path: "/i/bookmarks" },
  { id: "lists", label: "Lists", description: "Curated timelines", path: "/i/lists" },
];

/**
 * The page is natively zoomed by the UI scale, so CSS px are smaller than
 * the window's logical px by that factor.
 */
export function boundsFromRect(rect: Pick<DOMRect, "left" | "top" | "width" | "height">, zoom: number): XFeedBounds {
  const scale = Number.isFinite(zoom) && zoom > 0 ? zoom : 1;
  return {
    x: Math.round(rect.left * scale),
    y: Math.round(rect.top * scale),
    width: Math.max(1, Math.round(rect.width * scale)),
    height: Math.max(1, Math.round(rect.height * scale)),
  };
}

/** `/search?q=…` for free text, or a profile path for `@handle`. */
export function xPathForQuery(input: string): string | null {
  const query = input.trim();
  if (!query) return null;
  const handle = query.match(/^@([A-Za-z0-9_]{1,15})$/);
  if (handle) return `/${handle[1]}`;
  try {
    const url = new URL(query);
    if (/(^|\.)(x|twitter)\.com$/.test(url.hostname)) return `${url.pathname}${url.search}` || "/home";
  } catch {
    // Not a URL; search for it.
  }
  return `/search?q=${encodeURIComponent(query)}&src=typed_query`;
}

// Commands run concurrently on the native side; a hide sent after a show
// must not land before it, so visibility changes go through one queue.
let visibility: Promise<unknown> = Promise.resolve();

function queued(command: string, args?: Record<string, unknown>): Promise<void> {
  const next = visibility.catch(() => undefined).then(() => invoke<void>(command, args));
  visibility = next;
  return next;
}

export function showXFeed(bounds: XFeedBounds, path?: string): Promise<void> {
  return queued("x_feed_show", { bounds, path });
}

export function setXFeedBounds(bounds: XFeedBounds): Promise<void> {
  return queued("x_feed_set_bounds", { bounds });
}

export function hideXFeed(): Promise<void> {
  return queued("x_feed_hide");
}

export function navigateXFeed(path: string): Promise<void> {
  return invoke("x_feed_navigate", { path });
}

export function xFeedAction(action: "back" | "forward" | "reload"): Promise<void> {
  return invoke("x_feed_action", { action });
}

export function captureXFeed(): Promise<XCapture> {
  return invoke<XCapture>("x_feed_capture");
}
