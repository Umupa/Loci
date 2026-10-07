import { useEffect, useRef, useSyncExternalStore } from "react";
import { createPortal } from "react-dom";
import { X } from "../../shared/ui/icons";
import { LAYER } from "../../shared/lib/layers";
import { IS_MAC, MOD, SHIFT } from "../../platform/tauri/platform";
import { closedTabs } from "../../features/workspace/model/closedTabs";

const VISIBLE_MS = 8000;

/**
 * Closing a tab is never final: this says so, and offers the way back for a
 * few seconds. The same history stays reachable from ⌘⇧T and the switcher.
 */
export function ClosedTabToast({ onUndo }: { onUndo: (batch: number) => void }) {
  const notice = useSyncExternalStore(closedTabs.subscribe, closedTabs.notice);
  const hovering = useRef(false);

  useEffect(() => {
    if (!notice) return;
    let timer = window.setTimeout(expire, VISIBLE_MS);
    function expire() {
      // A pointer resting on the toast is reading it: wait until it leaves.
      if (hovering.current) timer = window.setTimeout(expire, 1500);
      else closedTabs.dismissNotice();
    }
    return () => window.clearTimeout(timer);
  }, [notice]);

  if (!notice) return null;
  const what = notice.count > 1 ? `${notice.count} tabs` : notice.title ? `“${truncate(notice.title)}”` : "tab";
  return createPortal(
    <div className="pointer-events-none fixed inset-x-0 top-[52px] flex justify-center" style={{ zIndex: LAYER.toast }}>
      <div
        key={notice.batch}
        role="status"
        aria-live="polite"
        data-closed-tab-toast
        onPointerEnter={() => { hovering.current = true; }}
        onPointerLeave={() => { hovering.current = false; }}
        className="approval-toast pointer-events-auto flex max-w-[min(520px,calc(100vw-32px))] items-center gap-3 rounded-xl border border-content/10 bg-background-base/90 py-2 pl-4 pr-2 text-[13px] text-content shadow-xl backdrop-blur-xl"
      >
        <span className="min-w-0 truncate">Closed {what}</span>
        <button type="button" onClick={() => onUndo(notice.batch)}
          className="flex shrink-0 items-center gap-2 rounded-lg bg-content/10 py-1 pl-3 pr-2 font-medium hover:bg-content/15">
          Undo
          <kbd className="rounded border border-content/12 bg-content/6 px-1 font-sans text-[10px] font-normal leading-4 text-content/55">
            {IS_MAC ? `${MOD}${SHIFT}T` : `Ctrl+Shift+T`}
          </kbd>
        </button>
        <button type="button" aria-label="Dismiss" title="Dismiss" onClick={() => closedTabs.dismissNotice()}
          className="grid size-6 shrink-0 place-items-center rounded-md text-content/45 hover:bg-content/10 hover:text-content">
          <X className="size-3" strokeWidth={1.75} />
        </button>
      </div>
    </div>,
    document.body,
  );
}

function truncate(title: string): string {
  return title.length > 36 ? `${title.slice(0, 35)}…` : title;
}
