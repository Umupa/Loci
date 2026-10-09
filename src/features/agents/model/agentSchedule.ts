/**
 * When a habit runs: every hour at a minute, or at a local time every day,
 * on weekdays, or on one day of the week.
 */
export type ScheduleKind = "hourly" | "daily" | "weekdays" | "weekly";

export type Schedule = {
  scheduleKind: ScheduleKind;
  /** Minute past the hour, for hourly habits. */
  minute: number;
  /** "HH:MM", local time. */
  time: string;
  /** 0 is Sunday, for weekly habits. */
  dayOfWeek: number;
};

const WEEKDAYS = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
] as const;

export function isScheduleKind(value: string): value is ScheduleKind {
  return (
    value === "hourly" ||
    value === "daily" ||
    value === "weekdays" ||
    value === "weekly"
  );
}

/** The first time the schedule comes due after `after`. */
export function nextScheduledRunAt(
  schedule: Schedule,
  after = Date.now(),
): number {
  const start = new Date(after);
  start.setSeconds(0, 0);
  const [hour, minute] = parseTime(schedule.time);
  if (schedule.scheduleKind === "hourly") {
    const candidate = new Date(start);
    candidate.setMinutes(clamp(schedule.minute, 0, 59), 0, 0);
    if (candidate.getTime() <= after)
      candidate.setHours(candidate.getHours() + 1);
    return candidate.getTime();
  }

  const candidate = new Date(start);
  candidate.setHours(hour, minute, 0, 0);
  if (schedule.scheduleKind === "daily") {
    if (candidate.getTime() <= after)
      candidate.setDate(candidate.getDate() + 1);
    return candidate.getTime();
  }
  if (schedule.scheduleKind === "weekdays") {
    if (candidate.getTime() <= after)
      candidate.setDate(candidate.getDate() + 1);
    while (candidate.getDay() === 0 || candidate.getDay() === 6) {
      candidate.setDate(candidate.getDate() + 1);
    }
    return candidate.getTime();
  }

  const day = clamp(schedule.dayOfWeek, 0, 6);
  let days = (day - candidate.getDay() + 7) % 7;
  if (days === 0 && candidate.getTime() <= after) days = 7;
  candidate.setDate(candidate.getDate() + days);
  return candidate.getTime();
}

/** The schedule in words: "Weekdays at 9:00 AM". */
export function scheduleLabel(
  schedule: Schedule,
): string {
  const time = formatClock(schedule.time);
  if (schedule.scheduleKind === "hourly") {
    return `Hourly at :${String(schedule.minute).padStart(2, "0")}`;
  }
  if (schedule.scheduleKind === "daily") return `Daily at ${time}`;
  if (schedule.scheduleKind === "weekdays") return `Weekdays at ${time}`;
  return `${WEEKDAYS[schedule.dayOfWeek] ?? "Weekly"} at ${time}`;
}

function parseTime(value: string): [number, number] {
  const [hour, minute] = value.split(":").map(Number);
  return [clamp(hour, 0, 23), clamp(minute, 0, 59)];
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

function formatClock(value: string): string {
  const [hour, minute] = parseTime(value);
  return new Date(2000, 0, 1, hour, minute).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
}
