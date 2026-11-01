import { useId, useLayoutEffect, useMemo, useRef, type KeyboardEvent, type ReactNode, type RefObject } from "react";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { File, Folder, Mortarboard, Palette, Pencil, PenLine, Plus, Search, StickyNote, X, type IconComponent } from "../../../shared/ui/icons";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import type { Canvas } from "../../canvas/canvas";
import type { OpenFileFn } from "../../files/model/filePlace";
import type { CourseSummary } from "../../learning/model/course";
import { notePreview, type Note } from "../../notes";
import { agentLook, type Agent } from "../../agents/model/agent";
import { isGuide, type StoredDocument } from "../../agents/model/agentDocuments";
import { LIBRARY_SEGMENTS, type LibrarySegment } from "../model/libraryCourse";
import { samePage, type MentorLesson, type MentorPage } from "../model/mentorPage";
import { MentorFilesSection } from "./filesSlot";
import { LibraryCourses, type CourseBadge } from "./LibraryCourses";
import { LibraryList, type LibraryEntry } from "./LibraryList";
import { focusFirstItem } from "./listKeys";

export type LibraryData = { courses?: CourseSummary[]; documents?: StoredDocument[]; notes?: Note[]; canvases?: Canvas[] };
export type LibraryChange = { segment?: LibrarySegment; course?: string; filter?: string };

const LABELS: Record<LibrarySegment, string> = { courses: "Courses", sources: "Sources", notes: "Notes", files: "Files" };
const ICONS: Record<LibrarySegment, IconComponent> = { courses: Mortarboard, sources: File, notes: Pencil, files: Folder };

type Props = {
  agent: Agent;
  /** Ahead of the header's segments, when the library is the window's left edge. */
  headerLeading?: ReactNode;
  /** At the end of the header, such as folding the library away. */
  headerEnd?: ReactNode;
  data: LibraryData;
  errors: Partial<Record<keyof LibraryData | "habits", string>>;
  onRetry: () => void;
  page?: MentorPage;
  lesson?: MentorLesson;
  onOpen: (page: MentorPage) => void;
  onNewNote: () => void;
  creatingNote: boolean;
  onOpenFile: OpenFileFn;
  /** A file or folder in the Files tree was renamed or moved. */
  onFileMoved?: (from: string, to: string) => void;
  /** A file or folder in the Files tree went to the Trash. */
  onFileDeleted?: (path: string) => void;
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
  /** A source, guide, course or note saved by the turn that is running now. */
  isNew?: (kind: "document" | "course" | "note" | "canvas", id: string) => boolean;
};

/**
 * The segment a mentor without a remembered choice opens on: the kind of thing
 * the reader already shows, and Courses otherwise. It reads only the page, so
 * a late listing cannot move the tab after it has been seen.
 */
export function defaultSegment(page?: MentorPage): LibrarySegment {
  if (page?.kind === "document") return "sources";
  if (page?.kind === "note" || page?.kind === "canvas") return "notes";
  if (page?.kind === "file") return "files";
  return "courses";
}

/**
 * The left column: one kind of thing at a time, chosen at the top. Courses
 * shows the course being learned and where to continue; Sources, Notes (with
 * drawings) and Files are one list each, with a filter for that list.
 */
