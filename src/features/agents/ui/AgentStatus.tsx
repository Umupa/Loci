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

/** The agent's status line: the state, and what it is on. */
export function AgentStatus({
  state,
  className = "",
}: {
  state: AgentState;
  className?: string;
}) {
  return (
    <span className={`min-w-0 truncate text-xs text-content/50 ${className}`}>
      {AGENT_STATUS_LABEL[state.status]}
      {state.activity ? ` · ${state.activity}` : ""}
    </span>
  );
}
