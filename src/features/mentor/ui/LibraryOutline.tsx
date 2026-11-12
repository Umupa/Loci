import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { Check, ChevronDown, File, FileScript, Ungroup, type IconComponent } from "../../../shared/ui/icons";
import { lessonPlanned, type CourseLesson, type CourseWithProgress, type LearningStatus } from "../../learning/model/course";
import { requestChapter } from "../../learning/model/chapterRequest";
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
  const chapters: Chapter[] = course.data.chapters.map((chapter, at) => ({ key: String(at), title: chapter.title, lessons: chapter.lessons }));
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
        const planned = !!course.bodies && lessonPlanned(course, lesson as CourseLesson);
        // A lesson the mentor wrote needs no kind: it is the lesson itself.
        const kind = planned || course.bodies?.has(lesson.id) ? undefined : KINDS[lessonKind(lesson)];
        return <li key={lesson.id}>
          <button ref={current ? active : undefined} type="button" data-library-item data-library-lesson={lesson.id} data-planned={planned ? "" : undefined}
            className={`library-lesson library-lesson--${planned ? "planned" : state}${current ? " library-lesson--current" : ""}`}
            aria-current={current ? "step" : undefined} aria-label={`${lesson.title}, ${planned ? "Planned" : statusLabel(state)}`}
            aria-describedby={marks ? `${marksId}-${lesson.id}` : undefined}
            title={lesson.title} onClick={() => { if (!planned || !requestChapter(course.agentId, course, lesson.id)) onSelect(lesson.id); }}>
            <span aria-hidden className={`library-mark library-mark--${planned ? "planned" : state}`}>{state === "mastered" ? <Check className="size-2" strokeWidth={3.5} /> : null}</span>
            <span className="library-lesson-title"><span>{lesson.title}</span></span>
            {kind ? <span className="library-lesson-kind" title={kind.label} data-lesson-kind={lessonKind(lesson)}><kind.Icon aria-hidden className="size-3.5" /></span> : null}
            {marks ? <span id={`${marksId}-${lesson.id}`} className="library-lesson-marks">{marks}</span> : null}
          </button>
        </li>;
      })}</ol> : null;
      if (chapter.title === null) return <div key={chapter.key}>{lessons}</div>;
      return <section key={chapter.key} className="library-chapter" aria-label={chapter.title}>
        <button type="button" data-library-item className="library-chapter-title" aria-expanded={open} title={chapter.title}
          onClick={() => setOpen(chapter.key, !open)} onKeyDown={chapterKeys(chapter, open)}>
          <span className="library-chapter-name">{chapter.title}</span>
          <ChevronDown aria-hidden className="library-chevron size-3 shrink-0" />
        </button>
        {lessons}
      </section>;
    })}
  </nav>;
}