export function MentorLibrary({ agent, headerLeading, headerEnd, data, errors, onRetry, page, lesson, onOpen, onNewNote, creatingNote, onOpenFile, onFileMoved, onFileDeleted, segment: chosen, course, filter, onChange, onDraft, courseBadge, isNew }: Props) {
  const id = useId();
  const panel = useRef<HTMLDivElement>(null);
  const segment = chosen ?? defaultSegment(page);
  // A new segment starts at its first row, not at the old list's offset.
  useLayoutEffect(() => { if (panel.current) panel.current.scrollTop = 0; }, [segment]);
  const query = filter?.segment === segment ? filter.text : "";
  const tabs = useRef<HTMLDivElement>(null);
  const pill = useSegmentPill(tabs, segment);
  // Only the segment being shown reports its own load failure.
  const failure = segment === "courses" ? errors.courses
    : segment === "sources" ? errors.documents
      : segment === "notes" ? errors.notes ?? errors.canvases
        : undefined;
  const notesCount = data.notes || data.canvases ? (data.notes?.length ?? 0) + (data.canvases?.length ?? 0) : undefined;
  const counts: Record<LibrarySegment, number | undefined> = {
    courses: data.courses && data.courses.length > 1 ? data.courses.length : undefined,
    sources: data.documents?.length || undefined,
    notes: notesCount || undefined,
    files: undefined,
  };

  // First-hand sources first, then the mentor's own guides, each under its heading once both kinds exist.
  const sources = useMemo<LibraryEntry[] | undefined>(() => {
    if (!data.documents) return undefined;
    const both = data.documents.some(isGuide) && data.documents.some((document) => !isGuide(document));
    const entry = (document: StoredDocument): LibraryEntry => {
      const guide = isGuide(document);
      const pdf = guide ? undefined : document.pdf;
      const pdfLabel = pdf ? `PDF${pdf.pages ? ` · ${pdf.pages} pages` : ""}` : undefined;
      return {
        kind: "document", id: document.id, title: document.title,
        // A source kept as a PDF shows the PDF's own icon, as the Files tree does.
        icon: guide ? <PenLine className="size-3.5" /> : pdf ? <FileTypeIcon name={pdf.path} isDir={false} size={14} /> : <File className="size-3.5" />,
        subtitle: (guide ? [document.subject, "Mentor's guide"] : [document.subject, pdfLabel, sourceName(document.sourceUrl)]).filter(Boolean).join(" · "),
        // The PDF opens in the reader in place, with highlights and notes as any other PDF.
        target: pdf
          ? { kind: "file", path: pdf.path }
          : { kind: "document", document: { id: document.id, title: document.title, body: "", ...(document.subject ? { subject: document.subject } : {}) } },
        ...(both ? { group: guide ? "Mentor's guides" : "Sources" } : {}),
      };
    };
    return [...data.documents.filter((document) => !isGuide(document)), ...data.documents.filter(isGuide)].map(entry);
  }, [data.documents]);
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
      onOpen={onOpen} onSelect={(courseId) => onChange({ course: courseId })} onDraft={onDraft} badge={courseBadge}
      isNew={(courseId) => isNew?.("course", courseId) ?? false}
      error={failure} onRetry={onRetry} />;
  } else if (segment === "files") {
    body = MentorFilesSection ? <MentorFilesSection agentId={agent.id} filter={query} onOpenFile={(path) => onOpenFile(path)}
      onFileMoved={onFileMoved} onFileDeleted={onFileDeleted} onClearQuery={() => onChange({ segment, filter: "" })} /> : null;
  } else {
    const entries = segment === "sources" ? sources : notes;
    // A PDF source opens as a file page; the Sources segment stays chosen
    // instead of falling back to Files for the kind of page now showing.
    const open = segment === "sources" ? (target: MentorPage) => { onChange({ segment: "sources" }); onOpen(target); } : onOpen;
    body = <LibraryList entries={entries} query={query} isCurrent={(target) => samePage(page, target)} onOpen={open}
      isNew={(entry) => isNew?.(entry.kind, entry.id) ?? false}
      subject={segment === "sources" ? "sources" : "notes"} error={failure} onRetry={onRetry}
      empty={segment === "sources" ? `First-hand material ${agentLook(agent).name} saves, and guides it writes, appear here.` : "Your notes and drawings appear here."} />;
  }

  return <nav className="mentor-library" aria-label={`${agent.name || "Mentor"} library`} data-mentor-library={agent.id} data-library-segment={segment}>
    <header className="mentor-library-header" data-tauri-drag-region="deep">
      {headerLeading}
      <div ref={tabs} role="tablist" aria-label="Library" className="mentor-library-segments" onKeyDown={tabKeys}>
        <span ref={pill} aria-hidden className="mentor-library-pill" />
        {LIBRARY_SEGMENTS.map((entry) => {
          const Icon = ICONS[entry];
          const selected = entry === segment;
          const label = counts[entry] ? `${LABELS[entry]}, ${counts[entry]}` : LABELS[entry];
          // The chosen segment opens into a labelled pill; the others stay a single icon.
          // Every label is kept so it can fold away rather than vanish.
          return <button key={entry} type="button" role="tab" id={`${id}-${entry}`} data-segment={entry} data-tauri-drag-region="false"
            aria-selected={selected} aria-controls={`${id}-panel`} aria-label={label} title={selected ? undefined : label} tabIndex={selected ? 0 : -1}
            className="mentor-library-segment" onClick={() => onChange({ segment: entry })}>
            <Icon aria-hidden className="size-4 shrink-0" />
            <span className="mentor-library-segment-text" aria-hidden data-open={selected || undefined}><span className="mentor-library-segment-inner">
              <span className="mentor-library-segment-label">{LABELS[entry]}</span>
              {counts[entry] ? <span className="mentor-library-count">{counts[entry]}</span> : null}
            </span></span>
          </button>;
        })}
      </div>
      <div className="min-w-0 flex-1" data-tauri-drag-region="deep" />
      {headerEnd}
    </header>
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

const PILL_GLIDE_MS = 340;
const easeOut = (t: number) => 1 - Math.pow(1 - t, 4);

/**
 * One pill behind the segments that glides to the chosen one. The chosen
 * segment widens as its label unfolds, so the pill follows the segment's live
 * box each frame rather than a box measured once.
 */
function useSegmentPill(tabs: RefObject<HTMLDivElement | null>, segment: LibrarySegment) {
  const pill = useRef<HTMLSpanElement>(null);
  const at = useRef<{ x: number; w: number } | null>(null);
  useLayoutEffect(() => {
    const list = tabs.current;
    const mark = pill.current;
    if (!list || !mark) return;
    const target = list.querySelector<HTMLElement>(`[data-segment="${segment}"]`);
    if (!target) return;
    const place = (x: number, w: number) => {
      at.current = { x, w };
      mark.style.transform = `translate3d(${x}px, 0, 0)`;
      mark.style.width = `${w}px`;
    };
    const from = at.current;
    const still = !from || window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    let frame = 0;
    const start = performance.now();
    const step = (now: number) => {
      const t = still ? 1 : Math.min(1, (now - start) / PILL_GLIDE_MS);
      const e = easeOut(t);
      const x = target.offsetLeft, w = target.offsetWidth;
      place(from && t < 1 ? from.x + (x - from.x) * e : x, from && t < 1 ? from.w + (w - from.w) * e : w);
      frame = t < 1 ? requestAnimationFrame(step) : 0;
    };
    step(start);
    // A count arriving or a narrow column resizes the segment after the glide.
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(() => {
      if (!frame) place(target.offsetLeft, target.offsetWidth);
    });
    observer?.observe(target);
    return () => { cancelAnimationFrame(frame); observer?.disconnect(); };
  }, [tabs, segment]);
  return pill;
}

function sourceName(url: string | null | undefined): string {
  if (!url) return "";
  try { return new URL(url).hostname; } catch { return "Source"; }
}
