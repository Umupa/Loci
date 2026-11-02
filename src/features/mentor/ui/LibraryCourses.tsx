import { useEffect, useMemo, useState, type KeyboardEvent, type ReactNode } from "react";
import { Plus } from "../../../shared/ui/icons";
import { agentLook, type Agent } from "../../agents/model/agent";
import { COURSES_CHANGED_EVENT, loadCourse, type CourseChangedDetail, type CourseSummary } from "../../learning/model/course";
import { loadCoursePath, pathSteps, type PathRead, type PathStep } from "../../learning/model/coursePath";
import { useLiveCourse } from "../../learning/ui/CourseOutline";
import { courseProgress, courseState, nextLesson, withoutOrdinal } from "../model/libraryCourse";
import type { MentorLesson, MentorPage } from "../model/mentorPage";
import { LibraryOutline } from "./LibraryOutline";
import { LibraryLoadError } from "./LibraryList";
import { listKeyDown } from "./listKeys";

/** Room after a course's title (no lesson) or a lesson's title, for counts such as highlights. */
export type CourseBadge = (courseId: string, lessonId?: string) => ReactNode;

/** What "ask for a course" puts in the composer, for the user to finish. */
export const NEW_COURSE_PROMPT = "I'd like a new course on ";
/** What "plan a path" puts in the composer. */
export const NEW_PATH_PROMPT = "Plan a learning path of short courses for me, in order, from what we have and what is missing: ";

/** The mentor's learning path, read again whenever its courses change. */
export function useCoursePath(agentId: string): PathRead | undefined {
  const [read, setRead] = useState<{ agentId: string; read?: PathRead }>();
  const [version, setVersion] = useState(0);
  useEffect(() => {
    const changed = (event: Event) => { if ((event as CustomEvent<CourseChangedDetail>).detail?.agentId === agentId) setVersion((value) => value + 1); };
    window.addEventListener(COURSES_CHANGED_EVENT, changed);
    return () => window.removeEventListener(COURSES_CHANGED_EVENT, changed);
  }, [agentId]);
  useEffect(() => {
    let live = true;
    // A mentor whose content is not in a folder has no path: the segment stays as it was.
    void loadCoursePath(agentId).then((found) => { if (live) setRead({ agentId, read: found }); }, () => { if (live) setRead({ agentId }); });
    return () => { live = false; };
  }, [agentId, version]);
  return read?.agentId === agentId ? read.read : undefined;
}

/** Opens a course at the lesson to continue with. */
async function pickCourse(agentId: string, entry: CourseSummary, onSelect: (id: string) => void, onOpen: (page: MentorPage) => void) {
  onSelect(entry.id);
  let itemId: string | undefined;
  try {
    const loaded = await loadCourse(entry.id, agentId);
    itemId = loaded ? nextLesson(loaded)?.id : undefined;
  } catch { /* The course opens at its start. */ }
  onOpen({ kind: "course", course: { courseId: entry.id, agentId, title: entry.title, ...(itemId ? { itemId } : {}) } });
}

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
  /** Why the course listing could not be read, if it could not. */
  error?: string;
  onRetry?: () => void;
  /** A course saved by the turn that is running now. */
  isNew?: (courseId: string) => boolean;
};

/** One course row: on the path (numbered, maybe planned) or not (`position` absent). */
type Row = { id: string; title: string; read: number; total: number; position?: number; planned?: boolean; pending?: PathStep["pending"]; summary?: CourseSummary };

/**
 * The Courses segment. With a learning path: the path and its progress, its
 * courses in order on a line, then any course not on it. Without one: the
 * courses as rows, or a single course's own head. Either way the current
 * course opens in place under its row, one at a time, showing its chapters
 * and lessons; the outline's current lesson and the reader's next/previous
 * are where to continue.
 */
