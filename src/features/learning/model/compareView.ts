/**
 * What a comparison lesson on screen shows, part by part, so `reader show`
 * (and tests) can say which parts are shown and at which commit, without
 * reading the DOM.
 */
export type ComparePartView = {
  label: string;
  collapsed: boolean;
  /** A file part: the file, and the commit its text is at (none: the working tree). */
  file?: string; commit?: string; lines?: [number, number];
  /** How the pin stands: current, moved, changed, missing-commit, … */
  pin?: string;
  /** A document part. */
  document?: string; section?: string;
  /** The text could not be read. */
  error?: string;
};
export type CompareView = { courseId: string; lessonId: string; parts: ComparePartView[] };

const views = new Map<string, CompareView>();

/** A comparison reports itself; `undefined` clears it when that same lesson leaves the reader. */
export function publishCompareView(agentId: string, view: CompareView | undefined, leaving?: { courseId: string; lessonId: string }): void {
  if (view) { views.set(agentId, view); return; }
  const current = views.get(agentId);
  if (current && (!leaving || (current.courseId === leaving.courseId && current.lessonId === leaving.lessonId))) views.delete(agentId);
}

export function compareView(agentId: string): CompareView | undefined {
  return views.get(agentId);
}
