import { t, useLocale } from "../../shared/i18n/locale";
import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { LAYER } from "../../shared/lib/layers";

export type SavedToastData =
  | { type: "canvas"; id: string; title: string }
  | { type: "note"; id: string };

type Props = {
  toast: SavedToastData;
  onOpen: (toast: SavedToastData) => void;
  onDismiss: () => void;
};

const VISIBLE_MS = 4000;

export function SavedToast({ toast, onOpen, onDismiss }: Props) {
  useLocale();
  const hovering = useRef(false);
  const onDismissRef = useRef(onDismiss);
  onDismissRef.current = onDismiss;

  useEffect(() => {
    let timer = window.setTimeout(expire, VISIBLE_MS);
    function expire() {
      if (hovering.current) timer = window.setTimeout(expire, 1000);
      else onDismissRef.current();
    }
    return () => window.clearTimeout(timer);
  }, [toast]);

  const label =
    toast.type === "canvas"
      ? t("Saved to \"{0}\"", truncate(toast.title || "Untitled drawing"))
      : t("Saved to Notes");

  return createPortal(
    <div
      className="pointer-events-none fixed inset-x-0 bottom-[52px] flex justify-center"
      style={{ zIndex: LAYER.toast }}
    >
      <div
        key={`${toast.type}-${toast.id}`}
        role="status"
        aria-live="polite"
        onPointerEnter={() => { hovering.current = true; }}
        onPointerLeave={() => { hovering.current = false; }}
        className="approval-toast pointer-events-auto flex items-center gap-3 rounded-xl border border-content/10 bg-background-base/90 py-2 pl-4 pr-2 text-[13px] text-content shadow-xl backdrop-blur-xl"
      >
        <span className="min-w-0 truncate text-content/80">{label}</span>
        <button
          type="button"
          onClick={() => { onOpen(toast); onDismiss(); }}
          className="flex shrink-0 items-center gap-1.5 rounded-lg bg-content/10 px-3 py-1 font-medium hover:bg-content/15"
        >
          {t("Open")}</button>
      </div>
    </div>,
    document.body,
  );
}

function truncate(title: string): string {
  return title.length > 32 ? `${title.slice(0, 31)}…` : title;
}
