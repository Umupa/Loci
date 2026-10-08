import { LoaderCircle, Plus, Search, File, Trash2, X, ListFilter } from "../../../shared/ui/icons";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import {
  Fragment,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type DragEvent as ReactDragEvent,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent as ReactMouseEvent,
} from "react";
import { useMarkdownMode } from "../../sessions/ui/MarkdownModeToggle";
import { ProjectLogoIcon } from "../../projects/ui/ProjectLogoIcon";
import { ProjectMascot } from "../../projects/ui/ProjectMascot";
import { SearchableProjectPicker } from "../../projects/ui/SearchableProjectPicker";
import { OverlayNav } from "../../../app/shell/TitleBar";
import { CollapsiblePane, SecondarySidebarToggle, useSecondarySidebar } from "../../../app/shell/SecondarySidebar";
import { WindowControls } from "../../../app/shell/WindowControls";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { useTabGroupLogos } from "../../projects/hooks/useTabGroupLogos";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import {
  createNote,
  getNote,
  deleteNote,
  loadNotes,
  MAX_NOTE_TAGS,
  NOTES_CHANGED_EVENT,
  normalizeNoteTags,
  notePreview,
  noteSourceProject,
  noteTitle,
  peekNotes,
  upsertNote,
  requestAddNoteToChat,
  type Note,
} from "../notes";
import {
  insertNoteImagesMarkdown,
  saveNoteImagesFromFiles,
  saveNoteImagesFromPaths,
  type NoteImageAsset,
} from "../noteImages";
import { projectKey, projectName } from "../../../shared/lib/paths";
import { IS_MAC } from "../../../platform/tauri/platform";
import { looksLikeProject, sameProjectPath, type RecentProject } from "../../projects/model/recents";
import {
  loadTabGroupColors,
  loadTabGroupCustomColors,
  loadTabGroupMascots,
  resolveTabGroupColor,
  resolveTabGroupLogo,
  resolveTabGroupMascot,
} from "../../workspace/model/tabGroups";
import { AgentMarkdown, MarkdownSourceHighlight } from "../../sessions/ui/AgentMarkdown";

const MIN_WIDTH = 240;
const MAX_WIDTH = 420;
const DEFAULT_WIDTH = 280;

let rememberedWidth = DEFAULT_WIDTH;
let rememberedNoteId: string | null = null;

// Keep pending saves ordered across editor unmounts and reopened notes.
const noteSaveQueues = new Map<
  string,
  { pending: Promise<void>; saved?: Note }
>();

function enqueueNoteSave(
  id: string,
  save: (latest?: Note) => void | Promise<Note | void>,
) {
  const queue = noteSaveQueues.get(id) ?? { pending: Promise.resolve() };
  const persist = async () => {
    const saved = await save(queue.saved);
    if (saved) queue.saved = saved;
  };
  const pending = queue.pending.then(persist, persist).finally(() => {
    if (queue.pending === pending) noteSaveQueues.delete(id);
  });
  queue.pending = pending;
  noteSaveQueues.set(id, queue);
  return pending;
}

type Props = {
  besideRail?: boolean;
  compactRail?: boolean;
  cwd?: string;
  recents: RecentProject[];
  onClose: () => void;
  onToggleSidebar?: () => void;
  openRequest?: NoteOpenRequest;
};

export type NoteOpenRequest = { id: string; sequence: number };

type NoteEditorActions = { id: string; rename: (title: string) => void; remove: () => Promise<void> };

