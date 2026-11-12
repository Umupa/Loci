import { lessonPlanned, type CourseWithProgress } from "../../learning/model/course";

/**
 * A lesson as the tree draws its leaf: read (ink), reading (grey), written and
 * not read (pale stone) or only planned (a dashed outline).
 */
export type TreeLessonState = "read" | "reading" | "unread" | "planned";
export type TreeLesson = { id: string; title: string; state: TreeLessonState };
export type TreeChapter = { key: string; title: string; lessons: TreeLesson[]; parents: number[] };
export type TreeCourse = { id: string; title: string; chapters: TreeChapter[] };

/**
 * A course's chapters as the tree reads them: each stands on the chapters its
 * `after` names, or on the one before it when it names none; the first stands
 * on the ground.
 */
export function treeCourse(course: Pick<CourseWithProgress, "id" | "title" | "data" | "progress" | "bodies">): TreeCourse {
  const chapters = course.data.chapters;
  const index = new Map(chapters.flatMap((chapter, at) => chapter.id ? [[chapter.id, at] as const] : []));
  return {
    id: course.id, title: course.title,
    chapters: chapters.map((chapter, at) => ({
      key: chapter.id ?? String(at),
      title: chapter.title,
      parents: chapter.after !== undefined
        ? chapter.after.map((id) => index.get(id)).filter((parent): parent is number => parent !== undefined && parent < at)
        : at > 0 ? [at - 1] : [],
      lessons: chapter.lessons.map((lesson) => {
        const status = course.progress.get(lesson.id);
        return {
          id: lesson.id, title: lesson.title,
          state: lessonPlanned(course, lesson) ? "planned" : status === "mastered" ? "read" : status === "learning" ? "reading" : "unread",
        };
      }),
    })),
  };
}

/** Whether anything in these courses has been written to read yet. */
export function anythingWritten(courses: readonly TreeCourse[]): boolean {
  return courses.some((course) => course.chapters.some((chapter) => chapter.lessons.some((lesson) => lesson.state !== "planned")));
}

export type Point = [number, number];
/** A leaf: a lens along its bough, turned by `angle` degrees about its centre. */
export type TreeLeaf = TreeLesson & { cx: number; cy: number; angle: number; next: boolean };
/** A stroke of wood: a sampled curve, inked, pale or dashed. */
export type TreeLimb = { d: string; tone: "ink" | "pale" | "dash"; width: number };
export type TreeLabel = { key: string; title: string; x: number; y: number; anchor: "start" | "middle" | "end"; written: boolean };
export type InkTree = {
  course: TreeCourse;
  /** The drawing's box, in its own units. */
  box: { x: number; y: number; width: number; height: number };
  ground: number;
  /** The trunk's outline: all of it pale, and inked up to the highest chapter being read. */
  trunk: { pale: string; ink?: string };
  rings: { cx: number; cy: number; rx: number; ry: number }[];
  limbs: TreeLimb[];
  leaves: TreeLeaf[];
  labels: TreeLabel[];
  /** Where the course's name goes, under the ground. */
  foot: Point;
};

/** A leaf's lens at `k` of its size: two curves meeting at its tips. */
export function leafPath({ cx, cy }: { cx: number; cy: number }, k = 1): string {
  const w = 110, h = 26;
  const f = (value: number) => value.toFixed(1);
  return `M${f(cx - (w / 2) * k)} ${f(cy)}C${f(cx - w * 0.22 * k)} ${f(cy - h * k)},${f(cx + w * 0.22 * k)} ${f(cy - h * k)},${f(cx + (w / 2) * k)} ${f(cy)}`
    + `C${f(cx + w * 0.22 * k)} ${f(cy + h * k)},${f(cx - w * 0.22 * k)} ${f(cy + h * k)},${f(cx - (w / 2) * k)} ${f(cy)}Z`;
}

/** The rings a leaf to go on with wears inside it, as fractions of its size. */
export const LEAF_RINGS = [0.82, 0.67, 0.52, 0.37];

const GROUND = 0;
const CX = 0;
/** The trunk's sway at a height. */
const trunkX = (y: number) => CX + 11 * Math.sin((GROUND - y) / 85);

/** A small seeded random, so a course draws the same tree every time. */
function seeded(text: string): () => number {
  let seed = 7;
  for (const char of text) seed = (seed * 31 + char.charCodeAt(0)) % 2147483647 || 7;
  return () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 - 0.5; };
}

function sampled(point: (t: number) => Point, from: number, to: number): string {
  let d = "";
  for (let t = from; t <= to + 0.001; t += 0.02) {
    const [x, y] = point(Math.min(t, to));
    d += `${d ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`;
  }
  return d;
}

