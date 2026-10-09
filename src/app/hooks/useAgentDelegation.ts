import { useCallback, useEffect, useRef } from "react";
import { hasPendingApproval, type Session } from "../../features/sessions/model/session";
import type { TurnOutcome } from "../../features/sessions/model/turnOutcome";
import {
  AgentSessionCompletionBatches, agentSessionCompletionResult, completionMessage,
  type AgentCompletionMessage,
} from "../../features/agents/model/agentSessionCompletion";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

type Options = {
  runtime: SessionRuntime;
  submission: SessionSubmission;
  /** A saved conversation by id, from memory or the store. */
  loadSession: (id: string) => Promise<Session | null>;
};

/** The message that started the agent's current turn, which groups what it launches. */
export function agentTurnId(chat: Pick<Session, "blocks">): string {
  for (let i = chat.blocks.length - 1; i >= 0; i--) {
    const block = chat.blocks[i];
    if (block.role === "user" && !block.draft) return block.id;
  }
  return "";
}

/**
 * Reports delegated work back to the agent that started it. Sessions an agent
 * launches in one turn form a group; once that turn has ended and every one
 * of them has stopped, the agent gets their results together as a new turn,
 * as soon as it is idle.
 */
export function useAgentDelegation(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const { sessions } = options.runtime;
  /** Reports ready for a chat that is still busy, oldest first. */
  const waiting = useRef(new Map<string, AgentCompletionMessage[]>());
  const delivering = useRef(new Set<string>());

  const session = (id: string) => latest.current.runtime.sessionsRef.current.find((entry) => entry.id === id);

  const deliver = useCallback(async (chatId: string) => {
    if (delivering.current.has(chatId)) return;
    const next = waiting.current.get(chatId)?.[0];
    if (!next) return;
    delivering.current.add(chatId);
    try {
      const { runtime, submission, loadSession } = latest.current;
      let chat = session(chatId);
      if (!chat) {
        // Put away while idle: bring it back to receive its report.
        const saved = await loadSession(chatId);
        if (!saved) { waiting.current.delete(chatId); return; }
        runtime.bindRestoredSession(saved);
        runtime.updateSessions((current) => current.some((entry) => entry.id === chatId) ? current : [...current, saved]);
        chat = session(chatId);
      }
      // It must never steer the agent's own work or jump ahead of the user's messages.
      if (!chat || chat.busy || chat.pendingQuestion || hasPendingApproval(chat.blocks) || chat.queuedMessages?.length) return;
      const done = () => {
        const rest = (waiting.current.get(chatId) ?? []).filter((message) => message.id !== next.id);
        if (rest.length) waiting.current.set(chatId, rest);
        else waiting.current.delete(chatId);
      };
      if (chat.blocks.some((block) => block.appRequestId === next.id)) { done(); return; }
      const accepted = await submission.submit(chatId, next.title, [], {
        appRequestId: next.id, agentCompletion: { completion: next.completion, report: next.text },
      });
      if (accepted) done();
    } finally {
      delivering.current.delete(chatId);
    }
  }, []);

  const batches = useRef<AgentSessionCompletionBatches | null>(null);
  if (!batches.current) {
    batches.current = new AgentSessionCompletionBatches((chatId, message) => {
      const queue = waiting.current.get(chatId) ?? [];
      if (!queue.some((entry) => entry.id === message.id)) waiting.current.set(chatId, [...queue, message]);
      void deliver(chatId);
    });
  }

  // A group closes when the turn that launched it ends; reports go out once their chat is idle.
  useEffect(() => {
    batches.current!.closeInactive(({ chatId, turn }) => {
      const chat = session(chatId);
      return !!chat?.busy && agentTurnId(chat) === turn;
    });
    for (const chatId of waiting.current.keys()) void deliver(chatId);
  }, [sessions, deliver]);

  /**
   * Watches one launch or follow-up for the agent's current turn. The result
   * settles it; `accept` confirms the submission went through, and `discard`
   * drops one that was rejected and already reported to the agent.
   */
  const monitor = useCallback((chatId: string, requestId: string, sessionId: string, project: string, prompt: string) => {
    const chat = session(chatId);
    const settle = batches.current!.watch({ chatId, turn: chat ? agentTurnId(chat) : "" }, requestId, sessionId, { awaitAcceptance: true });
    return Object.assign(
      (outcome: TurnOutcome) => settle(agentSessionCompletionResult({ requestId, sessionId, project, prompt, outcome, session: session(sessionId) })),
      { accept: settle.accept, discard: settle.discard },
    );
  }, []);

  /** The agent stopped, archived or deleted the session itself, so it expects no report on it. */
  const dismiss = useCallback((chatId: string, sessionId: string) => {
    batches.current!.dismissSession(chatId, sessionId);
    const queue = waiting.current.get(chatId);
    if (!queue) return;
    const rest = queue.flatMap((message) => {
      if (message.completion.sessionCount && message.completion.sessionCount > 1) {
        const results = reportsIn(message).filter((result) => result.sessionId !== sessionId);
        return results.length ? [completionMessage(message.id, results)] : [];
      }
      return message.completion.sessionId === sessionId ? [] : [message];
    });
    if (rest.length) waiting.current.set(chatId, rest);
    else waiting.current.delete(chatId);
  }, []);

  return { monitor, dismiss };
}

/** The reports a batched notification carries, read back from its payload. */
function reportsIn(message: AgentCompletionMessage): Parameters<typeof completionMessage>[1] {
  const separator = message.text.indexOf("\n\n");
  try {
    const payload = JSON.parse(message.text.slice(separator + 2)) as { sessions?: Parameters<typeof completionMessage>[1] };
    return Array.isArray(payload.sessions) ? payload.sessions : [];
  } catch {
    return [];
  }
}

export type AgentDelegation = ReturnType<typeof useAgentDelegation>;
