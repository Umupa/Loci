import { useEffect, useState } from "react";
import { COURSES_CHANGED_EVENT, courseItems, lessonPlanned, loadCourse, PROGRESS_EVENT, type CourseChangedDetail, type CourseLesson, type ProgressDetail, type CourseWithProgress, type LearningStatus } from "../model/course";
import { requestChapter } from "../model/chapterRequest";
import "./CoursePane.css";

export { PROGRESS_EVENT, type ProgressDetail } from "../model/course";
/** What a status is called. */
export const READING_STATUS: Record<LearningStatus, string> = { untouched: "Not started", learning: "Reading", mastered: "Read" };

export function statusLabel(status: LearningStatus): string {
  return READING_STATUS[status];
}

/** Chapters and lessons with their read marks; selecting one opens it in the reader. */
export function CourseOutline({ course, activeId, onSelect, id, hidden, className }: { course: CourseWithProgress; activeId: string | null; onSelect: (id: string) => void; id?: string; hidden?: boolean; className?: string }) {
  const items = courseItems(course.data);
  const mastered = items.filter((item) => course.progress.get(item.id) === "mastered").length;
  const row = (item: CourseLesson) => {
    const planned = !!course.bodies && lessonPlanned(course, item);
    const status = planned ? "planned" : course.progress.get(item.id) ?? "untouched";
    // One line each, on an ink spine: a filled dot once read, the mentor's dot where the reader is.
    return <li key={item.id}><button type="button" className={`course-pane__nav-item course-pane__nav-item--${status}${activeId === item.id ? " course-pane__nav-item--active" : ""}`} aria-current={activeId === item.id ? "step" : undefined} aria-label={`${item.title}, ${status === "planned" ? "Planned" : statusLabel(status)}`} title={item.title} onClick={() => { if (!planned || !requestChapter(course.agentId, course, item.id)) onSelect(item.id); }}><span className="course-pane__node" aria-hidden="true" /><span className="course-pane__nav-label">{item.title}</span></button></li>;
  };
  const done = `${mastered} / ${items.length} read`;
  return <nav id={id} hidden={hidden} className={`course-pane__nav${className ? ` ${className}` : ""}`} aria-label="Course navigation"><div className="course-pane__nav-intro" title={done}><progress max={items.length} value={mastered} aria-label={`Course completion, ${done}`} /></div>{course.data.chapters.map((chapter, at) => <section key={at} className="course-pane__chapter" aria-label={chapter.title}><h3 className="course-pane__chapter-title">{chapter.title}</h3><ol>{chapter.lessons.map(row)}</ol></section>)}</nav>;
}

/**
 * A course's latest saved state, following progress and revisions made
 * anywhere. No course (`null`) loads nothing, for a view that shows one only
 * some of the time and must keep its own elements meanwhile.
 */
export function useLiveCourse(courseId: string | null, agentId: string): { course: CourseWithProgress | null; error: string | null } {
  const scope = JSON.stringify([agentId, courseId]);
  const [state, setState] = useState<{ scope: string; course: CourseWithProgress | null; error: string | null }>({ scope, course: null, error: null });
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    if (courseId === null) return;
    let live = true;
    loadCourse(courseId, agentId).then(
      (course) => { if (live) setState({ scope, course, error: course ? null : "This course is no longer available." }); },
      (cause: unknown) => { if (live) setState({ scope, course: null, error: String(cause) }); },
    );
    return () => { live = false; };
  }, [scope, revision]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const changed = (event: Event) => {
      const detail = (event as CustomEvent<CourseChangedDetail>).detail;
      if (detail?.agentId === agentId && (detail.courseId === undefined || detail.courseId === courseId)) setRevision((value) => value + 1);
    };
    const progressed = (event: Event) => {
      const detail = (event as CustomEvent<ProgressDetail>).detail;
      if (detail?.courseId !== courseId || detail.agentId !== agentId) return;
      setState((previous) => {
        if (previous.scope !== scope || !previous.course || !courseItems(previous.course.data).some((item) => item.id === detail.itemId)) return previous;
        const progress = new Map(previous.course.progress); progress.set(detail.itemId, detail.status);
        return { ...previous, course: { ...previous.course, progress } };
      });
    };
    window.addEventListener(COURSES_CHANGED_EVENT, changed);
    window.addEventListener(PROGRESS_EVENT, progressed);
    return () => { window.removeEventListener(COURSES_CHANGED_EVENT, changed); window.removeEventListener(PROGRESS_EVENT, progressed); };
  }, [scope]); // eslint-disable-line react-hooks/exhaustive-deps
  return state.scope === scope ? { course: state.course, error: state.error } : { course: null, error: null };
}

/** The outline of a saved course, kept up to date on its own. */
export function LiveCourseOutline({ courseId, agentId, activeId, onSelect }: { courseId: string; agentId: string; activeId: string | null; onSelect: (id: string) => void }) {
  const { course, error } = useLiveCourse(courseId, agentId);
  if (!course) return error ? <p role="alert" className="course-error">{error}</p> : null;
  return <CourseOutline course={course} activeId={activeId} onSelect={onSelect} className="course-outline" />;
}
