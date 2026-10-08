import { t, useLocale } from "../../../shared/i18n/locale";
import { useEffect,useState } from "react";
import { Clock,Gauge,Play,X } from "../../../shared/ui/icons";
import type { UsageLimit } from "../model/session";
import { formatUsageLimitReset } from "../model/usageLimit";

const BUTTON =
  "flex h-6 shrink-0 items-center gap-1.5 rounded-md px-1.5 hover:bg-content/10 hover:text-content";

export function UsageLimitNotice({
  limit,
  onResume,
  onResumeAtReset,
  onDismiss,
}: {
  limit: UsageLimit;
  onResume?: () => void;
  onResumeAtReset?: (enabled: boolean) => void;
  onDismiss?: () => void;
}) {
  useLocale();
  const [now, setNow] = useState(Date.now);
  const waiting = limit.resetsAt != null && limit.resetsAt > now;
  // Tick the countdown, and flip to "Resume" once the window resets.
  useEffect(() => {
    if (!waiting) return;
    const timer = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, [waiting]);

  return (
    <div className="px-2 text-content/55" data-usage-limit>
      <div className="relative z-0 flex h-8 items-center gap-2 rounded-t-[10px] border border-b-0 border-amber-400/25 bg-amber-400/10 px-2 text-[12px]">
        <Gauge className="size-3.5 shrink-0 text-amber-400" />
        <span className="shrink-0 text-content/85">{t("Usage limit reached")}</span>
        <span className="min-w-0 flex-1 truncate">
          {limit.resetsAt == null
            ? ""
            : waiting
              ? t("Resets {0}", formatUsageLimitReset(limit.resetsAt, now))
              : t("Limit has reset")}
        </span>
        {!waiting ? (
          <button type="button" onClick={onResume} className={BUTTON}>
            <Play className="size-3.5" />
            {t("Resume")}</button>
        ) : limit.resumeAtReset ? (
          <button
            type="button"
            title={t("Cancel the automatic resume")}
            onClick={() => onResumeAtReset?.(false)}
            className={`${BUTTON} text-amber-400`}
          >
            <Clock className="size-3.5" />
            {t("Resuming at reset")}</button>
        ) : (
          <button
            type="button"
            title={t("Continue this session once the limit resets")}
            onClick={() => onResumeAtReset?.(true)}
            className={BUTTON}
          >
            <Clock className="size-3.5" />
            {t("Resume at reset")}</button>
        )}
        <button
          type="button"
          title={t("Dismiss")}
          aria-label={t("Dismiss usage limit notice")}
          onClick={onDismiss}
          className="grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content"
        >
          <X className="size-3.5" />
        </button>
      </div>
    </div>
  );
}
