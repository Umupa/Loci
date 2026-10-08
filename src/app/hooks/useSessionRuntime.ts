import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  type Dispatch,
  type MutableRefObject,
  type SetStateAction,
} from "react";
import { startHarnessBridge } from "../../integrations/harness/core/child";
import { applyHarnessEvents } from "../../integrations/harness/core/apply";
import { noteAgentFileActivity } from "../../features/files/model/agentActivity";
import { bindHarnessSession } from "../../integrations/harness/core/registry";
import type { HarnessEvent } from "../../integrations/harness/core/types";
import { sessionNeedsInput, type Session } from "../../features/sessions/model/session";
import {
  flushSessionWrites,
  persistFingerprint,
  shouldPersistSession,
  upsertSession,
  type SessionSummary,
} from "../../features/sessions/data/sessionStore";
import {
  cancelScheduledFlush,
  scheduleHarnessFlush,
  type ScheduledFlush,
} from "../model/harnessFlush";

type RuntimeOptions = {
  sessions: Session[];
  sessionsRef: MutableRefObject<Session[]>;
  setSessions: Dispatch<SetStateAction<Session[]>>;
  isForeground?: (sessionId: string) => boolean;
  onPersisted?: (summary: SessionSummary) => void;
  onPersistenceError?: (error: unknown) => void;
  onFinished?: (session: Session) => void;
  onInput?: (session: Session) => void;
  onContinued?: (sessionId: string) => void;
};

