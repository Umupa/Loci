import { useMemo, useState } from "react";
import { ChevronRight } from "../../../shared/ui/icons";
import type { Block } from "../model/session";
import { turnActivity, VISIBLE_ACTIVITY } from "../model/turnProgress";
import { ActivitySpinner } from "./ActivitySpinner";

/**
 * The running turn in a few lines, newest first, under the work it is doing.
 * It is the only thing on screen while a mentor fetches sources or writes a
 * course and has not streamed any prose yet; once the turn ends its record is
 * the work trail above.
 */
export function TurnProgress({
  blocks,
  visible = true,
}: {
  blocks: readonly Block[];
  visible?: boolean;
}) {
  const entries = useMemo(() => turnActivity(blocks), [blocks]);
  const [expanded, setExpanded] = useState(false);
  const newest = entries[0];
  const shown = expanded ? entries : entries.slice(0, VISIBLE_ACTIVITY);

  return (
    <section
      data-turn-progress
      data-activity-status={newest?.status ?? "thinking"}
      aria-label="What the mentor is doing"
      className="mx-4 mb-1 mt-1 rounded-lg border border-stroke/70 bg-content/[0.025] px-2.5 py-1.5 font-sans"
    >
      <div className="flex min-w-0 items-center gap-1.5 text-[12px] leading-5 text-content/60">
        {visible ? (
          <ActivitySpinner className="inline-block w-3.5 shrink-0 select-none text-center text-[11px] leading-none text-content/45" />
        ) : (
          <span aria-hidden className="size-1.5 shrink-0 rounded-full bg-content/35" />
        )}
        <span data-activity-newest className="min-w-0 flex-1 truncate">
          {newest?.text ?? "Working…"}
        </span>
        {entries.length > VISIBLE_ACTIVITY ? (
          <button
            type="button"
            aria-expanded={expanded}
            aria-label={expanded ? "Show fewer steps" : `Show all ${entries.length} steps`}
            title={expanded ? "Show fewer steps" : `Show all ${entries.length} steps`}
            className="flex shrink-0 items-center gap-0.5 rounded px-1 text-[11px] text-content/40 hover:bg-content/8 hover:text-content/70"
            onClick={() => setExpanded((open) => !open)}
          >
            {expanded ? "Less" : `${entries.length}`}
            <ChevronRight
              aria-hidden
              className={`size-3 transition-transform ${expanded ? "rotate-90" : ""}`}
            />
          </button>
        ) : null}
      </div>
      {shown.slice(1).map((entry) => (
        <p
          key={entry.id}
          data-activity-entry
          data-activity-kind={entry.kind}
          data-activity-status={entry.status}
          className={`mt-0.5 min-w-0 truncate pl-5 text-[12px] leading-5 ${
            entry.status === "failed" ? "text-content/35" : "text-content/40"
          }`}
        >
          {entry.text}
        </p>
      ))}
    </section>
  );
}
