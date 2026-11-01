import { useMemo, useState, type ReactNode } from "react";
import { ChevronDown, Plus } from "../../../shared/ui/icons";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { agentLook, type Agent } from "../../agents/model/agent";
import { loadCourse, type CourseSummary } from "../../learning/model/course";
import { useLiveCourse } from "../../learning/ui/CourseOutline";
import { courseProgress, nextLesson } from "../model/libraryCourse";
import type { MentorLesson, MentorPage } from "../model/mentorPage";
import { LibraryOutline } from "./LibraryOutline";

/** Room after a course's title (no lesson) or a lesson's title, for counts such as highlights. */
export type CourseBadge = (courseId: string, lessonId?: string) => ReactNode;

/** What "ask for a course" puts in the composer, for the user to finish. */
export const NEW_COURSE_PROMPT = "I'd like a new course on ";
const ASK = "ask-for-course";

type Props = {
  agent: Agent;
  courses: CourseSummary[] | undefined;
  /** The course chosen for the library, if any. */
  selected?: string;
  page?: MentorPage;
  lesson?: MentorLesson;
  onOpen: (page: MentorPage) => void;
  onSelect: (courseId: string) => void;
  onDraft: (text: string) => void;
  badge?: CourseBadge;
};

/**
 * The Courses segment: which course (a switcher, ending with asking the
 * mentor for another), how far through it is, the lesson to continue with,
 * and its outline.
 */
export function LibraryCourses({ agent, courses: listed, selected, page, lesson, onOpen, onSelect, onDraft, badge }: Props) {
  const name = agentLook(agent).name;
  const open = page?.kind === "course" ? page.course : undefined;
  const courses = useMemo(() => {
    const all = [...(listed ?? [])];
    // A course just written may be open before the listing has it.
    if (open && !all.some((entry) => entry.id === open.courseId))
      all.unshift({ id: open.courseId, agentId: agent.id, engine: "reading", title: open.title, updatedAt: 0, itemCount: 0, masteredCount: 0 });
    return all;
  }, [listed, open?.courseId, open?.title, agent.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const current = courses.find((entry) => entry.id === selected)
    ?? courses.find((entry) => entry.id === open?.courseId)
    ?? [...courses].sort((a, b) => b.updatedAt - a.updatedAt)[0];

  if (listed === undefined && !open) return <p role="status" className="mentor-library-empty">Loading…</p>;
  if (!current) return <div className="library-courses-empty">
    <p className="mentor-library-empty">No course yet.</p>
    <button type="button" className="library-ask" onClick={() => onDraft(NEW_COURSE_PROMPT)}><Plus aria-hidden className="size-3.5" />Ask {name} for a course</button>
  </div>;
  return <CourseView key={current.id} agent={agent} name={name} courses={courses} current={current}
    activeId={open?.courseId === current.id ? lesson?.id ?? open.itemId ?? null : null}
    onOpen={onOpen} onSelect={onSelect} onDraft={onDraft} badge={badge} />;
}

function CourseView({ agent, name, courses, current, activeId, onOpen, onSelect, onDraft, badge }: {
  agent: Agent; name: string; courses: CourseSummary[]; current: CourseSummary; activeId: string | null;
  onOpen: Props["onOpen"]; onSelect: Props["onSelect"]; onDraft: Props["onDraft"]; badge?: CourseBadge;
}) {
  const { course, error } = useLiveCourse(current.id, agent.id);
  const [menu, setMenu] = useState<HTMLElement | null>(null);
  const openLesson = (courseId: string, title: string, itemId?: string) =>
    onOpen({ kind: "course", course: { courseId, agentId: agent.id, title, ...(itemId ? { itemId } : {}) } });

  // Choosing a course lands in it, at the lesson to continue with.
  const pick = async (id: string) => {
    if (id === ASK) { onDraft(NEW_COURSE_PROMPT); return; }
    const entry = courses.find((item) => item.id === id);
    if (!entry) return;
    onSelect(id);
    let itemId: string | undefined;
    try {
      const loaded = await loadCourse(id, agent.id);
      itemId = loaded ? nextLesson(loaded)?.id : undefined;
    } catch { /* The course opens at its start. */ }
    openLesson(id, entry.title, itemId);
  };
  const items: ContextMenuItem[] = [
    ...courses.map((entry): ContextMenuItem => ({ kind: "item", id: entry.id, label: entry.title, checked: entry.id === current.id,
      description: `${entry.masteredCount} / ${entry.itemCount} ${entry.engine === "build-your-own" ? "done" : "read"}` })),
    { kind: "sep" },
    { kind: "item", id: ASK, label: `Ask ${name} for a new course` },
  ];

  const progress = course ? courseProgress(course) : { read: current.masteredCount, total: current.itemCount };
  const reading = (course?.data.engine ?? current.engine) === "reading";
  const next = course ? nextLesson(course, activeId) : undefined;
  return <div className="library-course" data-library-course={current.id}>
    <div className="library-course-head">
      <button type="button" className="library-switcher" aria-haspopup="menu" aria-expanded={menu ? true : undefined}
        aria-label={`Course: ${current.title}. Switch course`} title={current.title}
        onClick={(event) => { const anchor = event.currentTarget; setMenu((shown) => shown ? null : anchor); }}>
        <span className="library-switcher-title">{course?.title ?? current.title}</span>
        <ChevronDown aria-hidden className="size-3 shrink-0 opacity-60" />
      </button>
      {badge?.(current.id)}
      <span className="library-progress-text">{progress.read} / {progress.total} {reading ? "read" : "done"}</span>
    </div>
    <div className="library-progress" role="progressbar" aria-label="Course progress" aria-valuemin={0} aria-valuemax={progress.total} aria-valuenow={progress.read}>
      <i style={{ width: progress.total ? `${(progress.read / progress.total) * 100}%` : 0 }} />
    </div>
    {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
    {course && progress.total && !next ? <p className="mentor-library-empty">All {progress.total} {reading ? "read" : "done"}.</p> : null}
    {course && next && next.id !== activeId ? <div className="library-continue" data-library-continue={next.id}>
      <p className="library-continue-label">Continue reading</p>
      <p className="library-continue-title" title={next.title}>{next.title}</p>
      <button type="button" className="library-continue-button primary-action" onClick={() => openLesson(current.id, course.title, next.id)}>Continue →</button>
    </div> : null}
    {course ? <LibraryOutline course={course} activeId={activeId} onSelect={(itemId) => openLesson(current.id, course.title, itemId)}
      badge={badge ? (lessonId) => badge(current.id, lessonId) : undefined} /> : null}
    {menu ? <ContextMenu anchor={menu} ariaLabel="Courses" items={items} onClose={() => setMenu(null)}
      onPick={(id) => { setMenu(null); void pick(id); }} /> : null}
  </div>;
}
