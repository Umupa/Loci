import { courseItems, lessonPlanned, loadCourse, type CourseWithProgress } from "../../learning/model/course";
import { loadLessonQuestions, type LessonQuestion } from "../../learning/model/lessonQuestions";

/** Away from a mentor at least this long, opening it again offers to pick up where things were left. */
export const RETURN_AFTER_MS = 6 * 60 * 60_000;
const KEY = "loci:mentor-active-at";

function read(): Record<string, number> {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(KEY) ?? "{}");
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, number> : {};
  } catch { return {}; }
}

/** When the learner was last with this mentor, on this device; 0 when never. */
export function mentorActiveAt(agentId: string): number {
  const at = read()[agentId];
  return typeof at === "number" && Number.isFinite(at) ? at : 0;
}

/** The learner is with this mentor now. */
export function touchMentor(agentId: string, now = Date.now()): void {
  try { localStorage.setItem(KEY, JSON.stringify({ ...read(), [agentId]: now })); } catch { /* a convenience; nothing breaks without it */ }
}

/** Whether coming back to this mentor now is coming back after a while. */
export function returningTo(agentId: string, now = Date.now()): boolean {
  const at = mentorActiveAt(agentId);
  return at > 0 && now - at >= RETURN_AFTER_MS;
}

type LessonRef = { courseId: string; courseTitle: string; lessonId: string; title: string };

/** Where things were left: the lesson last read, the question last asked, and the lesson to go on with. */
export type ReturnSummary = {
  last?: LessonRef & { read: boolean };
  question?: LessonQuestion;
  next?: LessonRef;
  /** What one click opens: the last lesson while it is unread, else the next. */
  go?: LessonRef;
};

/** The lesson after `lessonId` that has something to read. */
function after(course: CourseWithProgress, lessonId: string): LessonRef | undefined {
  const items = courseItems(course.data);
  const at = items.findIndex((item) => item.id === lessonId);
  const found = items.slice(at + 1).find((item) => !lessonPlanned(course, item));
  return found ? { courseId: course.id, courseTitle: course.title, lessonId: found.id, title: found.title } : undefined;
}

/**
 * Put together from what this device already has; no model is asked. The
 * last lesson is the one the reader was left on, else the one last asked
 * about.
 */
export async function returnSummary(agentId: string, left?: { courseId: string; lessonId?: string }): Promise<ReturnSummary> {
  const question = (await loadLessonQuestions(agentId, { limit: 1 }).catch(() => []))[0];
  const where = left?.lessonId ? { courseId: left.courseId, lessonId: left.lessonId } : question ? { courseId: question.courseId, lessonId: question.lessonId } : undefined;
  if (!where) return question ? { question } : {};
  const course = await loadCourse(where.courseId, agentId).catch(() => null);
  const lesson = course ? courseItems(course.data).find((item) => item.id === where.lessonId) : undefined;
  if (!course || !lesson) return question ? { question } : {};
  const read = course.progress.get(lesson.id) === "mastered";
  const last = { courseId: course.id, courseTitle: course.title, lessonId: lesson.id, title: lesson.title, read };
  const next = after(course, lesson.id);
  return { last, ...(question ? { question } : {}), ...(next ? { next } : {}), go: read ? next : last };
}
