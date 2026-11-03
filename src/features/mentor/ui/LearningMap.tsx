import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { agentLook, type Agent } from "../../agents/model/agent";
import { COURSES_CHANGED_EVENT, loadCourse, loadCourseSummaries, PROGRESS_EVENT, type CourseChangedDetail, type ProgressDetail } from "../../learning/model/course";
import { nextLesson, withoutOrdinal } from "../model/libraryCourse";
import { contours, layoutLearningMap, mapSize, roundedPath, type MapCourse, type MapPlot } from "../model/learningMap";
import type { MentorPage } from "../model/mentorPage";
import { useCoursePath } from "./LibraryCourses";
import "./LearningMap.css";

/** The mentor's courses in path order (then the rest), each with its lessons and how far each is read. */
function useMapCourses(agentId: string): { courses: MapCourse[]; next?: { courseId: string; lessonId: string }; loaded: boolean; title?: string } {
  const path = useCoursePath(agentId);
  const [state, setState] = useState<{ agentId: string; courses: MapCourse[]; next?: { courseId: string; lessonId: string } }>();
  const [version, setVersion] = useState(0);
  useEffect(() => {
    const bump = (event: Event) => {
      const detail = (event as CustomEvent<CourseChangedDetail | ProgressDetail>).detail;
      if (!detail || detail.agentId === agentId) setVersion((value) => value + 1);
    };
    window.addEventListener(COURSES_CHANGED_EVENT, bump);
    window.addEventListener(PROGRESS_EVENT, bump);
    return () => { window.removeEventListener(COURSES_CHANGED_EVENT, bump); window.removeEventListener(PROGRESS_EVENT, bump); };
  }, [agentId]);
  useEffect(() => {
    let live = true;
    void (async () => {
      const own = (await loadCourseSummaries().catch(() => [])).filter((course) => course.agentId === agentId);
      const order = path?.path?.courses ?? [];
      const known = new Map(own.map((course) => [course.id, course]));
      const ids = [...order.map((entry) => entry.id), ...own.filter((course) => !order.some((entry) => entry.id === course.id)).map((course) => course.id)];
      let next: { courseId: string; lessonId: string } | undefined;
      const courses = await Promise.all(ids.map(async (id): Promise<MapCourse> => {
        const summary = known.get(id);
        const planned = order.find((entry) => entry.id === id);
        if (!summary) return { id, title: planned?.title ?? id, lessons: [], planned: true };
        const course = await loadCourse(id, agentId).catch(() => null);
        if (!course || course.data.engine !== "reading") return { id, title: summary.title, lessons: [] };
        return {
          id, title: course.title,
          lessons: course.data.chapters.flatMap((chapter) => chapter.lessons).map((lesson) => ({ id: lesson.id, title: lesson.title, status: course.progress.get(lesson.id) ?? "untouched" })),
        };
      }));
      // Where to go on: the first course on the path with a lesson left, at its next lesson.
      for (const course of courses) {
        const found = course.lessons.length ? nextLesson({ data: { engine: "reading", chapters: [{ title: "", lessons: course.lessons }] }, progress: new Map(course.lessons.map((lesson) => [lesson.id, lesson.status])) }) : undefined;
        if (found) { next = { courseId: course.id, lessonId: found.id }; break; }
      }
      if (live) setState({ agentId, courses, next });
    })();
    return () => { live = false; };
  }, [agentId, path, version]);
  const shown = state?.agentId === agentId ? state : undefined;
  return { courses: shown?.courses ?? [], next: shown?.next, loaded: !!shown, title: path?.path?.title };
}

function useSize<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => {
      const rect = element.getBoundingClientRect();
      // Whole tens: a pixel of resize does not reshuffle the map.
      setSize((current) => {
        const width = Math.round(rect.width / 10) * 10, height = Math.round(rect.height / 10) * 10;
        return current.width === width && current.height === height ? current : { width, height };
      });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return [ref, size] as const;
}

/** Roughly how wide a label is at the map's size: CJK and full-width forms take a full em. */
function labelWidth(text: string): number {
  let width = 0;
  for (const char of text) width += /[\u2E80-\uFFEF]/u.test(char) ? 13.5 : 7.6;
  return width;
}

/**
 * A course's name as its region can hold it: the part before a colon (the
 * subject, without its subtitle), cut short with an ellipsis if still too wide.
 */
export function mapLabel(title: string, room: number): string {
  const subject = withoutOrdinal(title).split(/[：:]/)[0].trim() || withoutOrdinal(title);
  if (labelWidth(subject) <= room) return subject;
  let shown = "";
  for (const char of subject) {
    if (labelWidth(`${shown}${char}…`) > room) break;
    shown += char;
  }
  return shown ? `${shown.trimEnd()}…` : "";
}

