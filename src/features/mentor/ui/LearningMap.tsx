import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { agentLook, type Agent } from "../../agents/model/agent";
import { COURSES_CHANGED_EVENT, loadCourse, PROGRESS_EVENT, type CourseChangedDetail, type CourseSummary, type CourseWithProgress, type ProgressDetail } from "../../learning/model/course";
import { nextLesson, withoutOrdinal } from "../model/libraryCourse";
import { chordWidth, contours, layoutLearningMap, mapSize, roundedPath, type MapCourse, type MapPlot } from "../model/learningMap";
import type { MentorPage } from "../model/mentorPage";
import { useCoursePath } from "./LibraryCourses";
import "./LearningMap.css";

/**
 * The mentor's courses in path order (then the rest), each with its lessons and
 * how far each is read. `listed` is the workspace's course listing, undefined
 * until it is read. Each course is read once, all at the same time; a course
 * or progress change reads them again.
 */
function useMapCourses(agentId: string, listed: readonly CourseSummary[] | undefined): { courses: MapCourse[]; next?: { courseId: string; lessonId: string }; loaded: boolean; title?: string } {
  const path = useCoursePath(agentId);
  const [state, setState] = useState<{ agentId: string; courses: MapCourse[]; next?: { courseId: string; lessonId: string } }>();
  const [version, setVersion] = useState(0);
  const reads = useRef<{ key: string; courses: Map<string, Promise<CourseWithProgress | null>> }>(undefined);
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
    if (!listed) return;
    let live = true;
    const key = `${agentId}\0${version}`;
    if (reads.current?.key !== key) reads.current = { key, courses: new Map() };
    const cache = reads.current.courses;
    const read = (id: string) => {
      let pending = cache.get(id);
      if (!pending) { pending = loadCourse(id, agentId).catch(() => null); cache.set(id, pending); }
      return pending;
    };
    const order = path?.path?.courses ?? [];
    const known = new Map(listed.map((course) => [course.id, course]));
    const ids = [...order.map((entry) => entry.id), ...listed.filter((course) => !order.some((entry) => entry.id === course.id)).map((course) => course.id)];
    void (async () => {
      let next: { courseId: string; lessonId: string } | undefined;
      const courses = await Promise.all(ids.map(async (id): Promise<MapCourse> => {
        const summary = known.get(id);
        const planned = order.find((entry) => entry.id === id);
        if (!summary) return { id, title: planned?.title ?? id, lessons: [], planned: true };
        const course = await read(id);
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
  }, [agentId, listed, path, version]);
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

/** Roughly how wide a label is at `size` px: CJK and full-width forms take a full em. */
function labelWidth(text: string, size = 13.5): number {
  let width = 0;
  for (const char of text) width += /[\u2E80-\uFFEF]/u.test(char) ? 1 : 0.563;
  return width * size;
}

/** A title's subject: the part before a colon, without its ordinal. */
function subject(title: string): string {
  return withoutOrdinal(title).split(/[：:]/)[0].trim() || withoutOrdinal(title);
}

/** `text` cut short with an ellipsis to fit `room`. */
function ellipsize(text: string, room: number, size: number): string {
  if (labelWidth(text, size) <= room) return text;
  let shown = "";
  for (const char of text) {
    if (labelWidth(`${shown}${char}…`, size) > room) break;
    shown += char;
  }
  return shown ? `${shown.trimEnd()}…` : "";
}

/** A course's name as its region can hold it, on one line. */
export function mapLabel(title: string, room: number): string {
  return ellipsize(subject(title), room, 13.5);
}

/**
 * Text broken into at most `max` lines of `room` width: CJK breaks between
 * any two characters, other words stay whole unless one alone is too wide.
 * The last line ends in an ellipsis when the text runs on.
 */
export function wrapLabel(text: string, room: number, max: number, size: number): string[] {
  const tokens = text.match(/[\u2E80-\uFFEF]|[^\s\u2E80-\uFFEF]+|\s+/gu) ?? [];
  const lines: string[] = [];
  let line = "";
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (labelWidth(line + token, size) <= room) { line += token; continue; }
    if (/^\s+$/.test(token)) { lines.push(line); line = ""; }
    else if (!line.trim() || labelWidth(token, size) > room) {
      // A word wider than a line breaks where it must.
      for (const char of token) {
        if (labelWidth(line + char, size) > room) { lines.push(line); line = ""; }
        line += char;
      }
    } else { lines.push(line); line = token; }
    if (lines.length >= max) {
      const rest = [lines.pop() ?? "", line, ...tokens.slice(i + 1)].join("");
      return [...lines, ellipsize(rest.trim(), room, size)].filter(Boolean);
    }
  }
  if (line.trim()) lines.push(line);
  return lines.map((value) => value.trim()).filter(Boolean).slice(0, max);
}

const LESSON_LINE = 1.3;

type PlotLabel = { course?: string; lines: string[]; size: number; x: number; y: number };

/**
 * A lesson's name as its plot holds it, broken over a few lines, a size
 * smaller rather than a word broken in two; the first plot of a course also
 * carries the course's name above it. Nothing when the plot is too small.
 */
function lessonLabel(plot: MapPlot, course?: string): PlotLabel | null {
  const [x, y] = plot.center;
  const ys = plot.shape.map((point) => point[1]);
  const tall = Math.max(...ys) - Math.min(...ys);
  const text = subject(plot.lesson.title);
  const longest = Math.max(0, ...(text.match(/[^\s\u2E80-\uFFEF]+/gu) ?? []).map((word) => labelWidth(word, 1)));
  for (const size of [12.5, 11.5, 10.5]) {
    const line = size * LESSON_LINE;
    const max = Math.min(3, Math.floor((tall * 0.62) / line) - (course ? 1 : 0));
    if (max < 1) return null;
    const half = ((max + (course ? 1 : 0)) * line) / 2;
    const room = Math.min(chordWidth(plot.shape, y - half), chordWidth(plot.shape, y), chordWidth(plot.shape, y + half)) * 0.8 - 6;
    if (room < 36) return null;
    if (longest * size > room && size > 10.5) continue;
    const lines = wrapLabel(text, room, max, size);
    if (!lines.length) return null;
    const heading = course ? ellipsize(course, room, size) : undefined;
    return { course: heading || undefined, lines, size, x, y };
  }
  return null;
}

const STATUS_LABEL = { mastered: "Read", learning: "Reading", untouched: "Not read yet" } as const;

function Plot({ plot, next, course, onOpen }: { plot: MapPlot; next: boolean; course?: string; onOpen: () => void }) {
  const { lesson, shape } = plot;
  const label = lessonLabel(plot, course);
  const rows = label ? [...(label.course ? [label.course] : []), ...label.lines] : [];
  const line = label ? label.size * LESSON_LINE : 0;
  return <g className="learning-map__plot" data-status={lesson.status} data-next={next || undefined} role="button" tabIndex={0}
    aria-label={`${lesson.title}, ${STATUS_LABEL[lesson.status]}`} onClick={onOpen}
    onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onOpen(); } }}>
    <title>{`${lesson.title} · ${STATUS_LABEL[lesson.status]}`}</title>
    <path d={roundedPath(shape, 18)} className="learning-map__ground" />
    {next ? contours(shape).map((ring, index) => <path key={index} d={roundedPath(ring, Math.max(3, 16 - index * 1.5))} className="learning-map__contour" />) : null}
    {label ? <text className="learning-map__name" fontSize={label.size} x={label.x} y={label.y - (rows.length * line) / 2 + line * 0.75}>
      {rows.map((row, index) => <tspan key={index} x={label.x} dy={index ? line : 0}
        className={label.course && index === 0 ? "learning-map__course" : undefined}>{row}</tspan>)}
    </text> : null}
  </g>;
}

