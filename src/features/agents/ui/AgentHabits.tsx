import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Clock, Pause, Play, Plus, Trash2, Zap } from "../../../shared/ui/icons";
import { ResourceHeader, RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { subscribeAgentFiles } from "../model/agentFiles";
import {
  addHabit,
  checkHabitsNow,
  habitRunningSince,
  habitScheduleLabel,
  habitStarting,
  habitsToday,
  loadHabits,
  nextHabitRunAt,
  subscribeHabitsRunning,
  updateHabits,
  type Habit,
  type HabitRun,
  type HabitSchedule,
} from "../model/agentHabits";
import type { ScheduleKind } from "../model/agentSchedule";

/** The agent's habits, reloaded whenever its folder changes or a run ends. */
function useHabits(agentId: string, enabled = true): Habit[] | undefined {
  const [habits, setHabits] = useState<Habit[]>();
  useEffect(() => {
    if (!enabled) return;
    let live = true;
    const refresh = () => {
      void loadHabits(agentId).then((next) => { if (live) setHabits(next); }).catch(() => {});
    };
    refresh();
    const stopFiles = subscribeAgentFiles(refresh);
    const stopRuns = subscribeHabitsRunning(refresh);
    window.addEventListener("focus", refresh);
    // Runs move nextRunAt along without a panel event; check now and then.
    const timer = window.setInterval(refresh, 30_000);
    return () => {
      live = false;
      stopFiles();
      stopRuns();
      window.removeEventListener("focus", refresh);
      window.clearInterval(timer);
    };
  }, [agentId, enabled]);
  return habits;
}

let runningVersion = 0;
const subscribeRunning = (onChange: () => void) => subscribeHabitsRunning(() => { runningVersion += 1; onChange(); });

const OUTCOME: Record<NonNullable<Habit["lastOutcome"]>, string> = {
  posted: "told you something",
  quiet: "nothing to report",
  failed: "failed",
};

const when = new Intl.DateTimeFormat(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });

function habitLine(habit: Habit): string {
  if (habitRunningSince(habit.id) != null) return "Running now";
  if (habitStarting(habit)) return "Starting…";
  const last = habit.lastOutcome ? ` · last ${OUTCOME[habit.lastOutcome]}` : "";
  return habit.enabled ? `${habitScheduleLabel(habit.schedule)}${last}` : `Paused${last}`;
}

const fieldClass =
  "w-full rounded-md border border-stroke bg-content/5 px-2 py-1.5 text-[13px] text-content outline-none placeholder:text-content/35 focus:border-content/30";
const iconButton =
  "grid size-5 shrink-0 place-items-center rounded text-content/40 hover:text-content disabled:opacity-40";

