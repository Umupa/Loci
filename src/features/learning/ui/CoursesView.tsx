import { ask } from "@tauri-apps/plugin-dialog";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { OverlayNav } from "../../../app/shell/TitleBar";
import { WindowControls } from "../../../app/shell/WindowControls";
import { IS_MAC } from "../../../platform/tauri/platform";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { Chatting, ListFilter, LoaderCircle, Mortarboard, RefreshCw, Search, Trash2 } from "../../../shared/ui/icons";
import { ACTION_GHOST, Chip, EmptyDetail, IconButton } from "../../../shared/ui/inboxParts";
import { agentLook, agentsSnapshot, listAgents, subscribeAgents, type Agent } from "../../agents/model/agent";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { COURSES_CHANGED_EVENT, deleteCourse, loadCourseSummaries, type CourseSummary } from "../model/course";
import { CoursePane, PROGRESS_EVENT } from "./CoursePane";

type Props = {
  besideRail?: boolean;
  compactRail?: boolean;
  onClose: () => void;
  onToggleSidebar?: () => void;
  /** Go to the agent's conversation to talk the course over. */
  onOpenAgent: (agentId: string) => void;
};

const LIST_MIN = 240;
const LIST_MAX = 420;
const LIST_DEFAULT = 300;
let rememberedListWidth = LIST_DEFAULT;
let rememberedSelection: { agentId: string; id: string } | null = null;

const sameCourse = (a: { agentId: string; id: string } | null, b: { agentId: string; id: string }) => !!a && a.agentId === b.agentId && a.id === b.id;

/** Every course in every agent's library, newest first; a course whose owner is gone is not listed. */
export function CoursesView({ besideRail = false, compactRail = false, onClose, onToggleSidebar, onOpenAgent }: Props) {
  const roster = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  const agents = useMemo(() => new Map(listAgents().map((agent) => [agent.id, agent])), [roster]);
  const [courses, setCourses] = useState<CourseSummary[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [agentFilter, setAgentFilter] = useState<string | null>(null);
  const [menuAnchor, setMenuAnchor] = useState<HTMLElement | null>(null);
  const [selected, setSelectedState] = useState(rememberedSelection);
  const refreshGeneration = useRef(0);
  const resize = useDragResize({
    min: LIST_MIN,
    max: () => Math.min(LIST_MAX, Math.round(window.innerWidth * 0.5)),
    defaultWidth: LIST_DEFAULT,
    initial: rememberedListWidth,
    onCommit: (width) => { rememberedListWidth = width; },
  });

  const setSelected = (next: { agentId: string; id: string } | null) => {
    rememberedSelection = next;
    setSelectedState(next);
  };

  const refresh = useCallback(() => {
    const generation = ++refreshGeneration.current;
    setLoading(true);
    void loadCourseSummaries().then(
      (list) => { if (generation === refreshGeneration.current) { setCourses(list); setError(null); } },
      (cause) => { if (generation === refreshGeneration.current) setError(String(cause)); },
    ).finally(() => { if (generation === refreshGeneration.current) setLoading(false); });
  }, []);

  useEffect(() => {
    refresh();
    // Reading a lesson changes the counts on its card.
    window.addEventListener(COURSES_CHANGED_EVENT, refresh);
    window.addEventListener(PROGRESS_EVENT, refresh);
    return () => {
      refreshGeneration.current += 1;
      window.removeEventListener(COURSES_CHANGED_EVENT, refresh);
      window.removeEventListener(PROGRESS_EVENT, refresh);
    };
  }, [refresh]);

  const owned = useMemo(() => (courses ?? []).filter((course) => agents.has(course.agentId)), [courses, agents]);
  const shown = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return owned.filter((course) => (!agentFilter || course.agentId === agentFilter)
      && (!needle || course.title.toLowerCase().includes(needle) || agentName(agents.get(course.agentId)).toLowerCase().includes(needle)));
  }, [owned, agents, agentFilter, query]);
  const current = selected ? owned.find((course) => sameCourse(selected, course)) : undefined;
  const owners = useMemo(() => [...new Set(owned.map((course) => course.agentId))].flatMap((id) => agents.get(id) ?? []), [owned, agents]);

  const menuItems: ContextMenuItem[] = [
    { kind: "item", id: "", label: "All agents", checked: !agentFilter },
    ...(owners.length ? [{ kind: "sep" as const }] : []),
    ...owners.map((agent) => ({ kind: "item" as const, id: agent.id, label: agentName(agent), checked: agentFilter === agent.id })),
  ];

  const remove = async (course: CourseSummary) => {
    if (!await ask(`Delete "${course.title}"? Its reading progress goes with it. The documents it points at stay in the library.`,
      { title: "Delete course", kind: "warning", okLabel: "Delete", cancelLabel: "Cancel" })) return;
    try {
      await deleteCourse(course.agentId, course.id);
      if (sameCourse(selected, course)) setSelected(null);
    } catch (cause) {
      setError(String(cause));
    }
  };

  const list = (
    <div ref={resize.setPaneRef} className="relative flex h-full min-h-0 shrink-0 flex-col border-r border-stroke">
      <div className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
        <div className="relative flex h-7 min-w-0 flex-1 items-center">
          <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Filter courses" aria-label="Filter courses"
            spellCheck={false} autoComplete="off"
            className="h-7 w-full rounded-md bg-transparent pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/40" />
        </div>
        <IconButton label="Filter by agent" active={!!menuAnchor || !!agentFilter} onClick={(event) => setMenuAnchor(event.currentTarget)}>
          <ListFilter className="size-3" />
        </IconButton>
        <IconButton label="Refresh" onClick={refresh}>
          {loading ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />}
        </IconButton>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-none">
        {error ? <p role="alert" className="px-3 py-2 text-[12px] text-red-400/90">{error}</p> : null}
        {courses === null ? (
          <div className="flex justify-center py-10 text-content/40"><LoaderCircle className="size-4 animate-spin" /></div>
        ) : !shown.length ? (
          <p className="px-3 py-2 text-[12px] text-content/50">
            {query.trim() || agentFilter ? "No matching courses" : "No courses yet. Ask an agent to build one."}
          </p>
        ) : (
          <ul className="flex flex-col gap-0.5 p-1.5">
            {shown.map((course) => (
              <li key={`${course.agentId}/${course.id}`}>
                <CourseRow course={course} agent={agents.get(course.agentId)!} active={sameCourse(selected, course)}
                  onSelect={() => setSelected({ agentId: course.agentId, id: course.id })} />
              </li>
            ))}
          </ul>
        )}
      </div>
      <div role="separator" aria-orientation="vertical" aria-label="Resize course list"
        className={`absolute inset-y-0 -right-px z-10 w-1.5 cursor-col-resize touch-none ${resize.dragging ? "bg-content/15" : "hover:bg-content/10"}`}
        onPointerDown={resize.onPointerDown} onDoubleClick={resize.onDoubleClick} />
    </div>
  );

  return (
    <div role="region" aria-label="Courses" data-app-courses className="flex min-h-0 min-w-0 flex-1 flex-col text-content">
      <div className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
        {IS_MAC && compactRail ? <div className="w-4 shrink-0" /> : null}
        {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
        {besideRail ? null : <OverlayNav onBack={onClose} onToggleSidebar={onToggleSidebar} />}
        <div className="flex min-w-0 flex-1 items-center gap-2 px-3 text-[13px]">
          <Mortarboard className="size-3.5 shrink-0 text-content/45" />
          <span className="min-w-0 truncate text-content">Courses</span>
        </div>
        {IS_MAC ? null : <WindowControls />}
      </div>
      <div className="flex min-h-0 min-w-0 flex-1">
        {list}
        <div className="relative flex min-h-0 min-w-0 flex-1 flex-col">
          {current ? (
            <CoursePane key={`${current.agentId}/${current.id}`} courseId={current.id} agentId={current.agentId} title={current.title}
              focused onFocus={() => undefined} onClose={() => setSelected(null)} onDiscussed={() => onOpenAgent(current.agentId)}
              actions={<>
                <button type="button" onClick={() => onOpenAgent(current.agentId)} className={ACTION_GHOST}>
                  <Chatting className="size-3.5" /> Chat with {agentName(agents.get(current.agentId))}
                </button>
                <IconButton label="Delete course" onClick={() => void remove(current)}><Trash2 className="size-3.5" /></IconButton>
              </>} />
          ) : (
            <EmptyDetail icon={<Mortarboard className="size-6" />}>Select a course</EmptyDetail>
          )}
        </div>
      </div>
      {menuAnchor ? <ContextMenu anchor={menuAnchor} items={menuItems} onPick={(id) => { setAgentFilter(id || null); setMenuAnchor(null); }}
        onClose={() => setMenuAnchor(null)} /> : null}
    </div>
  );
}

