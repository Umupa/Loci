import { Delaunay } from "d3-delaunay";
import type { LearningStatus } from "../../learning/model/course";

/*
 * The learning map: a mentor's courses as regions of one page, each split
 * into a plot per lesson. Loci is the method of loci, things kept in places,
 * so the courses are the ground and reading one inks its plots. The layout
 * is a pure function of the courses and the size, the same every time.
 */

export type Point = readonly [number, number];
export type Polygon = Point[];

export type MapLesson = { id: string; title: string; status: LearningStatus };
/** A course, or one the path names before it is written (`lessons` empty, `planned`). */
export type MapCourse = { id: string; title: string; lessons: MapLesson[]; planned?: boolean };

export type MapPlot = { courseId: string; lesson: MapLesson; index: number; shape: Polygon; center: Point };
export type MapRegion = { course: MapCourse; shape: Polygon; center: Point; plots: MapPlot[] };

/** Space between courses, and between the lessons of one. */
const COURSE_GAP = 10;
const LESSON_GAP = 3;
const RELAX_ROUNDS = 6;

export function area(polygon: readonly Point[]): number {
  let sum = 0;
  for (let i = 0; i < polygon.length; i++) {
    const [x0, y0] = polygon[i];
    const [x1, y1] = polygon[(i + 1) % polygon.length];
    sum += x0 * y1 - x1 * y0;
  }
  return sum / 2;
}

export function centroid(polygon: readonly Point[]): Point {
  let x = 0, y = 0, a = 0;
  for (let i = 0; i < polygon.length; i++) {
    const [x0, y0] = polygon[i];
    const [x1, y1] = polygon[(i + 1) % polygon.length];
    const f = x0 * y1 - x1 * y0;
    a += f; x += (x0 + x1) * f; y += (y0 + y1) * f;
  }
  if (Math.abs(a) < 1e-9) return polygon[0] ?? [0, 0];
  return [x / (3 * a), y / (3 * a)];
}

/** Sutherland–Hodgman: `subject` inside the convex `clipper`. */
export function clip(subject: readonly Point[], clipper: readonly Point[]): Polygon {
  let out: Polygon = [...subject];
  const sign = Math.sign(area(clipper)) || 1;
  for (let i = 0; i < clipper.length && out.length; i++) {
    const a = clipper[i], b = clipper[(i + 1) % clipper.length];
    const inside = (p: Point) => sign * ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])) >= 0;
    const cross = (p: Point, q: Point): Point => {
      const a1 = b[1] - a[1], b1 = a[0] - b[0], c1 = a1 * a[0] + b1 * a[1];
      const a2 = q[1] - p[1], b2 = p[0] - q[0], c2 = a2 * p[0] + b2 * p[1];
      const d = a1 * b2 - a2 * b1;
      return [(b2 * c1 - b1 * c2) / d, (a1 * c2 - a2 * c1) / d];
    };
    const input = out;
    out = [];
    for (let j = 0; j < input.length; j++) {
      const p = input[j], q = input[(j + 1) % input.length];
      if (inside(q)) { if (!inside(p)) out.push(cross(p, q)); out.push(q); }
      else if (inside(p)) out.push(cross(p, q));
    }
  }
  return out;
}

/**
 * A convex polygon moved in by `d` on every edge, or null when nothing is
 * left: the polygon cut by each edge's line shifted inward. Short edges at
 * sharp corners simply drop out, as they should.
 */
export function inset(polygon: readonly Point[], d: number): Polygon | null {
  const n = polygon.length;
  if (n < 3) return null;
  const sign = Math.sign(area(polygon)) || 1;
  let out: Polygon = [...polygon];
  for (let i = 0; i < n && out.length >= 3; i++) {
    const a = polygon[i], b = polygon[(i + 1) % n];
    const length = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (length < 1e-9) continue;
    // Inward unit normal, and how far inside the shifted edge a point is.
    const nx = (-(b[1] - a[1]) / length) * sign, ny = ((b[0] - a[0]) / length) * sign;
    const depth = (p: Point) => (p[0] - a[0]) * nx + (p[1] - a[1]) * ny - d;
    const input = out;
    out = [];
    for (let j = 0; j < input.length; j++) {
      const p = input[j], q = input[(j + 1) % input.length];
      const dp = depth(p), dq = depth(q);
      if (dp >= 0) out.push(p);
      if ((dp >= 0) !== (dq >= 0)) {
        const t = dp / (dp - dq);
        out.push([p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]);
      }
    }
  }
  return out.length >= 3 && Math.abs(area(out)) > 24 ? out : null;
}

/** An SVG path for the polygon with every corner rounded by up to `r`. */
export function roundedPath(polygon: readonly Point[], r: number): string {
  const n = polygon.length;
  let d = "";
  const f = (v: number) => v.toFixed(1);
  for (let i = 0; i < n; i++) {
    const a = polygon[(i - 1 + n) % n], b = polygon[i], c = polygon[(i + 1) % n];
    const l1 = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, l2 = Math.hypot(c[0] - b[0], c[1] - b[1]) || 1;
    const r1 = Math.min(r, l1 / 2) / l1, r2 = Math.min(r, l2 / 2) / l2;
    const start = [b[0] + (a[0] - b[0]) * r1, b[1] + (a[1] - b[1]) * r1];
    const end = [b[0] + (c[0] - b[0]) * r2, b[1] + (c[1] - b[1]) * r2];
    d += `${i ? "L" : "M"}${f(start[0])},${f(start[1])}Q${f(b[0])},${f(b[1])} ${f(end[0])},${f(end[1])}`;
  }
  return `${d}Z`;
}

