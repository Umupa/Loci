import type { Note } from "../../notes";

/** The tag an agent puts on a note to file it as a briefing in Feeds. */
export const BRIEFING_TAG = "briefing";
const SEEN_KEY = "loci.feeds.briefingsSeen";
/** Only the newest ids are remembered; older briefings count as read. */
const SEEN_MAX = 500;

export function isBriefing(note: Pick<Note, "tags">): boolean {
  return note.tags.includes(BRIEFING_TAG);
}

export function loadSeenBriefings(): Set<string> {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(SEEN_KEY) ?? "[]");
    return new Set(Array.isArray(value) ? value.filter((id): id is string => typeof id === "string") : []);
  } catch {
    return new Set();
  }
}

export function saveSeenBriefings(seen: ReadonlySet<string>): void {
  try {
    localStorage.setItem(SEEN_KEY, JSON.stringify([...seen].slice(-SEEN_MAX)));
  } catch {
    // Without storage the marks last until the window closes.
  }
}
