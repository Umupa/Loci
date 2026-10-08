import { t, useLocale } from "../../shared/i18n/locale";
import { Chatting, CheckCircle, ExcalidrawIcon, Pin } from "../../shared/ui/icons";
import { FileTypeIcon } from "../../shared/ui/FileTypeIcon";
import { Popover } from "../../shared/ui/Popover";
import { ActivitySpinner } from "../../features/sessions/ui/ActivitySpinner";
import { HarnessIcon } from "../../features/sessions/ui/HarnessIcon";
import { tabStatusLabel, type Tab, type TabStatus } from "../../features/workspace/model/tabSummary";

/** One colour per status, so a tab reads the same wherever it appears. */
export const STATUS_TEXT: Record<TabStatus, string> = {
  approval: "text-amber-400",
  busy: "text-accent",
  done: "text-teal-400",
  idle: "text-content/50",
};

/** A small mark that a tab needs the user, pulsing to catch the eye without moving anything. */
export function ApprovalDot() {
  useLocale();
  return (
    <span aria-hidden className="pointer-events-none absolute -right-[3px] -top-[3px] grid size-2 place-items-center">
      <span className="absolute inline-flex size-full rounded-full bg-amber-400/60 motion-safe:animate-ping" />
      <span className="relative size-[7px] rounded-full bg-amber-400 ring-[1.5px] ring-background-base" />
    </span>
  );
}

/**
 * The icon that stands for a whole tab: what it holds, or what it is doing.
 * Working shows a spinner and finished a check; waiting for the user adds a dot.
 */
export function TabGlyph({ tab, dimmed = false, size = "sm" }: { tab: Tab; dimmed?: boolean; size?: "sm" | "md" }) {
  useLocale();
  const box = size === "md" ? "size-4" : "size-3.5";
  let glyph;
  if (tab.status === "busy") {
    glyph = <ActivitySpinner className={`inline-block select-none text-center ${size === "md" ? "text-[13px]" : "text-[11px]"} leading-none text-accent`} />;
  } else if (tab.status === "done") {
    glyph = <CheckCircle className={`${box} shrink-0 text-teal-400`} strokeWidth={2} />;
  } else if (tab.paneKind === "canvas") {
    glyph = <ExcalidrawIcon className={`${box} shrink-0`} />;
  } else if (tab.paneKind === "file") {
    glyph = <FileTypeIcon name={tab.title} isDir={false} size={size === "md" ? 16 : 14} />;
  } else if (tab.harnesses[0]) {
    glyph = <HarnessIcon harness={tab.harnesses[0]} className={`${box} shrink-0`} />;
  } else {
    glyph = <Chatting className={`${box} shrink-0 text-content/50`} strokeWidth={1.75} />;
  }
  return (
    <span className={`relative grid ${box} shrink-0 place-items-center`}>
      {/* Only the glyph dims: a mark that asks for attention must stay bright. */}
      <span className={`grid size-full place-items-center ${dimmed && tab.status !== "done" ? "opacity-60" : ""}`}>{glyph}</span>
      {tab.status === "approval" ? <ApprovalDot /> : null}
    </span>
  );
}

/** The card that unfolds under a tab: everything its narrow label could not say. */
export function TabHoverCard({ tab, anchor, now }: { tab: Tab; anchor: HTMLElement; now: number }) {
  useLocale();
  const label = tabStatusLabel(tab, now);
  return (
    <Popover anchor={anchor} side="bottom" align="start" gap={6} width={304} constrainHeight={false} role="tooltip" className="pointer-events-none">
      <div className="flex flex-col gap-2 px-3 py-2.5">
        <div className="flex items-start gap-2.5">
          <span className="mt-0.5"><TabGlyph tab={tab} size="md" /></span>
          <div className="min-w-0 flex-1">
            <p className="line-clamp-2 text-[13px] font-medium leading-snug text-content">{tab.title || t("New session")}</p>
            <p className="mt-0.5 flex min-w-0 items-center gap-1.5 text-[11px] leading-snug">
              {tab.project ? <span className="min-w-0 truncate text-content/50">{tab.project}</span> : null}
              {tab.project && label ? <span aria-hidden className="text-content/25">·</span> : null}
              {label ? <span className={`shrink-0 ${STATUS_TEXT[tab.status ?? "idle"]}`}>{label}</span> : null}
            </p>
          </div>
          {tab.pinned ? <Pin className="mt-0.5 size-3 shrink-0 text-content/40" strokeWidth={1.75} /> : null}
        </div>
        {tab.preview ? (
          <p className="line-clamp-3 border-t border-stroke pt-2 text-[12px] leading-[1.5] text-content/65">{tab.preview}</p>
        ) : null}
        {tab.sessionCount > 1 || tab.multiPane ? (
          <p className="text-[11px] text-content/40">
            {tab.sessionCount > 1 ? t("{0} conversations", tab.sessionCount) : t("Split view")}
          </p>
        ) : null}
      </div>
    </Popover>
  );
}