const lit = (lesson: TreeLesson) => lesson.state === "read" || lesson.state === "reading";

/**
 * A course drawn as one ink tree. The first chapter is the lowest bough and
 * each later one sits higher, left and right in turn; chapters that stand on
 * the same chapters fork from one height to either side; the last chapter is
 * the crown. A bough grows with its lessons, each a leaf along it, the last
 * at its tip. Wood is inked as far as reading has reached.
 */
/** The steepest a leaf leans, either way: its name is read without tilting the head. */
export const LEAF_TILT_MAX = 35;

/** A leaf's turn, kept upright and within the lean a name can be read at. */
export function leafAngle(angle: number): number {
  let upright = ((((angle + 90) % 180) + 180) % 180) - 90;
  if (upright === -90) upright = 90;
  return Math.max(-LEAF_TILT_MAX, Math.min(LEAF_TILT_MAX, upright));
}

/**
 * The tree for the room it has: `aspect` is the room's width over its height.
 * A tree shorter than the room asks for grows taller between its boughs (up
 * to three times), so it fills the height without being stretched; a wider
 * room than that leaves it centred.
 */
export function inkTree(course: TreeCourse, next?: string, aspect?: number): InkTree {
  const natural = drawTree(course, next, 1);
  if (!aspect || !Number.isFinite(aspect) || aspect <= 0) return natural;
  const wanted = natural.box.width / aspect;
  if (wanted <= natural.box.height) return natural;
  // Height grows linearly with the gaps between boughs: one more draw at the scale that reaches it.
  const taller = drawTree(course, next, 2);
  const perUnit = taller.box.height - natural.box.height;
  if (perUnit <= 0) return natural;
  const scale = Math.min(3, 1 + (wanted - natural.box.height) / perUnit);
  return drawTree(course, next, scale);
}

