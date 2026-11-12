import { useCallback, useEffect, useRef } from "react";
import { forgetHarnessSession, respondHarnessApproval } from "../../integrations/harness/core/registry";
import type { ApprovalDecision } from "../../integrations/harness/core/types";
import { sessionChildHarnesses } from "../../features/sessions/model/handoff";
import { newSession, type Block, type RuntimeMode, type Session } from "../../features/sessions/model/session";
import type { TurnOutcome } from "../../features/sessions/model/turnOutcome";
import { agentForSession, agentLook, findAgent, listAgents, type AgentLook } from "../../features/agents/model/agent";
import { loadAgentFiles } from "../../features/agents/model/agentFiles";
import {
  clearWakeRun, dropRelays, isRelayed, markWakeRun, relayApproval, takeRelayedApproval, wakeReport,
  WAKE_APPROVAL_WAIT_MS, WAKE_RUN_TIMEOUT_MS,
} from "../../features/agents/model/agentWake";
import {
  afterHeartbeat, chatActivity, HEARTBEAT_ID, HEARTBEAT_NAME, heartbeatMinutes, heartbeatModel, heartbeatPrompt, loadHeartbeat,
  planHeartbeat, recentExchanges, updateHeartbeat,
} from "../../features/agents/model/agentHeartbeat";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

const TICK_MS = 60_000;
const POLL_MS = 2_000;
/** How often a post waits for the agent to finish replying before it lands anyway. */
const POST_RETRY_MS = 5_000;
const POST_RETRIES = 120;

/**
 * Only the newest scheduler runs heartbeats. A hot reload in development can
 * leave an older copy of this hook running beside the new one, with its own
 * idea of what is running; the newest claims the window and the rest stop.
 */
const OWNER = "__agentHeartbeatScheduler";
type OwnedWindow = Window & { [OWNER]?: symbol };

type Options = {
  runtime: SessionRuntime;
  submission: SessionSubmission;
  /** A saved conversation by id, from memory or the store. */
  loadSession: (id: string) => Promise<Session | null>;
  /** A heartbeat told the user something in its agent's chat. */
  onPosted?: (chat: Session, agentName: string) => void;
};

/** What a hidden run posts as, in the agent's chat. */
type RunTag = { id: string; name: string };

/**
 * Runs each agent's heartbeat once its chat has sat idle, while the app is
 * open: in a hidden session of its own, posting to the agent's chat only
 * when the run has something to say. One run at a time across all agents
 * keeps a wake from sleep from starting several at once.
 */