export function LibraryCourses({ agent, courses: listed, selected, page, lesson, onOpen, onSelect, onDraft, badge, error, onRetry, isNew }: Props) {
  const name = agentLook(agent).name;
  const pathRead = useCoursePath(agent.id);
  const path = pathRead?.path ?? undefined;
  const open = page?.kind === "course" ? page.course : undefined;
  const courses = useMemo(() => {
    const all = [...(listed ?? [])];
    // A course just written may be open before the listing has it.
    if (open && !all.some((entry) => entry.id === open.courseId))
      all.unshift({ id: open.courseId, agentId: agent.id, engine: "reading", title: open.title, updatedAt: 0, itemCount: 0, masteredCount: 0 });
    return all;
  }, [listed, open?.courseId, open?.title, agent.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const plan = useMemo(() => path ? pathSteps(path, courses) : undefined, [path, courses]);
  // With a path, the course to show is the one chosen, the one open, else the first one on the path not read to the end.
  const onPathNext = plan?.steps.find((step) => !step.planned && step.read < step.total) ?? plan?.steps.find((step) => !step.planned);
  const current = courses.find((entry) => entry.id === selected)
    ?? courses.find((entry) => entry.id === open?.courseId)
    ?? (onPathNext ? courses.find((entry) => entry.id === onPathNext.id) : undefined)
    ?? [...courses].sort((a, b) => b.updatedAt - a.updatedAt)[0];
  // The current course is open under its row until its row is clicked; choosing another opens that one.
  const [collapsed, setCollapsed] = useState<string | null>(null);
  const expandedId = current && current.id !== collapsed ? current.id : null;
  const activeId = (id: string) => open?.courseId === id ? lesson?.id ?? open.itemId ?? null : null;

  if (listed === undefined && !open) return error ? <LibraryLoadError subject="courses" onRetry={onRetry} />
    : <p role="status" className="mentor-library-empty">Loading…</p>;
  if (!current && !plan) return <div className="library-courses-empty">
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    <p className="mentor-library-empty">No course yet.</p>
    <button type="button" className="library-ask" onClick={() => onDraft(NEW_COURSE_PROMPT)}><Plus aria-hidden className="size-3.5" />Ask {name} for a course</button>
  </div>;

  const asks = <div className="library-asks">
    <button type="button" className="library-ask" onClick={() => onDraft(NEW_COURSE_PROMPT)}><Plus aria-hidden className="size-3.5" />Ask {name} for a course</button>
    {!plan && courses.length >= 2
      ? <button type="button" className="library-ask" onClick={() => onDraft(NEW_PATH_PROMPT)}><Plus aria-hidden className="size-3.5" />Ask {name} to plan a path</button> : null}
  </div>;

  // A single course needs no list: its own head, then its outline.
  if (!plan && courses.length === 1 && current) return <div className="library-courses" data-library-courses onKeyDown={listKeyDown}>
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    <SingleCourse agent={agent} current={current} activeId={activeId(current.id)} onOpen={onOpen} badge={badge} isNew={isNew?.(current.id) ?? false} />
    {asks}
  </div>;

  const fromSummary = (entry: CourseSummary): Row => ({ id: entry.id, title: entry.title, read: entry.masteredCount, total: entry.itemCount, summary: entry });
  const steps = plan?.steps.map((step): Row => ({ ...step, summary: courses.find((entry) => entry.id === step.id) }));
  const others = (plan ? plan.others : courses).map(fromSummary);
  const positions = new Map(plan?.steps.map((step) => [step.id, step.position]));
  const pick = (row: Row) => {
    if (row.planned || !row.summary) { onDraft(`Please write the course "${row.title}" (id ${row.id}) on my learning path.`); return; }
    if (row.id === current?.id) { setCollapsed(row.id === expandedId ? row.id : null); return; }
    setCollapsed(null);
    void pickCourse(agent.id, row.summary, onSelect, onOpen);
  };
  const row = (entry: Row) => <CourseRow key={entry.id} agent={agent} row={entry} positions={positions}
    current={entry.id === current?.id} expanded={entry.id === expandedId} activeId={activeId(entry.id)}
    isNew={isNew?.(entry.id) ?? false} badge={badge} onPick={() => pick(entry)} onOpen={onOpen} />;
  const written = plan?.steps.filter((step) => !step.planned) ?? [];
  const read = written.reduce((sum, step) => sum + step.read, 0);
  const total = written.reduce((sum, step) => sum + step.total, 0);

  return <div className="library-courses" data-library-courses onKeyDown={listKeyDown}>
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    {plan && steps ? <div className="library-path" data-library-path>
      <div className="library-path-head">
        <p className="library-path-kicker">Learning path · {steps.length} {steps.length === 1 ? "course" : "courses"}</p>
        <p className="library-path-title">{path?.title ?? "Learning path"}</p>
        <div className="library-progress-line">
          <Bar read={read} total={total} label="Path progress" />
          <span className="library-count" title={`${read} of ${total} lessons read`}>{read}/{total}</span>
        </div>
      </div>
      {pathRead?.error ? <p role="alert" className="mentor-library-empty">The path file has a problem: {pathRead.error}</p> : null}
      <ol className="library-steps" aria-label="Courses on the path">{steps.map(row)}</ol>
    </div> : null}
    {others.length ? <>
      {plan ? <p className="library-others">Other courses</p> : null}
      <ul className="library-steps library-steps--loose" aria-label={plan ? "Other courses" : "Courses"}>{others.map(row)}</ul>
    </> : null}
    {asks}
  </div>;
}

function Bar({ read, total, label }: { read: number; total: number; label?: string }) {
  return <span className="library-bar" role={label ? "progressbar" : undefined} aria-label={label} aria-hidden={label ? undefined : true}
    aria-valuemin={label ? 0 : undefined} aria-valuemax={label ? total : undefined} aria-valuenow={label ? read : undefined}>
    <i style={{ width: total ? `${(read / total) * 100}%` : 0 }} />
  </span>;
}

type RowProps = {
  agent: Agent; row: Row; positions: Map<string, number>; current: boolean; expanded: boolean; activeId: string | null;
  isNew: boolean; badge?: CourseBadge; onPick: () => void; onOpen: Props["onOpen"];
};

/**
 * A course as a row: its marker (a numbered dot on the path, a small ring
 * off it), title, progress and the courses best read first. Clicking opens
 * it at the lesson to continue with; clicking the open one folds it.
 */
function CourseRow({ agent, row, positions, current, expanded, activeId, isNew, badge, onPick, onOpen }: RowProps) {
  // Loaded only while open; the row stays the same element either way, so focus stays on it.
  const { course, error } = useLiveCourse(expanded ? row.id : null, agent.id);
  // While open, the outline's own progress is the freshest.
  const progress = expanded && course ? courseProgress(course) : row;
  const title = withoutOrdinal(row.title);
  const state = courseState(progress.read, progress.total);
  const pending = row.pending ?? [];
  const keys = (event: KeyboardEvent<HTMLButtonElement>) => {
    if (row.planned) return;
    if ((event.key === "ArrowRight" && !expanded) || (event.key === "ArrowLeft" && expanded)) { event.preventDefault(); onPick(); }
  };
  const summary = row.planned ? `${title}: not written yet. Ask for it.` : `${title}: ${progress.read} of ${progress.total} read`;
  return <li className="library-step" data-library-step={row.id} data-planned={row.planned || undefined}>
    <button type="button" data-library-item className="library-step-row" title={summary}
      aria-current={current ? "true" : undefined} aria-expanded={row.planned ? undefined : expanded} onClick={onPick} onKeyDown={keys}>
      {row.position !== undefined
        ? <span aria-hidden className={`library-dot library-dot--${row.planned ? "planned" : state}`}>{row.position}</span>
        : <span aria-hidden className={`library-dot library-dot--loose library-dot--${state}`} />}
      <span className="library-step-text">
        <span className="library-step-title">{title}{isNew ? <span className="mentor-library-new">New</span> : null}</span>
        <span className="library-step-meta">
          {row.planned ? <span className="library-step-planned">planned</span> : <>
            <Bar read={progress.read} total={progress.total} />
            <span className="library-count">{progress.read}/{progress.total}</span>
          </>}
          {pending.length ? <span className="library-tag" title={`Best after ${pending.map((item) => withoutOrdinal(item.title)).join(", ")}`}>
            After {pending.map((item) => positions.get(item.id) ?? withoutOrdinal(item.title)).join(", ")}
          </span> : null}
          {expanded ? badge?.(row.id) : null}
        </span>
      </span>
    </button>
    {expanded ? <div className="library-step-body" data-library-course={row.id} data-library-new={isNew || undefined}>
      {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
      {course ? <LibraryOutline course={course} activeId={activeId} onSelect={(itemId) => openLesson(agent.id, onOpen, row.id, course.title, itemId)}
        badge={badge ? (lessonId) => badge(row.id, lessonId) : undefined} /> : null}
    </div> : null}
  </li>;
}

function openLesson(agentId: string, onOpen: Props["onOpen"], courseId: string, title: string, itemId: string) {
  onOpen({ kind: "course", course: { courseId, agentId, title, itemId } });
}

/** The only course a mentor has: its head (title and progress) over its outline. */
function SingleCourse({ agent, current, activeId, onOpen, badge, isNew }: {
  agent: Agent; current: CourseSummary; activeId: string | null; onOpen: Props["onOpen"]; badge?: CourseBadge; isNew: boolean;
}) {
  const { course, error } = useLiveCourse(current.id, agent.id);
  const progress = course ? courseProgress(course) : { read: current.masteredCount, total: current.itemCount };
  const reading = (course?.data.engine ?? current.engine) === "reading";
  const title = withoutOrdinal(course?.title ?? current.title);
  return <div className="library-course" data-library-course={current.id} data-library-new={isNew || undefined}>
    <div className="library-path-head">
      <p className="library-course-title" title={title}>{title}{isNew ? <span className="mentor-library-new">New</span> : null}</p>
      <div className="library-progress-line">
        <Bar read={progress.read} total={progress.total} label="Course progress" />
        {badge?.(current.id)}
        <span className="library-count" title={`${progress.read} of ${progress.total} ${reading ? "read" : "done"}`}>{progress.read}/{progress.total}</span>
      </div>
    </div>
    {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
    {course ? <LibraryOutline course={course} activeId={activeId} onSelect={(itemId) => openLesson(agent.id, onOpen, current.id, course.title, itemId)}
      badge={badge ? (lessonId) => badge(current.id, lessonId) : undefined} /> : null}
  </div>;
}
