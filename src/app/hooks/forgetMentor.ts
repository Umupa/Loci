import { forgetPositions } from "../../features/mentor/model/readingPositions";
import { rememberNoteTarget } from "../../features/notes";
import { saveAgentPreview } from "../../features/agents/model/agentPreview";
import { ACTIVE_MENTOR_KEY, loadActiveMentorId } from "./useActiveMentor";
import { forgetMentorView } from "./useMentorView";

/**
 * What this window keeps about a mentor by its id, outside SQLite: its view
 * and reading positions, where "Add to notes" went, its last words on the rail,
 * and being the mentor a restart opens.
 */
export function forgetMentorLocally(agentId: string): void {
  forgetMentorView(agentId);
  forgetPositions(agentId);
  rememberNoteTarget(agentId, null);
  saveAgentPreview(agentId, undefined);
  try {
    if (loadActiveMentorId() === agentId) localStorage.removeItem(ACTIVE_MENTOR_KEY);
  } catch { /* Storage is unavailable; there is nothing in it to forget. */ }
}
