import {
useCallback,
useEffect,
useRef,
type Dispatch,
type RefObject,
type SetStateAction,
} from "react";

import { rememberLoadedSession } from "../../features/sessions/data/sessionCache";
import { shouldPersistSession } from "../../features/sessions/data/sessionStore";
import { sessionChildHarnesses } from "../../features/sessions/model/handoff";
import { hasLiveSessionWork } from "../../features/sessions/model/inFlight";
import type { Session } from "../../features/sessions/model/session";
import {
leafIds,
type WorkspaceTab,
} from "../../features/workspace/model/layout";
import { forgetHarnessSession } from "../../integrations/harness/core/registry";

const SESSION_DETACH_DELAY_MS = 250;

export function useIdleSessionDetach({
  sessions,
  sessionsRef,
  tabs,
  tabsRef,
  liveAgentsEnabled,
  unseenFinishedIds,
  openingSessionIds,
  loadedSessionCache,
  skipForgetSessionIds,
  keepSessionId,
  isForeground,
  persistSession,
  onError,
  setSessions,
}: {
  sessions: Session[];
  sessionsRef: RefObject<Session[]>;
  tabs: WorkspaceTab[];
  tabsRef: RefObject<WorkspaceTab[]>;
  liveAgentsEnabled: boolean;
  unseenFinishedIds: ReadonlySet<string>;
  openingSessionIds: RefObject<Set<string>>;
  loadedSessionCache: RefObject<Map<string, Session>>;
  skipForgetSessionIds: RefObject<Set<string>>;
  /** A conversation in view outside any tab, such as an agent's. */
  keepSessionId?: string;
  /** Recheck the synchronous view before releasing a session, even before React commits it. */
  isForeground?: (sessionId: string) => boolean;
  persistSession: (session: Session | undefined) => Promise<void>;
  onError: (error: unknown) => void;
  setSessions: Dispatch<SetStateAction<Session[]>>;
}) {
  // Dropping a session re-renders the whole app, so it waits until a switch
  // has painted, and a burst of switches pays for it once.
  const detachInputs = useRef({ liveAgentsEnabled, keepSessionId, isForeground, persistSession, onError });
  detachInputs.current = { liveAgentsEnabled, keepSessionId, isForeground, persistSession, onError };
  const unseenFinishedRef = useRef(unseenFinishedIds);
  unseenFinishedRef.current = unseenFinishedIds;
  const detachTimer = useRef<number | null>(null);
  const mounted = useRef(true);
  const saving = useRef(new Set<string>());
  // A failed snapshot is retried after navigation or editing, not on every
  // background update. Observe navigation even when it is faster than the timer.
  const navigationEpoch = useRef(0);
  const failed = useRef(new WeakMap<Session, number>());
  useEffect(() => { navigationEpoch.current += 1; }, [tabs, keepSessionId]);
  const detachIdleSessions = useCallback(function detachIdleSessions() {
    detachTimer.current = null;
    const sessions = sessionsRef.current;
    const visibleIds = new Set(
      tabsRef.current.flatMap((tab) => leafIds(tab.layout)),
    );

    for (const sessionId of visibleIds) {
      openingSessionIds.current.delete(sessionId);
      loadedSessionCache.current.delete(sessionId);
    }

    const canDetach = (session: Session) =>
      // A hidden run is removed by whoever started it, once its answer is read.
      !session.ephemeral &&
      session.id !== detachInputs.current.keepSessionId &&
      !detachInputs.current.isForeground?.(session.id) &&
      !tabsRef.current.some((tab) => leafIds(tab.layout).includes(session.id)) &&
      !hasLiveSessionWork(session) &&
      !openingSessionIds.current.has(session.id) &&
      !skipForgetSessionIds.current.has(session.id) &&
      !(detachInputs.current.liveAgentsEnabled && unseenFinishedRef.current.has(session.id));

    for (const session of sessions) {
      if (!canDetach(session) || saving.current.has(session.id) || failed.current.get(session) === navigationEpoch.current) continue;
      saving.current.add(session.id);
      const attemptEpoch = navigationEpoch.current;
      void (async () => {
        try {
          await detachInputs.current.persistSession(session);
          if (!mounted.current) return;
          const current = sessionsRef.current.find((entry) => entry.id === session.id);
          // Saving yields to navigation and new turns. Only release the exact
          // snapshot that was saved, and recheck ownership after the await.
          if (current !== session || !canDetach(session)) return;
          if (shouldPersistSession(session)) {
            rememberLoadedSession(loadedSessionCache.current, session);
          }
          for (const harness of sessionChildHarnesses(session)) {
            void forgetHarnessSession(harness, session.id).catch((error) => {
              if (mounted.current) detachInputs.current.onError(error);
            });
          }
          setSessions((previous) => previous.filter((entry) => entry !== session));
        } catch (error) {
          failed.current.set(session, attemptEpoch);
          if (mounted.current) detachInputs.current.onError(error);
        } finally {
          saving.current.delete(session.id);
          const current = sessionsRef.current.find((entry) => entry.id === session.id);
          // An edit during this write may already have consumed its detach
          // timer. Give the newer snapshot its own save before releasing it.
          if (mounted.current && current && (current !== session || attemptEpoch !== navigationEpoch.current) && canDetach(current) && detachTimer.current == null) {
            detachTimer.current = window.setTimeout(detachIdleSessions, SESSION_DETACH_DELAY_MS);
          }
        }
      })();
    }
  }, [
    sessionsRef,
    tabsRef,
    openingSessionIds,
    loadedSessionCache,
    skipForgetSessionIds,
    setSessions,
  ]);

  useEffect(() => {
    if (detachTimer.current != null) return;
    detachTimer.current = window.setTimeout(
      detachIdleSessions,
      SESSION_DETACH_DELAY_MS,
    );
  }, [
    sessions,
    tabs,
    liveAgentsEnabled,
    keepSessionId,
    detachIdleSessions,
  ]);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      if (detachTimer.current != null) window.clearTimeout(detachTimer.current);
      detachTimer.current = null;
    };
  }, []);
}
