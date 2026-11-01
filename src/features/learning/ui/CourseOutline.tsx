import { useEffect, useState } from "react";
import { Check } from "../../../shared/ui/icons";
import { COURSES_CHANGED_EVENT, courseItems, loadCourse, PROGRESS_EVENT, type CourseChangedDetail, type ProgressDetail, type CourseWithProgress, type LearningStatus } from "../model/course";
import "./CoursePane.css";

export { PROGRESS_EVENT, type ProgressDetail } from "../model/course";
/** What a status is called where the work is reading. */
export const READING_STATUS: Record<LearningStatus, string> = { untouched: "Not started", learning: "Reading", mastered: "Read" };
/** What a status is called where the work is building. */
export const LEARNING_STATUS: Record<LearningStatus, string> = { untouched: "Not started", learning: "Working", mastered: "Done" };

/** A status in the words the course's kind of work uses. */
export function statusLabel(status: LearningStatus, reading: boolean): string {
  return reading ? READING_STATUS[status] : LEARNING_STATUS[status];
}

export function StatusMark({ status }: { status: LearningStatus }) {
  return <span className={`course-status course-status--${status}`} aria-hidden="true">{status === "mastered" ? <Check className="size-2.5" strokeWidth={2.5} /> : null}</span>;
}

/** Chapters and lessons with their read marks; selecting one opens it in the reader. */
export function CourseOutline({ course, activeId, onSelect, id, hidden, className }: { course: CourseWithProgress; activeId: string | null; onSelect: (id: string) => void; id?: string; hidden?: boolean; className?: string }) {
  const items = courseItems(course.data);
  const reading = course.data.engine === "reading";
  const mastered = items.filter((item) => course.progress.get(item.id) === "mastered").length;
  const row = (item: { id: string; title: string }, index: number) => {
    const status = course.progress.get(item.id) ?? "untouched";
    return <li key={item.id}><button type="button" className={`course-pane__nav-item${activeId === item.id ? " course-pane__nav-item--active" : ""}`} aria-current={activeId === item.id ? "step" : undefined} aria-label={`${item.title}, ${statusLabel(status, reading)}`} onClick={() => onSelect(item.id)}><StatusMark status={status} /><span className="course-pane__nav-label"><span className="course-pane__step-number">{String(index + 1).padStart(2, "0")}</span>{item.title}</span></button></li>;
  };
  // Lessons are numbered through the whole course, in the order shown.
  let number = 0;
  return <nav id={id} hidden={hidden} className={`course-pane__nav${className ? ` ${className}` : ""}`} aria-label="Course navigation"><div className="course-pane__nav-intro">{reading ? null : <span>Build Your Own</span>}<p>{mastered} / {items.length} {reading ? "read" : "mastered"}</p><progress max={items.length} value={mastered} aria-label="Course completion" /></div>{course.data.engine === "reading"
    ? course.data.chapters.map((chapter, at) => <section key={at} className="course-pane__chapter" aria-label={chapter.title}><h3 className="course-pane__chapter-title"><span className="course-pane__chapter-dot" aria-hidden="true" />{chapter.title}</h3><ol>{chapter.lessons.map((lesson) => row(lesson, number++))}</ol></section>)
    : <ol>{items.map(row)}</ol>}</nav>;
}

/** A course's latest saved state, following progress and revisions made anywhere. */
export function useLiveCourse(courseId: string, agentId: string): { course: CourseWithProgress | null; error: string | null } {
  const scope = JSON.stringify([agentId, courseId]);
  const [state, setState] = useState<{ scope: string; course: CourseWithProgress | null; error: string | null }>({ scope, course: null, error: null });
  const [revision, setRevision] = useState(0);
  useEffect(() => {
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
