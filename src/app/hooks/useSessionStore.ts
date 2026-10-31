import { useCallback, useRef, useState, type Dispatch, type RefObject, type SetStateAction } from "react";
import { ask } from "@tauri-apps/plugin-dialog";
import { loadRecents } from "../../features/projects/model/recents";
import { createSessionRemover } from "../../features/sessions/model/sessionRemoval";
import { sessionDisplayTitle, type Session } from "../../features/sessions/model/session";
import { getSession, setSessionArchived } from "../../features/sessions/data/sessionStore";
import { rememberLoadedSession } from "../../features/sessions/data/sessionCache";

type Options = {
  sessionsRef: RefObject<Session[]>;
  updateSessions: Dispatch<SetStateAction<Session[]>>;
  stopSession: (id: string) => void | Promise<void>;
  flushPersistence: () => Promise<void>;
};

/**
 * The conversations this window holds in memory: mentors' chats, the
 * sessions they start, and whatever the reader shows. Sessions are loaded,
 * added and removed here; nothing here decides where they are shown.
 */
export function useSessionStore(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  // Folders other screens can offer, such as when choosing an agent's projects.
  const [recents] = useState(loadRecents);
  const [error, setError] = useState<string | null>(null);
  const loadedSessionCache = useRef(new Map<string, Session>());
  const openingSessionIds = useRef(new Set<string>());
  const skipForgetSessionIds = useRef(new Set<string>());
  const sessionLoads = useRef(new Map<string, Promise<Session | null>>());
  const sessionLoadEpochs = useRef(new Map<string, number>());
  const removingSessionIds = useRef(new Set<string>());
  const deletedSessionIds = useRef(new Set<string>());

  const isSessionUnavailable = useCallback((id: string) =>
    removingSessionIds.current.has(id) || deletedSessionIds.current.has(id), []);

  const invalidateLoadedSession = useCallback((id: string) => {
    openingSessionIds.current.delete(id);
    loadedSessionCache.current.delete(id);
    sessionLoads.current.delete(id);
    sessionLoadEpochs.current.set(id, (sessionLoadEpochs.current.get(id) ?? 0) + 1);
  }, []);

  /** Keeps a session in memory, where its turns can run and be shown. */
  const addSession = useCallback((session: Session) => {
    if (isSessionUnavailable(session.id)) throw new Error("This conversation is being removed or is no longer available.");
    latest.current.updateSessions((current) => current.some((entry) => entry.id === session.id) ? current : [...current, session]);
    return session.id;
  }, [isSessionUnavailable]);

  const loadSession = useCallback((id: string): Promise<Session | null> => {
    if (isSessionUnavailable(id)) return Promise.resolve(null);
    const open = latest.current.sessionsRef.current.find((session) => session.id === id);
    if (open) return Promise.resolve().then(() => isSessionUnavailable(id) ? null
      : latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? open);
    const cached = loadedSessionCache.current.get(id);
    if (cached) {
      loadedSessionCache.current.delete(id);
      return Promise.resolve().then(() => isSessionUnavailable(id) ? null : cached);
    }
    const pending = sessionLoads.current.get(id);
    if (pending) return pending;
    const epoch = sessionLoadEpochs.current.get(id) ?? 0;
    const loading = getSession(id).then((session) => {
      if (!session || isSessionUnavailable(id) || (sessionLoadEpochs.current.get(id) ?? 0) !== epoch) return null;
      return latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? session;
    }).catch(() => null);
    sessionLoads.current.set(id, loading);
    void loading.then(() => {
      if (sessionLoads.current.get(id) === loading) sessionLoads.current.delete(id);
    });
    return loading;
  }, [isSessionUnavailable]);

  /** Loads a stored session into memory so it can be shown, or throws when it is gone. */
  const ensureSession = useCallback(async (id: string, bind: (session: Session) => void): Promise<Session> => {
    openingSessionIds.current.add(id);
    try {
      const loaded = await loadSession(id);
      if (!loaded || isSessionUnavailable(id)) throw new Error("This conversation is no longer available.");
      const session = latest.current.sessionsRef.current.find((entry) => entry.id === id) ?? loaded;
      loadedSessionCache.current.delete(id);
      bind(session);
      addSession(session);
      return session;
    } finally { openingSessionIds.current.delete(id); }
  }, [addSession, isSessionUnavailable, loadSession]);

  const removeStoredSession = useCallback(async (id: string, mode: "archive" | "delete"): Promise<boolean> => {
    if (isSessionUnavailable(id)) return false;
    const cached = loadedSessionCache.current.get(id);
    removingSessionIds.current.add(id);
    invalidateLoadedSession(id);
    if (mode === "delete") skipForgetSessionIds.current.add(id);
    try {
      const seed = latest.current.sessionsRef.current.find((session) => session.id === id) ?? cached ?? await getSession(id);
      if (!seed) return false;
      const remover = createSessionRemover({
        mode,
        replacement: seed,
        confirm: async () => mode === "archive" || await ask(
          `Delete “${sessionDisplayTitle(seed.title, seed.harness)}”? This conversation will be permanently removed.`,
          { title: "Delete conversation", kind: "warning", okLabel: "Delete", cancelLabel: "Cancel" },
        ),
        stop: async (sessionId) => {
          await latest.current.stopSession(sessionId);
          await latest.current.flushPersistence();
        },
        workspace: {
          snapshot: () => ({ tabs: [], sessions: latest.current.sessionsRef.current, activeTabId: "" }),
          apply: (change) => {
            if (change.type === "stopped") {
              latest.current.updateSessions((sessions) => sessions.map((session) => session.id === id ? change.session : session));
              return;
            }
            invalidateLoadedSession(id);
            if (mode === "delete") deletedSessionIds.current.add(id);
            else rememberLoadedSession(loadedSessionCache.current, change.session ?? seed);
            latest.current.updateSessions(change.removal.sessions);
          },
        },
      });
      return await remover.remove(id);
    } catch (reason) {
      setError(String(reason));
      return false;
    } finally {
      removingSessionIds.current.delete(id);
      skipForgetSessionIds.current.delete(id);
      if (cached && !deletedSessionIds.current.has(id) && !loadedSessionCache.current.has(id)
          && !latest.current.sessionsRef.current.some((session) => session.id === id)) {
        rememberLoadedSession(loadedSessionCache.current, cached);
      }
    }
  }, [invalidateLoadedSession, isSessionUnavailable]);

  const archiveSession = useCallback(async (id: string, archived: boolean): Promise<boolean> => {
    if (archived) return removeStoredSession(id, "archive");
    if (isSessionUnavailable(id)) return false;
    try { await setSessionArchived(id, false); return true; }
    catch (reason) { setError(String(reason)); return false; }
  }, [isSessionUnavailable, removeStoredSession]);

  const removeSession = useCallback((id: string) => removeStoredSession(id, "delete"), [removeStoredSession]);

  return {
    recents, error, setError, isSessionUnavailable, loadedSessionCache, openingSessionIds, skipForgetSessionIds,
    addSession, loadSession, ensureSession, archiveSession, removeSession,
  };
}

export type SessionStore = ReturnType<typeof useSessionStore>;
