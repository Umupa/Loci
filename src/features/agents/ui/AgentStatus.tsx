import { CircleDashed } from "../../../shared/ui/icons";
import {
  AGENT_STATUS_LABEL,
  type AgentState,
  type AgentStatus as Status,
} from "../model/agent";

/** The status circle: accent when it needs you, its color pulsing while it works, grey at rest. */
export function AgentStatusDot({
  status,
  color,
  className,
}: {
  status: Status;
  color: string;
  className: string;
}) {
  return (
    <span
      aria-hidden
      className={`absolute rounded-full ring-1 ring-background-base ${className} ${
        status === "working"
          ? "motion-safe:animate-pulse"
          : status === "needs-you"
            ? "bg-accent"
            : "bg-content/30"
      }`}
      style={status === "working" ? { backgroundColor: color } : undefined}
    />
  );
}

/**
 * The header's one-line status. While the agent works it names the step in the
 * same words as the transcript's progress line; the full label stays on hover,
 * and a narrow header keeps only the name and its controls.
 */
export function AgentStatus({
  state,
  className = "",
}: {
  state: AgentState;
  className?: string;
}) {
  const title = [AGENT_STATUS_LABEL[state.status], state.activity]
    .filter(Boolean)
    .join(" · ");
  if (state.status === "working" && state.activity) {
    return (
      <span
        data-agent-activity
        title={title}
        className={`inline-flex min-w-0 max-w-[11rem] shrink items-center gap-1.5 text-xs text-content/50 ${className}`}
      >
        <CircleDashed
          aria-hidden
          className="size-3 shrink-0 motion-safe:animate-spin [animation-duration:2.4s]"
          strokeWidth={1.5}
        />
        <span className="min-w-0 truncate">{state.activity}</span>
      </span>
    );
  }
  return (
    <span
      title={title}
      className={`shrink-0 text-xs text-content/50 ${className}`}
    >
      {AGENT_STATUS_LABEL[state.status]}
    </span>
  );
}
