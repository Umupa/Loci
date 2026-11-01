import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import type { MentorViewState } from "../../../app/hooks/useMentorView";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import { SidebarLeft } from "../../../shared/ui/icons";
import { agentLook, type Agent } from "../../agents/model/agent";
import { readAgentDocument } from "../../agents/model/agentDocuments";
import type { AgentReading } from "../../agents/model/agentReading";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { useAgentResources } from "../../agents/ui/useAgentResources";
import type { Canvas } from "../../canvas/canvas";
import type { OpenFileFn } from "../../files/model/filePlace";
import { moveFileDrafts, setFileDraft } from "../../files/model/fileDrafts";
import { loadCourse } from "../../learning/model/course";
import { createNote, getNote } from "../../notes";
import { readingOf, type MentorLesson, type MentorPage } from "../model/mentorPage";
import { MentorBreadcrumb, mentorCrumbs } from "./MentorBreadcrumb";
import type { CourseBadge } from "./LibraryCourses";
import { useReadingPlace } from "./useReadingPlace";
import { MentorLibrary, type LibraryChange } from "./MentorLibrary";
import { MentorReader } from "./MentorReader";
import "./MentorWorkspace.css";

const LIBRARY_MIN = 200;
const CHAT_MIN = 320;
/** The reader keeps at least this much between the two columns. */
const READER_MIN = 360;

type Props = {
  agent: Agent;
  state: MentorViewState;
  /** The conversation, rendered by the app with its session wiring. */
  chat: ReactNode;
  /** Ahead of the title bar, when the workspace is the window's left edge. */
  leading?: ReactNode;
  /** After the title bar's own controls, such as the window's buttons. */
  trailing?: ReactNode;
  canvases: readonly Canvas[];
  onOpen: (page: MentorPage) => void;
  onClose: () => void;
  onLessonChange: (lesson: MentorLesson | null) => void;
  onRestoredChecked: (page: MentorPage, exists: boolean) => void;
  onToggleLibrary: () => void;
  /** Chooses the library's segment, its course or its filter. */
  onLibraryChange: (change: LibraryChange) => void;
  /** Puts a message in the conversation's composer without sending it. */
  onDraft: (text: string) => void;
  /** Room in the library after a course's or lesson's title. */
  courseBadge?: CourseBadge;
  onToggleChat: () => void;
  onResizeLibrary: (width: number) => void;
  onResizeChat: (width: number) => void;
  /** The lesson or page being read, for the conversation to know about. */
  onReading?: (reading: AgentReading | undefined) => void;
  onBeforeLeave?: (agentId: string, save: (() => Promise<boolean>) | null) => void;
  onCanvasAddToChat: (text: string) => void;
  onCanvasTitleChange: (id: string, title: string) => void;
  onOpenFile: OpenFileFn;
  renderSession: (id: string) => ReactNode;
  sessionTitle: (id: string) => string;
};

/** Whether a page remembered from an earlier visit can still be shown. */
export async function restoredPageExists(agentId: string, page: MentorPage): Promise<boolean> {
  if (page.kind === "course") return !!await loadCourse(page.course.courseId, agentId);
  if (page.kind === "document") return !!await readAgentDocument(agentId, page.document.id);
  if (page.kind === "note") return !!await getNote(page.id);
  // Drawings and files say for themselves when they are gone.
  return true;
}

/**
 * One mentor's workspace: the outline and library on the left, the reader in
 * the middle and the conversation on the right. Opening anything replaces
 * what the reader showed; nothing opens beside it.
 */
