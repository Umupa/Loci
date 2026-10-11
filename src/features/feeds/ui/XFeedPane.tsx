import { openUrl } from "@tauri-apps/plugin-opener";
import { useLayoutEffect, useRef, useState } from "react";
import { ChevronLeft, ChevronRight, ExternalLink, LoaderCircle, RefreshCw, StickyNote, XLogo } from "../../../shared/ui/icons";
import { loadUiScale, UI_SCALE_CHANGE_EVENT } from "../../settings/model/uiScale";
import { hasXContent, xCaptureMarkdown, type XCapture } from "../model/feedContext";
import { boundsFromRect, captureXFeed, hideXFeed, setXFeedBounds, showXFeed, xFeedAction } from "../model/xFeed";
import { ACTION_FILLED, ACTION_GHOST, ACTION_OUTLINE, FeedProviderMark, IconButton } from "./feedUi";

type Props = {
  onSendToAgent: (capture: XCapture) => void;
  onSaveNote: (title: string, body: string) => Promise<void>;
};

const pageTitle = (capture: XCapture) => capture.title.replace(/\s*\/\s*X\s*$/, "").trim() || "X";

/**
 * Action header plus an empty slot. x.com renders in a native window that
 * Loci keeps glued over the slot, so nothing from this page may paint there.
 */
export function XFeedPane({ onSendToAgent, onSaveNote }: Props) {
  const slot = useRef<HTMLDivElement>(null);
  const live = useRef(false);
  const [busy, setBusy] = useState<"agent" | "note" | "open" | null>(null);
  const [error, setError] = useState<string | null>(null);

  useLayoutEffect(() => {
    const element = slot.current;
    if (!element) return;
    live.current = true;
    const bounds = () => boundsFromRect(element.getBoundingClientRect(), loadUiScale());
    void showXFeed(bounds()).catch((cause) => { if (live.current) setError(String(cause)); });
    let frame = 0;
    const sync = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => void setXFeedBounds(bounds()).catch(() => undefined));
    };
    const observer = new ResizeObserver(sync);
    observer.observe(element);
    window.addEventListener("resize", sync);
    window.addEventListener(UI_SCALE_CHANGE_EVENT, sync);
    return () => {
      live.current = false;
      cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("resize", sync);
      window.removeEventListener(UI_SCALE_CHANGE_EVENT, sync);
      void hideXFeed().catch(() => undefined);
    };
  }, []);

  const capture = async (kind: "agent" | "note" | "open") => {
    setBusy(kind);
    setError(null);
    try {
      const page = await captureXFeed();
      if (!live.current) return;
      if (kind === "open") {
        await openUrl(page.url);
        return;
      }
      if (!hasXContent(page)) {
        setError("Nothing to capture yet. Open a post or select some text.");
        return;
      }
      if (kind === "agent") onSendToAgent(page);
      else await onSaveNote(pageTitle(page), xCaptureMarkdown(page));
    } catch (cause) {
      if (live.current) setError(String(cause));
    } finally {
      if (live.current) setBusy(null);
    }
  };

  const spinner = <LoaderCircle className="size-3.5 animate-spin" />;
  return (
    <section aria-label="X" className="flex h-full min-h-0 min-w-0 flex-1 flex-col">
      <div className="shrink-0 border-b border-stroke">
        <div className="flex w-full flex-col gap-2.5 px-6 py-3">
          <div className="flex min-w-0 items-center gap-2 text-[12px] text-content/50">
            <FeedProviderMark provider="x" />
            <span className="shrink-0">x.com</span>
            <span className="min-w-0 truncate">Signed in with your own account</span>
            <span className="ml-auto flex shrink-0 items-center gap-0.5">
              <IconButton label="Back" onClick={() => void xFeedAction("back")}><ChevronLeft className="size-3.5" /></IconButton>
              <IconButton label="Forward" onClick={() => void xFeedAction("forward")}><ChevronRight className="size-3.5" /></IconButton>
              <IconButton label="Reload" onClick={() => void xFeedAction("reload")}><RefreshCw className="size-3.5" /></IconButton>
            </span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" disabled={!!busy} onClick={() => void capture("agent")} className={ACTION_FILLED}>
              {busy === "agent" ? spinner : null} Send to agent
            </button>
            <button type="button" disabled={!!busy} onClick={() => void capture("note")} className={ACTION_OUTLINE}>
              {busy === "note" ? spinner : <StickyNote className="size-3.5" />} Save as note
            </button>
            <button type="button" disabled={!!busy} onClick={() => void capture("open")} className={ACTION_GHOST}>
              <ExternalLink className="size-3.5" /> Open in browser
            </button>
            {error ? <span role="alert" className="min-w-0 truncate text-[12px] text-red-400/90">{error}</span> : null}
          </div>
        </div>
      </div>
      <div ref={slot} data-x-feed-slot className="relative min-h-0 flex-1">
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 text-content/30">
          <XLogo className="size-6" />
          <span className="text-[12px]">Loading X…</span>
        </div>
      </div>
    </section>
  );
}
