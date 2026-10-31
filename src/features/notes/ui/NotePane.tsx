import { useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { StickyNote, X } from "../../../shared/ui/icons";
import { ResourceHeader } from "../../../shared/ui/ResourceHeader";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { deleteNote, getNote, NOTES_CHANGED_EVENT, type Note } from "../notes";
import { NoteEditor, type NoteEditorActions } from "./NoteEditor";

type Props = {
  noteId: string;
  agentId?: string;
  focused: boolean;
  onFocus: () => void;
  onClose: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  onBack?: () => void;
  /** Shown as the window's one reader: a reader header with Close, no pane chrome. */
  reader?: boolean;
  /** The overview waits for pending edits before leaving this page. */
  onBeforeLeave?: (save: (() => Promise<boolean>) | null) => void;
};

const buttonClass = "grid size-6 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content";

/** The same note editor in the overview and in a movable workspace pane. */
export function NotePane({ noteId, agentId, focused, onFocus, onClose, onPaneDragStart, onBack, onBeforeLeave, reader = false }: Props) {
  const embedded = reader || !!onBack;
  const scope = `${agentId ?? ""}/${noteId}`;
  const [loaded, setLoaded] = useState<{ scope: string; note: Note | null }>();
  const note = loaded?.scope === scope ? loaded.note : undefined;
  const [error, setError] = useState<string>();
  const [reload, setReload] = useState(0);
  const actions = useRef<NoteEditorActions | null>(null);
  const register = useCallback((value: NoteEditorActions | null) => { actions.current = value; }, []);
  const save = useCallback(async () => !actions.current || actions.current.save(), []);
  useEffect(() => {
    onBeforeLeave?.(save);
    return () => onBeforeLeave?.(null);
  }, [save, onBeforeLeave]);
  useEffect(() => {
    let live = true;
    let request = 0;
    setError(undefined);
    const load = () => {
      const turn = ++request;
      void getNote(noteId).then((found) => {
        if (!live || turn !== request) return;
        // A note no mentor owns can be read in any mentor's reader; it stays unowned.
        setLoaded({ scope, note: found && (!agentId || !found.agentId || found.agentId === agentId) ? found : null });
        setError(undefined);
      }, (cause) => { if (live && turn === request) setError(String(cause)); });
    };
    load();
    window.addEventListener(NOTES_CHANGED_EVENT, load);
    return () => { live = false; window.removeEventListener(NOTES_CHANGED_EVENT, load); };
  }, [noteId, agentId, scope, reload]);
  const leave = async (next: () => void) => { if (await save()) next(); };
  return (
    <section aria-label={note?.title ?? "Note"} className="flex h-full min-h-0 min-w-0 flex-1 flex-col" onPointerDown={() => { if (!focused) onFocus(); }}>
      {embedded ? <ResourceHeader title={note?.title ?? "Note"} backLabel="Back to notes" onBack={onBack ? () => void leave(onBack) : undefined} onClose={() => void leave(onClose)} /> : <PaneHeader onPaneDragStart={onPaneDragStart}>
        <StickyNote className="size-3.5 shrink-0 text-content/50" />
        <span className="min-w-0 flex-1 truncate text-xs" title={note?.title}>{note?.title ?? "Note"}</span>
        <button type="button" className={buttonClass} title="Close" aria-label="Close note" onClick={() => void leave(onClose)}><X className="size-3.5" /></button>
      </PaneHeader>}
      {error ? <div role="alert" className="p-4 text-xs text-content/60"><p>{error}</p><button type="button" className="mt-2 underline" onClick={() => setReload((value) => value + 1)}>Retry</button></div> : null}
      {note === undefined ? !error && <p role="status" className="p-4 text-xs text-content/50">Opening note…</p>
        : note === null ? <p role="status" className="p-4 text-xs text-content/50">This note is no longer available.</p>
        : <NoteEditor key={note.id} note={note} compact={embedded} onActions={register} onSaved={(saved) => setLoaded((current) => current?.scope === scope ? { scope, note: saved } : current)}
            onDelete={async (id) => { await deleteNote(id); (onBack ?? onClose)(); }}
            onAddToChat={(draft) => {
              const targetSessionId = agentId ? findAgent(agentId)?.sessionId : undefined;
              requestAddToChat(`${draft.title}\n\n${draft.body}`, "quote", { targetSessionId });
            }} />}
    </section>
  );
}
