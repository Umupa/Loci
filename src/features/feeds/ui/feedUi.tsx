import { useState, type ReactNode } from "react";
import { XLogo } from "../../../shared/ui/icons";
import type { FeedTab } from "../model/feedSources";

/** Detail action buttons, shared with the inbox look: filled, outlined, bare. */
const ACTION = "inline-flex items-center gap-1.5 rounded-md px-3 text-[12px] disabled:cursor-default disabled:opacity-40";
export const ACTION_FILLED = `${ACTION} h-6.5 bg-content text-background-base hover:bg-content/80`;
export const ACTION_OUTLINE = `${ACTION} h-7 border border-content/15 text-content/80 hover:bg-content/5`;
export const ACTION_GHOST = `${ACTION} h-7 text-content/70 hover:bg-content/10 hover:text-content`;

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

export function Avatar({ src, name, size = 16 }: { src?: string | null; name?: string | null; size?: number }) {
  const [failed, setFailed] = useState(false);
  const style = { width: size, height: size };
  if (!src || failed) {
    return (
      <span aria-hidden style={{ ...style, fontSize: Math.max(9, size * 0.45) }}
        className="grid shrink-0 place-items-center rounded-full bg-content/12 font-medium uppercase text-content/55">
        {(name ?? "?").slice(0, 1)}
      </span>
    );
  }
  return <img src={src} alt="" style={style} referrerPolicy="no-referrer" loading="lazy" onError={() => setFailed(true)}
    className="shrink-0 rounded-full bg-content/10 object-cover" />;
}

export function Person({ name, avatar, size = 16 }: { name: string; avatar?: string | null; size?: number }) {
  return (
    <span className="inline-flex min-w-0 items-center gap-1.5">
      <Avatar src={avatar} name={name} size={size} />
      <span className="min-w-0 truncate">{name}</span>
    </span>
  );
}

/** Small tag in cards and headers; the dot carries the color. */
export function Chip({ children, dot, compact = false, title }: { children: ReactNode; dot?: string; compact?: boolean; title?: string }) {
  return (
    <span title={title} className={`inline-flex min-w-0 items-center gap-1 rounded bg-content/8 px-1.5 py-px text-content/50 ${compact ? "max-w-24 text-[10px]" : "text-[11px]"}`}>
      {dot ? <span aria-hidden className={`size-1.5 shrink-0 rounded-full ${dot}`} /> : null}
      <span className="min-w-0 truncate">{children}</span>
    </span>
  );
}

export function IconButton({ label, active = false, disabled, onClick, children }: {
  label: string;
  active?: boolean;
  disabled?: boolean;
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
  children: ReactNode;
}) {
  return (
    <button type="button" title={label} aria-label={label} disabled={disabled} onClick={onClick}
      className={`grid size-6 shrink-0 place-items-center rounded-md text-content/45 hover:bg-content/10 hover:text-content disabled:cursor-default disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-content/45 ${active ? "bg-selection text-content" : ""}`}>
      {children}
    </button>
  );
}

export function EmptyDetail({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <div className="flex h-full flex-1 flex-col items-center justify-center px-6 text-center">
      <span className="mb-3 text-content/30">{icon}</span>
      <p className="text-[13px] text-content/45">{children}</p>
    </div>
  );
}
