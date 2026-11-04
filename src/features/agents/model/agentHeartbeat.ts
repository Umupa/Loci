import type { Block, HarnessId } from "../../sessions/model/session";
import { findModel, mergeModelSettings, modelsFor } from "../../sessions/model/models";
import type { AgentLook } from "./agent";
import { agentContext, editAgentFile, readAgentFile, type AgentFiles } from "./agentFiles";
import { QUIET_MARKER } from "./agentHabits";

/**
 * A wake-up after the mentor's chat has sat idle: it looks for follow-ups it
 * owes the learner and proposes them. It runs the way a habit does, in a
 * hidden session that posts to the chat only when it has something to say.
 */

/** Its posts carry this as their habit id; no stored habit uses it. */
export const HEARTBEAT_ID = "heartbeat";
export const HEARTBEAT_NAME = "Heartbeat";
export const DEFAULT_HEARTBEAT_MINUTES = 30;
/** 0 turns it off. */
export const HEARTBEAT_INTERVALS = [0, 15, 30, 60, 120] as const;
const MAX_INTERVAL_MS = 4 * 60 * 60_000;
const QUIET_BEFORE_BACKOFF = 3;
const RECENT_KEPT = 5;
const RECENT_CHARS = 300;

/** heartbeat.json, beside habits.json in the app's data folder. */
export type HeartbeatState = {
  /** Idle minutes before it wakes; absent means the default, 0 is off. */
  minutes?: number;
  /** When it last ran or was skipped: the cursor for what is new. */
  lastRunAt: number;
  /** Model runs in a row that found nothing; the interval backs off. */
  quietStreak: number;
  /** What it raised lately, newest first, so it does not raise it again. */
  recent: string[];
  /** MEMORY.md as the last run saw it; a change is a new follow-up to look at. */
  memoryHash?: string;
};

const isNumber = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v) && v >= 0;

export function parseHeartbeat(text: string | null | undefined): HeartbeatState {
  let value: Record<string, unknown> = {};
  try {
    const parsed: unknown = text?.trim() ? JSON.parse(text) : {};
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) value = parsed as Record<string, unknown>;
  } catch {
    // A broken file starts over rather than stopping the heartbeat.
  }
  // Keys this version does not know stay, for whoever wrote them.
  const { minutes, memoryHash, ...rest } = value;
  return {
    ...rest,
    ...(isNumber(minutes) ? { minutes } : {}),
    lastRunAt: isNumber(value.lastRunAt) ? value.lastRunAt : 0,
    quietStreak: isNumber(value.quietStreak) ? value.quietStreak : 0,
    recent: Array.isArray(value.recent) ? value.recent.filter((item): item is string => typeof item === "string").slice(0, RECENT_KEPT) : [],
    ...(typeof memoryHash === "string" ? { memoryHash } : {}),
  };
}

export function serializeHeartbeat(state: HeartbeatState): string {
  return `${JSON.stringify(state, null, 2)}\n`;
}

export function heartbeatMinutes(state: Pick<HeartbeatState, "minutes">): number {
  return state.minutes ?? DEFAULT_HEARTBEAT_MINUTES;
}

/** After three quiet runs in a row each doubles the wait, up to four hours. */
export function heartbeatIntervalMs(minutes: number, quietStreak: number): number {
  const base = minutes * 60_000;
  if (quietStreak < QUIET_BEFORE_BACKOFF) return base;
  const doubled = base * 2 ** Math.min(quietStreak - (QUIET_BEFORE_BACKOFF - 1), 4);
  return Math.min(doubled, Math.max(base, MAX_INTERVAL_MS));
}

/** Hidden prompts the app sends in the user's place are not the user. */
const fromUser = (block: Block) =>
  block.role === "user" && !block.draft && !block.agentSessionCompletion && !block.agentSetup;

/**
 * When the chat last moved, and when the user last wrote. The heartbeat's own
 * posts do not count, or each one would wake the next.
 */
export function chatActivity(blocks: readonly Block[]): { lastAt: number; lastUserAt: number } {
  let lastAt = 0;
  let lastUserAt = 0;
  for (const block of blocks) {
    if (block.agentHabit) {
      if (block.agentHabit.id !== HEARTBEAT_ID) lastAt = Math.max(lastAt, block.agentHabit.at);
      continue;
    }
    if (block.role !== "user" || block.startedAt == null) continue;
    const at = block.startedAt + (block.durationMs ?? 0);
    lastAt = Math.max(lastAt, at);
    if (fromUser(block)) lastUserAt = Math.max(lastUserAt, block.startedAt);
  }
  return { lastAt, lastUserAt };
}

export type HeartbeatPlan =
  /** Off, not idle long enough, or the chat is busy: nothing to do or save. */
  | { kind: "wait" }
  /** Save `state`; nothing to ask the model. */
  | { kind: "skip"; state: HeartbeatState }
  /** Save `state`, then run. */
  | { kind: "run"; state: HeartbeatState };

/**
 * Whether to wake now. The first look after it is turned on only marks where
 * it starts; after that it waits for the chat to sit idle for the interval,
 * and asks the model only when the chat or memory moved since last time.
 */
