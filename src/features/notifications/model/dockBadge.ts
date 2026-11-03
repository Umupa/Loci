import { transport } from "../../../platform/transport";
import { sessionNeedsInput, type Session } from "../../sessions/model/session";

let lastCount = -1;

/** Push the pending-approval count to the macOS Dock badge. */
export function syncDockBadge(sessions: Session[]): void {
  let count = 0;
  for (const session of sessions) {
    if (sessionNeedsInput(session)) count++;
  }
  if (count === lastCount) return;
  lastCount = count;
  void transport.call("set_dock_badge", { count }).catch(() => {});
}
