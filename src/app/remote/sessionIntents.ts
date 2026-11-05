import type { Dispatch, SetStateAction } from "react";
import type { Session } from "../../features/sessions/model/session";
import type { AgentTemplate } from "../../features/agents/templates";
import { applyAgentChanges, reorderAgents, type Agent } from "../../features/agents/model/agent";
import type { SessionSubmission } from "../hooks/useSessionSubmission";
import type { SessionStore } from "../hooks/useSessionStore";
import type { useAgents } from "../hooks/useAgents";
import type { useAgentHabits } from "../hooks/useAgentHabits";

type Agents = Pick<ReturnType<typeof useAgents>, "chat" | "create" | "reset" | "remove">;

type IntentSources = {
  submission: SessionSubmission;
  agents: Agents;
  agentHabits: Pick<ReturnType<typeof useAgentHabits>, "approve">;
  store: Pick<SessionStore, "archiveSession" | "removeSession">;
  updateSessions: Dispatch<SetStateAction<Session[]>>;
  /** The host's roster, changed field by field for a connected window. */
  roster?: { update: typeof applyAgentChanges; reorder: typeof reorderAgents };
};

/**
 * Everything a person can do to a session, by name. The window's own panes
 * take their callbacks from here, and a connected device's intents run the
 * same entries, so both drive a session the same way.
 */
export function sessionIntents({ submission, agents, agentHabits, store, updateSessions,
  roster = { update: applyAgentChanges, reorder: reorderAgents } }: IntentSources) {
  return {
    "session.submit": submission.onSubmit,
    "session.stop": submission.stop,
    // An approval a habit's hidden run asked for goes back to that run.
    "session.approve": agentHabits.approve,
    "session.answer": submission.answer,
    "session.keepQuestionOpen": submission.keepQuestionOpen,
    "session.changeModel": submission.changeModel,
    "session.changeModelSettings": submission.changeModelSettings,
    "session.changeRuntimeMode": submission.changeRuntimeMode,
    "session.compact": submission.compact,
    "session.saveDraft": submission.saveDraft,
    "session.removeDraft": submission.removeDraft,
    "session.queue.delete": submission.deleteQueuedMessage,
    "session.queue.edit": submission.editQueuedMessage,
    "session.queue.editing": submission.queuedMessageEditingChange,
    "session.queue.steer": submission.steerQueuedMessage,
    "session.queue.resume": submission.resumeQueue,
    "session.usageLimit.resume": submission.usageLimitResume,
    "session.usageLimit.resumeAtReset": submission.usageLimitResumeAtReset,
    "session.usageLimit.dismiss": submission.usageLimitDismiss,
    "session.btw.submit": submission.btwSubmit,
    "session.btw.retry": submission.btwRetry,
    "session.btw.stop": submission.btwStop,
    "session.btw.delete": submission.btwDelete,
    "session.btw.modelChange": submission.btwModelChange,
    "session.dismissNoteCard": (sessionId: string) =>
      updateSessions((current) => current.map((entry) => entry.id === sessionId ? { ...entry, noteCard: undefined } : entry)),
    "session.archive": store.archiveSession,
    "session.delete": store.removeSession,
    /** The agent's conversation, loaded into memory without changing what this window shows. */
    "agent.open": async (agentId: string) => (await agents.chat(agentId))?.id ?? null,
    "agent.create": (template?: AgentTemplate) => agents.create(template, { show: false }),
    "agent.reset": (agentId: string) => agents.reset(agentId),
    "agent.remove": (agentId: string, options?: { confirmed?: boolean }) => agents.remove(agentId, options),
    /** A connected window's change to one agent: only the fields it changed (`agentChanges`). */
    "agent.update": (agentId: string, changed: Partial<Agent>, removed: string[]) => { roster.update(agentId, changed, removed); },
    "agent.reorder": (ids: string[]) => roster.reorder(ids),
  };
}

export type SessionIntents = ReturnType<typeof sessionIntents>;

/**
 * Intents that ask before they destroy something. The device that sent one
 * asks its user first and says so with `{ confirmed: true }` as the last
 * argument; the host never opens a dialog for another device.
 */
export const CONFIRMED_INTENTS: ReadonlySet<string> = new Set(["agent.reset", "agent.remove", "session.delete"]);
