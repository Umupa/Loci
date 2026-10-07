/** Unsaved edits to a file, and the disk text they were made against. */
export type FileDraft = { text: string; base: string };

// Panes unmount when their tab is hidden or the file is moved, so a draft
// lives here rather than in the pane that is editing it.
const drafts = new Map<string, FileDraft>();

export function getFileDraft(path: string): FileDraft | null {
  return drafts.get(path) ?? null;
}

export function setFileDraft(path: string, draft: FileDraft | null) {
  if (draft) drafts.set(path, draft);
  else drafts.delete(path);
}

/** A moved or renamed file keeps its unsaved edits. */
export function moveFileDrafts(rebase: (path: string) => string) {
  for (const [path, draft] of [...drafts]) {
    const next = rebase(path);
    if (next === path) continue;
    drafts.delete(path);
    drafts.set(next, draft);
  }
}

export function hasFileDrafts(): boolean {
  return drafts.size > 0;
}

/**
 * Record an edit. Returns the draft to keep, or null when the text is back to
 * what is on disk and there is nothing left to save.
 */
export function editDraft(current: FileDraft | null, disk: string, text: string): FileDraft | null {
  const base = current?.base ?? disk;
  return text === base ? null : { text, base };
}

/** The disk changed under an unsaved draft: saving now would overwrite it. */
export function draftConflicts(draft: FileDraft | null, disk: string): boolean {
  return draft !== null && draft.base !== disk;
}
