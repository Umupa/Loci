import { useEffect, useMemo, useState, type ReactNode } from "react";
import { ChevronDown, Plus } from "../../../shared/ui/icons";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { agentLook, type Agent } from "../../agents/model/agent";
import { COURSES_CHANGED_EVENT, loadCourse, type CourseChangedDetail, type CourseSummary } from "../../learning/model/course";
import { loadCoursePath, pathSteps, type PathRead, type PathStep } from "../../learning/model/coursePath";
import { useLiveCourse } from "../../learning/ui/CourseOutline";
import { courseProgress, nextLesson } from "../model/libraryCourse";
import type { MentorLesson, MentorPage } from "../model/mentorPage";
import { LibraryOutline } from "./LibraryOutline";
import { LibraryLoadError } from "./LibraryList";

/** Room after a course's title (no lesson) or a lesson's title, for counts such as highlights. */
export type CourseBadge = (courseId: string, lessonId?: string) => ReactNode;

/** What "ask for a course" puts in the composer, for the user to finish. */
export const NEW_COURSE_PROMPT = "I'd like a new course on ";
/** What "plan a path" puts in the composer. */
export const NEW_PATH_PROMPT = "Plan a learning path of short courses for me, in order, from what we have and what is missing: ";
const ASK = "ask-for-course";
const ASK_PATH = "ask-for-path";

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

