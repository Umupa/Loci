import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { ChevronDown, FilePlusCorner } from "../../../shared/ui/icons";
// The modules themselves, not the notes index: a reader's tests stub the index for their own notes.
import { listAgentNotes, loadNotes, type Note } from "../../notes/notes";
import { announceNoteSaved, MissingNoteError, rememberedNoteTarget, rememberNoteTarget, type NoteTarget } from "../../notes/noteTarget";
import { NotePicker } from "../../sessions/ui/TranscriptSelectionMenu";
import "./ReadingToolbar.css";

/*
 * The small bar beside a passage, the same in every reader: on a selection,
 * and on a highlight already kept. Each action is one button; a bar for a
 * kind of passage adds its own (a table or a figure, later) the same way.
 */

/** Whose notes a reader's passages go to. The note last chosen is remembered per mentor. */
export type NoteShelf = { scope: string; agentId?: string; list: () => Promise<Note[]> };

/** The mentor's notes, as the conversation's Add to notes uses them, with the same remembered note. */
export function useNoteShelf(agentId?: string): NoteShelf {
  return useMemo(() => ({
    scope: agentId ?? "global", ...(agentId ? { agentId } : {}),
    list: () => agentId ? listAgentNotes(agentId) : loadNotes(),
  }), [agentId]);
}

const keepSelection = (event: { preventDefault(): void }) => event.preventDefault();

export function ToolbarButton({ icon, label, title, onClick, disabled, iconOnly = false, pressed, danger = false }: {
  icon: ReactNode; label: string; title?: string; onClick: () => void; disabled?: boolean;
  /** A label a tooltip says, for actions that are clear from their icon. */
  iconOnly?: boolean;
  pressed?: boolean;
  /** It removes something the reader kept. */
  danger?: boolean;
}) {
  return <button type="button" className={`reading-toolbar__button${danger ? " reading-toolbar__button--danger" : ""}`} disabled={disabled} title={title ?? label}
    aria-label={iconOnly ? label : undefined} aria-pressed={pressed} onMouseDown={keepSelection} onClick={onClick}>
    {icon}{iconOnly ? null : <span>{label}</span>}
  </button>;
}

export const ToolbarDivider = () => <span aria-hidden="true" className="reading-toolbar__divider" />;

/**
 * Save to note: the passage goes to the note it went to last, without asking.
 * The first time, after that note is gone, or from the chevron, it asks which.
 */
export function useSaveToNote(shelf: NoteShelf | undefined, save: (target: NoteTarget) => Promise<Note>) {
  const scope = shelf?.scope ?? "global";
  const [target, setTarget] = useState(() => rememberedNoteTarget(scope));
  const [picking, setPicking] = useState<{ error: string | null } | null>(null);
  const previousScope = useRef(scope);
  useEffect(() => {
    if (previousScope.current === scope) return;
    previousScope.current = scope;
    setTarget(rememberedNoteTarget(scope));
    setPicking(null);
  }, [scope]);

  const saveTo = async (choice: NoteTarget) => {
    const saved = await save(choice);
    // A new note becomes the place the next passage goes, beside this one.
    const next: NoteTarget = { kind: "note", id: saved.id, title: saved.title };
    rememberNoteTarget(scope, next);
    setTarget(next);
    setPicking(null);
    announceNoteSaved(saved);
  };

  /** Resolves true once saved, false when it asked which note instead. */
  const run = async (): Promise<boolean> => {
    if (!target) { setPicking({ error: null }); return false; }
    try {
      await saveTo(target);
      return true;
    } catch (cause) {
      if (!(cause instanceof MissingNoteError)) throw cause;
      rememberNoteTarget(scope, null);
      setTarget(null);
      setPicking({ error: cause.message });
      return false;
    }
  };

  const title = target?.kind === "note" ? `Save to “${target.title || "Untitled"}”` : target ? "Save to a new note" : "Save to a note…";
  const button = (onRun: () => void, disabled?: boolean) => shelf ? <span className="reading-toolbar__split">
    <ToolbarButton icon={<FilePlusCorner className="size-3.5" />} label="Save to note" title={title} disabled={disabled} onClick={onRun} />
    {target ? <button type="button" className="reading-toolbar__button reading-toolbar__chevron" disabled={disabled} title="Choose another note"
      aria-label="Choose another note" onMouseDown={keepSelection} onClick={() => setPicking({ error: null })}><ChevronDown className="size-3" /></button> : null}
  </span> : null;
  const picker = (onSaved: () => void) => shelf && picking ? <NotePicker listNotes={shelf.list} error={picking.error}
    onBack={() => setPicking(null)} onPick={async (choice) => { await saveTo(choice); onSaved(); }} /> : null;

  return { picking: !!picking && !!shelf, run, button, picker, cancel: () => setPicking(null) };
}
