import { useEffect, useMemo, useRef, useState, type MouseEvent, type ReactNode } from "react";
import { ask } from "../../../platform/dialog";
import { Popover, type PopoverAnchor } from "../../../shared/ui/Popover";
import { Highlighter, MoreHorizontal, Plus, RotateCcw } from "../../../shared/ui/icons";
import { useCourseMarks } from "../../learning/ui/LessonMarks";
import { agentLook, type Agent } from "../../agents/model/agent";
import { resetCourseProgress, type CourseSummary } from "../../learning/model/course";
import { useLiveCourse } from "../../learning/ui/CourseOutline";
import { courseProgress, withoutOrdinal } from "../model/libraryCourse";
import type { MentorLesson, MentorPage } from "../model/mentorPage";
import { LibraryOutline } from "./LibraryOutline";
import { LibraryLoadError } from "./LibraryList";
import { listKeyDown } from "./listKeys";

/** Room after a course's title (no lesson) or a lesson's title, for counts such as highlights. */
export type CourseBadge = (courseId: string, lessonId?: string) => ReactNode;

/** What "ask for a course" puts in the composer, for the user to finish. */
export const NEW_COURSE_PROMPT = "I'd like a new course on ";
type Props = {
  agent: Agent;
  courses: CourseSummary[] | undefined;
  /** The course last chosen for the library, brought into view. */
  selected?: string;
  page?: MentorPage;
  lesson?: MentorLesson;
  onOpen: (page: MentorPage) => void;
  onDraft: (text: string) => void;
  badge?: CourseBadge;
  /** Why the course listing could not be read, if it could not. */
  error?: string;
  onRetry?: () => void;
  /** A course saved by the turn that is running now. */
  isNew?: (courseId: string) => boolean;
};

/** Courses in the order they were first written, so a new one goes to the end. */
export function courseOrder(courses: readonly CourseSummary[]): CourseSummary[] {
  return [...courses].sort((a, b) => (a.createdAt ?? a.updatedAt) - (b.createdAt ?? b.updatedAt) || a.id.localeCompare(b.id));
}

/**
 * The Courses segment: one outline of chapters and lessons. A mentor with
 * several courses (a Lens reading several repositories) has them one after
 * another, each under its title. The outline's current lesson and the
 * reader's next/previous are where to continue.
 */
export function LibraryCourses({ agent, courses: listed, selected, page, lesson, onOpen, onDraft, badge, error, onRetry, isNew }: Props) {
  const name = agentLook(agent).name;
  const open = page?.kind === "course" ? page.course : undefined;
  const courses = useMemo(() => {
    const all = courseOrder(listed ?? []);
    // A course just written may be open before the listing has it.
    if (open && !all.some((entry) => entry.id === open.courseId))
      all.push({ id: open.courseId, agentId: agent.id, engine: "reading", title: open.title, updatedAt: 0, itemCount: 0, masteredCount: 0 });
    return all;
  }, [listed, open?.courseId, open?.title, agent.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const activeId = (id: string) => open?.courseId === id ? lesson?.id ?? open.itemId ?? null : null;
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (selected) list.current?.querySelector(`[data-library-course="${CSS.escape(selected)}"]`)?.scrollIntoView?.({ block: "nearest" });
  }, [selected]);

  if (listed === undefined && !open) return error ? <LibraryLoadError subject="courses" onRetry={onRetry} />
    : <p role="status" className="mentor-library-empty">Loading…</p>;
  if (!courses.length) return <div className="library-courses-empty">
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    <p className="mentor-library-empty">No course yet.</p>
    <button type="button" className="library-ask" onClick={() => onDraft(NEW_COURSE_PROMPT)}><Plus aria-hidden className="size-3.5" />Ask {name} for a course</button>
  </div>;

  return <div ref={list} className="library-courses" data-library-courses onKeyDown={listKeyDown}>
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    {courses.map((entry) => <CourseSection key={entry.id} agent={agent} current={entry} activeId={activeId(entry.id)} onOpen={onOpen} badge={badge}
      isNew={isNew?.(entry.id) ?? false} />)}
  </div>;
}