function drawTree(course: TreeCourse, next: string | undefined, stretch: number): InkTree {
  const rnd = seeded(course.id);
  const chapters = course.chapters;
  const crown = chapters.length > 1 ? chapters.length - 1 : -1;
  // Tiers of boughs: one chapter, or two that stand on the same chapters.
  const tiers: number[][] = [];
  chapters.forEach((chapter, at) => {
    if (at === crown) return;
    const last = tiers[tiers.length - 1];
    const same = last?.length === 1 && chapters[last[0]].parents.join() === chapter.parents.join() && chapter.parents.length > 0;
    if (same) last.push(at); else tiers.push([at]);
  });
  const heights: number[] = [];
  const sides: number[] = [];
  let y = GROUND - 86 * stretch;
  let side = 1;
  tiers.forEach((tier, at) => {
    if (at) {
      const below = Math.max(...tiers[at - 1].map((index) => Math.min(chapters[index].lessons.length, 8)));
      y -= Math.max(102, 70 + below * 12) * stretch;
    }
    if (tier.length === 2) { heights[tier[0]] = heights[tier[1]] = y; sides[tier[0]] = -1; sides[tier[1]] = 1; side = -1; }
    else { heights[tier[0]] = y; sides[tier[0]] = side; side = -side; }
  });
  const top = tiers.length ? y - (crown >= 0 ? 150 : 110) * stretch : GROUND - 200 * stretch;

  const limbs: TreeLimb[] = [];
  const leaves: TreeLeaf[] = [];
  const labels: TreeLabel[] = [];
  let reach = 0;
  const leaf = (lesson: TreeLesson, cx: number, cy: number, angle: number) => leaves.push({ ...lesson, cx, cy, angle: leafAngle(angle), next: lesson.id === next });

  chapters.forEach((chapter, at) => {
    if (at === crown) return;
    const y0 = heights[at], d = sides[at];
    const x0 = trunkX(y0) + d * 6;
    const n = chapter.lessons.length;
    const length = 80 + Math.min(n, 9) * 60;
    const x2 = x0 + d * length, y2 = y0 - 50 - Math.min(n, 9) * 15;
    const cx = x0 + d * length * 0.55, cy = y0 - 6;
    const point = (t: number): Point => [(1 - t) * (1 - t) * x0 + 2 * t * (1 - t) * cx + t * t * x2, (1 - t) * (1 - t) * y0 + 2 * t * (1 - t) * cy + t * t * y2];
    const read = chapter.lessons.filter(lit).length;
    const written = chapter.lessons.some((lesson) => lesson.state !== "planned");
    limbs.push({ d: sampled(point, 0, 1), tone: written ? "pale" : "dash", width: written ? 3 : 1.2 });
    if (read) {
      limbs.push({ d: sampled(point, 0, 0.2 + (0.8 * read) / n), tone: "ink", width: 4.5 });
      reach = Math.min(reach, y0);
    }
    const slope = (Math.atan2(y2 - cy, x2 - cx) * 180) / Math.PI;
    chapter.lessons.forEach((lesson, index) => {
      const tip = index === n - 1;
      const [px, py] = point(tip ? 1 : 0.2 + (0.8 * (index + 0.5)) / n);
      const angle = (d > 0 ? slope : slope + 180) + rnd() * 8;
      if (tip) { leaf(lesson, px + d * 56, py - 22, angle - d * 4); return; }
      const up = index % 2 ? 1 : -1;
      const lx = px + d * 8;
      limbs.push({ d: `M${px.toFixed(1)} ${py.toFixed(1)}L${lx.toFixed(1)} ${(py + up * 12).toFixed(1)}`, tone: lesson.state === "planned" ? "dash" : "pale", width: 1.2 });
      leaf(lesson, lx, py + up * 33, angle * 0.5);
    });
    labels.push({ key: chapter.key, title: chapter.title, x: x0 + d * 18, y: y0 + 26, anchor: d > 0 ? "start" : "end", written });
  });

  if (crown >= 0) {
    const chapter = chapters[crown];
    const n = chapter.lessons.length;
    const x = trunkX(top);
    const written = chapter.lessons.some((lesson) => lesson.state !== "planned");
    if (chapter.lessons.some(lit)) reach = top;
    chapter.lessons.forEach((lesson, index) => {
      // Fanned about the top: an odd one out stands straight up.
      const offset = index - (n - 1) / 2;
      const row = n > 4 && index % 2 ? 40 : 0;
      // The stem ends at the leaf's inner tip: a leaning leaf's end nearest the trunk, or a flat one's underside.
      const tipX = offset === 0 ? x : x + offset * 150 - Math.sign(offset) * 50, tipY = offset === 0 ? top - 50 - row : top - 48 - row;
      limbs.push({ d: `M${x.toFixed(1)} ${(top + 6).toFixed(1)}Q${(x + offset * 8).toFixed(1)} ${(top - 30).toFixed(1)},${tipX.toFixed(1)} ${tipY.toFixed(1)}`,
        tone: lesson.state === "planned" ? "dash" : lit(lesson) ? "ink" : "pale", width: lesson.state === "planned" ? 1.2 : 2 });
      // One straight up lies flat on its stem; the others lean out to their side.
      leaf(lesson, x + offset * 150, top - (offset === 0 ? 64 : 70) - row, offset === 0 ? 0 : -24 * Math.sign(offset));
    });
    labels.push({ key: chapter.key, title: chapter.title, x, y: top - 118 - (n > 4 ? 40 : 0), anchor: "middle", written });
  }

  // The trunk: wide at the root, flaring into the ground, thin at the top.
  const outline = (from: number, to: number) => {
    let left = "", right = "";
    for (let at = from; at >= to; at -= 8) {
      const w = 3 + 15 * Math.pow((at - top) / (GROUND - top), 1.25) + (at > GROUND - 30 ? (at - (GROUND - 30)) * 0.55 : 0);
      left += `${left ? "L" : "M"}${(trunkX(at) - w).toFixed(1)} ${at}`;
      right = ` L${(trunkX(at) + w).toFixed(1)} ${at}${right}`;
    }
    return `${left}${right}Z`;
  };
  const rings = [0, 1, 2, 3].map((k) => ({ cx: CX, cy: GROUND + 4, rx: 70 + k * 46, ry: 5 + k * 4.5 }));

  // Its box: every leaf (half a leaf's length around its centre), label and ring.
  const xs = [...leaves.flatMap((entry) => [entry.cx - 60, entry.cx + 60]), ...labels.map((label) => label.x + (label.anchor === "end" ? -160 : label.anchor === "start" ? 160 : 0)), CX - 210, CX + 210];
  const minY = Math.min(...leaves.map((entry) => entry.cy - 60), ...labels.map((label) => label.y - 20), top - 20);
  const half = Math.max(...xs.map((value) => Math.abs(value - CX))) + 24;
  const maxY = GROUND + 52;
  return {
    course, ground: GROUND,
    box: { x: CX - half, y: minY - 12, width: half * 2, height: maxY - minY + 12 },
    trunk: { pale: outline(GROUND, top), ...(reach < 0 ? { ink: outline(GROUND, reach) } : {}) },
    rings, limbs, leaves, labels, foot: [CX, GROUND + 44],
  };
}
