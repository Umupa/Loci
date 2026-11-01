import { useEffect,useMemo,useRef,useState,type ReactNode } from "react";
import { ChevronDown,FilePlusCorner,MessageSquarePlus,Plus,StickyNote } from "../../../shared/ui/icons";
import { MissingNoteError,rememberedNoteTarget,rememberNoteTarget,type Note,type NoteTarget } from "../../notes";
import { Popover } from "../../../shared/ui/Popover";
import { type TranscriptSelection } from "../model/transcriptSelection";

type Props = {
  selection: TranscriptSelection | null;
  onAddToChat?: (text: string, blockId?: string) => void;
  /** Save the passage to a new note or to the end of one already written. */
  onAddToNotes?: (text: string, target: NoteTarget) => void | Promise<Note | void>;
  /** The notes a passage may be added to. */
  listNotes?: () => Promise<Note[]>;
  /** Whose notes these are: the last choice is remembered per mentor. */
  notesScope?: string;
  onDismiss: () => void;
};

export function TranscriptSelectionMenu({
  selection,
  onAddToChat,
  onAddToNotes,
  listNotes,
  notesScope = "global",
  onDismiss,
}: Props) {
  const [picking, setPicking] = useState(false);
  const [target, setTarget] = useState(() => rememberedNoteTarget(notesScope));
  const [pickError, setPickError] = useState<string | null>(null);
  useEffect(() => { setTarget(rememberedNoteTarget(notesScope)); setPicking(false); setPickError(null); }, [notesScope]);
  const onDismissRef = useRef(onDismiss);
  onDismissRef.current = onDismiss;

  // Scrolling or resizing moves the text out from under the menu, so the
  // selection it acts on is gone; drop it rather than chase the range.
  useEffect(() => {
    if (!selection) return;
    const dismiss = () => onDismissRef.current();
    window.addEventListener("scroll", dismiss, true);
    window.addEventListener("resize", dismiss);
    return () => {
      window.removeEventListener("scroll", dismiss, true);
      window.removeEventListener("resize", dismiss);
    };
  }, [selection]);

  if (!selection) return null;

  return (
    <Popover
      anchor={selection.rect}
      side="top"
      align="center"
      onDismiss={(reason) => {
        if (reason === "escape") window.getSelection()?.removeAllRanges();
        onDismiss();
      }}
      role="toolbar"
      aria-label="Selected text actions"
      className="p-1"
    >
      {picking && onAddToNotes ? <NotePicker listNotes={listNotes} error={pickError}
        onBack={() => { setPicking(false); setPickError(null); }}
        onPick={async (choice) => {
          const saved = await onAddToNotes(selection.text, choice);
          const next: NoteTarget = choice.kind === "note" ? { kind: "note", id: choice.id, title: saved?.title ?? choice.title } : choice;
          rememberNoteTarget(notesScope, next);
          setTarget(next);
          window.getSelection()?.removeAllRanges();
          onDismiss();
        }} /> :
      <div className="flex min-w-36 flex-col items-stretch gap-0.5">
        {onAddToChat ? (
          <SelectionAction
            label="Add to chat"
            errorLabel="Could not add to chat."
            onSelect={() => onAddToChat(selection.text, selection.blockId)}
            onDismiss={onDismiss}
          >
            <MessageSquarePlus
              aria-hidden="true"
              className="size-3.5"
            />
          </SelectionAction>
        ) : null}
        {onAddToNotes ? (
          <div className="flex flex-wrap items-stretch gap-0.5">
            <SelectionAction
              label={target ? target.kind === "new" ? "Add to a new note" : `Add to “${target.title || "Untitled"}”` : "Add to notes…"}
              errorLabel="Could not save note."
              onSelect={target ? async () => {
                try {
                  const saved = await onAddToNotes(selection.text, target);
                  if (saved && target.kind === "note" && saved.title !== target.title) {
                    const next = { kind: "note" as const, id: saved.id, title: saved.title };
                    rememberNoteTarget(notesScope, next);
                    setTarget(next);
                  }
                } catch (error) {
                  if (!(error instanceof MissingNoteError)) throw error;
                  rememberNoteTarget(notesScope, null);
                  setTarget(null);
                  setPickError(error.message);
                  setPicking(true);
                  return false;
                }
              } : () => { setPicking(true); return false; }}
              onDismiss={onDismiss}
            >
              <FilePlusCorner aria-hidden="true" className="size-3.5 shrink-0" />
            </SelectionAction>
            {target ? <button type="button" title="Choose another note" aria-label="Choose another note"
              onMouseDown={(event) => event.preventDefault()} onClick={() => setPicking(true)}
              className="grid h-8 w-7 shrink-0 place-items-center rounded-lg text-content/50 hover:bg-content/5 hover:text-content">
              <ChevronDown className="size-3.5" />
            </button> : null}
          </div>
        ) : null}
      </div>}
    </Popover>
  );
}

