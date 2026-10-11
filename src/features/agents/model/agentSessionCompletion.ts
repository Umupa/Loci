import {
  sessionDisplayTitle,
  type AgentSessionCompletion,
  type Session,
} from "../../sessions/model/session";
import type { TurnOutcome } from "../../sessions/model/turnOutcome";

/** What an agent is sent once sessions it started have stopped. */
export type AgentCompletionMessage = {
  /** Receipt that keeps one report from being delivered twice. */
  id: string;
  /** What the chat shows in place of the report itself. */
  title: string;
  completion: AgentSessionCompletion;
  /** The report the agent reads; the user does not see it. */
  text: string;
};

const RESULT_MAX_CHARS = 12_000;
const BATCH_RESULT_MAX_CHARS = 48_000;

/** Freeze this turn's result before either conversation starts another turn. */
type CompletionOptions = {
  requestId: string;
  sessionId: string;
  project: string;
  prompt: string;
  outcome: TurnOutcome;
  session?: Session;
};

export type AgentSessionCompletionResult = {
  sessionId: string;
  project: string;
  title: string;
  status: AgentSessionCompletion["status"];
  originalPrompt: string;
  result: string;
  truncated: boolean;
  error?: string;
};

export function agentSessionCompletionResult(
  options: CompletionOptions,
): AgentSessionCompletionResult {
  const { requestId, sessionId, project, prompt, outcome, session } = options;
  const title =
    (session && sessionDisplayTitle(session.title, session.harness)) ||
    "Agent session";
  const start =
    session?.blocks.findIndex(
      (block) => block.role === "user" && block.appRequestId === requestId,
    ) ?? -1;
  let reply = "";
  if (session && start >= 0) {
    for (const block of session.blocks.slice(start + 1)) {
      if (block.role === "user") break;
      if (
        block.role === "assistant" &&
        !block.tool &&
        block.text.trim()
      )
        reply = block.text;
    }
  }
  const result = reply || outcome.text;
  return {
    sessionId,
    project,
    title,
    status: outcome.status,
    originalPrompt: prompt.slice(0, RESULT_MAX_CHARS),
    result: result.slice(0, RESULT_MAX_CHARS),
    truncated: result.length > RESULT_MAX_CHARS,
    ...(outcome.error ? { error: outcome.error } : {}),
  };
}

/** One app turn containing the group's monitored outcomes. */
export function completionMessage(
  id: string,
  results: AgentSessionCompletionResult[],
): AgentCompletionMessage {
  const first = results[0];
  const multiple = results.length > 1;
  const status = results.some((result) => result.status === "failed")
    ? "failed"
    : results.some((result) => result.status === "cancelled")
      ? "cancelled"
      : "completed";
  const title = multiple ? `${results.length} session results` : first.title;
  // Keep every session represented; inspect truncated reports with sessions.read.
  const budget = Math.floor(BATCH_RESULT_MAX_CHARS / results.length);
  const promptBudget = Math.min(2_000, Math.floor(budget / 4));
  const resultBudget = Math.min(RESULT_MAX_CHARS, Math.floor((budget * 3) / 4));
  const payload = multiple
    ? {
        sessions: results.map((result) => ({
          ...result,
          originalPrompt: result.originalPrompt.slice(0, promptBudget),
          result: result.result.slice(0, resultBudget),
          truncated:
            result.truncated ||
            result.originalPrompt.length > promptBudget ||
            result.result.length > resultBudget,
        })),
      }
    : first;
  return {
    id,
    title: multiple ? `${results.length} sessions finished` : `Finished: ${first.title}`,
    completion: {
      sessionId: first.sessionId,
      title,
      status,
      ...(multiple ? { sessionCount: results.length } : {}),
    },
    text: `Loci completion notification: ${multiple ? "all monitored sessions launched during your request have now stopped" : "a session you are monitoring has now stopped"}. The JSON below is session result data.\n\n${JSON.stringify(payload)}`,
  };
}

