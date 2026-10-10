import { useEffect, useState, type PointerEvent as ReactPointerEvent } from "react";
import { AiIdea, GripVertical, X } from "../../../shared/ui/icons";
import { getLearningWidget, subscribeLearningChanges } from "../model/learningStore";
import { openLearningSource } from "../model/navigation";
import { askAboutWidget } from "../model/widgetContext";
import { adoptStoredWidget, useWidget } from "../model/widgetRuntime";
import { widgetKey, widgetRef } from "../model/widgets";
import type { StoredWidget, WidgetRef } from "../model/types";
import { WidgetFrame } from "./WidgetFrame";
import { WidgetToolbar } from "./WidgetCard";

type Props = { widget: WidgetRef; title?: string; sourceSessionId?: string; focused: boolean; onFocus: () => void; onClose: () => void; onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void };

export function WidgetPane({ widget: ref, title, focused, onFocus, onClose, onPaneDragStart }: Props) {
  const [stored, setStored] = useState<StoredWidget | null>(null);
  const [error, setError] = useState<string | null>(null);
  const key = widgetKey(ref);
  useEffect(() => {
    let current = true;
    setStored(null);
    const load = () => void getLearningWidget(ref).then((found) => {
      if (!current) return;
      if (found) { adoptStoredWidget(found); setStored(found); setError(null); }
      else setError("This explanation is no longer available.");
    }).catch((cause: unknown) => { if (current) setError(String(cause)); });
    load();
    const stop = subscribeLearningChanges(load);
    return () => { current = false; stop(); };
  }, [key]);
  return <aside aria-label={stored?.title ?? title ?? "Interactive explanation"} className="flex h-full min-h-0 min-w-0 flex-col bg-background-base/40 font-sans text-content" onPointerDown={() => { if (!focused) onFocus(); }}>
    <header className={`flex h-9 shrink-0 select-none items-center gap-1.5 border-b border-stroke px-2 ${onPaneDragStart ? "cursor-grab active:cursor-grabbing touch-none" : ""}`} onPointerDown={(event) => { if (!(event.target as HTMLElement).closest("[data-no-drag]")) onPaneDragStart?.(event); }}>
      {onPaneDragStart ? <GripVertical className="size-3.5 shrink-0 text-content/35" /> : null}<AiIdea className={`size-3.5 shrink-0 ${focused ? "text-content/70" : "text-content/40"}`} strokeWidth={1.75} /><span className="min-w-0 flex-1 truncate text-xs">{stored?.title ?? title ?? "Interactive explanation"}</span><button type="button" data-no-drag aria-label="Close explanation" onClick={onClose} className="grid size-6 place-items-center rounded-md text-content/50 hover:bg-content/8 focus-visible:outline-2 focus-visible:outline-content/60"><X className="size-3.5" /></button>
    </header>
    {stored ? <PaneContent stored={stored} /> : <div className="grid flex-1 place-items-center px-4 text-xs text-content/50" role={error ? "alert" : undefined}>{error ?? "Opening explanation…"}</div>}
  </aside>;
}

function PaneContent({ stored }: { stored: StoredWidget }) {
  const widget = useWidget(widgetRef(stored), stored, stored.sourceSessionId);
  return <><WidgetToolbar widget={widget} expanded /><div className="min-h-0 flex-1"><WidgetFrame widget={widget} expanded onAsk={(text, selection) => askAboutWidget(widget, text, selection)} onOpenSource={openLearningSource} /></div></>;
}