const FOLD_KEY = (agentId: string) => `loci:path-folded:${agentId}`;
function readFolded(agentId: string): boolean {
  try { return localStorage.getItem(FOLD_KEY(agentId)) === "1"; } catch { return false; }
}
function writeFolded(agentId: string, folded: boolean) {
  try { if (folded) localStorage.setItem(FOLD_KEY(agentId), "1"); else localStorage.removeItem(FOLD_KEY(agentId)); } catch { /* Kept for this view only. */ }
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

/**
 * The Courses segment: which course (a switcher, ending with asking the
 * mentor for another), how far through it is, and its outline. The outline's
 * current lesson and the reader's own next/previous are where to continue.
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

  if (listed === undefined && !open) return error ? <LibraryLoadError subject="courses" onRetry={onRetry} />
    : <p role="status" className="mentor-library-empty">Loading…</p>;
  if (plan && path) return <>
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    <PathView agentId={agent.id} title={path.title} steps={plan.steps} others={plan.others} currentId={current?.id} problem={pathRead?.error ?? undefined}
      onPick={(entry) => void pickCourse(agent.id, entry, onSelect, onOpen)}
      onPlanned={(step) => onDraft(`Please write the course "${step.title}" (id ${step.id}) on my learning path.`)} />
    {current ? <CourseView key={current.id} agent={agent} name={name} courses={courses} current={current} inPath
      activeId={open?.courseId === current.id ? lesson?.id ?? open.itemId ?? null : null}
      onOpen={onOpen} onSelect={onSelect} onDraft={onDraft} badge={badge} isNew={isNew?.(current.id) ?? false} /> : null}
  </>;
  if (!current) return <div className="library-courses-empty">
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    <p className="mentor-library-empty">No course yet.</p>
    <button type="button" className="library-ask" onClick={() => onDraft(NEW_COURSE_PROMPT)}><Plus aria-hidden className="size-3.5" />Ask {name} for a course</button>
  </div>;
  return <>
    {error ? <LibraryLoadError subject="courses" onRetry={onRetry} /> : null}
    <CourseView key={current.id} agent={agent} name={name} courses={courses} current={current}
      activeId={open?.courseId === current.id ? lesson?.id ?? open.itemId ?? null : null}
      onOpen={onOpen} onSelect={onSelect} onDraft={onDraft} badge={badge} isNew={isNew?.(current.id) ?? false} />
  </>;
}

function CourseView({ agent, name, courses, current, activeId, onOpen, onSelect, onDraft, badge, isNew, inPath = false }: {
  agent: Agent; name: string; courses: CourseSummary[]; current: CourseSummary; activeId: string | null;
  onOpen: Props["onOpen"]; onSelect: Props["onSelect"]; onDraft: Props["onDraft"]; badge?: CourseBadge; isNew?: boolean;
  /** Shown under a learning path, which already names the course and its progress: only the outline. */
  inPath?: boolean;
}) {
  const { course, error } = useLiveCourse(current.id, agent.id);
  const [menu, setMenu] = useState<HTMLElement | null>(null);
  const openLesson = (courseId: string, title: string, itemId?: string) =>
    onOpen({ kind: "course", course: { courseId, agentId: agent.id, title, ...(itemId ? { itemId } : {}) } });

  // Choosing a course lands in it, at the lesson to continue with.
  const pick = async (id: string) => {
    if (id === ASK) { onDraft(NEW_COURSE_PROMPT); return; }
    if (id === ASK_PATH) { onDraft(NEW_PATH_PROMPT); return; }
    const entry = courses.find((item) => item.id === id);
    if (entry) await pickCourse(agent.id, entry, onSelect, onOpen);
  };
  const items: ContextMenuItem[] = [
    ...courses.map((entry): ContextMenuItem => ({ kind: "item", id: entry.id, label: entry.title, checked: entry.id === current.id,
      description: `${entry.masteredCount} / ${entry.itemCount} ${entry.engine === "build-your-own" ? "done" : "read"}` })),
    { kind: "sep" },
    { kind: "item", id: ASK, label: `Ask ${name} for a new course` },
    ...(courses.length >= 2 ? [{ kind: "item" as const, id: ASK_PATH, label: `Ask ${name} to plan a path` }] : []),
  ];

  const progress = course ? courseProgress(course) : { read: current.masteredCount, total: current.itemCount };
  const reading = (course?.data.engine ?? current.engine) === "reading";
  if (inPath) return <div className="library-course library-course--in-path" data-library-course={current.id} data-library-new={isNew || undefined}>
    {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
    {course ? <LibraryOutline course={course} activeId={activeId} onSelect={(itemId) => openLesson(current.id, course.title, itemId)}
      badge={badge ? (lessonId) => badge(current.id, lessonId) : undefined} /> : null}
  </div>;
  return <div className="library-course" data-library-course={current.id} data-library-new={isNew || undefined}>
    <div className="library-course-head">
      <button type="button" className="library-switcher" aria-haspopup="menu" aria-expanded={menu ? true : undefined}
        aria-label={`Course: ${current.title}. Switch course${isNew ? " (new)" : ""}`} title={current.title}
        onClick={(event) => { const anchor = event.currentTarget; setMenu((shown) => shown ? null : anchor); }}>
        <span className="library-switcher-title">{course?.title ?? current.title}</span>
        {isNew ? <span className="mentor-library-new">New</span> : null}
        <ChevronDown aria-hidden className="size-3 shrink-0 opacity-60" />
      </button>
      {badge?.(current.id)}
      <span className="library-progress-text" title={`${progress.read} of ${progress.total} ${reading ? "read" : "done"}`}>{progress.read}/{progress.total}</span>
    </div>
    <div className="library-progress" role="progressbar" aria-label="Course progress" aria-valuemin={0} aria-valuemax={progress.total} aria-valuenow={progress.read}>
      <i style={{ width: progress.total ? `${(progress.read / progress.total) * 100}%` : 0 }} />
    </div>
    {error ? <p role="alert" className="mentor-library-empty">{error}</p> : null}
    {course ? <LibraryOutline course={course} activeId={activeId} onSelect={(itemId) => openLesson(current.id, course.title, itemId)}
      badge={badge ? (lessonId) => badge(current.id, lessonId) : undefined} /> : null}
    {menu ? <ContextMenu anchor={menu} ariaLabel="Courses" items={items} onClose={() => setMenu(null)}
      onPick={(id) => { setMenu(null); void pick(id); }} /> : null}
  </div>;
}

/**
 * The learning path: its courses in order, each with how far it is read, a
 * planned course muted, and "Best after" while a prerequisite is not read to
 * the end (a hint; every course stays open). Folds to the course chosen.
 */
function PathView({ agentId, title, steps, others, currentId, problem, onPick, onPlanned }: {
  agentId: string; title?: string; steps: PathStep[]; others: CourseSummary[]; currentId?: string; problem?: string;
  onPick: (entry: CourseSummary) => void; onPlanned: (step: PathStep) => void;
}) {
  const [folded, setFolded] = useState(() => readFolded(agentId));
  const toggle = () => setFolded((value) => { writeFolded(agentId, !value); return !value; });
  const written = steps.filter((step) => !step.planned);
  const read = written.reduce((sum, step) => sum + step.read, 0);
  const total = written.reduce((sum, step) => sum + step.total, 0);
  const shown = folded ? steps.filter((step) => step.id === currentId) : steps;
  const summary = (step: PathStep): CourseSummary => ({ id: step.id, agentId, engine: "reading", title: step.title, updatedAt: 0, itemCount: step.total, masteredCount: step.read });
  return <div className="library-path" data-library-path>
    <div className="library-path-head">
      <button type="button" className="library-path-fold" aria-expanded={!folded} aria-label={folded ? "Show the whole path" : "Fold the path"} title={folded ? "Show the whole path" : "Fold the path"} onClick={toggle}>
        <ChevronDown aria-hidden className="size-3 shrink-0 opacity-60" style={folded ? { transform: "rotate(-90deg)" } : undefined} />
        <span className="library-path-title">{title ?? "Learning path"}</span>
      </button>
      <span className="library-progress-text" title={`${read} of ${total} lessons read`}>{read}/{total}</span>
    </div>
    {problem ? <p role="alert" className="mentor-library-empty">The path file has a problem: {problem}</p> : null}
    <ol className="library-path-list" aria-label="Courses on the path">
      {shown.map((step) => <li key={step.id}>
        <button type="button" className="library-path-step" aria-current={step.id === currentId ? "true" : undefined} data-planned={step.planned || undefined}
          title={step.planned ? `${step.title}: not written yet. Ask for it.` : `${step.title}: ${step.read} of ${step.total} read`}
          onClick={() => step.planned ? onPlanned(step) : onPick(summary(step))}>
          <span className="library-path-n">{step.position}</span>
          <span className="library-path-name">{step.title}</span>
          {step.planned ? <span className="library-path-planned">planned</span> : <>
            <span className="library-path-bar" aria-hidden><i style={{ width: step.total ? `${(step.read / step.total) * 100}%` : 0 }} /></span>
            <span className="library-progress-text">{step.read}/{step.total}</span>
          </>}
        </button>
        {!folded && step.pending.length ? <p className="library-path-after">Best after {step.pending.map((item) => item.title).join(", ")}</p> : null}
      </li>)}
    </ol>
    {!folded && others.length ? <>
      <p className="library-path-others">Other courses</p>
      <ul className="library-path-list" aria-label="Other courses">
        {others.map((entry) => <li key={entry.id}>
          <button type="button" className="library-path-step" aria-current={entry.id === currentId ? "true" : undefined} onClick={() => onPick(entry)} title={entry.title}>
            <span className="library-path-n" />
            <span className="library-path-name">{entry.title}</span>
            <span className="library-progress-text">{entry.masteredCount}/{entry.itemCount}</span>
          </button>
        </li>)}
      </ul>
    </> : null}
  </div>;
}
