import { useEffect, useSyncExternalStore } from "react";
import { lessonMarkCounts, type MarkCount } from "../model/annotationCounts";
import { COURSES_CHANGED_EVENT, loadCourse } from "../model/course";
import { LEARNING_CHANGED_EVENT } from "../model/learningStore";
import "./LessonMarks.css";

/**
 * How many highlights and notes a lesson (or a whole course) has, as a small
 * muted count in the course outline. Nothing shows at zero. One fetch serves
 * every lesson of a course, and is refreshed when marks or courses change.
 */

type Entry = { counts?: Map<string, MarkCount>; loading?: boolean };
const cache = new Map<string, Entry>();
const listeners = new Set<() => void>();
let version = 0;
const notify = () => { version++; for (const listener of listeners) listener(); };

function refresh(agentId: string, courseId: string) {
  const key = `${agentId}\n${courseId}`;
  const entry = cache.get(key) ?? {};
  if (entry.loading) return;
  cache.set(key, { ...entry, loading: true });
  void loadCourse(courseId, agentId)
    .then((course) => course ? lessonMarkCounts(course) : new Map<string, MarkCount>())
    .then((counts) => { cache.set(key, { counts }); notify(); }, () => { cache.set(key, { ...cache.get(key), loading: false }); });
}

let watching = false;
function watch() {
  if (watching || typeof window === "undefined") return;
  watching = true;
  const stale = () => {
    for (const key of [...cache.keys()]) {
      const [agentId, courseId] = key.split("\n");
      cache.set(key, { ...cache.get(key), loading: false });
      refresh(agentId, courseId);
    }
  };
  window.addEventListener(LEARNING_CHANGED_EVENT, stale);
  window.addEventListener(COURSES_CHANGED_EVENT, stale);
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

/** The counts per lesson of one course, once known. */
export function useCourseMarks(agentId: string, courseId: string): Map<string, MarkCount> | undefined {
  useSyncExternalStore(subscribe, () => version, () => version);
  useEffect(() => {
    watch();
    if (!cache.get(`${agentId}\n${courseId}`)?.counts) refresh(agentId, courseId);
  }, [agentId, courseId]);
  return cache.get(`${agentId}\n${courseId}`)?.counts;
}

export function markLabel({ highlights, notes }: MarkCount): string {
  return `${highlights} highlight${highlights === 1 ? "" : "s"}${notes ? ` · ${notes} note${notes === 1 ? "" : "s"}` : ""}`;
}

/** A lesson's count, or the course's total without `lessonId`. */
export function LessonMarks({ agentId, courseId, lessonId }: { agentId: string; courseId: string; lessonId?: string }) {
  const counts = useCourseMarks(agentId, courseId);
  if (!counts) return null;
  const count = lessonId ? counts.get(lessonId) : [...counts.values()].reduce((sum, entry) => ({ highlights: sum.highlights + entry.highlights, notes: sum.notes + entry.notes }), { highlights: 0, notes: 0 });
  if (!count?.highlights) return null;
  const label = markLabel(count);
  return <span className="lesson-marks" title={label} data-lesson-marks={count.highlights}>
    <i aria-hidden className="lesson-marks__dot" />
    <span aria-hidden="true">{count.highlights}</span>
    {count.notes ? <i aria-hidden className="lesson-marks__note" /> : null}
    <span className="sr-only">{label}</span>
  </span>;
}