export function planHeartbeat(
  state: HeartbeatState,
  chat: { blocks: readonly Block[]; busy?: boolean },
  memoryHash: string,
  now: number,
): HeartbeatPlan {
  const minutes = heartbeatMinutes(state);
  if (minutes <= 0 || chat.busy) return { kind: "wait" };
  if (state.lastRunAt <= 0) return { kind: "skip", state: { ...state, lastRunAt: now, memoryHash } };
  const { lastAt, lastUserAt } = chatActivity(chat.blocks);
  // The user writing in its chat starts the back-off over.
  const quietStreak = lastUserAt > state.lastRunAt ? 0 : state.quietStreak;
  if (now - Math.max(state.lastRunAt, lastAt) < heartbeatIntervalMs(minutes, quietStreak)) return { kind: "wait" };
  const next = { ...state, lastRunAt: now, quietStreak, memoryHash };
  const changed = lastAt > state.lastRunAt || memoryHash !== state.memoryHash;
  return changed ? { kind: "run", state: next } : { kind: "skip", state: next };
}

/** The state after a run: what it raised is remembered, quiet runs add up. */
export function afterHeartbeat(state: HeartbeatState, outcome: { ok: boolean; report?: string }): HeartbeatState {
  if (outcome.report) {
    const raised = outcome.report.replace(/\s+/g, " ").trim();
    return {
      ...state,
      quietStreak: 0,
      recent: [raised.length > RECENT_CHARS ? `${raised.slice(0, RECENT_CHARS - 1)}…` : raised, ...state.recent].slice(0, RECENT_KEPT),
    };
  }
  return outcome.ok ? { ...state, quietStreak: state.quietStreak + 1 } : state;
}

/** The last two exchanges, shortened: what the two were in the middle of. */
export function recentExchanges(blocks: readonly Block[]): string {
  const exchanges: { user: string; agent: string }[] = [];
  for (const block of blocks) {
    if (fromUser(block)) exchanges.push({ user: block.text, agent: "" });
    else if (block.role === "assistant" && !block.agentHabit && exchanges.length) {
      const last = exchanges[exchanges.length - 1];
      last.agent = last.agent ? `${last.agent}\n${block.text}` : block.text;
    }
  }
  return exchanges.slice(-2).map(({ user, agent }) => {
    const said = `User: ${clip(user, 400)}`;
    return agent.trim() ? `${said}\nYou: ${clip(agent, 800)}` : said;
  }).join("\n\n");
}

function clip(text: string, max: number): string {
  const flat = text.trim();
  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

const GUIDANCE = `[Heartbeat] An inactivity wake-up from Loci, not a message from the learner. You run in a side session; the learner sees nothing unless you report.

Do one round:
1. Reread your soul's standing instructions for anything you are meant to keep an eye on.
2. Review your memory and the recent chat below for things you promised the learner and have not followed up on: a source you said you would find, an explanation you said you would come back to, a question left open.

A heartbeat does not authorize changes. Do not edit files, memory or courses, start sessions or run anything that changes state; propose it instead, in a short, specific message to the learner. At most 2 proposals.

Never quiz the learner, plan reviews or spaced repetition, or set mastery gates or scores. Never invent work to fill the interval, and never raise something you raised recently unless it changed. If nothing is worth raising, reply exactly ${QUIET_MARKER}.`;

/** The first message of a heartbeat's hidden run. */
export function heartbeatPrompt(
  look: AgentLook,
  files: AgentFiles,
  state: HeartbeatState,
  exchanges: string,
  now: number,
): string {
  const parts = [agentContext(look, files, { soul: true, memory: true }), GUIDANCE];
  if (exchanges.trim()) parts.push(`Recent chat with the learner:\n${exchanges.trim()}`);
  if (state.recent.length) parts.push(`You raised these lately:\n${state.recent.map((item) => `- ${item}`).join("\n")}`);
  parts.push(`Local time: ${new Date(now).toLocaleString()}`);
  return parts.join("\n\n");
}

/**
 * A smaller, faster model of the chat's provider (and, in a provider of
 * providers, the same upstream) for deciding whether anything is worth
 * raising, picked the way the text helpers pick one. None in the catalog
 * keeps the chat's own.
 */
export function heartbeatModel(
  harness: HarnessId,
  current: string,
  settings: Record<string, string>,
): { model: string; modelSettings: Record<string, string> } {
  const upstream = findModel(current)?.provider?.id;
  const light = modelsFor(harness).find((model) =>
    (!upstream || model.provider?.id === upstream) &&
    /haiku|mini|flash|nano|lite|luna/i.test(`${model.nativeId ?? ""} ${model.name} ${model.id}`));
  return light ? { model: light.id, modelSettings: mergeModelSettings(light, settings) } : { model: current, modelSettings: settings };
}

export async function loadHeartbeat(agentId: string): Promise<HeartbeatState> {
  return parseHeartbeat((await readAgentFile(agentId, "heartbeat.json")).text);
}

/** Change heartbeat.json over the version read, again if another save came between. */
export async function updateHeartbeat(
  agentId: string,
  change: (state: HeartbeatState) => HeartbeatState,
): Promise<HeartbeatState> {
  let result: HeartbeatState | undefined;
  await editAgentFile(agentId, "heartbeat.json", (text) => {
    result = change(parseHeartbeat(text));
    return serializeHeartbeat(result);
  });
  return result!;
}

/** Turning it back on starts from now, not from when it was last on. */
export function setHeartbeatMinutes(agentId: string, minutes: number): Promise<HeartbeatState> {
  return updateHeartbeat(agentId, (state) => {
    const wasOff = heartbeatMinutes(state) <= 0;
    const next = { ...state, minutes };
    return wasOff && minutes > 0 ? { ...next, lastRunAt: 0, quietStreak: 0 } : next;
  });
}
