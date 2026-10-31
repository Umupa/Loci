import { useId, useMemo, useRef, type KeyboardEvent, type ReactNode } from "react";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { File, Palette, Plus, Search, StickyNote, X } from "../../../shared/ui/icons";
import type { Canvas } from "../../canvas/canvas";
import type { OpenFileFn } from "../../files/model/filePlace";
import type { CourseSummary } from "../../learning/model/course";
import { notePreview, type Note } from "../../notes";
import { agentLook, type Agent } from "../../agents/model/agent";
import type { StoredDocument } from "../../agents/model/agentDocuments";
import { LIBRARY_SEGMENTS, type LibrarySegment } from "../model/libraryCourse";
import { samePage, type MentorLesson, type MentorPage } from "../model/mentorPage";
import { MentorFilesSection } from "./filesSlot";
import { LibraryCourses, type CourseBadge } from "./LibraryCourses";
import { LibraryList, type LibraryEntry } from "./LibraryList";
import { focusFirstItem } from "./listKeys";

export type LibraryData = { courses?: CourseSummary[]; documents?: StoredDocument[]; notes?: Note[]; canvases?: Canvas[] };
export type LibraryChange = { segment?: LibrarySegment; course?: string; filter?: string };

const LABELS: Record<LibrarySegment, string> = { courses: "Courses", sources: "Sources", notes: "Notes", files: "Files" };

type Props = {
  agent: Agent;
  data: LibraryData;
  errors: Partial<Record<keyof LibraryData | "habits", string>>;
  onRetry: () => void;
  page?: MentorPage;
  lesson?: MentorLesson;
  onOpen: (page: MentorPage) => void;
  onNewNote: () => void;
  creatingNote: boolean;
  onOpenFile: OpenFileFn;
  /** The segment chosen for this mentor; unset picks one from what it has. */
  segment?: LibrarySegment;
  /** The course the Courses segment shows. */
  course?: string;
  filter?: { segment: LibrarySegment; text: string };
  onChange: (change: LibraryChange) => void;
  /** Puts a message in the mentor's composer without sending it. */
  onDraft: (text: string) => void;
  /** Room after a course's or a lesson's title, for counts such as highlights. */
  courseBadge?: CourseBadge;
};

/** The segment a mentor without a remembered choice opens on. */
export function defaultSegment(data: LibraryData, page?: MentorPage): LibrarySegment {
  return page?.kind === "course" || !data.courses || data.courses.length ? "courses" : "sources";
}

/**
 * The left column: one kind of thing at a time, chosen at the top. Courses
 * shows the course being learned and where to continue; Sources, Notes (with
 * drawings) and Files are one list each, with a filter for that list.
 */
