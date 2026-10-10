import { AiIdea, ChevronRight, LoaderCircle } from "../../../shared/ui/icons";
import { useSavedWidgets } from "../hooks/useSavedWidgets";
import { openWidget, widgetRef } from "../model/widgets";
import type { WidgetOwner } from "../model/types";
import "./WidgetLibrary.css";

const updatedDate = new Intl.DateTimeFormat(undefined, { year: "numeric", month: "short", day: "numeric" });

export function WidgetLibrary({ owner }: { owner: WidgetOwner }) {
  const { widgets, error, reload } = useSavedWidgets(owner);
  return (
    <section aria-label="Saved explanations" className="learning-widget-library">
      {error ? (
        <div className="flex items-center gap-2 px-2 py-2 text-xs">
          <p role="alert" className="min-w-0 flex-1 text-red-400">Could not load saved explanations.</p>
          <button type="button" onClick={reload} className="shrink-0 rounded px-1.5 py-1 text-content/60 hover:bg-content/6 hover:text-content">
            Retry
          </button>
        </div>
      ) : null}
      {widgets === undefined ? (
        error ? null : <p role="status" className="learning-widget-library__loading"><LoaderCircle aria-hidden className="size-3.5" strokeWidth={1.75} />Loading…</p>
      ) : widgets.length ? (
        widgets.map((widget) => (
          <button
            key={widget.id}
            data-widget-library-item
            type="button"
            title={[widget.title, "Interactive explanation", widget.subject, updatedDate.format(widget.updatedAt)].filter(Boolean).join("\n")}
            onClick={() => openWidget(widgetRef(widget), widget.sourceSessionId, widget.title)}
            className="learning-widget-library__item"
          >
            <span className="learning-widget-library__icon"><AiIdea aria-hidden className="size-3.5" strokeWidth={1.75} /></span>
            <span className="learning-widget-library__title">{widget.title}</span>
            <ChevronRight aria-hidden className="learning-widget-library__arrow size-3.5" strokeWidth={1.75} />
          </button>
        ))
      ) : error ? null : (
        <div className="learning-widget-library__empty">
          <span className="learning-widget-library__empty-icon"><AiIdea aria-hidden className="size-5" strokeWidth={1.5} /></span>
          <p>No saved explanations yet.</p>
          <span>Keep an explanation from the chat to find it here.</span>
        </div>
      )}
    </section>
  );
}