/** A course's own menu, from its head's … or a right-click: for now, starting it over. */
function useCourseMenu(agentId: string, courseId: string, title: string) {
  const [anchor, setAnchor] = useState<PopoverAnchor | null>(null);
  const [error, setError] = useState<string>();
  const reset = async () => {
    setAnchor(null);
    if (!await ask(`Every lesson of “${withoutOrdinal(title)}” goes back to unread. Highlights and notes are kept.`,
      { title: "Reset progress?", kind: "warning", okLabel: "Reset", cancelLabel: "Cancel" })) return;
    try { await resetCourseProgress(courseId, agentId); setError(undefined); }
    catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
  };
  const popover = <>
    {anchor ? <Popover anchor={anchor} side="bottom" align="end" width={180} constrainHeight={false} onDismiss={() => setAnchor(null)} role="menu" aria-label="Course options" className="p-1">
      <button type="button" role="menuitem" autoFocus onClick={() => void reset()}
        className="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[13px] text-content/85 hover:bg-content/8">
        <RotateCcw aria-hidden className="size-3.5" />Reset progress…
      </button>
    </Popover> : null}
    {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
  </>;
  return {
    popover,
    openAt: (event: MouseEvent) => { event.preventDefault(); setAnchor({ x: event.clientX, y: event.clientY }); },
    openFrom: (event: MouseEvent<HTMLElement>) => setAnchor(event.currentTarget),
  };
}

function openLesson(agentId: string, onOpen: Props["onOpen"], courseId: string, title: string, itemId: string) {
  onOpen({ kind: "course", course: { courseId, agentId, title, itemId } });
}

/** A course in the outline: its head (title and progress) over its chapters and lessons. */
function CourseSection({ agent, current, activeId, onOpen, badge, isNew }: {
  agent: Agent; current: CourseSummary; activeId: string | null; onOpen: Props["onOpen"]; badge?: CourseBadge; isNew: boolean;
}) {
  const { course, error } = useLiveCourse(current.id, agent.id);
  const progress = course ? courseProgress(course) : { read: current.masteredCount, total: current.itemCount };
  const reading = (course?.data.engine ?? current.engine) === "reading";
  const title = withoutOrdinal(course?.title ?? current.title);
  const menu = useCourseMenu(agent.id, current.id, title);
  return <div className="library-course" data-library-course={current.id} data-library-new={isNew || undefined}>
    <div className="library-head" onContextMenu={menu.openAt}>
      <p className="library-course-title" title={title}>{title}{isNew ? <span className="mentor-library-new">New</span> : null}</p>
      <button type="button" className="library-head-more" aria-label="Course options" title="Course options" aria-haspopup="menu" onClick={menu.openFrom}>
        <MoreHorizontal aria-hidden className="size-3.5" />
      </button>
      {menu.popover}
      <ReadLine read={progress.read} total={progress.total} done={!reading} />
    </div>
    {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
    {course ? <LibraryOutline course={course} activeId={activeId} onSelect={(itemId) => openLesson(agent.id, onOpen, current.id, course.title, itemId)}
      badge={badge ? (lessonId) => badge(current.id, lessonId) : undefined} /> : null}
    {course ? <HighlightsLink agentId={agent.id} courseId={current.id} title={course.title} onOpen={onOpen} /> : null}
  </div>;
}

/** How far a course is read, as the line under its head fills: no numbers to read, only ink. */
function ReadLine({ read, total, done }: { read: number; total: number; done?: boolean }) {
  const share = total ? Math.min(1, read / total) : 0;
  return <span className="library-readline" role="img" aria-label={`${read} of ${total} ${done ? "done" : "read"}`} title={`${read} of ${total} ${done ? "done" : "read"}`}>
    <span style={{ width: `${(share * 100).toFixed(1)}%` }} />
  </span>;
}

/** Under a course's outline once it has any: its highlights, which are its notes, on one page. */
function HighlightsLink({ agentId, courseId, title, onOpen }: { agentId: string; courseId: string; title: string; onOpen: Props["onOpen"] }) {
  const counts = useCourseMarks(agentId, courseId);
  const total = counts ? [...counts.values()].reduce((sum, count) => sum + count.highlights, 0) : 0;
  if (!total) return null;
  return <button type="button" data-library-item className="library-ask library-highlights" onClick={() => onOpen({ kind: "highlights", courseId, agentId, title })}>
    <Highlighter aria-hidden className="size-3.5" />{total === 1 ? "1 highlight" : `${total} highlights`}
  </button>;
}