/** Owns event batching, provider binding, turn identities, and session saves. */
export function useSessionRuntime(options: RuntimeOptions) {
  const currentOptions = useRef(options);
  currentOptions.current = options;
  const { sessions, sessionsRef } = options;
  const queued = useRef(new Map<string, HarnessEvent[]>());
  const scheduled = useRef<ScheduledFlush | null>(null);
  const generations = useRef(new Map<string, number>());
  const activeTurns = useRef(new Set<string>());
  const bound = useRef(new Map<string, string>());
  // Boot and window-transfer sessions already came from a persisted snapshot.
  const saved = useRef(new Map(options.sessions
    .filter(shouldPersistSession)
    .map((session) => [session.id, persistFingerprint(session)])));
  const saving = useRef(new Set<Promise<unknown>>());
  const pendingSaves = useRef(new Set<string>());
  const saveTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const updateSessions = useCallback((update: SetStateAction<Session[]>) => {
    const before = sessionsRef.current;
    const next = typeof update === "function" ? update(before) : update;
    if (next === before) return;
    const retained = new Set(next.map((session) => session.id));
    for (const id of bound.current.keys()) {
      if (!retained.has(id)) bound.current.delete(id);
    }
    sessionsRef.current = next;
    currentOptions.current.setSessions(next);
    for (const session of next) {
      if (!sessionNeedsInput(session)) continue;
      const previous = before.find((entry) => entry.id === session.id);
      const approvalIds = session.blocks
        .filter((block) => block.approval && !block.approval.decided)
        .map((block) => block.approval!.requestId)
        .join(",");
      const previousIds = previous?.blocks
        .filter((block) => block.approval && !block.approval.decided)
        .map((block) => block.approval!.requestId)
        .join(",");
      if (
        approvalIds !== previousIds ||
        session.pendingQuestion?.requestId !== previous?.pendingQuestion?.requestId
      ) {
        currentOptions.current.onInput?.(session);
      }
    }
  }, [sessionsRef]);

  const flushEvents = useCallback(() => {
    cancelScheduledFlush(scheduled.current);
    scheduled.current = null;
    const batches = queued.current;
    if (!batches.size) return;
    queued.current = new Map();
    updateSessions((before) => {
      const next = before.map((session) => {
        const events = batches.get(session.id);
        return events ? applyHarnessEvents(session, events) : session;
      });
      return next.some((session, index) => session !== before[index]) ? next : before;
    });
  }, [updateSessions]);

  const enqueueEvent = useCallback((sessionId: string, event: HarnessEvent) => {
    noteAgentFileActivity(event);
    const events = queued.current.get(sessionId) ?? [];
    events.push(event);
    queued.current.set(sessionId, events);
    if (
      event.type === "approval.requested" || event.type === "approval.resolved" ||
      event.type === "question.asked" || event.type === "question.resolved"
    ) {
      // Approval and question controls must never wait behind a background timer.
      flushEvents();
      return;
    }
    const foreground = !document.hidden &&
      (currentOptions.current.isForeground?.(sessionId) ?? true);
    if (foreground && scheduled.current?.kind === "timeout") {
      cancelScheduledFlush(scheduled.current);
      scheduled.current = null;
    }
    if (!scheduled.current) {
      scheduled.current = scheduleHarnessFlush(flushEvents, foreground);
    }
  }, [flushEvents]);

  const persistSession = useCallback(async (input: Session | string | undefined) => {
    const session = typeof input === "string"
      ? sessionsRef.current.find((entry) => entry.id === input)
      : input;
    if (!session || !shouldPersistSession(session)) return;
    const fingerprint = persistFingerprint(session);
    if (saved.current.get(session.id) === fingerprint) return;
    const save = upsertSession(session).then((summary) => {
      if (!summary) return;
      saved.current.set(session.id, fingerprint);
      currentOptions.current.onPersisted?.(summary);
    });
    saving.current.add(save);
    try {
      await save;
    } catch (error) {
      // flushPersistence drains pending IDs before saving. Keep failures dirty
      // so the next explicit flush (especially quit) retries and can reject.
      pendingSaves.current.add(session.id);
      throw error;
    } finally {
      saving.current.delete(save);
    }
  }, [sessionsRef]);

  const flushPersistence = useCallback(async () => {
    flushEvents();
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = undefined;
    const ids = [...pendingSaves.current];
    pendingSaves.current.clear();
    await Promise.all(ids.map((id) => persistSession(id)));
    await Promise.all([...saving.current]);
    await flushSessionWrites();
  }, [flushEvents, persistSession]);

  const bindRestoredSession = useCallback((session: Session) => {
    if (!sessionsRef.current.some((entry) => entry.id === session.id)) {
      saved.current.set(session.id, persistFingerprint(session));
      pendingSaves.current.delete(session.id);
    }
    if (!session.providerSessionId) return;
    const key = [session.harness, session.providerSessionId, session.cwd,
      session.providerAccountId ?? ""].join("\0");
    if (bound.current.get(session.id) === key && sessionsRef.current.some((entry) => entry.id === session.id)) return;
    bindHarnessSession(session.harness, session.id, session.providerSessionId,
      session.cwd, session.providerAccountId, session.blocks);
    bound.current.set(session.id, key);
  }, [sessionsRef]);

  const beginTurn = useCallback((sessionId: string) => {
    flushEvents();
    const generation = (generations.current.get(sessionId) ?? 0) + 1;
    generations.current.set(sessionId, generation);
    activeTurns.current.add(sessionId);
    return generation;
  }, [flushEvents]);
  const isCurrentTurn = useCallback((sessionId: string, generation: number) =>
    generations.current.get(sessionId) === generation, []);
  const hasActiveTurn = useCallback((sessionId: string) => activeTurns.current.has(sessionId), []);
  const forgetTurn = useCallback((sessionId: string) => {
    generations.current.set(sessionId, (generations.current.get(sessionId) ?? 0) + 1);
    activeTurns.current.delete(sessionId);
  }, []);
  const finishTurn = useCallback((sessionId: string, generation: number) => {
    if (!isCurrentTurn(sessionId, generation)) return;
    activeTurns.current.delete(sessionId);
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    if (session) currentOptions.current.onFinished?.(session);
  }, [isCurrentTurn, sessionsRef]);
  const continued = useCallback((sessionId: string) => {
    currentOptions.current.onContinued?.(sessionId);
  }, []);

  useEffect(() => {
    const retained = new Set(sessions.map((session) => session.id));
    for (const id of bound.current.keys()) {
      if (!retained.has(id)) bound.current.delete(id);
    }
    for (const session of sessions) {
      if (!session.busy && !activeTurns.current.has(session.id)) bindRestoredSession(session);
      if (shouldPersistSession(session) && saved.current.get(session.id) !== persistFingerprint(session)) {
        pendingSaves.current.add(session.id);
      }
    }
    if (!pendingSaves.current.size || saveTimer.current) return;
    saveTimer.current = setTimeout(() => {
      void flushPersistence().catch((error) => currentOptions.current.onPersistenceError?.(error));
    }, 350);
  }, [sessions, bindRestoredSession, flushPersistence]);

  useEffect(() => {
    const releaseBridge = startHarnessBridge();
    return () => {
      flushEvents();
      void flushPersistence().catch((error) => currentOptions.current.onPersistenceError?.(error));
      releaseBridge();
    };
  }, [flushEvents, flushPersistence]);

  return useMemo(() => ({
    sessions, sessionsRef, updateSessions, enqueueEvent, flushEvents,
    persistSession, flushPersistence, bindRestoredSession, beginTurn,
    isCurrentTurn, hasActiveTurn, forgetTurn, finishTurn, continued,
  }), [sessions, sessionsRef, updateSessions, enqueueEvent, flushEvents,
    persistSession, flushPersistence, bindRestoredSession, beginTurn,
    isCurrentTurn, hasActiveTurn, forgetTurn, finishTurn, continued]);
}

export type SessionRuntime = ReturnType<typeof useSessionRuntime>;
