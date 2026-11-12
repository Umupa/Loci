import { useEffect, useState } from "react";
import { COURSES_CHANGED_EVENT } from "../model/course";
import { loadUnseenRevisions, REVISIONS_CHANGED_EVENT } from "../model/lessonRevisions";

/** A mentor's lessons revised and not yet looked at, as `course/lesson`; read again when a course changes. */
export function useUnseenRevisions(agentId: string): ReadonlySet<string> {
  const [state, setState] = useState<{ agentId: string; ids: ReadonlySet<string> }>({ agentId: "", ids: new Set() });
  useEffect(() => {
    let live = true;
    const load = () => void loadUnseenRevisions(agentId).then((ids) => { if (live) setState({ agentId, ids }); }, () => undefined);
    load();
    const changed = (event: Event) => { if ((event as CustomEvent<{ agentId?: string }>).detail?.agentId === agentId) load(); };
    window.addEventListener(COURSES_CHANGED_EVENT, changed);
    window.addEventListener(REVISIONS_CHANGED_EVENT, changed);
    return () => { live = false; window.removeEventListener(COURSES_CHANGED_EVENT, changed); window.removeEventListener(REVISIONS_CHANGED_EVENT, changed); };
  }, [agentId]);
  return state.agentId === agentId ? state.ids : new Set();
}
