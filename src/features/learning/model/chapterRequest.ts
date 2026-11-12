import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import type { CourseData } from "./course";

/**
 * What the composer is given when a planned lesson is chosen: a request for
 * the chapter it is in, since a mentor writes a chapter at a time. It waits
 * in the composer; nothing is sent.
 */
export function chapterRequestText(course: { id: string; title: string; data: CourseData }, lessonId: string): string | null {
  const chapter = course.data.chapters.find((entry) => entry.lessons.some((lesson) => lesson.id === lessonId));
  if (!chapter) return null;
  return `Write the chapter "${chapter.title}" of the course "${course.title}" (${course.id}).`;
}

/** Puts that request in the mentor's composer. False when the mentor has no conversation yet. */
export function requestChapter(agentId: string, course: { id: string; title: string; data: CourseData }, lessonId: string): boolean {
  const text = chapterRequestText(course, lessonId);
  const targetSessionId = findAgent(agentId)?.sessionId;
  if (!text || !targetSessionId) return false;
  requestAddToChat(text, "plain", { targetSessionId });
  return true;
}