/** What the agent does on its own, on a schedule: run now, pause, remove, or add one. */
export function AgentHabits({ agentId, habits: provided, onOpen, onCreate }: { agentId: string; habits?: Habit[]; onOpen?: (id: string) => void; onCreate?: () => void }) {
  const loaded = useHabits(agentId, provided === undefined);
  const habits = provided ?? loaded;
  useSyncExternalStore(subscribeRunning, () => runningVersion);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string>();
  const change = (id: string, edit: (habit: Habit) => Habit | undefined) =>
    updateHabits(agentId, (list) => ({
      habits: list.flatMap((habit) => habit.id === id ? (edit(habit) ?? []) : habit),
      result: undefined,
    })).then(() => setError(undefined), (reason: unknown) => setError(reason instanceof Error ? reason.message : String(reason)));
  const today = habitsToday((habits ?? []).filter((habit) => habit.enabled), Date.now());
  const shown = new Set(today.map((item) => item.habit.id));
  const later = (habits ?? []).filter((habit) => !shown.has(habit.id)).sort((a, b) => Number(b.enabled) - Number(a.enabled) || a.nextRunAt - b.nextRunAt);
  const groups = [
    { title: "Up next today", habits: today.filter((item) => item.state !== "done").map((item) => item.habit) },
    { title: "Done today", habits: today.filter((item) => item.state === "done").map((item) => item.habit) },
    { title: today.length ? "Later" : "Scheduled", habits: later },
  ].filter((group) => group.habits.length);
  return (
    <>
      {habits?.length === 0 && !adding ? <p className="text-xs text-content/45">None yet. Ask it to do something regularly, or add one here.</p> : null}
      {groups.map((group) => <section key={group.title} className="mb-4" aria-label={group.title}>
      <h3 className="flex items-center gap-2 px-2 pb-2 pt-1 text-[11px] font-medium text-content/40">{group.title}<span className="tabular-nums">{group.habits.length}</span></h3>
      <ul className="flex flex-col gap-px">
        {group.habits.map((habit) => {
          const running = habitRunningSince(habit.id) != null;
          return (
            <li key={habit.id} className="group flex items-center rounded-md hover:bg-content/5" title={habit.lastError ?? habit.instructions}>
              <button type="button" className="flex min-w-0 flex-1 items-center gap-2.5 rounded-md px-2 py-2 text-left" aria-label={`Habit: ${habit.name}`} onClick={() => onOpen?.(habit.id)}>
                <span aria-hidden className="grid size-7 shrink-0 place-items-center rounded-md bg-content/6 text-content/60"><Clock className="size-3.5" /></span>
                <span className="flex min-w-0 flex-1 flex-col"><span className={`truncate text-[12px] leading-5 ${habit.enabled ? "text-content/85" : "text-content/45"}`}>{habit.name}</span>
                <span className={`truncate text-[11px] leading-4 ${habit.lastOutcome === "failed" ? "text-red-400/80" : "text-content/40"}`}>
                  {habitLine(habit)}
                  {habit.enabled && !running ? ` · next ${when.format(habit.nextRunAt)}` : ""}
                </span></span>
              </button>
              <div className="flex shrink-0 items-center gap-0.5 pr-2 opacity-0 focus-within:opacity-100 group-hover:opacity-100">
                <button type="button" title="Run now" aria-label={`Run ${habit.name} now`} disabled={running || !!habit.runRequested} className={iconButton}
                  onClick={() => void change(habit.id, (current) => ({ ...current, runRequested: true })).then(checkHabitsNow)}>
                  <Zap className="size-3" strokeWidth={1.75} />
                </button>
                <button type="button" title={habit.enabled ? "Pause" : "Resume"} aria-label={`${habit.enabled ? "Pause" : "Resume"} ${habit.name}`} className={iconButton}
                  onClick={() => void change(habit.id, (current) => ({
                    ...current, enabled: !current.enabled,
                    // Turning it back on counts from now.
                    ...(current.enabled ? {} : { nextRunAt: nextHabitRunAt(current.schedule, Date.now()) }),
                  }))}>
                  {habit.enabled ? <Pause className="size-3" strokeWidth={1.75} /> : <Play className="size-3" strokeWidth={1.75} />}
                </button>
                <button type="button" title="Remove" aria-label={`Remove ${habit.name}`} className={iconButton} onClick={() => void change(habit.id, () => undefined)}>
                  <Trash2 className="size-3" strokeWidth={1.75} />
                </button>
              </div>
            </li>
          );
        })}
      </ul></section>)}
      {adding ? (
        <NewHabit onCancel={() => setAdding(false)}
          onAdd={(draft) => addHabit(agentId, draft).then(() => { setAdding(false); setError(undefined); },
            (reason: unknown) => setError(reason instanceof Error ? reason.message : String(reason)))} />
      ) : (
        <button type="button" onClick={onCreate ?? (() => setAdding(true))}
          className="inline-flex w-fit items-center gap-1.5 rounded-md border border-stroke px-2 py-1.5 text-xs text-content/70 hover:bg-content/8 hover:text-content">
          <Plus className="size-3" strokeWidth={1.75} /> Add habit
        </button>
      )}
      {error ? <p className="text-[11px] text-red-400/90">{error}</p> : null}
    </>
  );
}

