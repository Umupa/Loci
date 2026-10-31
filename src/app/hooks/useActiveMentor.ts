import { useCallback, useRef, useState } from "react";
import type { Session } from "../../features/sessions/model/session";

export type ActiveMentor = { agentId: string; sessionId: string };

/** The mentor the window shows; a new window or a restart opens it again. */
export const ACTIVE_MENTOR_KEY = "loci:active-mentor.v1";

export function loadActiveMentorId(): string | undefined {
  try {
    const value = localStorage.getItem(ACTIVE_MENTOR_KEY);
    return value && /^[A-Za-z0-9_-]+$/.test(value) ? value : undefined;
  } catch { return undefined; }
}

function saveActiveMentorId(id: string | null) {
  try {
    if (id) localStorage.setItem(ACTIVE_MENTOR_KEY, id);
    else localStorage.removeItem(ACTIVE_MENTOR_KEY);
  } catch { /* The window still shows it; only the next start forgets. */ }
}

/** Which mentor is open, and the conversation shown beside its reader. */
export function useActiveMentor() {
  const [current, setCurrent] = useState<ActiveMentor | null>(null);
  const currentRef = useRef<ActiveMentor | null>(null);
  const [composerFocusToken, focusComposer] = useState(0);
  const set = useCallback((next: ActiveMentor | null) => {
    currentRef.current = next;
    setCurrent(next);
  }, []);
  const open = useCallback((agentId: string, session: Session) => {
    set({ agentId, sessionId: session.id });
    saveActiveMentorId(agentId);
    focusComposer((token) => token + 1);
  }, [set]);
  const replaceSession = useCallback((previousId: string, fresh: Session) => {
    if (currentRef.current?.sessionId === previousId) set({ ...currentRef.current, sessionId: fresh.id });
  }, [set]);
  /** The conversation was removed with its agent. */
  const forgetSession = useCallback((id: string) => {
    if (currentRef.current?.sessionId !== id) return;
    set(null);
    saveActiveMentorId(null);
  }, [set]);
  return {
    current, currentRef, activeAgentId: current?.agentId ?? null, composerFocusToken,
    open, replaceSession, forgetSession,
    focusComposer: useCallback(() => focusComposer((token) => token + 1), []),
  };
}
