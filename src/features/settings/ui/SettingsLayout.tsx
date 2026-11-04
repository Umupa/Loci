import { createContext, useContext, type ReactNode } from "react";
import { useLocale } from "../../../shared/i18n/locale";

export const settingDomId = (id: string) => `setting-${id}`;
/** The row or group Settings just jumped to, so it can flash where you landed. */
export const RevealedSetting = createContext<string | null>(null);

/**
 * A titled card of related settings. Everything on a page lives in one, so a
 * page reads as a handful of topics instead of one long list of switches.
 */
export function Group({ id, title, description, action, children, }: {
    /** Matches a `SETTINGS_INDEX` id when the whole card is the search target. */
    id?: string;
    title: ReactNode;
    description?: string;
    action?: ReactNode;
    /** Without any, only the title shows, such as a collapsed section. */
    children?: ReactNode;
}) {
  useLocale();
    const revealed = useContext(RevealedSetting);
    const flash = id != null && revealed === id;
    return (<section id={id ? settingDomId(id) : undefined} data-setting-id={id} className="pt-8 first:pt-0">
      <div className="flex items-end gap-4 pb-2.5">
        <div className="min-w-0 flex-1">
          <h2 title={description} className="text-[13px] font-semibold text-content">{title}</h2>
        </div>
        {action ? <div className="shrink-0 pb-0.5">{action}</div> : null}
      </div>
      {children ? (<div className={`overflow-hidden rounded-xl border bg-content/3 transition-colors ${flash ? "border-accent/60" : "border-content/10"}`}>
        {children}
      </div>) : null}
    </section>);
}
/**
 * A setting: its name and its control. What it does is the name's hover text;
 * only a state the person must see now (an error, a result) shows as `status`.
 */
export function Row({ id, label, description, status, children, }: {
    /** Matches a `SETTINGS_INDEX` id so search can scroll here. */
    id?: string;
    label: ReactNode;
    description?: string;
    status?: ReactNode;
    children?: ReactNode;
}) {
  useLocale();
    const revealed = useContext(RevealedSetting);
    const flash = id != null && revealed === id;
    return (<div id={id ? settingDomId(id) : undefined} data-setting-id={id} className={`settings-row flex min-h-12 items-center gap-6 border-b border-content/5 px-4 py-2.5 transition-colors last:border-b-0 ${flash ? "bg-accent/10" : ""}`}>
      <div className="min-w-0 flex-1" title={description}>
        <div className="text-[13px] text-content">{label}</div>
        {status ? (<p role="status" className="mt-0.5 text-[12px] leading-relaxed text-content/50">
            {status}
          </p>) : null}
      </div>
      <div className="settings-row-control flex min-w-0 max-w-[60%] shrink-0 flex-wrap items-center justify-end gap-2">
        {children}
      </div>
    </div>);
}
/** A row whose control needs the full width, such as the theme gallery. */
export function BlockRow({ id, label, description, children, }: {
    id?: string;
    label: ReactNode;
    description?: string;
    children: ReactNode;
}) {
  useLocale();
    const revealed = useContext(RevealedSetting);
    const flash = id != null && revealed === id;
    return (<div id={id ? settingDomId(id) : undefined} data-setting-id={id} className={`border-b border-content/5 px-4 py-3.5 transition-colors last:border-b-0 ${flash ? "bg-accent/10" : ""}`}>
      <div title={description} className="text-[13px] text-content">{label}</div>
      <div className="mt-3">{children}</div>
    </div>);
}