export function MentorWorkspace({ agent, state, chat, leading, trailing, canvases, onOpen, onClose, onLessonChange, onRestoredChecked, onToggleLibrary, onLibraryChange, onDraft, courseBadge, onToggleChat, onResizeLibrary, onResizeChat, onReading, onBeforeLeave, onCanvasAddToChat, onCanvasTitleChange, onOpenFile, renderSession, sessionTitle }: Props) {
  const { data, errors, reload } = useAgentResources(agent.id);
  const body = useRef<HTMLDivElement>(null);
  const save = useRef<(() => Promise<boolean>) | null>(null);
  const [creating, setCreating] = useState(false);
  const [actionError, setActionError] = useState<string>();
  const mounted = useRef(true);
  useLayoutEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const registerSave = useCallback((next: (() => Promise<boolean>) | null) => {
    save.current = next;
    onBeforeLeave?.(agent.id, next);
  }, [agent.id, onBeforeLeave]);
  const leave = async (next: () => void) => { if (!save.current || await save.current()) next(); };
  const open = (page: MentorPage) => void leave(() => { setActionError(undefined); onOpen(page); });
  const close = () => void leave(onClose);

  const reading = readingOf(state.page, state.lesson);
  const readingKey = JSON.stringify(reading ?? null);
  useEffect(() => { onReading?.(reading); }, [readingKey]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => onReading?.(undefined), []); // eslint-disable-line react-hooks/exhaustive-deps
  const readerRef = useRef<HTMLElement>(null);
  useReadingPlace(readerRef, agent.id, readingKey);

  // A page remembered from the last visit may have been removed since.
  const restored = state.restored ? state.page : undefined;
  useEffect(() => {
    if (!restored) return;
    let live = true;
    restoredPageExists(agent.id, restored).then((exists) => { if (live) onRestoredChecked(restored, exists); }, () => { if (live) onRestoredChecked(restored, true); });
    return () => { live = false; };
  }, [agent.id, restored]); // eslint-disable-line react-hooks/exhaustive-deps

  const newNote = async () => {
    if (creating) return;
    setCreating(true); setActionError(undefined);
    try {
      const note = await createNote({ title: "", agentId: agent.id, ...(agent.sessionId ? { sourceSessionId: agent.sessionId } : {}) });
      if (mounted.current) open({ kind: "note", id: note.id });
    } catch (cause) { if (mounted.current) setActionError(String(cause)); }
    finally { if (mounted.current) setCreating(false); }
  };

  // A rename, move or trash in the Files tree follows the file the reader has
  // open, including its unsaved edits, so Save never writes the old path.
  const fileMoved = (from: string, to: string) => {
    const rebase = (path: string) => path === from || path.startsWith(`${from}/`) ? to + path.slice(from.length) : path;
    moveFileDrafts(rebase);
    const page = state.page;
    if (page?.kind !== "file") return;
    const next = rebase(page.path);
    if (next === page.path) return;
    setActionError(undefined);
    onOpen({ kind: "file", path: next });
  };
  const fileDeleted = (path: string) => {
    const page = state.page;
    if (page?.kind !== "file" || (page.path !== path && !page.path.startsWith(`${path}/`))) return;
    setFileDraft(page.path, null);
    onClose();
  };

  const library = useDragResize({
    min: LIBRARY_MIN, direction: "right", defaultWidth: 260, initial: state.libraryWidth, onCommit: onResizeLibrary,
    max: () => Math.max(LIBRARY_MIN, (body.current?.clientWidth ?? window.innerWidth) - READER_MIN - (state.chat ? CHAT_MIN : 0)),
  });
  const conversation = useDragResize({
    min: CHAT_MIN, direction: "left", defaultWidth: 420, initial: state.chatWidth, onCommit: onResizeChat,
    max: () => Math.max(CHAT_MIN, (body.current?.clientWidth ?? window.innerWidth) - READER_MIN - (state.library ? LIBRARY_MIN : 0)),
  });
  const name = agentLook(agent).name;
  const chatLabel = state.chat ? "Hide conversation" : `Chat with ${name}`;
  const libraryLabel = state.library ? "Hide library" : "Show library";

  return <section className="mentor-workspace" data-mentor-workspace={agent.id} aria-label={`${name} workspace`}>
    <header className="mentor-titlebar" data-tauri-drag-region="deep">
      {leading}
      <button type="button" data-tauri-drag-region="false" className="mentor-titlebar-button" aria-label={libraryLabel} title={libraryLabel} aria-pressed={state.library} onClick={onToggleLibrary}>
        <SidebarLeft className="size-3.5" />
      </button>
      <MentorBreadcrumb agent={agent} crumbs={mentorCrumbs(agent, state.page, state.lesson, data, sessionTitle)} />
      <div className="min-w-0 flex-1" data-tauri-drag-region="deep" />
      <button type="button" data-tauri-drag-region="false" className={`mentor-chat-toggle ${state.chat ? "bg-content/8 text-content" : "text-content/60"}`}
        aria-pressed={state.chat} aria-label={chatLabel} title={chatLabel} onClick={onToggleChat}>
        <AgentAvatar name={agent.avatar} color={agent.color} className="size-3.5 shrink-0" />
        {state.chat ? null : <span>Chat</span>}
      </button>
      {trailing}
    </header>
    <div ref={body} className="mentor-body">
      <aside ref={library.setPaneRef} className="mentor-library-column" hidden={!state.library} aria-label="Outline and library">
        <MentorLibrary agent={agent} data={data} errors={errors} onRetry={reload} page={state.page} lesson={state.lesson}
          onOpen={open} onNewNote={() => void newNote()} creatingNote={creating} onOpenFile={(path) => open({ kind: "file", path })}
          onFileMoved={fileMoved} onFileDeleted={fileDeleted}
          segment={state.segment} course={state.course} filter={state.filter} onChange={onLibraryChange} onDraft={onDraft} courseBadge={courseBadge} />
        {actionError ? <p role="alert" className="mentor-library-error">{actionError}</p> : null}
        <div role="separator" aria-label="Resize library" aria-orientation="vertical" tabIndex={0} className="mentor-resize mentor-resize--right"
          onPointerDown={library.onPointerDown} onDoubleClick={library.onDoubleClick}
          onKeyDown={(event) => {
            if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
            event.preventDefault();
            library.setWidth(library.width + (event.key === "ArrowRight" ? 20 : -20));
          }} />
      </aside>
      <main ref={readerRef} className="mentor-reader" aria-label="Reader" data-mentor-reader={state.page?.kind ?? "empty"}
        onKeyDown={(event) => {
          if (event.key !== "Escape" || event.defaultPrevented || !state.page) return;
          event.preventDefault(); event.stopPropagation();
          close();
        }}>
        <MentorReader agent={agent} page={state.page} request={state.request} canvases={canvases}
          onClose={close} onLessonChange={onLessonChange} onBeforeLeave={registerSave}
          onCanvasAddToChat={onCanvasAddToChat} onCanvasTitleChange={onCanvasTitleChange} onOpenFile={onOpenFile} renderSession={renderSession} />
      </main>
      <aside ref={conversation.setPaneRef} className="mentor-chat-column" hidden={!state.chat} aria-label={`Conversation with ${name}`}>
        <div role="separator" aria-label="Resize conversation" aria-orientation="vertical" tabIndex={0} className="mentor-resize mentor-resize--left"
          onPointerDown={conversation.onPointerDown} onDoubleClick={conversation.onDoubleClick}
          onKeyDown={(event) => {
            if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
            event.preventDefault();
            conversation.setWidth(conversation.width + (event.key === "ArrowLeft" ? 20 : -20));
          }} />
        {chat}
      </aside>
    </div>
  </section>;
}
