import { expect, it } from "vitest";
import type { Block } from "../../sessions/model/session";
import {
  afterHeartbeat,
  chatActivity,
  HEARTBEAT_ID,
  heartbeatIntervalMs,
  heartbeatModel,
  heartbeatPrompt,
  parseHeartbeat,
  planHeartbeat,
  recentExchanges,
  serializeHeartbeat,
  type HeartbeatState,
} from "./agentHeartbeat";
import { QUIET_MARKER } from "./agentWake";
import type { AgentFiles } from "./agentFiles";

const MIN = 60_000;
const NOW = 1_800_000_000_000;
const state = (over: Partial<HeartbeatState> = {}): HeartbeatState => ({
  lastRunAt: NOW - 60 * MIN, quietStreak: 0, recent: [], memoryHash: "m", ...over,
});
const user = (id: string, startedAt: number, text = "hi"): Block => ({ id, role: "user", text, startedAt, durationMs: 1_000 });
const reply = (id: string, text: string): Block => ({ id, role: "assistant", text });
const chat = (blocks: Block[], busy = false) => ({ blocks, busy });

it("keeps what it knows and unknown keys, and starts over from a broken file", () => {
  const text = serializeHeartbeat({ ...state({ minutes: 15, recent: ["a"] }), extra: 1 } as HeartbeatState);
  expect(parseHeartbeat(text)).toMatchObject({ minutes: 15, recent: ["a"], quietStreak: 0, extra: 1 });
  expect(parseHeartbeat("nope")).toEqual({ lastRunAt: 0, quietStreak: 0, recent: [] });
  expect(parseHeartbeat(null).minutes).toBeUndefined();
});

it("only marks where it starts the first time it looks", () => {
  const plan = planHeartbeat(state({ lastRunAt: 0 }), chat([user("u", NOW - 90 * MIN)]), "m", NOW);
  expect(plan).toEqual({ kind: "skip", state: expect.objectContaining({ lastRunAt: NOW }) });
});

it("is off at 0 minutes and while the chat is busy", () => {
  const blocks = [user("u", NOW - 50 * MIN)];
  expect(planHeartbeat(state({ minutes: 0 }), chat(blocks), "m", NOW)).toEqual({ kind: "wait" });
  expect(planHeartbeat(state(), chat(blocks, true), "m", NOW)).toEqual({ kind: "wait" });
});

it("waits until the chat has sat idle for the interval", () => {
  expect(planHeartbeat(state(), chat([user("u", NOW - 10 * MIN)]), "m", NOW)).toEqual({ kind: "wait" });
  expect(planHeartbeat(state({ minutes: 60 }), chat([user("u", NOW - 45 * MIN)]), "m", NOW)).toEqual({ kind: "wait" });
  expect(planHeartbeat(state(), chat([user("u", NOW - 45 * MIN)]), "m", NOW)).toMatchObject({ kind: "run", state: { lastRunAt: NOW } });
});

it("does not ask the model when nothing moved since the last heartbeat", () => {
  const old = [user("u", NOW - 120 * MIN)];
  expect(planHeartbeat(state(), chat(old), "m", NOW)).toMatchObject({ kind: "skip", state: { lastRunAt: NOW } });
  // A memory change is something new to follow up.
  expect(planHeartbeat(state(), chat(old), "m2", NOW)).toMatchObject({ kind: "run", state: { memoryHash: "m2" } });
});

it("does not count its own posts as activity", () => {
  const blocks: Block[] = [
    user("u", NOW - 120 * MIN),
    { ...reply("hb", "Shall I find that paper?"), agentHabit: { id: HEARTBEAT_ID, name: "Heartbeat", at: NOW - 40 * MIN } },
  ];
  expect(chatActivity(blocks).lastAt).toBe(NOW - 120 * MIN + 1_000);
  expect(planHeartbeat(state(), chat(blocks), "m", NOW).kind).toBe("skip");
  // A habit's post is news.
  blocks[1] = { ...blocks[1], agentHabit: { id: "h1", name: "Digest", at: NOW - 40 * MIN } };
  expect(planHeartbeat(state(), chat(blocks), "m", NOW).kind).toBe("run");
});

