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

/** Keep the title short; the activity is available on hover. */
export function AgentStatus({
  state,
  className = "",
}: {
  state: AgentState;
  className?: string;
}) {
  return (
    <span title={[AGENT_STATUS_LABEL[state.status], state.activity].filter(Boolean).join(" · ")}
      className={`shrink-0 text-xs text-content/50 ${className}`}>
      {AGENT_STATUS_LABEL[state.status]}
    </span>
  );
}
