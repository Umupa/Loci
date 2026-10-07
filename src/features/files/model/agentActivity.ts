import type { HarnessEvent } from "../../../integrations/harness";
import { notifyDirsChanged } from "./fileTree";
import { nudgeWatchedFiles } from "./fileWatch";

/** A second look catches a write whose mtime had not landed at the first. */
const SETTLE_MS = 150;

/**
 * Agents change files through tools the app cannot see inside (edits, shell
 * commands, scripts), so any finished tool call or reply is taken as a reason
 * to re-list the open folders and re-stat the open files. Both checks are
 * debounced and cheap when nothing changed.
 */
export function noteAgentFileActivity(event: HarnessEvent) {
  const finishedTool = event.type === "tool.updated"
    && (event.status === "completed" || event.status === "success" || event.status === "failed");
  if (!finishedTool && event.type !== "message.completed" && event.type !== "session.ended") return;
  refresh();
  window.setTimeout(refresh, SETTLE_MS);
}

function refresh() {
  notifyDirsChanged();
  nudgeWatchedFiles();
}