/** A small deterministic generator, seeded by the courses, so a map keeps its shape. */
function random(seed: string): () => number {
  let state = 2166136261;
  for (let i = 0; i < seed.length; i++) state = Math.imul(state ^ seed.charCodeAt(i), 16777619) >>> 0;
  state = state % 2147483646 + 1;
  return () => (state = (state * 16807) % 2147483647) / 2147483647;
}

type Box = readonly [number, number, number, number];

/** Moves each point to the middle of its cell, within `within` when given, so cells come out even. */
function relax(points: [number, number][], box: Box, within: readonly Point[] | null, rounds: number) {
  for (let round = 0; round < rounds; round++) {
    const voronoi = Delaunay.from(points).voronoi([...box]);
    points.forEach((point, i) => {
      const raw = voronoi.cellPolygon(i);
      if (!raw) return;
      const cell = within ? clip(raw.slice(0, -1) as Point[], within) : (raw.slice(0, -1) as Point[]);
      if (cell.length < 3) return;
      const [x, y] = centroid(cell);
      point[0] = x; point[1] = y;
    });
  }
}

/** Cells of `points` inside the box, as open polygons (Voronoi needs at least one point). */
function cells(points: readonly (readonly [number, number])[], box: Box): Polygon[] {
  if (points.length === 1) return [[[box[0], box[1]], [box[2], box[1]], [box[2], box[3]], [box[0], box[3]]]];
  const voronoi = Delaunay.from(points as [number, number][]).voronoi([...box]);
  return points.map((_, i) => (voronoi.cellPolygon(i)?.slice(0, -1) ?? []) as Polygon);
}

/**
 * Lays the courses out over `width` × `height`: one region per course, in
 * path order from the top left, each cut into one plot per lesson. A lesson's
 * plots run in reading order along the region's long side.
 */
export function layoutLearningMap(courses: readonly MapCourse[], width: number, height: number): MapRegion[] {
  if (!courses.length || width < 40 || height < 40) return [];
  const next = random(courses.map((course) => `${course.id}:${course.lessons.length}`).join("|"));
  const box: Box = [0, 0, width, height];
  // Seeds in reading order along a gentle zigzag, then evened out.
  const columns = Math.max(1, Math.round(Math.sqrt((courses.length * width) / height)));
  const rows = Math.ceil(courses.length / columns);
  const seeds: [number, number][] = courses.map((_, i) => {
    const row = Math.floor(i / columns), column = row % 2 ? columns - 1 - (i % columns) : i % columns;
    return [((column + 0.5 + (next() - 0.5) * 0.5) / columns) * width, ((row + 0.5 + (next() - 0.5) * 0.5) / rows) * height];
  });
  relax(seeds, box, null, 2);
  const regionCells = cells(seeds, box);
  return courses.map((course, ci) => {
    const region = inset(regionCells[ci], COURSE_GAP / 2) ?? regionCells[ci];
    const xs = region.map((p) => p[0]), ys = region.map((p) => p[1]);
    const bounds: Box = [Math.min(...xs) - 1, Math.min(...ys) - 1, Math.max(...xs) + 1, Math.max(...ys) + 1];
    const count = Math.max(course.lessons.length, 1);
    const points: [number, number][] = [];
    for (let attempt = 0; points.length < count && attempt < count * 200; attempt++) {
      const p: [number, number] = [bounds[0] + next() * (bounds[2] - bounds[0]), bounds[1] + next() * (bounds[3] - bounds[1])];
      if (clip([p, [p[0] + 0.01, p[1]], [p[0], p[1] + 0.01]], region).length) points.push(p);
    }
    while (points.length < count) points.push([...centroid(region)] as [number, number]);
    relax(points, bounds, region, RELAX_ROUNDS);
    const horizontal = bounds[2] - bounds[0] >= bounds[3] - bounds[1];
    points.sort((a, b) => horizontal ? a[0] - b[0] || a[1] - b[1] : a[1] - b[1] || a[0] - b[0]);
    const lessonCells = cells(points, bounds);
    const plots = course.lessons.flatMap((lesson, index): MapPlot[] => {
      const cell = clip(lessonCells[index], region);
      const shape = cell.length >= 3 ? inset(cell, LESSON_GAP / 2) : null;
      return shape ? [{ courseId: course.id, lesson, index, shape, center: centroid(shape) }] : [];
    });
    return { course, shape: region, center: centroid(region), plots };
  });
}

/**
 * The ground a map takes: about a plot's worth per lesson (a course not
 * written yet counts as a few), never more than the room there is, in the
 * room's proportions. A mentor with one short course draws a small map, not
 * a few giant plots.
 */
export const PLOT_AREA = 24000;
export function mapSize(courses: readonly MapCourse[], width: number, height: number): { width: number; height: number } {
  const plots = courses.reduce((sum, course) => sum + (course.planned || !course.lessons.length ? 4 : course.lessons.length), 0);
  if (!plots || width <= 0 || height <= 0) return { width: 0, height: 0 };
  const scale = Math.min(1, Math.sqrt((plots * PLOT_AREA) / (width * height)));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

/** The rings drawn inside a plot being read, like contour lines, from the edge in: a few, not a fill. */
export function contours(shape: readonly Point[], step = 6, limit = 6): Polygon[] {
  const rings: Polygon[] = [];
  for (let k = 1; k <= limit; k++) {
    const ring = inset(shape, k * step);
    if (!ring) break;
    rings.push(ring);
  }
  return rings;
}
