import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { ChevronDown, ChevronRight } from "../../../shared/ui/icons";
import type { CourseWithProgress, LearningStatus } from "../../learning/model/course";
import { statusLabel } from "../../learning/ui/CourseOutline";
import { listKeyDown } from "./listKeys";

type Props = {
  course: CourseWithProgress;
  /** The lesson the reader shows, when it shows this course. */
  activeId: string | null;
  onSelect: (lessonId: string) => void;
  /** Room after a lesson's title. */
  badge?: (lessonId: string) => ReactNode;
};

type Chapter = { key: string; title: string | null; lessons: { id: string; title: string }[] };

/**
 * The course's chapters and lessons, following the reader: the open lesson
 * is marked and kept in view, read lessons are ticked and quiet, and a
 * lesson begun shows a half circle. Chapters fold; one wholly read starts
 * folded unless the open lesson is in it.
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

  let number = 0;
  return <nav className="library-outline" aria-label="Course navigation" onKeyDown={listKeyDown}>
    {chapters.map((chapter, at) => {
      const open = isOpen(chapter);
      const first = number;
      number += chapter.lessons.length;
      const lessons = open ? <ol className="library-outline-lessons">{chapter.lessons.map((lesson, index) => {
        const state = status(lesson.id);
        const current = lesson.id === activeId;
        const marks = badge?.(lesson.id);
        return <li key={lesson.id}>
          <button ref={current ? active : undefined} type="button" data-library-item data-library-lesson={lesson.id}
            className={`library-lesson library-lesson--${state}${current ? " library-lesson--current" : ""}`}
            aria-current={current ? "step" : undefined} aria-label={`${lesson.title}, ${statusLabel(state, reading)}`}
            aria-describedby={marks ? `${marksId}-${lesson.id}` : undefined}
            title={lesson.title} onClick={() => onSelect(lesson.id)}>
            <span aria-hidden className={`library-mark library-mark--${state}`}>{state === "mastered" ? "✓" : ""}</span>
            <span className="library-lesson-number" aria-hidden>{String(first + index + 1).padStart(2, "0")}</span>
            <span className="library-lesson-title">{lesson.title}</span>
            {marks ? <span id={`${marksId}-${lesson.id}`} className="ml-auto flex">{marks}</span> : null}
          </button>
        </li>;
      })}</ol> : null;
      if (chapter.title === null) return <div key={chapter.key}>{lessons}</div>;
      return <section key={chapter.key} className="library-chapter" aria-label={chapter.title}>
        <button type="button" data-library-item className="library-chapter-title" aria-expanded={open}
          onClick={() => setOpen(chapter.key, !open)} onKeyDown={chapterKeys(chapter, open)}>
          {open ? <ChevronDown aria-hidden className="size-3 shrink-0" /> : <ChevronRight aria-hidden className="size-3 shrink-0" />}
          <span className="library-chapter-dot" style={{ background: `var(--course-chapter-${at % 6})` }} aria-hidden />
          <span className="min-w-0 flex-1 truncate">{chapter.title}</span>
          {open ? null : <span className="mentor-library-count">{chapter.lessons.length}</span>}
        </button>
        {lessons}
      </section>;
    })}
  </nav>;
}