export function useAgentHeartbeat(options: Options, enabled = true) {
  const latest = useRef(options);
  latest.current = options;

  const session = (id: string) => latest.current.runtime.sessionsRef.current.find((entry) => entry.id === id);

  /** The agent's chat in memory; one put away while idle is brought back from the store. */
  const openChat = useCallback(async (chatId: string) => {
    const open = session(chatId);
    if (open) return open;
    const { runtime, loadSession } = latest.current;
    const saved = await loadSession(chatId);
    if (!saved) return undefined;
    runtime.bindRestoredSession(saved);
    runtime.updateSessions((current) => current.some((entry) => entry.id === chatId) ? current : [...current, saved]);
    return session(chatId);
  }, []);

  /** Adds a block to an agent's chat outside any turn, once no reply is streaming. */
  const appendToChat = useCallback(async (chatId: string, block: Block, then?: (chat: Session) => void, attempt = 0) => {
    const chat = await openChat(chatId).catch(() => undefined);
    if (!chat) return;
    if (chat.busy && attempt < POST_RETRIES) {
      window.setTimeout(() => void appendToChat(chatId, block, then, attempt + 1), POST_RETRY_MS);
      return;
    }
    const { runtime } = latest.current;
    runtime.updateSessions((current) => current.map((entry) => entry.id === chatId ? { ...entry, blocks: [...entry.blocks, block] } : entry));
    void runtime.persistSession(chatId).catch(() => undefined);
    const posted = session(chatId);
    if (posted) then?.(posted);
  }, [openChat]);

  const decideBlock = useCallback((chatId: string, blockId: string, decided: "allow" | "deny" | "cancelled") => {
    const { runtime } = latest.current;
    runtime.updateSessions((current) => current.map((entry) => entry.id === chatId ? {
      ...entry,
      blocks: entry.blocks.map((block) => block.id === blockId && block.approval ? { ...block, approval: { ...block.approval, decided } } : block),
    } : entry));
    void runtime.persistSession(chatId).catch(() => undefined);
  }, []);

  /**
   * Answers an approval in an agent's chat. One a hidden run asked
   * for goes back to that run; any other is the conversation's own.
   */
  const approve = useCallback((sessionId: string, requestId: number, decision: ApprovalDecision) => {
    const chat = session(sessionId);
    const asked = chat && agentForSession(sessionId)
      ? chat.blocks.find((block) => block.agentHabit && block.approval?.requestId === requestId) : undefined;
    if (!asked) {
      latest.current.submission.approve(sessionId, requestId, decision);
      return;
    }
    const relay = takeRelayedApproval(sessionId, requestId);
    const run = relay ? session(relay.runId) : undefined;
    if (relay && run) respondHarnessApproval(run.harness, run.id, relay.requestId, decision);
    decideBlock(sessionId, asked.id, relay && run ? (decision === "deny" ? "deny" : "allow") : "cancelled");
  }, [decideBlock]);

  useEffect(() => {
    if (!enabled) return;
    const owner = Symbol("agent-heartbeat");
    (window as OwnedWindow)[OWNER] = owner;
    let stopped = false;
    let running = false;
    // A check that came mid-run happens as soon as that run ends.
    let checkAgain = false;

    /**
     * Sends the run's turn and waits for it, relaying any approval it asks
     * for to the agent's chat. Only time spent working counts toward the
     * timeout; time waiting on the user has its own, much longer limit.
     */
    const watchRun = async (chatId: string, tag: RunTag, runId: string, start: () => Promise<TurnOutcome>): Promise<TurnOutcome> => {
      let settled: TurnOutcome | undefined;
      const turn = start().then((outcome) => (settled = outcome),
        (error: unknown) => (settled = { status: "failed", text: "", error: error instanceof Error ? error.message : String(error) }));
      let working = 0;
      let waiting = 0;
      while (!settled) {
        await Promise.race([turn, new Promise((resolve) => setTimeout(resolve, POLL_MS))]);
        if (settled) break;
        const pending = session(runId)?.blocks.filter((block) => block.approval && !block.approval.decided) ?? [];
        for (const block of pending) {
          if (isRelayed(runId, block.approval!.requestId)) continue;
          // The chat shows it like any approval; the answer is routed back in `approve`.
          const blockId = crypto.randomUUID();
          const requestId = relayApproval({ chatId, runId, requestId: block.approval!.requestId, blockId });
          void appendToChat(chatId, {
            id: blockId, role: "approval", text: block.text, ...(block.tool ? { tool: block.tool } : {}),
            approval: { requestId }, agentHabit: { id: tag.id, name: tag.name, at: Date.now() },
          });
        }
        if (pending.length) waiting += POLL_MS;
        else working += POLL_MS;
        if (working >= WAKE_RUN_TIMEOUT_MS || waiting >= WAKE_APPROVAL_WAIT_MS) {
          return { status: "failed", text: "",
            error: waiting >= WAKE_APPROVAL_WAIT_MS ? "Nobody answered its approval request." : "It took too long and was stopped." };
        }
      }
      return settled;
    };

    const removeRun = async (runId: string) => {
      const { runtime, submission } = latest.current;
      const run = session(runId);
      await submission.stopSessionWork(runId).catch(() => undefined);
      if (run) await Promise.all(sessionChildHarnesses(run).map((harness) => forgetHarnessSession(harness, runId).catch(() => undefined)));
      runtime.updateSessions((current) => current.filter((entry) => entry.id !== runId));
    };

    /** One hidden run for the agent's chat, its report posted there when it has one. */
    const runHidden = async (agentId: string, chat: Session, look: AgentLook, tag: RunTag, setup: {
      model: string; modelSettings: Record<string, string>; mode: RuntimeMode; prompt: string; startedAt: number;
    }): Promise<{ outcome: TurnOutcome; report?: string }> => {
      const { runtime, submission } = latest.current;
      const run: Session = {
        ...newSession(chat.harness, chat.cwd, setup.model, setup.mode, setup.modelSettings),
        title: `${look.name} · ${tag.name}`,
        ephemeral: true,
      };
      markWakeRun(run.id, agentId);
      runtime.updateSessions((current) => [...current, run]);
      const outcome = await watchRun(chat.id, tag, run.id,
        () => submission.runTurn(run.id, setup.prompt, { appAccess: true }))
        .catch((error: unknown): TurnOutcome => ({ status: "failed", text: "", error: error instanceof Error ? error.message : String(error) }));
      for (const relay of dropRelays(run.id)) decideBlock(relay.chatId, relay.blockId, "cancelled");
      await removeRun(run.id);
      clearWakeRun(run.id);

      const report = outcome.status === "completed" ? wakeReport(outcome.text) : undefined;
      if (report) {
        void appendToChat(chat.id, { id: crypto.randomUUID(), role: "assistant", text: report, agentHabit: { ...tag, at: Date.now() } },
          (posted) => latest.current.onPosted?.(posted, look.name));
      }
      return { outcome, ...(report ? { report } : {}) };
    };

    /**
     * The agent's heartbeat, if its chat has sat idle long enough and moved
     * since the last one. A quiet result is dropped; the chat never sees it.
     */
    // Agents whose heartbeat has been looked at since the app started.
    const looked = new Set<string>();
    const beat = async (agentId: string, chatId: string) => {
      // Only the first look after the app starts may find runs missed while it was closed.
      const first = !looked.has(agentId);
      looked.add(agentId);
      const state = await loadHeartbeat(agentId);
      const minutes = heartbeatMinutes(state);
      // Cheap first: nothing is due before a whole interval has passed.
      if (minutes <= 0 || (state.lastRunAt > 0 && Date.now() - state.lastRunAt < minutes * 60_000)) return;
      // A chat put away is read, not brought back, until there is something to post.
      const chat = session(chatId) ?? await latest.current.loadSession(chatId);
      if (!chat || stopped) return;
      const files = await loadAgentFiles(agentId);
      const record = findAgent(agentId);
      if (stopped || !record) return;
      const now = Date.now();
      const plan = planHeartbeat(state, chat, files.memoryHash, now, first);
      if (plan.kind === "wait") return;
      const { lastRunAt, quietStreak, memoryHash } = plan.state;
      // Over the latest file, so an interval changed meanwhile stays.
      const claimed = await updateHeartbeat(agentId, (current) => ({ ...current, lastRunAt, quietStreak, ...(memoryHash ? { memoryHash } : {}) }));
      if (plan.kind === "skip" || stopped) return;
      const look = agentLook(record);
      const { outcome, report } = await runHidden(agentId, chat, look, { id: HEARTBEAT_ID, name: HEARTBEAT_NAME }, {
        ...heartbeatModel(chat.harness, chat.model, chat.modelSettings),
        mode: chat.runtimeMode,
        prompt: heartbeatPrompt(look, files, claimed, recentExchanges(chat.blocks), now, chatActivity(chat.blocks).lastUserAt),
        startedAt: now,
      });
      await updateHeartbeat(agentId, (current) => afterHeartbeat(current, { ok: outcome.status === "completed", ...(report ? { report } : {}) }));
    };

    const tick = async () => {
      if ((window as OwnedWindow)[OWNER] !== owner) stopped = true;
      if (stopped) return;
      if (running) { checkAgain = true; return; }
      running = true;
      checkAgain = false;
      try {
        for (const { id, sessionId } of listAgents()) {
          if (stopped) return;
          // A chat never opened has nothing to follow up.
          if (!sessionId) continue;
          await beat(id, sessionId).catch((error) => console.warn("Heartbeat could not run", error));
        }
      } catch (error) {
        console.warn("Could not check agent heartbeats", error);
      } finally {
        running = false;
        if (checkAgain && !stopped) void tick();
      }
    };

    void tick();
    const timer = window.setInterval(() => void tick(), TICK_MS);
    return () => {
      stopped = true;
      window.clearInterval(timer);
      if ((window as OwnedWindow)[OWNER] === owner) delete (window as OwnedWindow)[OWNER];
    };
  }, [enabled, appendToChat, decideBlock, openChat]);

  return { approve };
}