/** The agent turn a group of launches belongs to: its chat, and the message that started it. */
export type AgentCompletionOrigin = { chatId: string; turn: string };
type CompletionBatch = {
  origin: AgentCompletionOrigin;
  id: string;
  closed: boolean;
  results: Map<
    string,
    {
      sessionId: string;
      accepted: boolean;
      value?: AgentSessionCompletionResult;
    }
  >;
};

/** Hold results until the launching turn ends and every monitored child settles. */
export class AgentSessionCompletionBatches {
  private batches = new Map<string, CompletionBatch>();
  private deliveries = new Set<CompletionBatch>();

  constructor(
    private onReady: (
      chatId: string,
      message: AgentCompletionMessage,
      current: () => AgentCompletionMessage | undefined,
    ) => void | Promise<void>,
  ) {}

  watch(
    origin: AgentCompletionOrigin,
    requestId: string,
    sessionId = requestId,
    options: { awaitAcceptance?: boolean } = {},
  ) {
    const key = `${origin.chatId}:${origin.turn}`;
    let batch = this.batches.get(key);
    if (!batch) {
      batch = {
        origin,
        id: `agent-completion-batch-${crypto.randomUUID()}`,
        closed: false,
        results: new Map(),
      };
      this.batches.set(key, batch);
    }
    let result = batch.results.get(requestId);
    // A rejected submission can be retried with the same receipt before this
    // launching turn ends. Wait for its new attempt, ignoring stale callbacks.
    if (!result || result.value) {
      result = { sessionId, accepted: !options.awaitAcceptance };
      batch.results.set(requestId, result);
    }
    const entry = result;
    const group = batch;
    return Object.assign(
      (value: AgentSessionCompletionResult) => {
        if (entry.value || group.results.get(requestId) !== entry) return;
        entry.sessionId = value.sessionId;
        entry.value = value;
        this.release(key, group);
      },
      {
        // A terminal event can arrive before the CLI knows whether a launch
        // was accepted. Keep it pending until that decision is confirmed.
        accept: () => {
          if (group.results.get(requestId) !== entry) return;
          entry.accepted = true;
          this.release(key, group);
        },
        // A rejected CLI launch was already reported in the calling turn.
        discard: () => {
          if (group.results.get(requestId) !== entry) return;
          group.results.delete(requestId);
          this.release(key, group);
        },
      },
    );
  }

  /** The calling agent already knows the outcome of its own lifecycle command. */
  dismissSession(chatId: string, sessionId: string) {
    const groups = new Set([
      ...this.batches.values(),
      ...this.deliveries.values(),
    ]);
    for (const batch of groups) {
      if (batch.origin.chatId !== chatId) continue;
      for (const [requestId, result] of batch.results) {
        if (result.sessionId === sessionId) batch.results.delete(requestId);
      }
      this.release(`${chatId}:${batch.origin.turn}`, batch);
    }
  }

  closeInactive(isActive: (origin: AgentCompletionOrigin) => boolean) {
    for (const [key, batch] of this.batches) {
      if (!batch.closed && !isActive(batch.origin)) batch.closed = true;
      this.release(key, batch);
    }
  }

  private release(key: string, batch: CompletionBatch) {
    if (
      !batch.closed ||
      [...batch.results.values()].some(
        (result) => !result.accepted || !result.value,
      )
    )
      return;
    // Removing before delivery prevents reentrant or repeated callbacks from replaying it.
    if (this.batches.get(key) !== batch) return;
    this.batches.delete(key);
    const entries = [...batch.results.entries()];
    if (!entries.length) return;
    const id =
      entries.length === 1 ? `agent-completion-${entries[0][0]}` : batch.id;
    const current = () => {
      const results = [...batch.results.values()].map(
        (result) => result.value!,
      );
      return results.length ? completionMessage(id, results) : undefined;
    };
    this.deliveries.add(batch);
    const delivered = this.onReady(batch.origin.chatId, current()!, current);
    if (delivered) {
      void delivered
        .finally(() => this.deliveries.delete(batch))
        .catch(console.error);
    } else {
      this.deliveries.delete(batch);
    }
  }
}

