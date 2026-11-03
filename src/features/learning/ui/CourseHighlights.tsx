import { useEffect, useState } from "react";
import { ResourceHeader } from "../../../shared/ui/ResourceHeader";
import { lessonAnnotations } from "../model/annotationCounts";
import { COURSES_CHANGED_EVENT, loadCourse, type CourseWithProgress } from "../model/course";
import { LEARNING_CHANGED_EVENT } from "../model/learningStore";
import type { Annotation } from "../model/types";
import { blockLabel } from "../model/blockAnchor";
import "./CourseHighlights.css";

type Loaded = { course: CourseWithProgress; marks: Map<string, Annotation[]> };

/** Where a mark starts in its lesson: by page, then height, for a PDF; by place in the text otherwise. */
function readingOrder(a: Annotation, b: Annotation): number {
  const pdf = (entry: Annotation) => entry.anchors[0] ? [entry.anchors[0].page, entry.anchors[0].rects[0]?.y ?? 0] : null;
  const [pa, pb] = [pdf(a), pdf(b)];
  if (pa && pb) return pa[0] - pb[0] || pa[1] - pb[1] || a.createdAt - b.createdAt;
  return (a.anchor?.start ?? 0) - (b.anchor?.start ?? 0) || a.createdAt - b.createdAt;
}

function useCourseHighlights(agentId: string, courseId: string) {
  const [state, setState] = useState<{ key: string; loaded?: Loaded; error?: string }>();
  const [version, setVersion] = useState(0);
  const key = `${agentId}\n${courseId}`;
  useEffect(() => {
    const again = () => setVersion((value) => value + 1);
    window.addEventListener(LEARNING_CHANGED_EVENT, again);
    window.addEventListener(COURSES_CHANGED_EVENT, again);
    return () => { window.removeEventListener(LEARNING_CHANGED_EVENT, again); window.removeEventListener(COURSES_CHANGED_EVENT, again); };
  }, []);
  useEffect(() => {
    let live = true;
    void loadCourse(courseId, agentId).then(async (course) => {
      if (!course) throw new Error("This course is no longer there.");
      const marks = await lessonAnnotations(course);
      if (live) setState({ key, loaded: { course, marks } });
    }).catch((error: unknown) => { if (live) setState({ key, error: error instanceof Error ? error.message : String(error) }); });
    return () => { live = false; };
  }, [key, version]); // eslint-disable-line react-hooks/exhaustive-deps
  return state?.key === key ? state : undefined;
}

/**
 * A course's highlights, which are its notes: every passage kept in its
 * lessons, in the order they are read, each with the thought written on it.
 * A passage opens its lesson.
 */
export function CourseHighlights({ agentId, courseId, title, onOpenLesson, onClose }: {
  agentId: string; courseId: string; title: string;
  onOpenLesson: (lessonId: string) => void;
  onClose: () => void;
}) {
  const state = useCourseHighlights(agentId, courseId);
  const lessons = state?.loaded?.course.data.engine === "reading" ? state.loaded.course.data.chapters.flatMap((chapter) => chapter.lessons) : [];
  const kept = lessons.map((lesson) => ({ lesson, marks: [...(state?.loaded?.marks.get(lesson.id) ?? [])].sort(readingOrder) })).filter((entry) => entry.marks.length);
  const count = kept.reduce((sum, entry) => sum + entry.marks.length, 0);
  return <>
    <ResourceHeader title={`Highlights · ${state?.loaded?.course.title ?? title}`} onClose={onClose} />
    <div className="course-highlights" data-reading-scroll>
      <div className="course-highlights__body reader-body reader-measure">
        {!state ? <p role="status" className="course-highlights__empty">Loading…</p>
          : state.error ? <p role="alert" className="course-highlights__empty">{state.error}</p>
          : !count ? <p className="course-highlights__empty">Select text in a lesson and press H.</p>
          : kept.map(({ lesson, marks }) => <section key={lesson.id} className="course-highlights__lesson" aria-label={lesson.title}>
            <h2><button type="button" onClick={() => onOpenLesson(lesson.id)}>{lesson.title}</button></h2>
            {marks.map((mark) => <button key={mark.id} type="button" className="course-highlights__entry" onClick={() => onOpenLesson(lesson.id)}>
              <span className="course-highlights__quote">{mark.source.quote || (mark.anchor?.block ? blockLabel(mark.anchor.block.kind) : "")}</span>
              {mark.note ? <span className="course-highlights__note">{mark.note}</span> : null}
            </button>)}
          </section>)}
      </div>
    </div>
  </>;
}
