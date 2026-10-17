import { useCallback, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import type { AgentOverviewPage, AgentOverviewState, AgentOverviewTab } from "../../../app/hooks/useAgentOverview";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { Clock, File, Mortarboard, Palette, PanelLeft, Plus, StickyNote } from "../../../shared/ui/icons";
import type { OpenCourseDetail } from "../../learning/model/course";
import { CoursePane } from "../../learning/ui/CoursePane";
import { createNote, notePreview } from "../../notes";
import { NotePane } from "../../notes/ui/NotePane";
import type { RecentProject } from "../../projects/model/recents";
import type { AgentDocument } from "../../sessions/model/cards";
import { agentLook, type Agent } from "../model/agent";
import { AgentDocumentReader } from "./AgentDocumentReader";
import { AgentHabitDetail, AgentHabits, AgentNewHabit } from "./AgentHabits";
import { HABITS_MAX } from "../model/agentHabits";
import { useAgentResources } from "./useAgentResources";
import "./AgentOverview.css";

const TABS = [
  { id: "courses", label: "Courses", Icon: Mortarboard },
  { id: "documents", label: "Documents", Icon: File },
  { id: "notes", label: "Notes", Icon: StickyNote },
  { id: "habits", label: "Habits", Icon: Clock },
  { id: "canvases", label: "Canvases", Icon: Palette },
] as const;
const EMPTY: Record<AgentOverviewTab, string> = {
  courses: "Ask your agent to arrange a course. Saved courses appear here.",
  documents: "Sources and documents saved by this agent appear here.",
  notes: "Keep your own notes here, or save a document as a note.",
  habits: "Ask your agent to schedule recurring work, or add a habit.",
  canvases: "Drawings saved in this agent’s library appear here.",
};

type Props = {
  agent: Agent;
  state: AgentOverviewState;
  recents: readonly RecentProject[];
  onTabChange: (tab: AgentOverviewTab) => void;
  onOpen: (page: AgentOverviewPage) => void;
  onBack: () => void;
  onClose: () => void;
  onResize: (width: number) => void;
  onExpandCourse: (course: OpenCourseDetail) => void;
  onExpandDocument: (document: AgentDocument) => void;
  onExpandNote: (id: string) => void;
  onOpenCanvas: (id: string) => void;
  onBeforeLeave?: (agentId: string, save: (() => Promise<boolean>) | null) => void;
};

/** A compact index of one agent's work, with readers on top of the same list. */
export function AgentOverview({ agent, state, recents, onTabChange, onOpen, onBack, onClose, onResize, onExpandCourse, onExpandDocument, onExpandNote, onOpenCanvas, onBeforeLeave }: Props) {
  const { data, errors, reload } = useAgentResources(agent.id);
  const overview = useRef<HTMLElement | null>(null);
  const scroll = useRef<HTMLDivElement>(null);
  const positions = useRef<Partial<Record<AgentOverviewTab, number>>>({});
  const selection = useRef<Partial<Record<AgentOverviewTab, string>>>({});
  const save = useRef<(() => Promise<boolean>) | null>(null);
  const [actionError, setActionError] = useState<string>();
  const [creating, setCreating] = useState(false);
  const mounted = useRef(true);
  useLayoutEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const registerSave = useCallback((next: (() => Promise<boolean>) | null) => {
    save.current = next;
    onBeforeLeave?.(agent.id, next);
  }, [agent.id, onBeforeLeave]);
  const leave = async (next: () => void) => { if (!save.current || await save.current()) next(); };
  const resize = useDragResize({
    min: 320, max: () => Math.max(320, (overview.current?.parentElement?.clientWidth ?? window.innerWidth) - 360),
    direction: "left", defaultWidth: 400, initial: state.width, onCommit: onResize,
  });
  const setOverviewRef = useCallback((element: HTMLElement | null) => {
    overview.current = element;
    resize.setPaneRef(element);
  }, [resize.setPaneRef]);
  useLayoutEffect(() => {
    if (scroll.current) scroll.current.scrollTop = positions.current[state.tab] ?? 0;
  }, [state.tab, state.page, state.open]);
  const show = (page: AgentOverviewPage, id: string) => {
    selection.current[state.tab] = id;
    onOpen(page);
  };
  const expand = (run: () => void) => { run(); onBack(); };
  const create = async () => {
    if (creating) return;
    setCreating(true); setActionError(undefined);
    try {
      const note = await createNote({ title: "", agentId: agent.id, ...(agent.sessionId ? { sourceSessionId: agent.sessionId } : {}) });
      if (mounted.current) show({ kind: "note", id: note.id }, note.id);
    } catch (cause) { if (mounted.current) setActionError(String(cause)); }
    finally { if (mounted.current) setCreating(false); }
  };
  const page = state.page;
  const current = TABS.find((tab) => tab.id === state.tab)!;
  const contents = data[state.tab];
  let reader: ReactNode;
  if (page?.kind === "course") {
    reader = <CoursePane key={`${agent.id}/${page.course.courseId}`} {...page.course} sourceSessionId={agent.sessionId}
      focused onFocus={() => {}} onClose={() => void leave(onClose)} onBack={onBack}
      onExpand={(itemId) => expand(() => onExpandCourse({ ...page.course, itemId, sourceSessionId: agent.sessionId }))} />;
  } else if (page?.kind === "document") {
    reader = <AgentDocumentReader key={`${agent.id}/${page.document.id}`} agentId={agent.id} document={page.document}
      focused onFocus={() => {}} onClose={onClose} onBack={onBack}
      onExpand={(document) => expand(() => onExpandDocument(document))} />;
  } else if (page?.kind === "note") {
    reader = <NotePane key={page.id} noteId={page.id} agentId={agent.id} recents={recents}
      focused onFocus={() => {}} onClose={onClose} onBack={onBack} onBeforeLeave={registerSave}
      onExpand={() => expand(() => onExpandNote(page.id))} />;
  } else if (page?.kind === "new-habit") {
    reader = <AgentNewHabit agentId={agent.id} onBack={onBack} onClose={onClose} />;
  } else if (page?.kind === "habit") {
    reader = <AgentHabitDetail agentId={agent.id} habit={data.habits?.find((habit) => habit.id === page.id)}
      loading={data.habits === undefined} onBack={onBack} onClose={onClose} />;
  }
  return <>
    {state.open ? <button type="button" className="agent-overview-backdrop" aria-label="Close overview overlay" onClick={() => void leave(onClose)} /> : null}
    <aside ref={setOverviewRef} hidden={!state.open} aria-label={`${agentLook(agent).name} overview`} className="agent-overview" data-agent-overview={agent.id}
      onKeyDown={(event) => {
        if (event.key !== "Escape" || event.defaultPrevented) return;
        event.preventDefault(); event.stopPropagation();
        void leave(state.page ? onBack : onClose);
      }}>
      <div role="separator" aria-label="Resize overview" aria-orientation="vertical" tabIndex={0} className="agent-overview-resize" onPointerDown={resize.onPointerDown}
        onKeyDown={(event) => {
          if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
          event.preventDefault();
          resize.setWidth(resize.width + (event.key === "ArrowLeft" ? 20 : -20));
        }} />
      {reader ?? <>
        <header className="agent-overview-header" data-tauri-drag-region="deep">
          <div role="tablist" aria-label="Agent resources" className="agent-overview-tabs" onKeyDown={(event) => {
            const index = TABS.findIndex((tab) => tab.id === state.tab);
            const next = event.key === "ArrowRight" ? (index + 1) % TABS.length : event.key === "ArrowLeft" ? (index + TABS.length - 1) % TABS.length : event.key === "Home" ? 0 : event.key === "End" ? TABS.length - 1 : undefined;
            if (next === undefined) return;
            event.preventDefault();
            void leave(() => { onTabChange(TABS[next].id); event.currentTarget.querySelector<HTMLButtonElement>(`[data-tab="${TABS[next].id}"]`)?.focus(); });
          }}>
            {TABS.map(({ id, label, Icon }) => <button key={id} type="button" role="tab" data-tab={id}
              aria-label={`${label}${data[id] ? `, ${data[id]!.length}` : ""}`} aria-selected={state.tab === id} tabIndex={state.tab === id ? 0 : -1}
              title={label} data-tauri-drag-region="false" className="agent-overview-tab" onClick={() => void leave(() => { setActionError(undefined); onTabChange(id); })}>
              <Icon className="size-3.5 shrink-0" strokeWidth={1.75} />
              <span className="agent-overview-tab-label" data-open={state.tab === id} aria-hidden={state.tab !== id}><span><span>{label}</span>{data[id]?.length ? <span className="agent-overview-count">{data[id]!.length}</span> : null}</span></span>
            </button>)}
          </div>
          {state.tab === "notes" ? <button type="button" title="New note" aria-label="New note" disabled={creating} className="agent-overview-action" onClick={() => void create()}><Plus className="size-3.5" /></button> : null}
          {state.tab === "habits" ? <button type="button" title="New habit" aria-label="New habit" disabled={!data.habits || data.habits.length >= HABITS_MAX} className="agent-overview-action" onClick={() => onOpen({ kind: "new-habit" })}><Plus className="size-3.5" /></button> : null}
          <button type="button" title="Hide overview" aria-label="Hide overview" className="agent-overview-action" data-tauri-drag-region="false" onClick={() => void leave(onClose)}><PanelLeft className="size-3.5 rotate-180" /></button>
        </header>
        <div ref={scroll} role="tabpanel" aria-label={current.label} className="agent-overview-list" onScroll={(event) => { positions.current[state.tab] = event.currentTarget.scrollTop; }}>
          {errors[state.tab] || actionError ? <div role="alert" className="agent-overview-error"><p>{actionError ?? errors[state.tab]}</p><button type="button" onClick={reload}>Retry</button></div> : null}
          {contents === undefined ? !errors[state.tab] && <p role="status" className="agent-overview-empty">Loading {current.label.toLowerCase()}…</p>
            : state.tab !== "habits" && !contents.length ? <p className="agent-overview-empty">{EMPTY[state.tab]}</p> : null}
          {state.tab === "courses" ? data.courses?.map((course) => <ResourceRow key={course.id} icon={<Mortarboard className="size-4" />} title={course.title}
            subtitle={`${course.itemCount} ${course.engine === "reading" ? "lessons" : "steps"} · ${course.masteredCount} ${course.engine === "reading" ? "read" : "mastered"}`}
            selected={selection.current.courses === course.id} kind="course" id={course.id}
            onOpen={() => show({ kind: "course", course: { courseId: course.id, agentId: agent.id, title: course.title, sourceSessionId: agent.sessionId } }, course.id)} />) : null}
          {state.tab === "documents" ? data.documents?.map((document) => <ResourceRow key={document.id} icon={<File className="size-4" />} title={document.title}
            subtitle={[document.subject, sourceName(document.sourceUrl) || "Document"].filter(Boolean).join(" · ")}
            selected={selection.current.documents === document.id} kind="document" id={document.id}
            onOpen={() => show({ kind: "document", document: { id: document.id, title: document.title, body: "", ...(document.subject ? { subject: document.subject } : {}) } }, document.id)} />) : null}
          {state.tab === "notes" ? data.notes?.map((note) => <ResourceRow key={note.id} icon={<StickyNote className="size-4" />} title={note.title}
            subtitle={notePreview(note.body, note.title) || "Note"} selected={selection.current.notes === note.id} kind="note" id={note.id}
            onOpen={() => show({ kind: "note", id: note.id }, note.id)} />) : null}
          {state.tab === "canvases" ? data.canvases?.map((canvas) => <ResourceRow key={canvas.id} icon={<Palette className="size-4" />} title={canvas.title}
            subtitle={formatRelativeTime(new Date(canvas.updatedAt).toISOString()) || "Drawing"} selected={selection.current.canvases === canvas.id} kind="canvas" id={canvas.id}
            onOpen={() => { selection.current.canvases = canvas.id; onOpenCanvas(canvas.id); }} />) : null}
          {state.tab === "habits" && data.habits ? <AgentHabits agentId={agent.id} habits={data.habits} onCreate={() => onOpen({ kind: "new-habit" })} onOpen={(id) => show({ kind: "habit", id }, id)} /> : null}
        </div>
      </>}
    </aside>
  </>;
}

function sourceName(url: string | null | undefined): string {
  if (!url) return "";
  try { return new URL(url).hostname; } catch { return "Source"; }
}

function ResourceRow({ icon, title, subtitle, selected, kind, id, onOpen }: { icon: ReactNode; title: string; subtitle: string; selected: boolean; kind: string; id: string; onOpen: () => void }) {
  return <button type="button" className="agent-resource-row" data-resource-kind={kind} data-resource-id={id} aria-label={`${kind}: ${title}`} aria-current={selected || undefined} onClick={onOpen} title={title}>
    <span aria-hidden className="agent-resource-icon">{icon}</span>
    <span className="agent-resource-copy"><span className="agent-resource-title">{title}</span><span className="agent-resource-subtitle">{subtitle}</span></span>
  </button>;
}
