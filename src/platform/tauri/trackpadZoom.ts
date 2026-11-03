import { transport, type Unlisten } from "../transport";
import { isTauri } from "../native";

type MagnifyHandler = (delta: number) => void;

// The native side forwards pinches per window, so surfaces share one claim:
// the most recent claimer receives them, and the hook stays on while any
// surface holds a claim.
const claims: MagnifyHandler[] = [];
let unlisten: Promise<Unlisten | void> | null = null;

/**
 * Routes trackpad pinches in this window to `onMagnify` with AppKit's
 * incremental magnification (`scale *= 1 + delta`), until the returned
 * release runs. WKWebView turns no pinch into DOM events, so this is the
 * only way a surface sees one on macOS.
 */
export function claimTrackpadMagnify(onMagnify: MagnifyHandler): () => void {
  if (!isTauri()) return () => {};

  claims.push(onMagnify);
  if (claims.length === 1) {
    const subscription: Promise<Unlisten | void> = transport.listen<number>(
      "trackpad_magnify",
      (event) => {
        // A released subscription can still deliver events until async cleanup
        // finishes. It must not forward those events to a newer set of claims.
        if (unlisten !== subscription) return;
        claims[claims.length - 1]?.(event.payload);
      },
    ).catch(console.error);
    unlisten = subscription;
    void transport.call("set_trackpad_zoom_enabled", { enabled: true }).catch(
      console.error,
    );
  }
  let released = false;
  return () => {
    if (released) return;
    released = true;
    claims.splice(claims.lastIndexOf(onMagnify), 1);
    if (claims.length) return;
    void unlisten?.then((stop) => stop?.()).catch(console.error);
    unlisten = null;
    void transport.call("set_trackpad_zoom_enabled", { enabled: false }).catch(
      console.error,
    );
  };
}
