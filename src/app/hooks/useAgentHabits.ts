import { useCallback, useEffect, useRef } from "react";
import { forgetHarnessSession, respondHarnessApproval } from "../../integrations/harness/core/registry";
import type { ApprovalDecision } from "../../integrations/harness/core/types";
import { sessionChildHarnesses } from "../../features/sessions/model/handoff";
import { newSession, type Block, type Session } from "../../features/sessions/model/session";
import type { TurnOutcome } from "../../features/sessions/model/turnOutcome";
import { agentForSession, agentLook, findAgent, listAgents } from "../../features/agents/model/agent";
import { loadAgentFiles } from "../../features/agents/model/agentFiles";
import {
  afterRun, claimHabit, clearHabitRun, dropRelays, dueHabits, HABIT_APPROVAL_WAIT_MS, HABIT_RUN_TIMEOUT_MS,
  habitReport, habitRunPrompt, isRelayed, loadHabits, markHabitRun, relayApproval, setHabitRunning,
  subscribeCheckHabitsNow, takeRelayedApproval, updateHabits, type Habit,
} from "../../features/agents/model/agentHabits";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

const TICK_MS = 60_000;
const POLL_MS = 2_000;
/** How often a post waits for the agent to finish replying before it lands anyway. */
const POST_RETRY_MS = 5_000;
const POST_RETRIES = 120;

/**
 * Only the newest scheduler runs habits. A hot reload in development can
 * leave an older copy of this hook running beside the new one, with its own
 * idea of what is running; the newest claims the window and the rest stop.
 */
const OWNER = "__agentHabitsScheduler";
type OwnedWindow = Window & { [OWNER]?: symbol };

type Options = {
  runtime: SessionRuntime;
  submission: SessionSubmission;
  /** A saved conversation by id, from memory or the store. */
  loadSession: (id: string) => Promise<Session | null>;
  /** A habit told the user something in its agent's chat. */
  onPosted?: (chat: Session, agentName: string) => void;
};

/**
 * Runs each agent's habits on schedule while the app is open: in a hidden
 * session of its own, posting to the agent's chat only when the run has
 * something to say. One run at a time across all agents keeps a wake from
 * sleep from starting several at once.
 */
export function useAgentHabits(options: Options, enabled = true) {
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
   * Answers an approval in an agent's chat. One a habit's hidden run asked
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
    const owner = Symbol("agent-habits");
    (window as OwnedWindow)[OWNER] = owner;
    let stopped = false;
    let running = false;
    // A check asked for mid-run happens as soon as that run ends.
    let checkAgain = false;

    /**
     * Sends the run's turn and waits for it, relaying any approval it asks
     * for to the agent's chat. Only time spent working counts toward the
     * timeout; time waiting on the user has its own, much longer limit.
     */
    const watchRun = async (chatId: string, habit: Habit, runId: string, start: () => Promise<TurnOutcome>): Promise<TurnOutcome> => {
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
            approval: { requestId }, agentHabit: { id: habit.id, name: habit.name, at: Date.now() },
          });
        }
        if (pending.length) waiting += POLL_MS;
        else working += POLL_MS;
        if (working >= HABIT_RUN_TIMEOUT_MS || waiting >= HABIT_APPROVAL_WAIT_MS) {
          return { status: "failed", text: "",
            error: waiting >= HABIT_APPROVAL_WAIT_MS ? "Nobody answered its approval request." : "It took too long and was stopped." };
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

    const runHabit = async (agentId: string, chatId: string, habitId: string) => {
      const { runtime, submission } = latest.current;
      const chat = await openChat(chatId);
      if (!chat || stopped || !findAgent(agentId)) return;
      const files = await loadAgentFiles(agentId);
      if (stopped || !findAgent(agentId)) return;
      const now = Date.now();
      // Claim after preparation, from the latest definition. A queued habit
      // may have been removed, paused, rescheduled or claimed in another window.
      const habit = await claimHabit(agentId, habitId, now);
      const record = findAgent(agentId);
      if (!habit || stopped || !record) return;
      const look = agentLook(record);
      const run: Session = {
        // Nobody is watching a habit's run, so it cannot stop to ask before
        // each step unless it was set to. Anything the harness asks goes to
        // the user in the chat.
        ...newSession(chat.harness, chat.cwd, chat.model, habit.access === "auto" ? "auto" : "full-access", chat.modelSettings),
        title: `${look.name} · ${habit.name}`,
        ephemeral: true,
      };
      markHabitRun(run.id, agentId);
      setHabitRunning(habit.id, now);
      runtime.updateSessions((current) => [...current, run]);
      // /operator gives the run the same app access the agent has.
      const outcome = await watchRun(chatId, habit, run.id,
        () => submission.runTurn(run.id, `/operator ${habitRunPrompt(look, files, habit, now)}`))
        .catch((error: unknown): TurnOutcome => ({ status: "failed", text: "", error: error instanceof Error ? error.message : String(error) }));
      for (const relay of dropRelays(run.id)) decideBlock(relay.chatId, relay.blockId, "cancelled");
      await removeRun(run.id);
      clearHabitRun(run.id);
      setHabitRunning(habit.id);

      const report = outcome.status === "completed" ? habitReport(outcome.text) : undefined;
      if (report) {
        void appendToChat(chatId, { id: crypto.randomUUID(), role: "assistant", text: report, agentHabit: { id: habit.id, name: habit.name, at: Date.now() } },
          (posted) => latest.current.onPosted?.(posted, look.name));
      }
      await updateHabits(agentId, (habits) => ({
        habits: habits.map((entry) => entry.id === habit.id ? afterRun(entry, Date.now(), {
          kind: outcome.status !== "completed" ? "failed" : report ? "posted" : "quiet",
          ...(outcome.status !== "completed" ? { error: outcome.error ?? "The run did not finish." } : {}),
          ...(report ? { report } : {}),
          startedAt: now,
        }) : entry),
        result: undefined,
      }));
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
          // Habits are set up in its chat, so one never opened has none.
          if (!sessionId) continue;
          const { run, skipped } = dueHabits(await loadHabits(id), Date.now());
          if (!run.length && !skipped.length) continue;
          if (skipped.length) {
            await updateHabits(id, (habits) => {
              const stale = new Set(dueHabits(habits, Date.now()).skipped.map((habit) => habit.id));
              return { habits: habits.map((habit) => stale.has(habit.id) ? afterRun(habit, Date.now()) : habit), result: undefined };
            });
          }
          for (const habit of run) {
            if (stopped) return;
            await runHabit(id, sessionId, habit.id).catch((error) => console.warn(`Habit "${habit.name}" could not run`, error));
          }
        }
      } catch (error) {
        console.warn("Could not check agent habits", error);
      } finally {
        running = false;
        if (checkAgain && !stopped) void tick();
      }
    };

    void tick();
    const timer = window.setInterval(() => void tick(), TICK_MS);
    const stopChecks = subscribeCheckHabitsNow(() => void tick());
    return () => {
      stopped = true;
      window.clearInterval(timer);
      stopChecks();
      if ((window as OwnedWindow)[OWNER] === owner) delete (window as OwnedWindow)[OWNER];
    };
  }, [enabled, appendToChat, decideBlock, openChat]);

  return { approve };
}
