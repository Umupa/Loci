import { useEffect, useState, useSyncExternalStore } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Pause, Play, Plus, Trash2, Zap } from "../../../shared/ui/icons";
import { subscribeAgentFiles } from "../model/agentFiles";
import {
  addHabit,
  checkHabitsNow,
  habitRunningSince,
  habitScheduleLabel,
  habitStarting,
  loadHabits,
  nextHabitRunAt,
  subscribeHabitsRunning,
  updateHabits,
  type Habit,
  type HabitSchedule,
} from "../model/agentHabits";
import type { ScheduleKind } from "../model/agentSchedule";

/** The agent's habits, reloaded whenever its folder changes or a run ends. */
function useHabits(agentId: string): Habit[] | undefined {
  const [habits, setHabits] = useState<Habit[]>();
  useEffect(() => {
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
  }, [agentId]);
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
export function AgentHabits({ agentId }: { agentId: string }) {
  const habits = useHabits(agentId);
  useSyncExternalStore(subscribeRunning, () => runningVersion);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string>();
  const change = (id: string, edit: (habit: Habit) => Habit | undefined) =>
    updateHabits(agentId, (list) => ({
      habits: list.flatMap((habit) => habit.id === id ? (edit(habit) ?? []) : habit),
      result: undefined,
    })).then(() => setError(undefined), (reason: unknown) => setError(reason instanceof Error ? reason.message : String(reason)));
  return (
    <>
      {habits?.length === 0 && !adding ? <p className="text-xs text-content/45">None yet. Ask it to do something regularly, or add one here.</p> : null}
      <ul className="flex flex-col gap-px">
        {habits?.map((habit) => {
          const running = habitRunningSince(habit.id) != null;
          return (
            <li key={habit.id} className="group flex items-start gap-2 rounded-md px-1.5 py-1 hover:bg-content/5" title={habit.lastError ?? habit.instructions}>
              <div className="min-w-0 flex-1">
                <p className={`truncate text-[13px] ${habit.enabled ? "" : "text-content/50"}`}>{habit.name}</p>
                <p className={`truncate text-[11px] ${habit.lastOutcome === "failed" ? "text-red-400/80" : "text-content/40"}`}>
                  {habitLine(habit)}
                  {habit.enabled && !running ? ` · next ${when.format(habit.nextRunAt)}` : ""}
                </p>
              </div>
              <div className="flex shrink-0 items-center gap-0.5 pt-0.5 opacity-0 focus-within:opacity-100 group-hover:opacity-100">
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
      </ul>
      {adding ? (
        <NewHabit onCancel={() => setAdding(false)}
          onAdd={(draft) => addHabit(agentId, draft).then(() => { setAdding(false); setError(undefined); },
            (reason: unknown) => setError(reason instanceof Error ? reason.message : String(reason)))} />
      ) : (
        <button type="button" onClick={() => setAdding(true)}
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

function NewHabit({ onAdd, onCancel }: { onAdd: (draft: { name: string; instructions: string; schedule: HabitSchedule }) => void; onCancel: () => void }) {
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
        <button type="button" disabled={!ready} onClick={() => onAdd({ name: name.trim(), instructions: instructions.trim(), schedule })}
          className="rounded-md border border-stroke px-2 py-1 text-xs text-content/80 hover:bg-content/8 hover:text-content disabled:opacity-40">Add</button>
      </div>
    </div>
  );
}
