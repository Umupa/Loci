import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { Check, ChevronDown, File, FileScript, Ungroup, type IconComponent } from "../../../shared/ui/icons";
import type { CourseLesson, CourseWithProgress, LearningStatus } from "../../learning/model/course";
import { statusLabel } from "../../learning/ui/CourseOutline";
import { lessonKind, type LessonKind } from "../model/libraryCourse";

type Props = {
  course: CourseWithProgress;
  /** The lesson the reader shows, when it shows this course. */
  activeId: string | null;
  onSelect: (lessonId: string) => void;
  /** Room after a lesson's title. */
  badge?: (lessonId: string) => ReactNode;
};

type Chapter = { key: string; title: string | null; lessons: (Pick<CourseLesson, "id" | "title"> & Partial<CourseLesson>)[] };

const KINDS: Record<LessonKind, { label: string; Icon: IconComponent }> = {
  source: { label: "Source", Icon: File },
  code: { label: "Code tour", Icon: FileScript },
  compare: { label: "Comparison", Icon: Ungroup },
};

/**
 * The course's chapters and lessons, following the reader: the open lesson
 * is marked and kept in view, read lessons are ticked and quiet, and a
 * lesson begun shows a half circle. Chapters fold; one wholly read starts
 * folded unless the open lesson is in it. Its rows are `data-library-item`s
 * of the list around it, whose arrow keys move through them.
 */
export function LibraryOutline({ course, activeId, onSelect, badge }: Props) {
  const marksId = useId();
  const reading = course.data.engine === "reading";
  const chapters: Chapter[] = course.data.engine === "reading"
    ? course.data.chapters.map((chapter, at) => ({ key: String(at), title: chapter.title, lessons: chapter.lessons }))
    : [{ key: "steps", title: null, lessons: course.data.steps }];
  const status = (id: string): LearningStatus => course.progress.get(id) ?? "untouched";
  const [folds, setFolds] = useState<{ course: string; open: Record<string, boolean> }>({ course: course.id, open: {} });
  const overrides = folds.course === course.id ? folds.open : {};
  const holdsActive = (chapter: Chapter) => !!activeId && chapter.lessons.some((lesson) => lesson.id === activeId);
  const isOpen = (chapter: Chapter) => chapter.title === null || (overrides[chapter.key]
    ?? (holdsActive(chapter) || !chapter.lessons.length || chapter.lessons.some((lesson) => status(lesson.id) !== "mastered")));
  const setOpen = (key: string, open: boolean) => setFolds((current) => ({ course: course.id, open: { ...(current.course === course.id ? current.open : {}), [key]: open } }));

  // Opening a lesson unfolds its chapter, then brings the lesson into view.
  const activeChapter = chapters.find(holdsActive);
  const activeHidden = activeChapter ? !isOpen(activeChapter) : false;
  useEffect(() => {
    if (activeChapter && activeHidden) setOpen(activeChapter.key, true);
  }, [activeId, course.id]); // eslint-disable-line react-hooks/exhaustive-deps
  const active = useRef<HTMLButtonElement>(null);
  useEffect(() => { active.current?.scrollIntoView?.({ block: "nearest" }); }, [activeId, course.id, activeHidden]);

  const chapterKeys = (chapter: Chapter, open: boolean) => (event: KeyboardEvent<HTMLButtonElement>) => {
    if ((event.key === "ArrowRight" && !open) || (event.key === "ArrowLeft" && open)) {
      event.preventDefault();
      setOpen(chapter.key, !open);
    }
  };

  return <nav className="library-outline" aria-label="Course navigation">
    {chapters.map((chapter) => {
      const open = isOpen(chapter);
      const lessons = open ? <ol className="library-outline-lessons">{chapter.lessons.map((lesson) => {
        const state = status(lesson.id);
        const current = lesson.id === activeId;
        const marks = badge?.(lesson.id);
        // Build-your-own steps are all code; only a reading course's lessons say what they read.
        const kind = reading ? KINDS[lessonKind(lesson)] : undefined;
        return <li key={lesson.id}>
          <button ref={current ? active : undefined} type="button" data-library-item data-library-lesson={lesson.id}
            className={`library-lesson library-lesson--${state}${current ? " library-lesson--current" : ""}`}
            aria-current={current ? "step" : undefined} aria-label={`${lesson.title}, ${statusLabel(state, reading)}`}
            aria-describedby={marks ? `${marksId}-${lesson.id}` : undefined}
            title={lesson.title} onClick={() => onSelect(lesson.id)}>
            <span aria-hidden className={`library-mark library-mark--${state}`}>{state === "mastered" ? <Check className="size-2.5" strokeWidth={3} /> : null}</span>
            <span className="library-lesson-title"><span>{lesson.title}</span></span>
            {kind ? <span className="library-lesson-kind" title={kind.label} data-lesson-kind={lessonKind(lesson)}><kind.Icon aria-hidden className="size-3.5" /></span> : null}
            {marks ? <span id={`${marksId}-${lesson.id}`} className="library-lesson-marks">{marks}</span> : null}
          </button>
        </li>;
      })}</ol> : null;
      if (chapter.title === null) return <div key={chapter.key}>{lessons}</div>;
      const read = chapter.lessons.filter((lesson) => status(lesson.id) === "mastered").length;
      return <section key={chapter.key} className="library-chapter" aria-label={chapter.title}>
        <button type="button" data-library-item className="library-chapter-title" aria-expanded={open} title={chapter.title}
          onClick={() => setOpen(chapter.key, !open)} onKeyDown={chapterKeys(chapter, open)}>
          <ChevronDown aria-hidden className="library-chevron size-3 shrink-0" />
          <span className="library-chapter-name">{chapter.title}</span>
          <span className="library-count" aria-label={`${read} of ${chapter.lessons.length} ${reading ? "read" : "done"}`}>{read}/{chapter.lessons.length}</span>
        </button>
        {lessons}
      </section>;
    })}
  </nav>;
}
