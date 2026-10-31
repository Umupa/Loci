import type { ReactNode } from "react";
import { Mortarboard } from "../../../shared/ui/icons";
import type { Agent } from "../../agents/model/agent";
import type { CourseSummary } from "../../learning/model/course";
import { LiveCourseOutline } from "../../learning/ui/CourseOutline";
import type { MentorLesson, MentorPage } from "../model/mentorPage";

/** Room after a course's title (no lesson) or a lesson's title, for counts such as highlights. */
export type CourseBadge = (courseId: string, lessonId?: string) => ReactNode;

type Props = {
  agent: Agent;
  courses: CourseSummary[] | undefined;
  selected?: string;
  page?: MentorPage;
  lesson?: MentorLesson;
  onOpen: (page: MentorPage) => void;
  onSelect: (courseId: string) => void;
  onDraft: (text: string) => void;
  badge?: CourseBadge;
};

/** The Courses segment: the mentor's courses, then the chosen one's outline. */
export function LibraryCourses({ agent, courses: listed, selected, page, lesson, onOpen }: Props) {
  const open = page?.kind === "course" ? page.course : undefined;
  if (listed === undefined && !open) return <p role="status" className="mentor-library-empty">Loading…</p>;
  // A course just written may be open before the listing has it.
  const courses = [...(listed ?? [])];
  if (open && !courses.some((entry) => entry.id === open.courseId))
    courses.unshift({ id: open.courseId, agentId: agent.id, engine: "reading", title: open.title, updatedAt: 0, itemCount: 0, masteredCount: 0 });
  if (!courses.length) return <p className="mentor-library-empty">Ask your mentor to arrange a course.</p>;
  const current = courses.find((entry) => entry.id === (selected ?? open?.courseId)) ?? courses[0];
  return <div className="mentor-library-body">
    {courses.map((entry) => <button key={entry.id} type="button" className="mentor-library-row" data-resource-kind="course" data-resource-id={entry.id} aria-label={`course: ${entry.title}`}
      onClick={() => onOpen({ kind: "course", course: { courseId: entry.id, agentId: agent.id, title: entry.title } })}>
      <span aria-hidden className="mentor-library-icon"><Mortarboard className="size-3.5" /></span>
      <span className="mentor-library-copy"><span className="mentor-library-title">{entry.title}</span><span className="mentor-library-subtitle">{entry.masteredCount} / {entry.itemCount} read</span></span>
    </button>)}
    <LiveCourseOutline courseId={current.id} agentId={agent.id} activeId={open?.courseId === current.id ? lesson?.id ?? open.itemId ?? null : null}
      onSelect={(itemId) => onOpen({ kind: "course", course: { courseId: current.id, agentId: agent.id, title: current.title, itemId } })} />
  </div>;
}