export function MentorLibrary({ agent, data, errors, onRetry, page, lesson, onOpen, onNewNote, creatingNote, onOpenFile, segment: chosen, course, filter, onChange, onDraft, courseBadge }: Props) {
  const id = useId();
  const panel = useRef<HTMLDivElement>(null);
  const segment = chosen ?? defaultSegment(data, page);
  const query = filter?.segment === segment ? filter.text : "";
  const failure = Object.values(errors).find(Boolean);
  const notesCount = data.notes || data.canvases ? (data.notes?.length ?? 0) + (data.canvases?.length ?? 0) : undefined;
  const counts: Record<LibrarySegment, number | undefined> = {
    courses: data.courses && data.courses.length > 1 ? data.courses.length : undefined,
    sources: data.documents?.length || undefined,
    notes: notesCount || undefined,
    files: undefined,
  };

  const sources = useMemo<LibraryEntry[] | undefined>(() => data.documents?.map((document) => ({
    kind: "document", id: document.id, icon: <File className="size-3.5" />, title: document.title,
    subtitle: [document.subject, sourceName(document.sourceUrl)].filter(Boolean).join(" · "),
    target: { kind: "document", document: { id: document.id, title: document.title, body: "", ...(document.subject ? { subject: document.subject } : {}) } },
  })), [data.documents]);
  const notes = useMemo<LibraryEntry[] | undefined>(() => {
    if (!data.notes && !data.canvases) return undefined;
    const written = (data.notes ?? []).map((note) => ({ at: note.updatedAt, entry: {
      kind: "note", id: note.id, icon: <StickyNote className="size-3.5" />, title: note.title || "Untitled",
      subtitle: notePreview(note.body, note.title), target: { kind: "note", id: note.id },
    } satisfies LibraryEntry }));
    const drawn = (data.canvases ?? []).map((canvas) => ({ at: canvas.updatedAt, entry: {
      kind: "canvas", id: canvas.id, icon: <Palette className="size-3.5" />, title: canvas.title,
      subtitle: formatRelativeTime(new Date(canvas.updatedAt).toISOString()), target: { kind: "canvas", id: canvas.id },
    } satisfies LibraryEntry }));
    return [...written, ...drawn].sort((a, b) => b.at - a.at).map(({ entry }) => entry);
  }, [data.notes, data.canvases]);

  const tabKeys = (event: KeyboardEvent<HTMLDivElement>) => {
    const at = LIBRARY_SEGMENTS.indexOf(segment);
    const next = event.key === "ArrowRight" ? (at + 1) % LIBRARY_SEGMENTS.length
      : event.key === "ArrowLeft" ? (at + LIBRARY_SEGMENTS.length - 1) % LIBRARY_SEGMENTS.length
        : event.key === "Home" ? 0 : event.key === "End" ? LIBRARY_SEGMENTS.length - 1 : -1;
    if (next < 0) return;
    event.preventDefault();
    onChange({ segment: LIBRARY_SEGMENTS[next] });
    event.currentTarget.querySelector<HTMLElement>(`[data-segment="${LIBRARY_SEGMENTS[next]}"]`)?.focus();
  };

  let body: ReactNode;
  if (segment === "courses") {
    body = <LibraryCourses agent={agent} courses={data.courses} selected={course} page={page} lesson={lesson}
      onOpen={onOpen} onSelect={(courseId) => onChange({ course: courseId })} onDraft={onDraft} badge={courseBadge} />;
  } else if (segment === "files") {
    body = MentorFilesSection ? <MentorFilesSection agentId={agent.id} filter={query} onOpenFile={(path) => onOpenFile(path)} /> : null;
  } else {
    const entries = segment === "sources" ? sources : notes;
    body = <LibraryList entries={entries} query={query} isCurrent={(target) => samePage(page, target)} onOpen={onOpen}
      empty={segment === "sources" ? `Material ${agentLook(agent).name} saves, and documents it writes, appear here.` : "Your notes and drawings appear here."} />;
  }

  return <nav className="mentor-library" aria-label={`${agent.name || "Mentor"} library`} data-mentor-library={agent.id} data-library-segment={segment}>
    {failure ? <div role="alert" className="mentor-library-error"><p>{failure}</p><button type="button" onClick={onRetry}>Retry</button></div> : null}
    <div role="tablist" aria-label="Library" className="mentor-library-segments" onKeyDown={tabKeys}>
      {LIBRARY_SEGMENTS.map((entry) => <button key={entry} type="button" role="tab" id={`${id}-${entry}`} data-segment={entry}
        aria-selected={entry === segment} aria-controls={`${id}-panel`} tabIndex={entry === segment ? 0 : -1}
        className="mentor-library-segment" onClick={() => onChange({ segment: entry })}>
        <span>{LABELS[entry]}</span>{counts[entry] ? <span className="mentor-library-count">{counts[entry]}</span> : null}
      </button>)}
    </div>
    {segment === "courses" ? null : <div className="mentor-library-filter">
      <label className="mentor-library-filter-box">
        <Search aria-hidden className="size-3 shrink-0 opacity-50" />
        <input type="text" value={query} placeholder={`Filter ${LABELS[segment].toLowerCase()}`} aria-label={`Filter ${LABELS[segment].toLowerCase()}`}
          spellCheck={false} autoComplete="off"
          onChange={(event) => onChange({ segment, filter: event.target.value })}
          onKeyDown={(event) => {
            if (event.nativeEvent.isComposing) return;
            if (event.key === "Escape" && query) { event.preventDefault(); event.stopPropagation(); onChange({ segment, filter: "" }); }
            else if (event.key === "ArrowDown" && focusFirstItem(panel.current)) event.preventDefault();
          }} />
        {query ? <button type="button" className="mentor-library-filter-clear" aria-label="Clear filter" title="Clear filter" onClick={() => onChange({ segment, filter: "" })}><X className="size-3" /></button> : null}
      </label>
      {segment === "notes" ? <button type="button" className="mentor-library-action" title="New note" aria-label="New note" disabled={creatingNote} onClick={onNewNote}><Plus className="size-3.5" /></button> : null}
    </div>}
    <div ref={panel} role="tabpanel" id={`${id}-panel`} aria-labelledby={`${id}-${segment}`} className="mentor-library-panel" data-library-section={segment}>
      {body}
    </div>
  </nav>;
}

function sourceName(url: string | null | undefined): string {
  if (!url) return "";
  try { return new URL(url).hostname; } catch { return "Source"; }
}