function agentName(agent: Agent | undefined): string {
  return agent ? agentLook(agent).name : "Agent";
}

function CourseRow({ course, agent, active, onSelect }: { course: CourseSummary; agent: Agent; active: boolean; onSelect: () => void }) {
  const look = agentLook(agent);
  const done = course.itemCount > 0 && course.masteredCount >= course.itemCount;
  const kind = course.engine === "build-your-own" ? "steps" : "lessons";
  return (
    <button type="button" aria-current={active ? "true" : undefined} onClick={onSelect}
      className={`flex w-full flex-col rounded-md border px-2.5 py-2 text-left ${
        active ? "border-transparent bg-selection text-content" : "border-transparent text-content/80 hover:bg-content/5 hover:text-content"}`}>
      <span className="flex items-center gap-2">
        <span className="flex min-w-0 flex-1 items-center gap-1.5">
          <AgentAvatar name={look.avatar} color={look.color} className="size-3.5 shrink-0" />
          <span className="min-w-0 truncate text-[11px] text-content/50">
            {look.name} · {course.engine === "build-your-own" ? "Build your own" : "Reading"}
          </span>
        </span>
        <span className="shrink-0 text-[11px] tabular-nums text-content/45">{formatRelativeTime(new Date(course.updatedAt).toISOString())}</span>
      </span>
      <span className="mt-1 line-clamp-2 text-[13px] font-semibold leading-snug text-content">{course.title}</span>
      <span className="mt-1.5 flex min-w-0 items-center gap-2">
        <span aria-hidden className="h-1 min-w-0 flex-1 overflow-hidden rounded-full bg-content/10">
          <span className={`block h-full rounded-full ${done ? "bg-emerald-400" : "bg-accent"}`}
            style={{ width: `${course.itemCount ? Math.round((course.masteredCount / course.itemCount) * 100) : 0}%` }} />
        </span>
        <Chip compact dot={done ? "bg-emerald-400" : course.masteredCount ? "bg-accent" : "bg-content/30"}>
          {course.masteredCount}/{course.itemCount} {kind}
        </Chip>
      </span>
    </button>
  );
}
