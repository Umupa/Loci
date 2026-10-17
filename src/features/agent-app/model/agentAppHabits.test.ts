// @vitest-environment happy-dom
import { expect, it } from "vitest";
import { newSession } from "../../sessions/model/session";
import { setHabitRunning, type Habit } from "../../agents/model/agentHabits";
import { handleAgentApp, type AgentAppHost } from "./agentApp";

function habitsFixture(own = true) {
  const source = newSession("codex", "/tmp/project", "codex:test");
  source.id = "agent";
  let stored: Habit[] = [];
  const host = {
    agentOf: (id: string) =>
      id === "agent" ? { id: "agent-1", projects: [], habitRun: !own } : undefined,
    habits: {
      load: async () => stored,
      update: async <T,>(
        _agentId: string,
        change: (list: Habit[]) => { habits: Habit[]; result: T },
      ) => {
        const next = change(stored);
        stored = next.habits;
        return next.result;
      },
    },
    now: () => new Date(2026, 9, 5, 8),
  } as unknown as AgentAppHost;
  const run = (action: string, input: Record<string, unknown> = {}) =>
    handleAgentApp(source, `req-${Math.random()}`, action, input, host);
  return { run, habits: () => stored };
}

it("lets an agent add, pause, try and remove its habits", async () => {
  const { run, habits } = habitsFixture();
  const added = (await run("habits.add", {
    name: "Morning CI check",
    instructions: "Tell me if CI on main is red.",
    schedule: { kind: "weekdays", time: "09:00" },
  })) as { habit: { id: string; schedule: string } };
  expect(added.habit.schedule).toBe("Weekdays at 9:00 AM");
  expect(habits()[0].nextRunAt).toBe(new Date(2026, 9, 5, 9).getTime());
  const id = added.habit.id;
  await run("habits.update", { id, enabled: false });
  expect(habits()[0].enabled).toBe(false);
  await run("habits.run", { id });
  // Runs once now, paused or not, and leaves the schedule alone.
  expect(habits()[0]).toMatchObject({
    runRequested: true,
    enabled: false,
    nextRunAt: new Date(2026, 9, 5, 9).getTime(),
  });
  expect(await run("habits.list")).toMatchObject({
    habits: [{ id, name: "Morning CI check", enabled: false }],
  });
  await run("habits.remove", { id });
  expect(habits()).toEqual([]);
  await expect(run("habits.remove", { id })).rejects.toThrow("No habit");
});

it("keeps habits to an agent's own conversation", async () => {
  await expect(habitsFixture(false).run("habits.list")).rejects.toThrow(
    "Only an agent",
  );
});

it("refuses to start a habit that is already running", async () => {
  const { run } = habitsFixture();
  const added = (await run("habits.add", {
    name: "PR check",
    instructions: "Look at open PRs.",
    schedule: { kind: "daily", time: "08:30" },
  })) as { habit: { id: string } };
  setHabitRunning(added.habit.id, Date.now());
  await expect(run("habits.run", { id: added.habit.id })).rejects.toThrow(
    "already running",
  );
  expect(await run("habits.list")).toMatchObject({
    habits: [{ id: added.habit.id, running: true }],
  });
  setHabitRunning(added.habit.id);
});


it("runs a habit in Auto mode when asked, and back to full access on request", async () => {
  const { run, habits } = habitsFixture();
  const added = (await run("habits.add", {
    name: "Market brief",
    instructions: "Summarise the morning's market news.",
    schedule: { kind: "weekdays", time: "08:30" },
    access: "auto",
  })) as { habit: { id: string; access: string } };
  expect(added.habit.access).toBe("auto");
  expect(habits()[0].access).toBe("auto");
  await run("habits.update", { id: added.habit.id, access: "full" });
  expect(habits()[0].access).toBeUndefined();
  await expect(run("habits.add", { name: "x", instructions: "y", schedule: { kind: "daily", time: "09:00" }, access: "root" }))
    .rejects.toThrow('access must be "full" or "auto"');
});
