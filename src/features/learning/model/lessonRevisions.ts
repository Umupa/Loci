import { transport } from "../../../platform/transport";

/** A lesson's text before its last revision, and whether the learner has looked at what changed. */
export type LessonRevision = { courseId: string; lessonId: string; previous?: string; revisedAt: number; seen: boolean };

/** Fired on `window` when a revision is looked at. */
export const REVISIONS_CHANGED_EVENT = "loci:lesson-revisions";

export function loadLessonRevision(agentId: string, courseId: string, lessonId: string): Promise<LessonRevision | null> {
  return transport.call<LessonRevision | null>("lesson_revision_get", { agentId, courseId, lessonId });
}

/** The mentor's lessons revised since the learner last looked, as `course/lesson`. */
export async function loadUnseenRevisions(agentId: string): Promise<Set<string>> {
  const list = await transport.call<LessonRevision[]>("lesson_revisions_unseen", { agentId });
  return new Set((Array.isArray(list) ? list : []).map((entry) => `${entry.courseId}/${entry.lessonId}`));
}

export async function markRevisionSeen(agentId: string, courseId: string, lessonId: string): Promise<void> {
  await transport.call("lesson_revision_seen", { agentId, courseId, lessonId });
  if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent(REVISIONS_CHANGED_EVENT, { detail: { agentId } }));
}
