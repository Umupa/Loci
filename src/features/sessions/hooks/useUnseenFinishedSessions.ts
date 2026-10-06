import { useRef } from "react";
import { nextUnseenFinishedSessions } from "../model/sessionDone";

export function useUnseenFinishedSessions(
  busySessionIds: ReadonlySet<string>,
  activeSessionId?: string,
): Set<string> {
  const busyForDoneRef = useRef(busySessionIds);
  const focusedForDoneRef = useRef(activeSessionId);
  const unseenFinishedRef = useRef<Set<string>>(new Set());
  if (
    busyForDoneRef.current !== busySessionIds ||
    focusedForDoneRef.current !== activeSessionId
  ) {
    unseenFinishedRef.current = nextUnseenFinishedSessions({
      previousBusyIds: busyForDoneRef.current,
      busyIds: busySessionIds,
      previousUnseenIds: unseenFinishedRef.current,
      focusedSessionId: activeSessionId,
    });
    busyForDoneRef.current = busySessionIds;
    focusedForDoneRef.current = activeSessionId;
  }
  return unseenFinishedRef.current;
}