it("backs off after three quiet runs, up to four hours, and starts over when the user writes", () => {
  expect(heartbeatIntervalMs(30, 2)).toBe(30 * MIN);
  expect(heartbeatIntervalMs(30, 3)).toBe(60 * MIN);
  expect(heartbeatIntervalMs(30, 4)).toBe(120 * MIN);
  expect(heartbeatIntervalMs(30, 9)).toBe(240 * MIN);
  expect(heartbeatIntervalMs(120, 9)).toBe(240 * MIN);

  const quiet = state({ quietStreak: 3, memoryHash: "old" });
  // Memory moved, but 60 quiet minutes have not passed since the last run.
  expect(planHeartbeat({ ...quiet, lastRunAt: NOW - 45 * MIN }, chat([]), "m", NOW)).toEqual({ kind: "wait" });
  // The user wrote since: the streak resets and 30 minutes is enough again.
  const wrote = planHeartbeat({ ...quiet, lastRunAt: NOW - 80 * MIN }, chat([user("u", NOW - 40 * MIN)]), "m", NOW);
  expect(wrote).toMatchObject({ kind: "run", state: { quietStreak: 0 } });
});

it("counts quiet runs and remembers what it raised, newest first and capped", () => {
  expect(afterHeartbeat(state({ quietStreak: 1 }), { ok: true })).toMatchObject({ quietStreak: 2 });
  expect(afterHeartbeat(state({ quietStreak: 1 }), { ok: false })).toMatchObject({ quietStreak: 1 });
  let next = state({ quietStreak: 4 });
  for (let i = 0; i < 7; i++) next = afterHeartbeat(next, { ok: true, report: `idea ${i}\n` + "x".repeat(400) });
  expect(next.quietStreak).toBe(0);
  expect(next.recent).toHaveLength(5);
  expect(next.recent[0].startsWith("idea 6 x")).toBe(true);
  expect(next.recent[0].length).toBeLessThanOrEqual(300);
});

it("brings the last two exchanges, leaving out hidden prompts and posts", () => {
  const blocks: Block[] = [
    user("1", 1, "first"), reply("1r", "one"),
    user("2", 2, "second"), reply("2r", "two"),
    { ...user("s", 3, "set yourself up"), agentSetup: true },
    user("3", 4, "third"), reply("3r", "three"),
    { ...reply("h", "habit"), agentHabit: { id: "h1", name: "Digest", at: 5 } },
  ];
  expect(recentExchanges(blocks)).toBe("User: second\nYou: two\n\nUser: third\nYou: three");
});

it("asks for at most two proposals, never quizzes, and lists what it raised", () => {
  const files = { id: "a", dir: "/a", soul: "Teach Rust.", soulHash: "s", memory: "- promised: find the Pin RFC", memoryHash: "m", memoryPath: "/a/MEMORY.md", topics: [] } as unknown as AgentFiles;
  const look = { name: "Kern", avatar: "nova", color: "red" };
  const prompt = heartbeatPrompt(look, files, state({ recent: ["Offered the async book"] }), "User: hi", NOW);
  expect(prompt).toContain("Teach Rust.");
  expect(prompt).toContain("find the Pin RFC");
  expect(prompt).toContain("At most 2 proposals");
  expect(prompt).toContain("Never quiz the learner, plan reviews or spaced repetition, or set mastery gates or scores");
  expect(prompt).toContain("never raise something you raised recently");
  expect(prompt).toContain("- Offered the async book");
  expect(prompt).toContain("User: hi");
  expect(prompt).toContain(`reply exactly ${QUIET_MARKER}`);
  expect(prompt).toContain(`Local time: ${new Date(NOW).toLocaleString()}`);
});

it("runs on a smaller model of the same provider, or the chat's own when there is none", () => {
  expect(heartbeatModel("claude", "claude:opus-5-5", {}).model).toBe("claude:haiku-4.5");
  expect(heartbeatModel("grok", "grok:grok-4.6", { effort: "high" })).toEqual({ model: "grok:grok-4.6", modelSettings: { effort: "high" } });
});

it("runs once after the app starts when it missed runs while closed, and otherwise only when something moved", async () => {
  const { planHeartbeat } = await import("./agentHeartbeat");
  const now = 10 * 60 * 60_000;
  const state = { lastRunAt: now - 3 * 60 * 60_000, quietStreak: 0, recent: [], memoryHash: "m" };
  const chat = { blocks: [{ id: "u", role: "user", text: "hi", startedAt: now - 5 * 60 * 60_000 }] as never[] };
  expect(planHeartbeat(state, chat, "m", now).kind).toBe("skip");
  expect(planHeartbeat(state, chat, "m", now, true).kind).toBe("run");
  // Not missed: the last run is within the interval.
  expect(planHeartbeat({ ...state, lastRunAt: now - 10 * 60_000 }, chat, "m", now, true).kind).toBe("wait");
});