export function NotesView({
  besideRail = false,
  compactRail = false,
  cwd,
  recents,
  onClose,
  onToggleSidebar,
  openRequest,
}: Props) {
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  const listLock = useLockOverscroll<HTMLDivElement>();
  const resize = useDragResize({
    min: MIN_WIDTH,
    max: () => Math.min(MAX_WIDTH, Math.round(window.innerWidth * 0.5)),
    defaultWidth: DEFAULT_WIDTH,
    initial: rememberedWidth,
    onCommit: (width) => {
      rememberedWidth = width;
    },
  });
  const [notes, setNotes] = useState<Note[]>(() => peekNotes() ?? []);
  const [loading, setLoading] = useState(() => peekNotes() === null);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [linkedScope, setLinkedScope] = useState<{ id: string } | null>(null);
  const linkedNote = linkedScope ? notes.find((note) => note.id === linkedScope.id) : undefined;
  const scopedCwd = linkedNote ? linkedNote.sourceCwd : cwd;
  const projectCwd = scopedCwd && looksLikeProject(scopedCwd) ? scopedCwd : undefined;
  const [noteNavigation, setNoteNavigation] = useState<{ sequence: number; status: "loading" | "ready" | "error"; error?: string }>();
  const openRequestRef = useRef(openRequest);
  openRequestRef.current = openRequest;
  const listRead = useRef(0);
  const navigationVersion = useRef(0);
  const [selectedId, setSelectedId] = useState<string | null>(() => {
    const cached = peekNotes();
    return (
      cached?.find((note) => note.id === rememberedNoteId)?.id ??
      cached?.[0]?.id ??
      rememberedNoteId
    );
  });
  const [creating, setCreating] = useState(false);
  const [noteMenu, setNoteMenu] = useState<{ x: number; y: number; id: string } | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [timeFilter, setTimeFilter] = useState<"all" | "today" | "7d" | "30d">("all");
  const [filterAnchor, setFilterAnchor] = useState<HTMLButtonElement | null>(null);
  const [listOpen, toggleList] = useSecondarySidebar("notes");
  const editorActions = useRef<NoteEditorActions | null>(null);
  const registerEditorActions = useCallback((actions: NoteEditorActions | null) => { editorActions.current = actions; }, []);
  const logos = useTabGroupLogos();
  const [groupMascots] = useState(loadTabGroupMascots);
  const [groupColors] = useState(loadTabGroupColors);
  const [groupCustomColors] = useState(loadTabGroupCustomColors);

  const refresh = useCallback(async () => {
    const read = ++listRead.current;
    try {
      const next = await loadNotes(true);
      if (read !== listRead.current) return;
      setNotes(next);
      setError(null);
      setSelectedId((current) => {
        const preferred = current ?? rememberedNoteId;
        if (preferred && next.some((note) => note.id === preferred)) {
          return preferred;
        }
        return openRequestRef.current ? current : next[0]?.id ?? null;
      });
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!openRequest) {
      setLinkedScope(null);
      setNoteNavigation(undefined);
      return;
    }
    let cancelled = false;
    const navigation = ++navigationVersion.current;
    const read = ++listRead.current;
    const baseline = new Map(notes.map((entry) => [entry.id, entry]));
    setQuery("");
    setTimeFilter("all");
    setFilterAnchor(null);
    setNoteNavigation({ sequence: openRequest.sequence, status: "loading" });
    setSelectedId(null);
    void Promise.all([loadNotes(true), getNote(openRequest.id)]).then(([next, note]) => {
      if (cancelled || navigation !== navigationVersion.current) return;
      if (!note) throw new Error("This note no longer exists.");
      setNotes((current) => {
        const known = new Map(current.map((entry) => [entry.id, entry]));
        // Project-only saves keep updatedAt. Preserve observations made since
        // this read began even when their timestamp is unchanged.
        const freshest = (candidate: Note, observed: Note | undefined) => observed && (
          observed.updatedAt > candidate.updatedAt ||
          (observed.updatedAt === candidate.updatedAt && known.get(candidate.id) !== baseline.get(candidate.id))
        ) ? observed : candidate;
        const list = read === listRead.current ? next.map((entry) => freshest(entry, known.get(entry.id))) : current;
        const target = freshest(note, list.find((entry) => entry.id === note.id));
        return [target, ...list.filter((entry) => entry.id !== target.id)];
      });
      setLinkedScope({ id: note.id });
      setSelectedId(note.id);
      setNoteNavigation({ sequence: openRequest.sequence, status: "ready" });
      setLoading(false);
    }).catch((error: unknown) => {
      if (!cancelled && navigation === navigationVersion.current) {
        setNoteNavigation({ sequence: openRequest.sequence, status: "error", error: String(error) });
        setLoading(false);
      }
    });
    return () => { cancelled = true; };
  }, [openRequest?.id, openRequest?.sequence]);

  useEffect(() => {
    if (!openRequestRef.current) void refresh();
    window.addEventListener(NOTES_CHANGED_EVENT, refresh);
    return () => window.removeEventListener(NOTES_CHANGED_EVENT, refresh);
  }, [refresh]);

  useEffect(() => {
    rememberedNoteId = selectedId;
  }, [selectedId]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      event.stopPropagation();
      onCloseRef.current();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const scopedNotes = useMemo(() => notes.filter((note) => !projectCwd ||
    !!note.sourceCwd && sameProjectPath(note.sourceCwd, projectCwd)), [notes, projectCwd]);
  const visible = useMemo(() => {
    const now = Date.now();
    const since = timeFilter === "today" ? new Date(now).setHours(0, 0, 0, 0)
      : timeFilter === "7d" ? now - 604800000
      : timeFilter === "30d" ? now - 2592000000
      : 0;
    const timePassed = scopedNotes.filter((note) => since === 0 || note.updatedAt >= since);
    const needle = query.trim().toLowerCase();
    if (!needle) return timePassed;
    return timePassed.filter((note) => {
      const project = noteSourceProject(note.sourceCwd)?.toLowerCase() ?? "";
      return (
        note.title.toLowerCase().includes(needle) ||
        note.body.toLowerCase().includes(needle) ||
        note.slug.toLowerCase().includes(needle) ||
        note.tags.some((tag) => tag.includes(needle.replace(/^#/, ""))) ||
        project.includes(needle)
      );
    });
  }, [scopedNotes, query, timeFilter]);

  const navigating = !!openRequest && (noteNavigation?.sequence !== openRequest.sequence || noteNavigation.status === "loading");
  const navigationError = noteNavigation?.status === "error" ? noteNavigation.error : undefined;
  const selected = navigating || navigationError ? null :
    visible.find((note) => note.id === selectedId) ??
    (openRequest ? null : visible[0]) ??
    null;

  const selectNote = (id: string) => {
    navigationVersion.current++;
    setSelectedId(id);
    if (openRequest) setNoteNavigation({ sequence: openRequest.sequence, status: "ready" });
  };

  const onCreate = async () => {
    if (creating) return;
    setCreating(true);
    try {
      const note = await createNote({
        title: "Untitled",
        body: "",
        ...(projectCwd ? { sourceCwd: projectCwd } : {}),
      });
      setNotes(await loadNotes(true));
      selectNote(note.id);
      setQuery("");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setCreating(false);
    }
  };

  const onSaved = (note: Note) => {
    setNotes((current) => {
      const next = current.map((item) => (item.id === note.id ? note : item));
      next.sort(
        (a, b) => b.updatedAt - a.updatedAt || a.id.localeCompare(b.id),
      );
      return next;
    });
  };

  const onDelete = async (id: string) => {
    try {
      await deleteNote(id);
      const next = await loadNotes(true);
      setNotes(next);
      setSelectedId((current) => {
        if (current !== id) return current;
        return next[0]?.id ?? null;
      });
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : String(err));
      throw err;
    }
  };

  const onAddToChat = (note: Note) => {
    requestAddNoteToChat(note);
    onClose();
  };

  const commitNoteRename = (id: string) => {
    const note = notes.find((n) => n.id === id);
    if (!note) { setRenamingId(null); return; }
    const title = renameDraft.trim() || note.title;
    if (title !== note.title) {
      if (editorActions.current?.id !== id) { setError("Select the note before renaming it."); return; }
      editorActions.current.rename(title);
    }
    setRenamingId(null);
  };

  const noteMenuItems: ContextMenuItem[] = [
    { kind: "item", id: "rename", label: "Rename" },
    { kind: "sep" },
    { kind: "item", id: "delete", label: "Delete", danger: true },
  ];

  const filterItems: ContextMenuItem[] = [
    { kind: "item", id: "all", label: "All time", checked: timeFilter === "all" },
    { kind: "item", id: "today", label: "Today", checked: timeFilter === "today" },
    { kind: "item", id: "7d", label: "Last 7 days", checked: timeFilter === "7d" },
    { kind: "item", id: "30d", label: "Last 30 days", checked: timeFilter === "30d" },
  ];

  const list = (
    <div
      ref={resize.setPaneRef}
      className="relative flex h-full min-h-0 shrink-0 flex-col border-r border-stroke"
    >
      <div className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
        <div className="relative flex h-7 min-w-0 flex-1 items-center">
          <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Filter notes"
            aria-label="Filter notes"
            spellCheck={false}
            autoComplete="off"
            className="h-7 w-full rounded-md bg-transparent pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/40"
          />
        </div>
        <button
          type="button"
          aria-label="Filter by time"
          title="Filter notes"
          onClick={(e: ReactMouseEvent<HTMLButtonElement>) => setFilterAnchor(e.currentTarget)}
          className={`grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content ${timeFilter !== "all" ? "text-accent" : "text-content/45"}`}
        >
          <ListFilter className="size-3.5" strokeWidth={1.75} />
        </button>
        <button
          type="button"
          title="New note"
          aria-label="New note"
          disabled={creating}
          onClick={() => void onCreate()}
          className="grid size-6 shrink-0 place-items-center rounded-md text-content/45 hover:bg-content/10 hover:text-content disabled:opacity-40"
        >
          {creating ? (
            <LoaderCircle
              className="size-3.5 animate-spin"
              strokeWidth={1.75}
            />
          ) : (
            <Plus className="size-3.5" strokeWidth={1.75} />
          )}
        </button>
      </div>
      <div
        ref={listLock}
        className="min-h-0 flex-1 overflow-y-auto overscroll-none"
      >
        {error && notes.length === 0 ? (
          <p className="px-3 py-2 text-[12px] text-content/50">{error}</p>
        ) : loading && notes.length === 0 ? (
          <div className="flex justify-center py-10 text-content/40">
            <LoaderCircle className="size-4 animate-spin" strokeWidth={1.75} />
          </div>
        ) : visible.length === 0 ? (
          <p className="px-3 py-2 text-[12px] text-content/50">
            {query.trim() || timeFilter !== "all"
              ? "No matching notes"
              : "No notes yet. Save a turn from the transcript, or create one here."}
          </p>
        ) : (
          <ul className="flex flex-col gap-0.5 p-1.5">
            {visible.map((note) => (
              <li key={note.id}>
                {renamingId === note.id ? (
                  <div className={`flex w-full flex-col rounded-md border px-2.5 py-2 ${selected?.id === note.id ? "border-transparent bg-selection" : "border-stroke"}`}>
                    <input
                      autoFocus
                      aria-label="Rename note"
                      value={renameDraft}
                      onChange={(e) => setRenameDraft(e.target.value)}
                      onBlur={() => void commitNoteRename(note.id)}
                      onKeyDown={(e: ReactKeyboardEvent<HTMLInputElement>) => {
                        if (e.key === "Enter") e.currentTarget.blur();
                        if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); setRenamingId(null); }
                      }}
                      className="min-w-0 w-full bg-transparent text-[13px] font-semibold text-content outline-none"
                    />
                  </div>
                ) : (
                  <NoteCard
                    note={note}
                    active={selected?.id === note.id}
                    logos={logos}
                    mascots={groupMascots}
                    colors={groupColors}
                    customColors={groupCustomColors}
                    onSelect={() => selectNote(note.id)}
                    onContextMenu={(e: ReactMouseEvent<HTMLButtonElement>) => {
                      e.preventDefault();
                      selectNote(note.id);
                      setNoteMenu({ x: e.clientX, y: e.clientY, id: note.id });
                    }}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
      <div
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize notes list"
        className={`absolute inset-y-0 -right-px z-10 w-1.5 cursor-col-resize touch-none ${
          resize.dragging ? "bg-content/15" : "hover:bg-content/10"
        }`}
        onPointerDown={resize.onPointerDown}
        onDoubleClick={resize.onDoubleClick}
      />
    </div>
  );

  return (
    <div
      role="region"
      aria-label="Notes"
      data-app-notes
      className="flex min-h-0 min-w-0 flex-1 flex-col text-content"
    >
      <div
        className="flex h-10 shrink-0 select-none items-center border-b border-stroke"
        data-tauri-drag-region="deep"
      >
        {IS_MAC && compactRail ? <div className="w-4 shrink-0" /> : null}
        {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
        {besideRail ? null : (
          <OverlayNav onBack={onClose} onToggleSidebar={onToggleSidebar} />
        )}
        <div className="flex shrink-0 items-center px-1.5">
          <SecondarySidebarToggle open={listOpen} onToggle={toggleList} name="notes list" />
        </div>
        <div className="flex min-w-0 flex-1 items-center gap-2 pr-3 text-[13px]">
          <File
            className="size-3.5 shrink-0 text-content/45"
            strokeWidth={1.75}
          />
          <span className="min-w-0 truncate text-content">Notes</span>
        </div>
        {IS_MAC ? null : <WindowControls />}
      </div>
      <div className="flex min-h-0 min-w-0 flex-1">
        <CollapsiblePane open={listOpen}>{list}</CollapsiblePane>
        {navigating ? <div role="status" className="flex flex-1 items-center justify-center text-sm text-content/50">Loading note…</div> : navigationError ?
          <div role="alert" className="flex flex-1 items-center justify-center px-4 text-sm text-content/60">{navigationError}</div> : <NoteDetail
          note={selected}
          recents={recents}
          activeCwd={scopedCwd}
          onSaved={onSaved}
          onDelete={onDelete}
          onActions={registerEditorActions}
          onAddToChat={onAddToChat}
        />}
      </div>
      {noteMenu ? <ContextMenu x={noteMenu.x} y={noteMenu.y} items={noteMenuItems} onPick={(id) => {
        if (id === "rename") {
          const note = notes.find((n) => n.id === noteMenu.id);
          if (note) { setRenamingId(note.id); setRenameDraft(note.title); }
        } else if (id === "delete") {
          if (editorActions.current?.id === noteMenu.id) void editorActions.current.remove();
        }
        setNoteMenu(null);
      }} onClose={() => setNoteMenu(null)} /> : null}
      {filterAnchor ? <ContextMenu anchor={filterAnchor} items={filterItems} onPick={(id) => {
        setTimeFilter(id as "all" | "today" | "7d" | "30d");
        setFilterAnchor(null);
      }} onClose={() => setFilterAnchor(null)} /> : null}
    </div>
  );
}

type ProjectMarks = {
  logos: Record<string, string>;
  mascots: Record<string, string>;
  colors: Record<string, number>;
  customColors: Record<string, string>;
};

function NoteProjectMark({
  cwd,
  logos,
  mascots,
  colors,
  customColors,
}: { cwd: string } & ProjectMarks) {
  const project = projectName(cwd);
  const key = projectKey(cwd);
  const logoPath = resolveTabGroupLogo(key, logos);
  const mascotName = resolveTabGroupMascot(key, mascots);
  const mascotColor = resolveTabGroupColor(key, colors, customColors, project);
  return (
    <span className="flex min-w-0 items-center gap-1.5">
      {logoPath ? (
        <ProjectLogoIcon
          path={logoPath}
          className="size-3.5 shrink-0 rounded-sm"
          imageClassName="size-3.5"
        />
      ) : (
        <ProjectMascot
          project={project}
          color={mascotColor}
          name={mascotName}
          className="size-3 shrink-0"
        />
      )}
      <span className="min-w-0 truncate">{project}</span>
    </span>
  );
}

function NoteDetailTab({
  label,
  selected,
  onSelect,
}: {
  label: string;
  selected: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={selected}
      onClick={onSelect}
      className={`relative flex h-9 items-center text-[12px] leading-none ${
        selected ? "text-content" : "text-content/50 hover:text-content"
      }`}
    >
      {label}
      {selected ? (
        <span className="absolute inset-x-0 bottom-0 h-0.5 bg-content" />
      ) : null}
    </button>
  );
}

function NoteCard({
  note,
  active,
  logos,
  mascots,
  colors,
  customColors,
  onSelect,
  onContextMenu,
}: {
  note: Note;
  active: boolean;
  onSelect: () => void;
  onContextMenu?: (e: ReactMouseEvent<HTMLButtonElement>) => void;
} & ProjectMarks) {
  const preview = notePreview(note.body, note.title);
  const project = noteSourceProject(note.sourceCwd);
  const time = formatRelativeTime(new Date(note.updatedAt).toISOString());
  const hint = [note.title, project].filter(Boolean).join(" · ");
  return (
    <button
      type="button"
      title={hint}
      aria-current={active ? "true" : undefined}
      onClick={onSelect}
      onContextMenu={onContextMenu}
      className={`flex w-full flex-col rounded-md border px-2.5 py-2 text-left ${
        active
          ? "border-transparent bg-selection text-content"
          : "border-transparent text-content/80 hover:bg-content/5 hover:text-content"
      }`}
    >
      <span className="flex items-center gap-2">
        {project && note.sourceCwd ? (
          <span className="min-w-0 flex-1 text-[11px] text-content/50">
            <NoteProjectMark
              cwd={note.sourceCwd}
              logos={logos}
              mascots={mascots}
              colors={colors}
              customColors={customColors}
            />
          </span>
        ) : (
          <span className="min-w-0 flex-1" />
        )}
        {time ? (
          <span className="shrink-0 text-[11px] tabular-nums text-content/45">
            {time}
          </span>
        ) : null}
      </span>
      <span className="mt-1 line-clamp-1 text-[13px] font-semibold leading-snug text-content">
        {note.title}
      </span>
      {preview ? (
        <span className="mt-1 line-clamp-1 text-[12px] leading-snug text-content/45">
          {preview}
        </span>
      ) : null}
      {note.tags.length > 0 ? (
        <span className="mt-1.5 flex min-w-0 items-center gap-1 overflow-hidden">
          {note.tags.slice(0, 3).map((tag) => (
            <span
              key={tag}
              className="max-w-24 truncate rounded bg-content/8 px-1.5 py-0.5 text-[10px] leading-none text-content/55"
            >
              #{tag}
            </span>
          ))}
          {note.tags.length > 3 ? (
            <span className="shrink-0 text-[10px] text-content/40">
              +{note.tags.length - 3}
            </span>
          ) : null}
        </span>
      ) : null}
    </button>
  );
}

function NoteDetail({
  note,
  recents,
  activeCwd,
  onSaved,
  onDelete,
  onActions,
  onAddToChat,
}: {
  note: Note | null;
  recents: RecentProject[];
  activeCwd?: string;
  onSaved: (note: Note) => void;
  onDelete: (id: string) => void | Promise<void>;
  onActions: (actions: NoteEditorActions | null) => void;
  onAddToChat: (note: Note) => void;
}) {
  if (!note) {
    return (
      <div className="flex h-full min-w-0 flex-1 flex-col items-center justify-center px-6 text-center">
        <File className="mb-3 size-6 text-content/30" strokeWidth={1.75} />
        <p className="text-[13px] text-content/45">Select a note</p>
      </div>
    );
  }
  return (
    <NoteEditor
      key={note.id}
      note={note}
      recents={recents}
      activeCwd={activeCwd}
      onSaved={onSaved}
      onDelete={onDelete}
      onActions={onActions}
      onAddToChat={onAddToChat}
    />
  );
}

function NoteEditor({
  note,
  recents,
  activeCwd,
  onSaved,
  onDelete,
  onActions,
  onAddToChat,
}: {
  note: Note;
  recents: RecentProject[];
  activeCwd?: string;
  onSaved: (note: Note) => void;
  onDelete: (id: string) => void | Promise<void>;
  onActions: (actions: NoteEditorActions | null) => void;
  onAddToChat: (note: Note) => void;
}) {
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const blank = !note.body.trim() && note.title === "Untitled";
  const [mode, setMode] = useMarkdownMode(note.id);
  type Edits = Partial<Pick<Note, "title" | "body" | "tags">>;
  const [edits, setEdits] = useState<Edits>({});
  const title = edits.title ?? note.title;
  const body = edits.body ?? note.body;
  const tags = edits.tags ?? note.tags;
  // Keep only an unsaved choice locally so completed moves survive reopening.
  const [projectChange, setProjectChange] = useState<{ path: string } | null>(
    null,
  );
  const sourceCwd = projectChange?.path ?? note.sourceCwd;
  const [saveError, setSaveError] = useState<string | null>(null);
  const [imageDrag, setImageDrag] = useState(false);
  const [imageBusy, setImageBusy] = useState(false);
  const editsRef = useRef(edits);
  const bodyRef = useRef(body);
  const projectChangeRef = useRef(projectChange);
  const noteRef = useRef(note);
  const dropZoneRef = useRef<HTMLDivElement>(null);
  const sourceFieldRef = useRef<HTMLTextAreaElement>(null);
  const lastDropAt = useRef(0);
  const skipSave = useRef(false);
  const saveTimer = useRef<number | null>(null);
  const onSavedRef = useRef(onSaved);
  const onDeleteRef = useRef(onDelete);
  onDeleteRef.current = onDelete;
  bodyRef.current = body;
  noteRef.current = note;
  onSavedRef.current = onSaved;
  const time = formatRelativeTime(new Date(note.updatedAt).toISOString());

  useEffect(() => {
    if (blank) setMode("source");
    // New untitled notes open in source so typing isn't behind the preview.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const editNote = useCallback((change: Edits) => {
    const next = { ...editsRef.current, ...change };
    editsRef.current = next;
    if (change.body !== undefined) bodyRef.current = change.body;
    setEdits(next);
  }, []);

  const persist = useCallback(async (latest?: Note) => {
    if (skipSave.current) return;
    const current = latest ?? noteRef.current;
    const changes = editsRef.current;
    const nextBody = changes.body ?? current.body;
    const nextTitle =
      (changes.title ?? current.title).trim() || noteTitle(nextBody);
    const nextTags = changes.tags ?? current.tags;
    const nextProject = projectChangeRef.current;
    const acceptSaved = (saved: Note) => {
      noteRef.current = saved;
      // A completed save only clears the edits included in that request.
      const remaining = { ...editsRef.current };
      if (remaining.title === changes.title) delete remaining.title;
      if (remaining.body === changes.body) delete remaining.body;
      if (remaining.tags === changes.tags) delete remaining.tags;
      editsRef.current = remaining;
      bodyRef.current = remaining.body ?? saved.body;
      setEdits(remaining);
      if (projectChangeRef.current === nextProject) {
        projectChangeRef.current = null;
        setProjectChange(null);
      }
      setSaveError(null);
    };
    if (
      nextTitle === current.title &&
      nextBody === current.body &&
      sameTags(nextTags, current.tags) &&
      (!nextProject || nextProject.path === current.sourceCwd)
    ) {
      acceptSaved(current);
      return current;
    }
    try {
      const saved = await upsertNote({
        id: current.id,
        title: nextTitle,
        body: nextBody,
        tags: nextTags,
        ...(nextProject ? { sourceCwd: nextProject.path } : {}),
      });
      acceptSaved(saved);
      onSavedRef.current(saved);
      return saved;
    } catch (err: unknown) {
      setSaveError(err instanceof Error ? err.message : String(err));
      return current;
    }
  }, []);

  const saveNow = useCallback(() => {
    if (saveTimer.current != null) window.clearTimeout(saveTimer.current);
    saveTimer.current = null;
    return enqueueNoteSave(note.id, persist);
  }, [note.id, persist]);

  const remove = useCallback(async () => {
    skipSave.current = true;
    if (saveTimer.current != null) window.clearTimeout(saveTimer.current);
    saveTimer.current = null;
    try { await enqueueNoteSave(note.id, () => onDeleteRef.current(note.id)); }
    catch (error) {
      skipSave.current = false;
      setSaveError(error instanceof Error ? error.message : String(error));
    }
  }, [note.id]);

  useEffect(() => {
    onActions({ id: note.id, rename: (title) => { editNote({ title }); void saveNow(); }, remove });
    return () => onActions(null);
  }, [note.id, onActions, editNote, saveNow, remove]);

  const scheduleSave = useCallback(() => {
    if (saveTimer.current != null) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => {
      saveTimer.current = null;
      void saveNow();
    }, 400);
  }, [saveNow]);

  const insertionRange = useCallback(() => {
    const field = sourceFieldRef.current;
    if (!field) {
      const end = bodyRef.current.length;
      return { start: end, end };
    }
    return {
      start: field.selectionStart,
      end: field.selectionEnd,
    };
  }, []);

  const addDroppedImages = useCallback(
    async (
      load: () => Promise<NoteImageAsset[]>,
      range: { start: number; end: number },
    ) => {
      setImageBusy(true);
      setImageDrag(false);
      try {
        const images = await load();
        const inserted = insertNoteImagesMarkdown(
          bodyRef.current,
          range.start,
          range.end,
          images,
        );
        editNote({ body: inserted.value });
        setSaveError(null);
        scheduleSave();
        window.requestAnimationFrame(() => {
          const field = sourceFieldRef.current;
          if (!field) return;
          field.focus();
          field.setSelectionRange(inserted.cursor, inserted.cursor);
        });
      } catch (err: unknown) {
        setSaveError(err instanceof Error ? err.message : String(err));
      } finally {
        setImageBusy(false);
      }
    },
    [editNote, scheduleSave],
  );

  useEffect(() => {
    let cancelled = false;
    let unlisten: (() => void) | undefined;

    const toClientPoint = (x: number, y: number) => {
      const scale = window.devicePixelRatio || 1;
      if (scale !== 1 && (x > window.innerWidth || y > window.innerHeight)) {
        return { x: x / scale, y: y / scale };
      }
      return { x, y };
    };
    const overDropZone = (x: number, y: number) => {
      const zone = dropZoneRef.current;
      if (!zone) return false;
      const point = toClientPoint(x, y);
      const rect = zone.getBoundingClientRect();
      return (
        point.x >= rect.left &&
        point.x <= rect.right &&
        point.y >= rect.top &&
        point.y <= rect.bottom
      );
    };

    void getCurrentWebview()
      .onDragDropEvent((event) => {
        if (event.payload.type === "leave") {
          setImageDrag(false);
          return;
        }
        const { x, y } = event.payload.position;
        const over = overDropZone(x, y);
        if (event.payload.type === "enter" || event.payload.type === "over") {
          setImageDrag(over);
          return;
        }
        if (event.payload.type !== "drop") return;
        setImageDrag(false);
        if (!over || Date.now() - lastDropAt.current < 250) return;
        lastDropAt.current = Date.now();
        const range = insertionRange();
        const paths = event.payload.paths;
        void addDroppedImages(
          () => saveNoteImagesFromPaths(note.id, paths),
          range,
        );
      })
      .then((fn) => {
        if (cancelled) fn();
        else unlisten = fn;
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, [addDroppedImages, insertionRange, note.id]);

  useEffect(() => {
    return () => {
      void saveNow();
    };
  }, [saveNow]);

  const onTitleKeyDown = (event: ReactKeyboardEvent<HTMLInputElement>) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    event.currentTarget.blur();
  };

  const canAddToChat = Boolean(body.trim());
  const draft: Note = {
    ...note,
    title: title.trim() || noteTitle(body),
    body,
    tags,
    sourceCwd,
  };

  return (
    <div
      ref={lockOverscroll}
      className="min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-none"
    >
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-5 px-8 py-8">
        <header className="flex flex-col gap-3">
          <div className="flex min-w-0 items-center gap-2 text-[12px] text-content/50">
            <File className="size-3.5 shrink-0" strokeWidth={1.75} />
            <span>Note</span>
            {note.slug ? (
              <span className="min-w-0 truncate">{note.slug}</span>
            ) : null}
            <SearchableProjectPicker
              cwd={sourceCwd ?? "~"}
              recents={recents}
              mode="move"
              railCwd={activeCwd}
              buttonClassName="px-1.5"
              onSelectProject={(path) => {
                const change = { path };
                projectChangeRef.current = change;
                setProjectChange(change);
                void saveNow();
              }}
            />
          </div>
          <input
            value={title}
            onChange={(event) => {
              editNote({ title: event.target.value });
              scheduleSave();
            }}
            onBlur={() => {
              const next = title.trim() || noteTitle(body);
              if (next !== title) editNote({ title: next });
              void saveNow();
            }}
            onKeyDown={onTitleKeyDown}
            aria-label="Note title"
            className="w-full border-0 bg-transparent p-0 text-[20px] font-semibold leading-tight text-content outline-none placeholder:text-content/35"
            placeholder="Untitled"
          />
          {time ? (
            <div className="text-[12px] text-content/50">Updated {time}</div>
          ) : null}
          <NoteTagsEditor
            tags={tags}
            onChange={(next) => {
              editNote({ tags: next });
              scheduleSave();
            }}
          />
          <div className="flex flex-wrap items-center gap-2 pt-1">
            <button
              type="button"
              disabled={!canAddToChat}
              onClick={() => onAddToChat(draft)}
              className="inline-flex items-center gap-1 rounded-md bg-content px-3 h-6.5 text-[12px] text-background-base hover:bg-content/80 disabled:cursor-default disabled:opacity-40"
            >
              Add to chat
            </button>
            <button
              type="button"
              onClick={() => { void remove(); }}
              className="inline-flex items-center gap-1.5 rounded-md px-3 h-7 text-[12px] text-content/70 hover:bg-content/10 hover:text-red-400"
            >
              <Trash2 className="size-3.5" strokeWidth={1.75} />
              Delete
            </button>
          </div>
          {saveError ? (
            <div
              role="alert"
              className="flex items-center gap-2 text-[12px] text-red-400/90"
            >
              <span>Could not save note: {saveError}</span>
              <button
                type="button"
                onClick={() => {
                  setSaveError(null);
                  void saveNow();
                }}
                className="shrink-0 underline hover:no-underline"
              >
                Retry
              </button>
            </div>
          ) : null}
        </header>
        <div
          role="tablist"
          aria-label="Note sections"
          className="flex h-9 items-stretch gap-4 border-b border-stroke"
        >
          <NoteDetailTab
            label="Preview"
            selected={mode === "preview"}
            onSelect={() => setMode("preview")}
          />
          <NoteDetailTab
            label="Source"
            selected={mode === "source"}
            onSelect={() => setMode("source")}
          />
        </div>
        <div
          ref={dropZoneRef}
          aria-busy={imageBusy}
          className={`relative min-h-[448px] rounded-lg border transition-colors ${
            imageDrag ? "border-accent/60 bg-accent/5" : "border-transparent"
          }`}
          onDragOver={(event: ReactDragEvent<HTMLDivElement>) => {
            if (!hasDroppedFiles(event.dataTransfer)) return;
            event.preventDefault();
            event.dataTransfer.dropEffect = "copy";
            setImageDrag(true);
          }}
          onDragLeave={(event: ReactDragEvent<HTMLDivElement>) => {
            const next = event.relatedTarget as Node | null;
            if (next && event.currentTarget.contains(next)) return;
            setImageDrag(false);
          }}
          onDrop={(event: ReactDragEvent<HTMLDivElement>) => {
            if (!hasDroppedFiles(event.dataTransfer)) return;
            event.preventDefault();
            setImageDrag(false);
            if (Date.now() - lastDropAt.current < 250) return;
            lastDropAt.current = Date.now();
            const files = [...event.dataTransfer.files];
            if (files.length === 0) return;
            const range = insertionRange();
            void addDroppedImages(
              () => saveNoteImagesFromFiles(note.id, files),
              range,
            );
          }}
        >
          {imageDrag || imageBusy ? (
            <div className="pointer-events-none absolute inset-0 z-20 grid place-items-center rounded-lg bg-background-base/80 text-[12px] text-content/70 backdrop-blur-sm">
              {imageBusy ? "Adding images…" : "Drop images here"}
            </div>
          ) : null}
          {mode === "source" ? (
            <NoteSource
              textareaRef={sourceFieldRef}
              autoFocus={blank}
              value={body}
              onChange={(next) => {
                editNote({ body: next });
                scheduleSave();
              }}
            />
          ) : body.trim() ? (
            <AgentMarkdown text={body} cwd={sourceCwd} hardBreaks />
          ) : (
            <p className="text-[13px] text-content/45">No description</p>
          )}
        </div>
      </div>
    </div>
  );
}

function NoteSource({
  value,
  onChange,
  textareaRef,
  autoFocus = false,
}: {
  value: string;
  onChange: (value: string) => void;
  textareaRef: { current: HTMLTextAreaElement | null };
  autoFocus?: boolean;
}) {
  const lines = value.split("\n");
  const gutterWidth = `calc(${Math.max(String(lines.length).length, 2)}ch + 0.75rem)`;
  const textOffset = `calc(${gutterWidth} + 0.75rem)`;

  return (
    <div className="relative min-h-[448px]">
      <div
        aria-hidden
        className="pointer-events-none grid font-mono text-[13px] leading-5 text-content/85"
        style={{
          gridTemplateColumns: `${gutterWidth} minmax(0, 1fr)`,
        }}
      >
        {lines.map((line, index) => (
          <Fragment key={index}>
            <div className="select-none pr-2 text-right tabular-nums whitespace-nowrap text-content/40">
              {index + 1}
            </div>
            <div className="min-h-5 min-w-0 pl-3 whitespace-pre-wrap wrap-break-word">
              {line ? <MarkdownSourceHighlight text={line} /> : "\u00a0"}
            </div>
          </Fragment>
        ))}
      </div>
      <div
        aria-hidden
        className="pointer-events-none absolute inset-y-0 w-px bg-content/10"
        style={{ left: gutterWidth }}
      />
      <textarea
        ref={textareaRef}
        value={value}
        autoFocus={autoFocus}
        onChange={(event) => onChange(event.target.value)}
        spellCheck={false}
        placeholder="Write markdown…"
        className="markdown-source-field absolute inset-0 h-full w-full resize-none overflow-hidden border-0 bg-transparent py-0 pr-0 font-mono text-[13px] leading-5 whitespace-pre-wrap wrap-break-word outline-none"
        style={{ paddingLeft: textOffset }}
      />
    </div>
  );
}

function NoteTagsEditor({
  tags,
  onChange,
}: {
  tags: string[];
  onChange: (tags: string[]) => void;
}) {
  const [value, setValue] = useState("");

  const addTag = (input = value) => {
    const next = normalizeNoteTags([...tags, input]);
    setValue("");
    if (!sameTags(next, tags)) onChange(next);
  };

  return (
    <div
      className="flex min-w-0 flex-wrap items-center gap-1.5"
      aria-label="Tags"
    >
      <span className="mr-0.5 text-[11px] text-content/45">Tags</span>
      {tags.map((tag) => (
        <span
          key={tag}
          className="inline-flex h-6 max-w-48 items-center gap-1 rounded-md bg-content/8 pl-2 pr-1 text-[11px] text-content/70"
        >
          <span className="truncate">#{tag}</span>
          <button
            type="button"
            title={`Remove #${tag}`}
            aria-label={`Remove #${tag}`}
            onClick={() => onChange(tags.filter((item) => item !== tag))}
            className="grid size-4 shrink-0 place-items-center rounded text-content/40 hover:bg-content/10 hover:text-content"
          >
            <X className="size-2.5" strokeWidth={1.75} />
          </button>
        </span>
      ))}
      {tags.length < MAX_NOTE_TAGS ? (
        <input
          value={value}
          onChange={(event) => {
            const next = event.target.value;
            if (next.endsWith(",")) addTag(next.slice(0, -1));
            else setValue(next);
          }}
          onBlur={() => {
            if (value.trim()) addTag();
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === ",") {
              event.preventDefault();
              addTag();
              return;
            }
            if (event.key === "Backspace" && !value && tags.length > 0) {
              onChange(tags.slice(0, -1));
            }
          }}
          aria-label="Add note tag"
          placeholder="Add tag…"
          spellCheck={false}
          autoComplete="off"
          className="h-6 min-w-20 flex-1 border-0 bg-transparent px-1 text-[11px] text-content outline-none placeholder:text-content/35"
        />
      ) : null}
    </div>
  );
}

function sameTags(left: readonly string[], right: readonly string[]): boolean {
  return (
    left.length === right.length &&
    left.every((tag, index) => tag === right[index])
  );
}

function hasDroppedFiles(data: DataTransfer | null): data is DataTransfer {
  if (!data) return false;
  return [...data.types].some(
    (type) => type === "Files" || type === "application/x-moz-file",
  );
}