/** The first time, and whenever asked: a new note, or one already written. */
function NotePicker({ listNotes, error, onBack, onPick }: {
  listNotes?: () => Promise<Note[]>;
  error: string | null;
  onBack: () => void;
  onPick: (target: NoteTarget) => Promise<void>;
}) {
  const [notes, setNotes] = useState<Note[] | null>(listNotes ? null : []);
  const [query, setQuery] = useState("");
  const [pending, setPending] = useState(false);
  const [failure, setFailure] = useState<string | null>(error);
  useEffect(() => {
    if (!listNotes) return;
    let live = true;
    void listNotes().then((list) => { if (live) setNotes(list); }, () => { if (live) setNotes([]); });
    return () => { live = false; };
  }, [listNotes]);
  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return [...(notes ?? [])].sort((a, b) => b.updatedAt - a.updatedAt)
      .filter((note) => !needle || note.title.toLowerCase().includes(needle));
  }, [notes, query]);
  const pick = async (target: NoteTarget) => {
    setPending(true);
    setFailure(null);
    try { await onPick(target); }
    catch (cause) { setFailure(cause instanceof Error ? cause.message : String(cause)); }
    finally { setPending(false); }
  };
  const item = "flex h-8 w-full min-w-0 items-center gap-2 rounded-lg px-2.5 text-left font-sans text-[13px] leading-none text-content outline-none hover:bg-content/5 focus-visible:bg-content/5 disabled:opacity-40";
  return (
    <div role="menu" aria-label="Add to which note" className="flex w-64 flex-col gap-0.5"
      onKeyDown={(event) => { if (event.key === "Escape" && query) { event.stopPropagation(); setQuery(""); } }}>
      <div className="flex items-center justify-between px-2.5 pb-1 pt-1.5 font-sans text-[11px] text-content/45">
        <span>Add to…</span>
        <button type="button" onMouseDown={(event) => event.preventDefault()} onClick={onBack} className="hover:text-content">Back</button>
      </div>
      <button type="button" role="menuitem" disabled={pending} onMouseDown={(event) => event.preventDefault()} onClick={() => void pick({ kind: "new" })} className={item}>
        <Plus aria-hidden="true" className="size-3.5 shrink-0" />New note
      </button>
      {notes === null || notes.length > 0 ? <>
        <div role="separator" className="mx-1 my-0.5 h-px bg-content/10" />
        {notes && notes.length > 6 ? <input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Find a note"
          aria-label="Find a note" spellCheck={false}
          className="mx-1 mb-0.5 h-7 rounded-md bg-content/5 px-2 font-sans text-[12px] text-content outline-none placeholder:text-content/35" /> : null}
        <div className="max-h-56 overflow-y-auto">
          {notes === null ? <p role="status" className="px-2.5 py-2 font-sans text-[12px] text-content/45">Loading notes…</p>
            : shown.length === 0 ? <p className="px-2.5 py-2 font-sans text-[12px] text-content/45">No note matches.</p>
            : shown.map((note) => <button key={note.id} type="button" role="menuitem" disabled={pending} title={note.title}
              onMouseDown={(event) => event.preventDefault()} onClick={() => void pick({ kind: "note", id: note.id, title: note.title })} className={item}>
              <StickyNote aria-hidden="true" className="size-3.5 shrink-0 text-content/50" />
              <span className="min-w-0 truncate">{note.title || "Untitled"}</span>
            </button>)}
        </div>
      </> : null}
      {failure ? <span role="alert" className="max-w-xs px-2.5 py-1 font-sans text-xs text-content/70">{failure}</span> : null}
    </div>
  );
}

function SelectionAction({
  label,
  errorLabel,
  children,
  onSelect,
  onDismiss,
}: {
  label: string;
  /** What failed, so a chat failure is not reported as a note. */
  errorLabel: string;
  children: ReactNode;
  /** Resolves `false` when it moved on to another step instead of finishing. */
  onSelect: () => void | false | Promise<unknown>;
  onDismiss: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <>
      <button
        type="button"
        disabled={pending}
        onMouseDown={(event) => event.preventDefault()}
        onClick={async () => {
          setPending(true);
          setError(null);
          try {
            const result = await onSelect();
            if (result === false) return;
            window.getSelection()?.removeAllRanges();
            onDismiss();
          } catch (error) {
            setError(error instanceof Error ? error.message : String(error));
          } finally {
            setPending(false);
          }
        }}
        className="flex h-8 w-full min-w-0 max-w-64 items-center gap-2 whitespace-nowrap rounded-lg px-2.5 font-sans text-[13px] leading-none text-content outline-none ring-accent-ring/40 hover:bg-content/5 focus-visible:ring-2"
      >
        {children}
        <span className="min-w-0 truncate">{label}</span>
      </button>
      {error && (
        <span
          role="alert"
          className="order-last max-w-xs basis-full px-2.5 py-1 text-xs text-content/70"
        >
          {errorLabel} {error}
        </span>
      )}
    </>
  );
}
