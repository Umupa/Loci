import { getNote, upsertNote, type Note } from "./notes";

/*
 * Where "Add to notes" puts a passage. The first time it asks — a new note or
 * one already written — and from then on it goes where it went last, until the
 * reader picks another. Remembered per mentor, since each keeps its own notes.
 */
export type NoteTarget = { kind: "new" } | { kind: "note"; id: string; title: string };

const KEY = "loci.noteTarget.";

export function rememberedNoteTarget(scope: string): NoteTarget | null {
  try {
    const value = JSON.parse(localStorage.getItem(KEY + scope) ?? "null") as NoteTarget | null;
    if (value?.kind === "new") return value;
    if (value?.kind === "note" && typeof value.id === "string") return { kind: "note", id: value.id, title: String(value.title ?? "") };
  } catch { /* nothing remembered */ }
  return null;
}

export function rememberNoteTarget(scope: string, target: NoteTarget | null) {
  try {
    if (target) localStorage.setItem(KEY + scope, JSON.stringify(target));
    else localStorage.removeItem(KEY + scope);
  } catch { /* remembered for this click only */ }
}

export class MissingNoteError extends Error {
  constructor() { super("That note is no longer there. Choose another."); }
}

/** Add a passage to the end of a note, a blank line after what is already there. */
export async function appendToNote(id: string, text: string): Promise<Note> {
  const note = await getNote(id);
  if (!note) throw new MissingNoteError();
  const passage = text.replace(/\r\n?/g, "\n").trim();
  const before = note.body.trimEnd();
  return upsertNote({
    id: note.id,
    title: note.title,
    body: before ? `${before}\n\n${passage}\n` : `${passage}\n`,
    tags: note.tags,
    ...(note.hash ? { expectedHash: note.hash } : {}),
  });
}
