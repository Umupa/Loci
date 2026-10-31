import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { File, Mortarboard, Palette, Search, StickyNote } from "../../../shared/ui/icons";
import { MatchText } from "../../../shared/ui/MatchText";
import { listAgents, type Agent } from "../../agents/model/agent";
import { listAgentDocuments, type StoredDocument } from "../../agents/model/agentDocuments";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { loadCanvases } from "../../canvas/canvas";
import { loadCourse, loadCourseSummaries, type CourseWithProgress } from "../../learning/model/course";
import { loadNotes } from "../../notes";
import { mentorSearchItems, searchMentorItems, type MentorSearchItem, type MentorSearchSources } from "../model/mentorSearch";
import "./MentorSearch.css";

/** Everything the palette searches, read fresh each time it opens. */
export async function loadMentorSearchSources(agents: readonly Agent[] = listAgents()): Promise<MentorSearchSources> {
  const ids = new Set(agents.map((agent) => agent.id));
  const [summaries, notes, canvases, documents] = await Promise.all([
    loadCourseSummaries().catch(() => []),
    loadNotes(true).catch(() => []),
    loadCanvases(true).catch(() => []),
    Promise.all(agents.map(async (agent) => [agent.id, await listAgentDocuments(agent.id).catch(() => [] as StoredDocument[])] as const)),
  ]);
  const courses = (await Promise.all(summaries.filter((course) => ids.has(course.agentId))
    .map((course) => loadCourse(course.id, course.agentId).catch(() => null)))).filter((course): course is CourseWithProgress => !!course);
  return { agents, courses, documents: new Map(documents), notes, canvases };
}

/** The characters of each query word where it first appears in the title. */
function matchPositions(title: string, query: string): number[] {
  const text = title.toLocaleLowerCase();
  return query.toLocaleLowerCase().split(/\s+/).filter(Boolean).flatMap((word) => {
    const at = text.indexOf(word);
    return at < 0 ? [] : Array.from({ length: word.length }, (_, offset) => at + offset);
  });
}

const KIND_LABEL: Record<MentorSearchItem["kind"], string> = { mentor: "Mentor", course: "Course", lesson: "Lesson", source: "Source", note: "Note", canvas: "Canvas" };

type Props = {
  onPick: (item: MentorSearchItem) => void;
  onClose: () => void;
  /** For tests: what to search instead of loading it. */
  sources?: MentorSearchSources;
};

/** ⌘K: find a mentor, or a course, lesson, source, note or canvas it keeps, and open it. */
export function MentorSearch({ onPick, onClose, sources }: Props) {
  const [loaded, setLoaded] = useState<MentorSearchSources | null>(sources ?? null);
  const [error, setError] = useState<string>();
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    input.current?.focus();
    if (sources) return;
    let live = true;
    loadMentorSearchSources().then((value) => { if (live) setLoaded(value); }, (cause: unknown) => { if (live) setError(String(cause)); });
    return () => { live = false; };
  }, [sources]);
  const items = useMemo(() => loaded ? mentorSearchItems(loaded) : [], [loaded]);
  const agents = useMemo(() => new Map((loaded?.agents ?? []).map((agent) => [agent.id, agent])), [loaded]);
  const results = useMemo(() => searchMentorItems(items, query), [items, query]);
  useEffect(() => setActive(0), [query]);
  useEffect(() => { list.current?.querySelector('[aria-selected="true"]')?.scrollIntoView?.({ block: "nearest" }); }, [active]);
  const pick = (item: MentorSearchItem | undefined) => { if (item) { onPick(item); onClose(); } };
  const icon = (item: MentorSearchItem): ReactNode => {
    if (item.kind === "mentor") {
      const agent = agents.get(item.agentId!);
      return agent ? <AgentAvatar name={agent.avatar} color={agent.color} className="size-4" /> : null;
    }
    const Icon = item.kind === "note" ? StickyNote : item.kind === "canvas" ? Palette : item.kind === "source" ? File : Mortarboard;
    return <Icon className="size-3.5" strokeWidth={1.75} />;
  };
  return <div className="mentor-search-backdrop" onPointerDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <div role="dialog" aria-label="Search mentors" className="mentor-search" data-app-search
      onKeyDown={(event) => {
        if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); onClose(); }
        else if (event.key === "ArrowDown") { event.preventDefault(); setActive((index) => Math.min(index + 1, results.length - 1)); }
        else if (event.key === "ArrowUp") { event.preventDefault(); setActive((index) => Math.max(index - 1, 0)); }
        else if (event.key === "Enter" && !event.nativeEvent.isComposing) { event.preventDefault(); pick(results[active]); }
      }}>
      <label className="mentor-search-field">
        <Search className="size-4 shrink-0 text-content/45" strokeWidth={1.75} />
        <input ref={input} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search mentors, courses, lessons, sources, notes and canvases"
          aria-label="Search" aria-controls="mentor-search-results" aria-activedescendant={results[active] ? `mentor-search-${active}` : undefined} />
      </label>
      <div ref={list} id="mentor-search-results" role="listbox" aria-label="Results" className="mentor-search-results">
        {error ? <p role="alert" className="mentor-search-empty">{error}</p>
          : !loaded ? <p role="status" className="mentor-search-empty">Loading…</p>
          : !results.length ? <p className="mentor-search-empty">{query.trim() ? "Nothing matches." : "No mentors yet."}</p>
          : results.map((item, index) => <button key={item.id} id={`mentor-search-${index}`} type="button" role="option" aria-selected={index === active}
            data-search-kind={item.kind} className="mentor-search-row" onPointerMove={() => setActive(index)} onClick={() => pick(item)}>
            <span aria-hidden className="mentor-search-icon">{icon(item)}</span>
            <span className="mentor-search-copy">
              <span className="mentor-search-title"><MatchText text={item.title} positions={matchPositions(item.title, query)} active /></span>
              <span className="mentor-search-context">{item.context}</span>
            </span>
            <span className="mentor-search-kind">{KIND_LABEL[item.kind]}</span>
          </button>)}
      </div>
    </div>
  </div>;
}
