import { useState, type ReactNode } from "react";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { ChevronDown, ChevronRight, File, Mortarboard, Palette, Plus, StickyNote } from "../../../shared/ui/icons";
import type { Canvas } from "../../canvas/canvas";
import type { OpenFileFn } from "../../files/model/filePlace";
import type { CourseSummary } from "../../learning/model/course";
import { LiveCourseOutline } from "../../learning/ui/CourseOutline";
import { notePreview, type Note } from "../../notes";
import type { Agent } from "../../agents/model/agent";
import type { StoredDocument } from "../../agents/model/agentDocuments";
import { MentorFilesSection } from "./filesSlot";
import { samePage, type MentorLesson, type MentorPage } from "../model/mentorPage";

export type LibraryData = { courses?: CourseSummary[]; documents?: StoredDocument[]; notes?: Note[]; canvases?: Canvas[] };
type Section = "outline" | "courses" | "sources" | "notes" | "canvases" | "files";
const COLLAPSED_KEY = "loci:mentor-library-collapsed.v1";
const SECTIONS: readonly Section[] = ["outline", "courses", "sources", "notes", "canvases", "files"];

function readCollapsed(): Set<Section> {
  try {
    const value = JSON.parse(localStorage.getItem(COLLAPSED_KEY) ?? "[]");
    return new Set(Array.isArray(value) ? value.filter((entry): entry is Section => SECTIONS.includes(entry)) : []);
  } catch { return new Set(); }
}

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
};

/** The left column: the open course's outline, then what the mentor keeps. */
export function MentorLibrary({ agent, data, errors, onRetry, page, lesson, onOpen, onNewNote, creatingNote, onOpenFile }: Props) {
  const [collapsed, setCollapsed] = useState(readCollapsed);
  const toggle = (section: Section) => setCollapsed((current) => {
    const next = new Set(current);
    if (next.has(section)) next.delete(section); else next.add(section);
    try { localStorage.setItem(COLLAPSED_KEY, JSON.stringify([...next])); } catch { /* Folding still works for this window. */ }
    return next;
  });
  const failure = Object.values(errors).find(Boolean);
  const course = page?.kind === "course" ? page.course : undefined;
  const section = (id: Section, label: string, count: number | undefined, body: ReactNode, action?: ReactNode) => {
    const open = !collapsed.has(id);
    return <section className="mentor-library-section" data-library-section={id} aria-label={label}>
      <div className="mentor-library-heading">
        <button type="button" className="mentor-library-toggle" aria-expanded={open} onClick={() => toggle(id)}>
          {open ? <ChevronDown className="size-3" /> : <ChevronRight className="size-3" />}
          <span className="min-w-0 truncate">{label}</span>
          {count ? <span className="mentor-library-count">{count}</span> : null}
        </button>
        {action}
      </div>
      {open ? <div className="mentor-library-body">{body}</div> : null}
    </section>;
  };
  const row = (target: MentorPage, icon: ReactNode, title: string, subtitle: string, kind: string, id: string) =>
    <button key={`${kind}:${id}`} type="button" className="mentor-library-row" data-resource-kind={kind} data-resource-id={id} aria-label={`${kind}: ${title}`}
      aria-current={samePage(page, target) || undefined} title={subtitle ? `${title}\n${subtitle}` : title} onClick={() => onOpen(target)}>
      <span aria-hidden className="mentor-library-icon">{icon}</span>
      <span className="mentor-library-copy"><span className="mentor-library-title">{title}</span>{subtitle ? <span className="mentor-library-subtitle">{subtitle}</span> : null}</span>
    </button>;
  const empty = (items: readonly unknown[] | undefined, text: string) => items === undefined ? <p role="status" className="mentor-library-empty">Loading…</p>
    : !items.length ? <p className="mentor-library-empty">{text}</p> : null;
  return <nav className="mentor-library" aria-label={`${agent.name || "Mentor"} library`} data-mentor-library={agent.id}>
    {failure ? <div role="alert" className="mentor-library-error"><p>{failure}</p><button type="button" onClick={onRetry}>Retry</button></div> : null}
    {course ? section("outline", course.title || "Course", undefined,
      <LiveCourseOutline courseId={course.courseId} agentId={agent.id} activeId={lesson?.id ?? course.itemId ?? null}
        onSelect={(itemId) => onOpen({ kind: "course", course: { ...course, itemId } })} />) : null}
    {section("courses", "Courses", data.courses?.length, <>
      {empty(data.courses, "Ask your mentor to arrange a course.")}
      {data.courses?.map((entry) => row({ kind: "course", course: { courseId: entry.id, agentId: agent.id, title: entry.title } }, <Mortarboard className="size-3.5" />, entry.title,
        `${entry.masteredCount} / ${entry.itemCount} ${entry.engine === "reading" ? "read" : "mastered"}`, "course", entry.id))}
    </>)}
    {section("sources", "Sources", data.documents?.length, <>
      {empty(data.documents, "Material your mentor saves, and documents it writes, appear here.")}
      {data.documents?.map((document) => row({ kind: "document", document: { id: document.id, title: document.title, body: "", ...(document.subject ? { subject: document.subject } : {}) } },
        <File className="size-3.5" />, document.title, [document.subject, sourceName(document.sourceUrl)].filter(Boolean).join(" · "), "document", document.id))}
    </>)}
    {section("notes", "Notes", data.notes?.length, <>
      {empty(data.notes, "Keep your own notes here.")}
      {data.notes?.map((note) => row({ kind: "note", id: note.id }, <StickyNote className="size-3.5" />, note.title || "Untitled", notePreview(note.body, note.title), "note", note.id))}
    </>, <button type="button" className="mentor-library-action" title="New note" aria-label="New note" disabled={creatingNote} onClick={onNewNote}><Plus className="size-3.5" /></button>)}
    {section("canvases", "Canvases", data.canvases?.length, <>
      {empty(data.canvases, "Drawings saved in this mentor's library appear here.")}
      {data.canvases?.map((canvas) => row({ kind: "canvas", id: canvas.id }, <Palette className="size-3.5" />, canvas.title,
        formatRelativeTime(new Date(canvas.updatedAt).toISOString()), "canvas", canvas.id))}
    </>)}
    {MentorFilesSection ? section("files", "Files", undefined, <MentorFilesSection agentId={agent.id} onOpenFile={(path) => onOpenFile(path)} />) : null}
  </nav>;
}

function sourceName(url: string | null | undefined): string {
  if (!url) return "";
  try { return new URL(url).hostname; } catch { return "Source"; }
}
