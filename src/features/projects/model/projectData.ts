import { projectKey } from "../../../shared/lib/paths";
import { normalizeProjectPath } from "./recents";
import { rebasePinnedSessionsCollapsed } from "../../sessions/model/pinnedSessions";
import { rebaseProjectProviders } from "../../sessions/model/projectProviders";

/** Move local per-folder settings after the filesystem resolver finds a rename. */
export function rebaseProjectData(from: string, to: string): void {
  const oldKey = projectKey(normalizeProjectPath(from));
  const newKey = projectKey(normalizeProjectPath(to));
  rebasePinnedSessionsCollapsed(from, to);
  rebaseProjectProviders(oldKey, newKey);
}
