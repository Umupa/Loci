import { useEffect, useRef, useState } from "react";
import { Check, ChevronDown } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import { subscribeAgentFiles } from "../model/agentFiles";
import { HEARTBEAT_INTERVALS, heartbeatMinutes, loadHeartbeat, setHeartbeatMinutes } from "../model/agentHeartbeat";

const label = (minutes: number) => minutes <= 0 ? "Off" : minutes < 60 ? `${minutes} min` : `${minutes / 60} h`;

/** How long its chat sits idle before the mentor looks for follow-ups. */
export function HeartbeatPicker({ agentId }: { agentId: string }) {
  const [minutes, setMinutes] = useState<number>();
  const [open, setOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    let live = true;
    const load = () => void loadHeartbeat(agentId).then((state) => { if (live) setMinutes(heartbeatMinutes(state)); }, () => undefined);
    load();
    const stop = subscribeAgentFiles(load);
    return () => { live = false; stop(); };
  }, [agentId]);
  const pick = (value: number) => {
    setOpen(false);
    setMinutes(value);
    // A save that failed shows what the file still says.
    void setHeartbeatMinutes(agentId, value).catch(() => loadHeartbeat(agentId).then((state) => setMinutes(heartbeatMinutes(state)), () => undefined));
  };
  const shown = minutes == null ? "" : label(minutes);
  return <>
    <button ref={anchor} type="button" aria-haspopup="menu" aria-expanded={open} aria-label={`Heartbeat: ${shown}`} disabled={minutes == null}
      onClick={() => setOpen((next) => !next)}
      className="flex max-w-52 items-center gap-1.5 rounded-md border border-content/10 bg-content/5 px-2 py-1 text-[12px] text-content hover:border-content/20">
      <span className="min-w-0 truncate">{shown}</span>
      <ChevronDown className="size-3.5 shrink-0 text-content/50" />
    </button>
    {open ? <Popover anchor={anchor} side="bottom" align="end" width={160} role="menu" aria-label="Heartbeat" onDismiss={() => setOpen(false)} className="p-1 font-sans">
      {HEARTBEAT_INTERVALS.map((value) => <button key={value} type="button" role="menuitemradio" aria-checked={value === minutes}
        onClick={() => pick(value)}
        className="flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-[13px] text-content hover:bg-content/6">
        <span className="min-w-0 flex-1 truncate">{label(value)}</span>
        {value === minutes ? <Check className="size-3.5 shrink-0" /> : null}
      </button>)}
    </Popover> : null}
  </>;
}
