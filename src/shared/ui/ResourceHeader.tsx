import { createContext, useContext, type ReactNode } from "react";
import { ChevronLeft, PanelLeft } from "./icons";

export const RESOURCE_ACTION = "grid size-6 shrink-0 place-items-center rounded-md text-content/55 hover:bg-content/8 hover:text-content disabled:opacity-40";

/** Controls every resource page in a surface shares, such as showing its conversation. */
export const ResourceHeaderExtra = createContext<ReactNode>(null);

/** What a surface puts ahead of every resource header, such as room for the window's buttons. */
export const ResourceHeaderLeading = createContext<ReactNode>(null);

/** Resource pages occupy the overview's same 40px navigation row. */
export function ResourceHeader({ title, titleContent, backLabel, onBack, onClose, children }: {
  title: string; titleContent?: ReactNode; backLabel: string; onBack: () => void; onClose: () => void; children?: ReactNode;
}) {
  const extra = useContext(ResourceHeaderExtra);
  const leading = useContext(ResourceHeaderLeading);
  return <header data-resource-header data-tauri-drag-region="deep" className="flex h-10 min-w-0 shrink-0 items-center gap-1 border-b border-stroke pl-2 pr-3 font-sans">
    {leading}
    <button type="button" data-tauri-drag-region="false" className={RESOURCE_ACTION} aria-label={backLabel} title={backLabel} onClick={onBack}><ChevronLeft className="size-3.5" strokeWidth={1.75} /></button>
    <h3 className="min-w-0 flex-1 truncate text-[13px] font-medium" title={title}>{titleContent ?? title}</h3>
    {children}
    {extra}
    <button type="button" data-tauri-drag-region="false" className={RESOURCE_ACTION} aria-label="Hide overview" title="Hide overview" onClick={onClose}><PanelLeft className="size-3.5 rotate-180" strokeWidth={1.75} /></button>
  </header>;
}