const KINDS: { id: ScheduleKind; label: string }[] = [
  { id: "hourly", label: "Hourly" },
  { id: "daily", label: "Daily" },
  { id: "weekdays", label: "Weekdays" },
  { id: "weekly", label: "Weekly" },
];
const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function NewHabit({ onAdd, onCancel, busy = false }: { busy?: boolean; onAdd: (draft: { name: string; instructions: string; schedule: HabitSchedule }) => void; onCancel: () => void }) {
  const [name, setName] = useState("");
  const [instructions, setInstructions] = useState("");
  const [schedule, setSchedule] = useState<HabitSchedule>({ scheduleKind: "weekdays", time: "09:00", minute: 0, dayOfWeek: 1 });
  const ready = !!name.trim() && !!instructions.trim();
  return (
    <div className="flex flex-col gap-1.5 rounded-md border border-stroke p-2">
      <input aria-label="Habit name" autoFocus value={name} maxLength={80} placeholder="Morning CI check" className={fieldClass}
        onChange={(event) => setName(event.target.value)}
        onKeyDown={(event) => { if (event.key === "Escape" && !isImeComposition(event.nativeEvent)) onCancel(); }} />
      <textarea aria-label="What it does" value={instructions} rows={3} maxLength={4000} className={`${fieldClass} resize-y text-xs leading-relaxed`}
        placeholder="What to do, and when it is worth telling you. It runs unattended with full access."
        onChange={(event) => setInstructions(event.target.value)} />
      <div className="flex gap-1.5">
        <select aria-label="How often" value={schedule.scheduleKind} className={`${fieldClass} min-w-0 flex-1`}
          onChange={(event) => setSchedule({ ...schedule, scheduleKind: event.target.value as ScheduleKind })}>
          {KINDS.map((kind) => <option key={kind.id} value={kind.id}>{kind.label}</option>)}
        </select>
        {schedule.scheduleKind === "weekly" ? (
          <select aria-label="Day" value={schedule.dayOfWeek} className={`${fieldClass} min-w-0 flex-1`}
            onChange={(event) => setSchedule({ ...schedule, dayOfWeek: Number(event.target.value) })}>
            {DAYS.map((day, index) => <option key={day} value={index}>{day}</option>)}
          </select>
        ) : null}
        {schedule.scheduleKind === "hourly" ? (
          <input aria-label="Minute past the hour" type="number" min={0} max={59} value={schedule.minute} className={`${fieldClass} w-16 shrink-0`}
            onChange={(event) => setSchedule({ ...schedule, minute: Math.min(59, Math.max(0, Math.trunc(Number(event.target.value)) || 0)) })} />
        ) : (
          <input aria-label="Time" type="time" value={schedule.time} className={`${fieldClass} w-24 shrink-0`}
            onChange={(event) => { if (event.target.value) setSchedule({ ...schedule, time: event.target.value }); }} />
        )}
      </div>
      <div className="flex justify-end gap-1.5">
        <button type="button" onClick={onCancel} className="rounded-md px-2 py-1 text-xs text-content/60 hover:bg-content/8 hover:text-content">Cancel</button>
        <button type="button" disabled={!ready || busy} onClick={() => onAdd({ name: name.trim(), instructions: instructions.trim(), schedule })}
          className="rounded-md border border-stroke px-2 py-1 text-xs text-content/80 hover:bg-content/8 hover:text-content disabled:opacity-40">{busy ? "Adding…" : "Add"}</button>
      </div>
    </div>
  );
}