const STATUS_LABEL = { mastered: "Read", learning: "Reading", untouched: "Not read yet" } as const;

function Plot({ plot, next, onOpen }: { plot: MapPlot; next: boolean; onOpen: () => void }) {
  const { lesson, shape } = plot;
  const d = roundedPath(shape, 14);
  return <g className="learning-map__plot" data-status={lesson.status} data-next={next || undefined} role="button" tabIndex={0}
    aria-label={`${lesson.title}, ${STATUS_LABEL[lesson.status]}`} onClick={onOpen}
    onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onOpen(); } }}>
    <title>{`${lesson.title} · ${STATUS_LABEL[lesson.status]}`}</title>
    <path d={d} className="learning-map__ground" />
    {lesson.status === "learning" ? contours(shape).map((ring, index) => <path key={index} d={roundedPath(ring, Math.max(4, 12 - index * 2))} className="learning-map__contour" />) : null}
  </g>;
}

/**
 * The reader before anything is open: the mentor's courses as a map. Each
 * lesson is a plot, inked once read, drawn in contour lines while being read,
 * stone until then; a course the path names but nobody wrote yet is only an
 * outline. A plot opens its lesson.
 */
export function LearningMap({ agent, onOpen }: { agent: Agent; onOpen: (page: MentorPage) => void }) {
  const { courses, next, loaded, title } = useMapCourses(agent.id);
  if (loaded && !courses.length) return <div className="mentor-reader-empty" data-tauri-drag-region="deep">
    <p>Ask {agentLook(agent).name} for a course.</p>
  </div>;
  return <LearningMapView courses={courses} next={next} title={title}
    onOpenLesson={(course, lessonId) => onOpen({ kind: "course", course: { courseId: course.id, agentId: agent.id, title: course.title, itemId: lessonId } })} />;
}

/** The map itself, from courses already loaded. */
export function LearningMapView({ courses, next, title, onOpenLesson }: {
  courses: readonly MapCourse[];
  /** The lesson to go on with, marked in the mentor's colour. */
  next?: { courseId: string; lessonId: string };
  /** The learning path's name. */
  title?: string;
  onOpenLesson: (course: MapCourse, lessonId: string) => void;
}) {
  const [frame, room] = useSize<HTMLDivElement>();
  const size = useMemo(() => mapSize(courses, room.width, room.height), [courses, room.width, room.height]);
  const regions = useMemo(() => layoutLearningMap(courses, size.width, size.height), [courses, size.width, size.height]);
  const lessons = courses.flatMap((course) => course.lessons);
  const read = lessons.filter((lesson) => lesson.status === "mastered").length;
  // One course is the map's whole subject: its name is the heading, not a label on the ground.
  const single = courses.length === 1;
  const heading = title ?? (single ? withoutOrdinal(courses[0].title) : undefined);
  return <section className="learning-map" aria-label="Learning map" data-learning-map>
    <header className="learning-map__head">
      <p className="learning-map__count" aria-label={`${read} of ${lessons.length} lessons read`}>{read}<small>/ {lessons.length}</small></p>
      {heading ? <h2 className="learning-map__title">{heading}</h2> : null}
    </header>
    <div ref={frame} className="learning-map__frame">
      {size.width ? <svg width={size.width} height={size.height} viewBox={`0 0 ${size.width} ${size.height}`} className="learning-map__svg">
        {regions.map((region) => region.course.planned || !region.plots.length
          ? <path key={region.course.id} d={roundedPath(region.shape, 18)} className="learning-map__planned"
            role="img" aria-label={`${region.course.title}, not written yet`}><title>{`${region.course.title} · not written yet`}</title></path>
          : <g key={region.course.id}>{region.plots.map((plot) => <Plot key={plot.lesson.id} plot={plot}
            next={next?.courseId === region.course.id && next.lessonId === plot.lesson.id}
            onOpen={() => onOpenLesson(region.course, plot.lesson.id)} />)}</g>)}
        {single ? null : regions.map((region) => {
          const done = region.course.lessons.filter((lesson) => lesson.status === "mastered").length;
          const xs = region.shape.map((point) => point[0]);
          const name = mapLabel(region.course.title, (Math.max(...xs) - Math.min(...xs)) * 0.86);
          return <g key={`label:${region.course.id}`} className="learning-map__label" transform={`translate(${region.center[0].toFixed(1)} ${region.center[1].toFixed(1)})`}>
            <text y={-3}>{name}</text>
            {region.course.lessons.length ? <text y={14} className="learning-map__label-count">{done} / {region.course.lessons.length}</text> : null}
          </g>;
        })}
      </svg> : null}
    </div>
    <footer className="learning-map__legend" aria-hidden>
      <span data-status="mastered">Read</span><span data-status="learning">Reading</span><span data-status="untouched">Not yet</span><span data-status="planned">To be written</span>
    </footer>
  </section>;
}
