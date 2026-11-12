import { useLiveCourse } from "../../learning/ui/CourseOutline";
import { lessonPlanned, type CourseLesson } from "../../learning/model/course";

/**
 * The outline folded to a strip beside a lesson being read: one short line
 * per lesson, a gap between chapters, the open lesson heavier. Pointing at it
 * opens the full outline over the text; a line opens its lesson.
 */
export function LessonStrip({ agentId, courseId, lessonId, onPeek, onSelect }: {
  agentId: string; courseId: string; lessonId?: string;
  onPeek: () => void;
  onSelect: (lessonId: string) => void;
}) {
  const { course } = useLiveCourse(courseId, agentId);
  return <nav className="lesson-strip" aria-label="Lessons" data-lesson-strip onPointerEnter={onPeek} onFocus={onPeek}>
    {course?.data.chapters.map((chapter, at) => <ol key={chapter.id ?? at} className="lesson-strip__chapter" aria-label={chapter.title}>
      {chapter.lessons.map((lesson) => {
        const planned = lessonPlanned(course, lesson as CourseLesson);
        const read = course.progress.get(lesson.id) === "mastered";
        return <li key={lesson.id}>
          <button type="button" className="lesson-strip__line" title={lesson.title} aria-label={lesson.title}
            aria-current={lesson.id === lessonId ? "step" : undefined} data-read={read || undefined} data-planned={planned || undefined}
            disabled={planned} onClick={() => onSelect(lesson.id)} />
        </li>;
      })}
    </ol>)}
  </nav>;
}