/** A habit's persisted reports are useful even when its background run is gone. */
export function AgentHabitDetail({ agentId, habit, loading, onBack, onClose }: {
  agentId: string; habit?: Habit; loading: boolean; onBack: () => void; onClose: () => void;
}) {
  const [error, setError] = useState<string>();
  useSyncExternalStore(subscribeRunning, () => runningVersion);
  const change = async (edit: (value: Habit) => Habit | undefined) => {
    if (!habit) return;
    try {
      await updateHabits(agentId, (items) => ({ habits: items.flatMap((item) => item.id === habit.id ? edit(item) ?? [] : item), result: undefined }));
      setError(undefined);
    } catch (cause) { setError(String(cause)); }
  };
  const running = habit && (habitRunningSince(habit.id) != null || habitStarting(habit));
  const date = (at: number) => new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(at);
  return <section className="flex min-h-0 flex-1 flex-col">
    <ResourceHeader title={habit?.name ?? "Habit"} backLabel="Back to habits" onBack={onBack} onClose={onClose}>
      {habit ? <><button type="button" className={RESOURCE_ACTION} title="Run now" aria-label="Run habit now" disabled={!!running} onClick={() => void change((item) => ({ ...item, runRequested: true })).then(checkHabitsNow)}><Zap className="size-3.5" /></button>
        <button type="button" className={RESOURCE_ACTION} title={habit.enabled ? "Pause" : "Resume"} aria-label={habit.enabled ? "Pause habit" : "Resume habit"} onClick={() => void change((item) => ({ ...item, enabled: !item.enabled, ...(item.enabled ? {} : { nextRunAt: nextHabitRunAt(item.schedule, Date.now()) }) }))}>{habit.enabled ? <Pause className="size-3.5" /> : <Play className="size-3.5" />}</button>
        <button type="button" className={RESOURCE_ACTION} title="Remove habit" aria-label="Remove habit" onClick={() => void change(() => undefined)}><Trash2 className="size-3.5" /></button></> : null}
    </ResourceHeader>
    {!habit ? <p className="p-4 text-xs text-content/50">{loading ? "Loading habit…" : "This habit is no longer available."}</p> : <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5">
      <p className="text-xs text-content/50">{habit.enabled ? habitScheduleLabel(habit.schedule) : "Paused"}{habit.enabled ? ` · next ${date(habit.nextRunAt)}` : ""}</p>
      <p className="mt-3 whitespace-pre-wrap text-[13px] leading-relaxed">{habit.instructions}</p>
      <p className="mt-3 text-xs text-content/45">Runs while Loci is open.</p>
      <label className="mt-3 flex items-start gap-2 text-xs text-content/70">
        <input type="checkbox" className="mt-0.5" checked={habit.access === "auto"} aria-label="Ask before risky steps"
          onChange={(event) => { const ask = event.target.checked; void change((item) => { const { access: _access, ...rest } = item; return ask ? { ...rest, access: "auto" } : rest; }); }} />
        <span>Ask before risky steps<span className="block text-content/45">Runs in Auto mode: anything the agent's CLI judges risky waits for you in the chat. Off, it runs unattended with full access. Turn this on for habits that read web pages.</span></span>
      </label>
      {error ? <p role="alert" className="mb-3 text-xs text-red-400">{error}</p> : null}
      <h3 className="mt-5 border-t border-stroke pb-2 pt-4 text-[11px] font-medium text-content/45">Recent runs</h3>
      {!habit.runs?.length ? <p className="mt-3 text-xs text-content/45">No runs yet.</p> : <ul className="-mx-2 flex flex-col gap-px">{habit.runs.map((run, index) => <HabitRunRow key={`${run.at}:${index}`} run={run} />)}</ul>}
    </div>}
  </section>;
}


function HabitRunRow({ run }: { run: HabitRun }) {
  const [open, setOpen] = useState(false);
  const detail = run.report ?? run.error;
  const label = run.outcome === "posted" ? "Messaged you" : run.outcome === "quiet" ? "Nothing to report" : "Couldn't finish";
  const at = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(run.at);
  return <li data-habit-run className={`rounded-md ${open ? "bg-content/5" : ""}`}>
    <button type="button" disabled={!detail} aria-expanded={detail ? open : undefined} onClick={() => setOpen((value) => !value)} className="flex w-full items-center gap-2.5 rounded-md px-2 py-2 text-left text-[12px] enabled:hover:bg-content/5">
      <span aria-hidden className={`size-2 shrink-0 rounded-full ${run.outcome === "failed" ? "bg-red-400" : run.outcome === "posted" ? "bg-accent" : "bg-content/25"}`} />
      <span className="min-w-0 flex-1 truncate text-content/85">{label}</span><span className="shrink-0 text-[11px] tabular-nums text-content/40">{at} · {Math.max(1, Math.round(run.durationMs / 1000))}s</span>
    </button>
    {open ? <div className="pb-3 pl-[26px] pr-3 text-xs leading-5 text-content/75">{run.report ? <AgentMarkdown text={run.report} /> : <p className="whitespace-pre-wrap text-red-400">{run.error}</p>}</div> : null}
  </li>;
}

export function AgentNewHabit({ agentId, onBack, onClose }: { agentId: string; onBack: () => void; onClose: () => void }) {
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  return <section className="flex min-h-0 flex-1 flex-col">
    <ResourceHeader title="New habit" backLabel="Back to habits" onBack={onBack} onClose={onClose} />
    <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5">
      <p className="mb-4 text-xs leading-5 text-content/45">A recurring task for this agent. It runs while Loci is open.</p>
      <NewHabit busy={busy} onCancel={onBack} onAdd={(draft) => {
        setBusy(true); setError(undefined);
        void addHabit(agentId, draft).then(() => { if (mounted.current) onBack(); }, (cause) => { if (mounted.current) setError(String(cause)); }).finally(() => { if (mounted.current) setBusy(false); });
      }} />
      {error ? <p role="alert" className="mt-3 text-xs text-red-400">{error}</p> : null}
    </div>
  </section>;
}
