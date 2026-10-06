
import claude from "../../../assets/providers/claude.svg";
import codex from "../../../assets/providers/codex.svg";








import type { HarnessId } from "../model/session";

export const HARNESS_ICONS: Record<HarnessId, string> = { claude, codex };

/** White marks that must follow `currentColor` so they stay visible in light mode. */




export function HarnessIcon({
  harness,
  className = "size-3.5",
}: {
  harness: HarnessId;
  className?: string;
}) {






  return (
    <img
      src={HARNESS_ICONS[harness]}
      alt=""
      draggable={false}
      className={`block object-contain ${className}`}
    />
  );
}
