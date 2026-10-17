import { useRef,useState } from "react";
import { Popover } from "../../../shared/ui/Popover";
import {
contextPercent,
contextRatio,
contextTooltip,
formatTokens,
type ContextUsage,
} from "../model/contextUsage";

const SIZE = 14;
const STROKE = 2;
const RADIUS = (SIZE - STROKE) / 2;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

/** Ring turns amber then red as the window fills. */
function ringClass(ratio: number): string {
  if (ratio >= 0.9) return "text-red-400";
  if (ratio >= 0.75) return "text-amber-400";
  return "text-content/45";
}

/**
 * Circular gauge for how full the model context window is.
 *
 * Renders nothing until the harness reports both halves — Cursor's ACP stream
 * carries no usage at all, and a ring guessing at a number is worse than no
 * ring.
 */
export function ContextMeter({
  usage,
  onCompact,
  compactDisabled = false,
  detailed = false,
  empty = false,
}: {
  usage?: ContextUsage;
  /** Keep the agent toolbar stable before usage arrives, without claiming a percentage. */
  empty?: boolean;
  onCompact?: () => void;
  compactDisabled?: boolean;
  /** Say the numbers beside the ring: the percentage, and the tokens used. */
  detailed?: boolean;
}) {
  const [hovered, setHovered] = useState(false);
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const ratio = contextRatio(usage);
  // A window nobody reported would make the ring a guess; the tokens used are
  // still a fact, so the detailed form can say those alone.
  if (!usage || (ratio === null && !detailed)) {
    if (!empty) return null;
    const label = usage ? `Context capacity not reported; ${formatTokens(usage.used)} tokens used` : "Context usage not reported yet";
    return <span title={label} className="flex shrink-0 items-center px-1"><MeterRing ratio={0} label={label} /></span>;
  }

  const { headline, detail } = contextTooltip(usage);
  const actionsOpen = open && onCompact != null;

  return (
    <div
      ref={root}
      className="relative shrink-0"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {onCompact ? (
        <button
          type="button"
          title="Context usage"
          aria-label={`${headline}, ${detail}. Open context actions`}
          aria-expanded={actionsOpen}
          onClick={() => setOpen((value) => !value)}
          className="-m-1 flex items-center gap-1.5 rounded-sm p-1 outline-none focus-visible:ring-1 focus-visible:ring-accent"
        >
          {ratio === null ? null : <MeterRing ratio={ratio} />}
          {detailed ? <MeterText usage={usage} ratio={ratio} /> : null}
        </button>
      ) : (
        <div className="flex items-center gap-1.5">
          {ratio === null ? null : <MeterRing ratio={ratio} label={`${headline}, ${detail}`} />}
          {detailed ? <MeterText usage={usage} ratio={ratio} /> : null}
        </div>
      )}
      {hovered || actionsOpen ? (
        <Popover
          anchor={root}
          side="top"
          align="end"
          onDismiss={onCompact ? () => setOpen(false) : undefined}
          className={`w-max px-2.5 py-1.5 ${actionsOpen ? "" : "pointer-events-none"}`}
        >
          <div className="text-[12px] leading-4 text-content">{headline}</div>
          <div className="text-[11px] leading-4 text-content/50">{detail}</div>
          {actionsOpen ? (
            <button
              type="button"
              disabled={compactDisabled}
              title={
                compactDisabled
                  ? "Wait for the current operation to finish"
                  : "Compact this conversation's context"
              }
              onClick={() => {
                setOpen(false);
                onCompact?.();
              }}
              className="mt-1.5 w-full rounded-md bg-content/10 px-2 py-1 text-[11px] text-content hover:bg-content/15 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Compact now
            </button>
          ) : null}
        </Popover>
      ) : null}
    </div>
  );
}

/** "69%  Tokens: 176K", tinted like the ring as the window fills. */
function MeterText({ usage, ratio }: { usage: ContextUsage; ratio: number | null }) {
  const percent = contextPercent(usage);
  return (
    <span className={`flex items-center gap-2.5 whitespace-nowrap text-[11px] tabular-nums leading-none ${ratio === null ? "text-content/45" : ringClass(ratio)}`}>
      {percent === null ? null : <span>{percent}%</span>}
      <span className="text-content/45">Tokens: {formatTokens(usage.used)}</span>
    </span>
  );
}

function MeterRing({ ratio, label }: { ratio: number; label?: string }) {
  return (
    <svg
      width={SIZE}
      height={SIZE}
      viewBox={`0 0 ${SIZE} ${SIZE}`}
      className={ringClass(ratio)}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <circle
        cx={SIZE / 2}
        cy={SIZE / 2}
        r={RADIUS}
        fill="none"
        stroke="currentColor"
        strokeWidth={STROKE}
        className="opacity-25"
      />
      {ratio > 0 ? <circle
        cx={SIZE / 2}
        cy={SIZE / 2}
        r={RADIUS}
        fill="none"
        stroke="currentColor"
        strokeWidth={STROKE}
        strokeLinecap="round"
        strokeDasharray={CIRCUMFERENCE}
        strokeDashoffset={CIRCUMFERENCE * (1 - ratio)}
        transform={`rotate(-90 ${SIZE / 2} ${SIZE / 2})`}
      /> : null}
    </svg>
  );
}