/**
 * The reader before anything is open: the mentor's courses as a map. Each
 * lesson is a plot named in place: ink once read, grey while being read,
 * pale stone until then, and the one to go on with drawn in contour lines; a course the path names but nobody wrote yet is only an
 * outline. A plot opens its lesson.
 */
export function LearningMap({ agent, courses: listed, onOpen }: { agent: Agent; courses: readonly CourseSummary[] | undefined; onOpen: (page: MentorPage) => void }) {
  const { courses, next, loaded, title } = useMapCourses(agent.id, listed);
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
          ? <g key={region.course.id} role="img" aria-label={`${region.course.title}, not written yet`}>
            <title>{`${region.course.title} · not written yet`}</title>
            <path d={roundedPath(region.shape, 18)} className="learning-map__planned" />
            <text className="learning-map__name" x={region.center[0]} y={region.center[1] + 4}>{mapLabel(region.course.title, (Math.max(...region.shape.map((p) => p[0])) - Math.min(...region.shape.map((p) => p[0]))) * 0.8)}</text>
          </g>
          : <g key={region.course.id}>{region.plots.map((plot) => <Plot key={plot.lesson.id} plot={plot}
            course={single || plot.index ? undefined : subject(region.course.title)}
            next={next?.courseId === region.course.id && next.lessonId === plot.lesson.id}
            onOpen={() => onOpenLesson(region.course, plot.lesson.id)} />)}</g>)}
      </svg> : null}
    </div>
    <footer className="learning-map__legend" aria-hidden>
      <span data-status="next">Up next</span><span data-status="mastered">Read</span><span data-status="learning">Reading</span><span data-status="untouched">Not yet</span><span data-status="planned">To be written</span>
    </footer>
  </section>;
}
