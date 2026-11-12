import { useEffect, useMemo, useState } from "react";
import { agentLook, type Agent } from "../../agents/model/agent";
import { COURSES_CHANGED_EVENT, loadCourse, PROGRESS_EVENT, type CourseChangedDetail, type CourseSummary, type CourseWithProgress, type ProgressDetail } from "../../learning/model/course";
import { requestChapter } from "../../learning/model/chapterRequest";
import type { Block } from "../../sessions/model/session";
import { turnActivity } from "../../sessions/model/turnProgress";
import { ActivitySpinner } from "../../sessions/ui/ActivitySpinner";
import { anythingWritten, inkTree, LEAF_RINGS, leafPath, treeCourse, type InkTree, type TreeLeaf } from "../model/knowledgeTree";
import { nextLesson, withoutOrdinal } from "../model/libraryCourse";
import type { MentorPage } from "../model/mentorPage";
import { courseOrder } from "./LibraryCourses";
import "./KnowledgeTree.css";

/**
 * Every course of the mentor, read in full, in the order they were written;
 * read again when a course changes, and kept current as lessons are read.
 * `listed` is the workspace's listing, undefined until it is read.
 */
function useCourses(agentId: string, listed: readonly CourseSummary[] | undefined): CourseWithProgress[] | undefined {
  const [state, setState] = useState<{ key: string; courses: CourseWithProgress[] }>();
  const [version, setVersion] = useState(0);
  useEffect(() => {
    const changed = (event: Event) => { if ((event as CustomEvent<CourseChangedDetail>).detail?.agentId === agentId) setVersion((value) => value + 1); };
    const progressed = (event: Event) => {
      const detail = (event as CustomEvent<ProgressDetail>).detail;
      if (detail?.agentId !== agentId) return;
      setState((current) => current && {
        ...current,
        courses: current.courses.map((course) => course.id !== detail.courseId ? course : { ...course, progress: new Map(course.progress).set(detail.itemId, detail.status) }),
      });
    };
    window.addEventListener(COURSES_CHANGED_EVENT, changed);
    window.addEventListener(PROGRESS_EVENT, progressed);
    return () => { window.removeEventListener(COURSES_CHANGED_EVENT, changed); window.removeEventListener(PROGRESS_EVENT, progressed); };
  }, [agentId]);
  const ids = listed ? courseOrder(listed).map((course) => course.id) : undefined;
  const key = ids ? `${agentId}\0${version}\0${ids.join("\0")}` : undefined;
  useEffect(() => {
    if (!key || !ids) return;
    let live = true;
    void Promise.all(ids.map((id) => loadCourse(id, agentId).catch(() => null))).then((loaded) => {
      if (live) setState({ key, courses: loaded.filter((course): course is CourseWithProgress => !!course && course.data.engine === "reading") });
    });
    return () => { live = false; };
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!state) return undefined;
  // A late answer for another mentor is not this one's.
  return state.key.startsWith(`${agentId}\0`) ? state.courses : undefined;
}

/** The size of an element, in whole tens so a pixel of resize does not redraw the tree. */
function useRoom(element: HTMLElement | null): { width: number; height: number } {
  const [room, setRoom] = useState({ width: 0, height: 0 });
  useEffect(() => {
    if (!element) return;
    const measure = () => {
      const width = Math.round(element.clientWidth / 10) * 10, height = Math.round(element.clientHeight / 10) * 10;
      setRoom((current) => current.width === width && current.height === height ? current : { width, height });
    };
    measure();
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(measure);
    observer?.observe(element);
    return () => observer?.disconnect();
  }, [element]);
  return room;
}

/** Roughly how wide a label is at `size` px: CJK and full-width forms take a full em. */
function labelWidth(text: string, size: number): number {
  let width = 0;
  for (const char of text) width += /[⺀-￯]/u.test(char) ? 1 : 0.56;
  return width * size;
}

/** `text` cut short with an ellipsis to fit `room` at `size` px. */
export function fitLabel(text: string, room: number, size = 12): string {
  if (labelWidth(text, size) <= room) return text;
  let shown = "";
  for (const char of text) {
    if (labelWidth(`${shown}${char}…`, size) > room) break;
    shown += char;
  }
  return `${shown.trimEnd()}…`;
}

const STATE_LABEL = { read: "Read", reading: "Reading", unread: "Not read yet", planned: "Planned" } as const;

type Props = {
  agent: Agent;
  courses: readonly CourseSummary[] | undefined;
  onOpen: (page: MentorPage) => void;
  /** The mentor's conversation while a turn runs, for what it is doing before anything is written. */
  turn?: readonly Block[];
};

/**
 * The reader before anything is open: each course as an ink tree. The first
 * chapter is the lowest bough and later ones sit higher; chapters that stand
 * on the same chapter fork from one height; the last is the crown. Each lesson
 * is a leaf: ink once read, grey while being read, pale stone until then, a
 * dashed outline while only planned, and the one to go on with ringed. Wood
 * is inked as far as reading has reached. A leaf opens its lesson; a planned
 * one asks for its chapter. Before anything is written, it shows what the
 * mentor is doing instead.
 */
export function KnowledgeTree({ agent, courses: listed, onOpen, turn }: Props) {
  const courses = useCourses(agent.id, listed);
  const next = useMemo(() => {
    for (const course of courses ?? []) {
      const found = nextLesson(course);
      if (found) return { courseId: course.id, lessonId: found.id };
    }
    return undefined;
  }, [courses]);
  // Each tree is drawn for its share of the room, so it fills the height.
  const [forest, setForest] = useState<HTMLDivElement | null>(null);
  const room = useRoom(forest);
  const count = Math.max(1, courses?.length ?? 1);
  const aspect = room.width && room.height ? (room.width - (count - 1) * 12) / count / room.height : undefined;
  const trees = useMemo(() => (courses ?? []).map((course) => ({ course, tree: inkTree(treeCourse(course), next?.courseId === course.id ? next.lessonId : undefined, aspect) })), [courses, next, aspect]);
  const written = anythingWritten(trees.map((entry) => entry.tree.course));
  if (turn && !written) return <FirstTurn agent={agent} blocks={turn} />;
  if (!courses) return <div className="mentor-reader-empty" data-tauri-drag-region="deep" />;
  if (!trees.length) return <div className="mentor-reader-empty" data-tauri-drag-region="deep"><p>Ask {agentLook(agent).name} for a course.</p></div>;
  const pick = (course: CourseWithProgress, lesson: TreeLeaf) => {
    if (lesson.state === "planned") { requestChapter(agent.id, course, lesson.id); return; }
    onOpen({ kind: "course", course: { courseId: course.id, agentId: agent.id, title: course.title, itemId: lesson.id } });
  };
  const leaves = trees.flatMap((entry) => entry.tree.leaves);
  const read = leaves.filter((leaf) => leaf.state === "read").length;
  const single = trees.length === 1;
  return <section className="knowledge-tree" aria-label="Knowledge tree" data-knowledge-tree>
    <header className="knowledge-tree__head">
      <p className="knowledge-tree__count" aria-label={`${read} of ${leaves.length} lessons read`}>{read}<small>/ {leaves.length}</small></p>
      {single ? <h2 className="knowledge-tree__heading">{withoutOrdinal(trees[0].course.title)}</h2> : null}
    </header>
    <div ref={setForest} className="knowledge-tree__forest">
      {trees.map(({ course, tree }) => <Tree key={course.id} tree={tree} titled={!single} onPick={(lesson) => pick(course, lesson)} />)}
    </div>
  </section>;
}

export function Tree({ tree, titled, onPick }: { tree: InkTree; titled: boolean; onPick: (lesson: TreeLeaf) => void }) {
  const { box } = tree;
  return <figure className="knowledge-tree__course" data-tree-course={tree.course.id}>
    <svg viewBox={`${box.x.toFixed(0)} ${box.y.toFixed(0)} ${box.width.toFixed(0)} ${box.height.toFixed(0)}`} className="knowledge-tree__svg"
      role="group" aria-label={withoutOrdinal(tree.course.title)} preserveAspectRatio="xMidYMax meet">
      {tree.rings.map((ring, index) => <ellipse key={index} {...ring} className="knowledge-tree__ring" />)}
      <path d={tree.trunk.pale} className="knowledge-tree__wood" data-tone="pale" />
      {tree.trunk.ink ? <path d={tree.trunk.ink} className="knowledge-tree__wood" /> : null}
      {tree.limbs.map((limb, index) => <path key={index} d={limb.d} className="knowledge-tree__limb" data-tone={limb.tone} strokeWidth={limb.width} />)}
      {tree.labels.map((label) => <text key={label.key} x={label.x} y={label.y} textAnchor={label.anchor} className="knowledge-tree__chapter" data-tree-chapter={label.key}
        data-planned={label.written ? undefined : ""}><title>{label.title}</title>{fitLabel(withoutOrdinal(label.title), 170, 12.5)}</text>)}
      {tree.leaves.map((leaf) => <g key={leaf.id} className="knowledge-tree__leaf" data-tree-lesson={leaf.id} data-state={leaf.state} data-current={leaf.next || undefined}
        transform={`rotate(${leaf.angle.toFixed(1)} ${leaf.cx.toFixed(1)} ${leaf.cy.toFixed(1)})`}
        role="button" tabIndex={0} aria-label={`${leaf.title}, ${leaf.next ? "Up next" : STATE_LABEL[leaf.state]}`}
        onClick={() => onPick(leaf)} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onPick(leaf); } }}>
        <title>{leaf.title}</title>
        <path d={leafPath(leaf)} className="knowledge-tree__blade" />
        {leaf.next ? LEAF_RINGS.map((k) => <path key={k} d={leafPath(leaf, k)} className="knowledge-tree__vein" />) : null}
        <text x={leaf.cx} y={leaf.cy + 4} className="knowledge-tree__name">{fitLabel(leaf.title, 96, 12)}</text>
      </g>)}
      {titled ? <text x={tree.foot[0]} y={tree.foot[1]} textAnchor="middle" className="knowledge-tree__title">{fitLabel(withoutOrdinal(tree.course.title), 380, 13)}</text> : null}
    </svg>
  </figure>;
}

/**
 * The mentor's first turn, before a lesson exists: what it has found and what
 * it is writing, newest first, from the same lines its conversation shows.
 */
function FirstTurn({ agent, blocks }: { agent: Agent; blocks: readonly Block[] }) {
  const entries = useMemo(() => turnActivity(blocks), [blocks]);
  const [newest, ...rest] = entries;
  return <section className="knowledge-tree__first" aria-label={`What ${agentLook(agent).name} is doing`} aria-live="polite" data-first-turn>
    <p className="knowledge-tree__now">
      <ActivitySpinner className="knowledge-tree__spinner" />
      <span>{newest?.text ?? `${agentLook(agent).name} is starting…`}</span>
    </p>
    {rest.length ? <ol className="knowledge-tree__log">
      {rest.map((entry) => <li key={entry.id} data-activity-kind={entry.kind} data-status={entry.status}>{entry.text}</li>)}
    </ol> : null}
  </section>;
}
