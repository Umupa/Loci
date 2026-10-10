import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  Check,
  ChevronRight,
  CircleDashed,
  Minus,
  Pause,
  X,
} from "../../../shared/ui/icons";

export type WorkFoldState =
  | "thinking"
  | "working"
  | "responding"
  | "waiting"
  | "done"
  | "error"
  | "interrupted";

type Props = {
  title: ReactNode;
  state: WorkFoldState;
  visible: boolean;
  expandable: boolean;
  open: boolean;
  onToggle: () => void;
};

const STATE_LABELS: Record<WorkFoldState, string> = {
  thinking: "Thinking",
  working: "Working",
  responding: "Responding",
  waiting: "Waiting",
  done: "Work complete",
  error: "Turn failed",
  interrupted: "Turn interrupted",
};

/** A fixed turn receipt whose motion follows only the work being watched. */
export function WorkFoldLine({
  title,
  state,
  visible,
  expandable,
  open,
  onToggle,
}: Props) {
  const active =
    state === "thinking" || state === "working" || state === "responding";
  const live = active || state === "waiting";
  const previous = useRef({ live, visible });
  const [completing, setCompleting] = useState(false);

  useEffect(() => {
    const was = previous.current;
    previous.current = { live, visible };
    // History and a turn that finished in a hidden pane stay still on return.
    const completedInView = was.live && was.visible && visible && state === "done";
    setCompleting(completedInView);
    if (!completedInView) return;
    const timer = window.setTimeout(() => setCompleting(false), 700);
    return () => window.clearTimeout(timer);
  }, [live, state, visible]);

  const row = `group flex w-full min-w-0 items-center gap-1.5 px-4 py-1 text-left${
    open ? " zen-fold-drop" : ""
  }`;
  const attributes = {
    "data-work-fold": live ? "live" : "done",
    "data-work-state": state,
    "data-work-animated": (visible && active) || undefined,
    "data-work-completing": completing || undefined,
    className: row,
  };
  const content = (
    <>
      <span
        data-work-mark
        aria-hidden
        className="relative flex size-3.5 shrink-0 items-center justify-center"
      >
        <span data-work-symbol className="flex size-3.5 items-center justify-center">
          {state === "waiting" ? (
            <Pause className="size-3.5" strokeWidth={1.75} />
          ) : state === "working" ? (
            <CircleDashed className="size-3.5" strokeWidth={1.75} />
          ) : (
            <span className="size-1.5 rounded-full bg-current" />
          )}
        </span>
        <span data-work-check className="absolute inset-0 flex items-center justify-center">
          <Check className="size-3.5" strokeWidth={2} />
        </span>
        {state === "error" ? (
          <span data-work-error className="absolute inset-0 flex items-center justify-center">
            <X className="size-3.5" strokeWidth={2} />
          </span>
        ) : state === "interrupted" ? (
          <span data-work-interrupted className="absolute inset-0 flex items-center justify-center">
            <Minus className="size-3.5" strokeWidth={2} />
          </span>
        ) : null}
      </span>
      <span data-work-title className="flex min-w-0 flex-1 items-center font-sans text-sm">
        {title}
      </span>
      {active ? (
        <span data-work-dots aria-hidden className="flex shrink-0 items-center gap-[3px]">
          <span />
          <span />
          <span />
        </span>
      ) : null}
      {expandable ? (
        <ChevronRight
          data-work-chevron
          aria-hidden
          className={`size-3.5 shrink-0 text-content/45${open ? " rotate-90" : ""}`}
          strokeWidth={1.75}
        />
      ) : null}
      <span data-work-announcement className="sr-only" role="status" aria-live="polite" aria-atomic="true">
        {STATE_LABELS[state]}
      </span>
    </>
  );

  return expandable ? (
    <button
      {...attributes}
      type="button"
      aria-expanded={open}
      aria-label={open ? "Hide the work" : "Show the work"}
      onClick={onToggle}
    >
      {content}
    </button>
  ) : (
    <div {...attributes}>{content}</div>
  );
}
