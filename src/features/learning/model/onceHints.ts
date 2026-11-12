/**
 * Hints that appear once, the first time they apply, and never again on this
 * device: selecting to ask, and the switch to a lesson's original.
 */
export type OnceHint = "select-to-ask" | "original";

const KEY = "loci.hintsSeen";

function seen(): Set<string> {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return new Set(Array.isArray(parsed) ? parsed.filter((entry): entry is string => typeof entry === "string") : []);
  } catch { return new Set(); }
}

export function hintSeen(hint: OnceHint): boolean {
  return seen().has(hint);
}

export function markHintSeen(hint: OnceHint): void {
  const all = seen();
  if (all.has(hint)) return;
  all.add(hint);
  try { localStorage.setItem(KEY, JSON.stringify([...all])); } catch { /* Shown again next time, then. */ }
}

/** The hint a lesson shows now, if any: asking first, then the original. */
export function lessonHint(lesson: { text: boolean; source: boolean; original: boolean }): OnceHint | null {
  if (lesson.text && !lesson.original && !hintSeen("select-to-ask")) return "select-to-ask";
  if (lesson.text && lesson.source && !hintSeen("original")) return "original";
  return null;
}
