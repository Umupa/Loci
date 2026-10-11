import { XLogo } from "../../../shared/ui/icons";
import type { FeedTab } from "../model/feedSources";

export const PROVIDER_LABELS: Record<FeedTab, string> = { v2ex: "V2EX", x: "X" };

/** V2EX has no glyph in the icon set; a "V" in a rounded square reads as its mark. */
function V2exMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden className={className}>
      <rect x="1.75" y="1.75" width="12.5" height="12.5" rx="3.5" />
      <path d="M5.25 5.25 8 10.75l2.75-5.5" />
    </svg>
  );
}

export function FeedProviderMark({ provider, className = "size-3.5 shrink-0" }: { provider: FeedTab; className?: string }) {
  return provider === "x" ? <XLogo className={className} /> : <V2exMark className={className} />;
}

