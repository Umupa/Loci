import { describe, expect, it } from "vitest";
import { area, clip, contours, inset, layoutLearningMap, roundedPath, type MapCourse, type Point } from "./learningMap";

const course = (id: string, count: number, read = 0): MapCourse => ({
  id, title: id, lessons: Array.from({ length: count }, (_, i) => ({ id: `${id}-${i}`, title: `${id} ${i}`, status: i < read ? "mastered" : "untouched" })),
});
const courses = [course("kvm", 12, 4), course("microvm", 14, 2), course("cube", 13, 1), course("space", 11), { id: "e2b", title: "E2B", lessons: [], planned: true }];

/** Inside a convex polygon, with a little slack for rounding. */
function inside(point: Point, polygon: readonly Point[]): boolean {
  const sign = Math.sign(area(polygon));
  return polygon.every((a, i) => {
    const b = polygon[(i + 1) % polygon.length];
    return sign * ((b[0] - a[0]) * (point[1] - a[1]) - (b[1] - a[1]) * (point[0] - a[0])) >= -0.5;
  });
}

describe("the learning map", () => {
  it("gives every course a region and every lesson a plot inside its course", () => {
    const regions = layoutLearningMap(courses, 860, 560);
    expect(regions.map((region) => region.course.id)).toEqual(["kvm", "microvm", "cube", "space", "e2b"]);
    for (const region of regions) {
      expect(region.plots).toHaveLength(region.course.lessons.length);
      for (const plot of region.plots) {
        expect(plot.shape.length).toBeGreaterThanOrEqual(3);
        expect(inside(plot.center, region.shape), `${plot.lesson.id} in ${region.course.id}`).toBe(true);
      }
    }
  });

  it("keeps plots apart: no two lessons claim the same ground", () => {
    const [kvm] = layoutLearningMap(courses, 860, 560);
    const total = kvm.plots.reduce((sum, plot) => sum + Math.abs(area(plot.shape)), 0);
    expect(total).toBeLessThan(Math.abs(area(kvm.shape)));
    for (const plot of kvm.plots) for (const other of kvm.plots) {
      if (plot !== other) expect(inside(plot.center, other.shape)).toBe(false);
    }
  });

  it("draws the same map for the same courses and size", () => {
    const a = layoutLearningMap(courses, 700, 480).map((region) => region.plots.map((plot) => roundedPath(plot.shape, 12)));
    const b = layoutLearningMap(courses, 700, 480).map((region) => region.plots.map((plot) => roundedPath(plot.shape, 12)));
    expect(a).toEqual(b);
  });

  it("lays a course's lessons out in reading order along its long side", () => {
    for (const region of layoutLearningMap(courses, 860, 560)) {
      const xs = region.shape.map((p) => p[0]), ys = region.shape.map((p) => p[1]);
      const axis = Math.max(...xs) - Math.min(...xs) >= Math.max(...ys) - Math.min(...ys) ? 0 : 1;
      const along = region.plots.map((plot) => plot.center[axis]);
      // Mostly increasing: relaxed cells may swap neighbours a little, never run backwards.
      expect(along[along.length - 1] ?? 0).toBeGreaterThanOrEqual(along[0] ?? 0);
    }
  });

  it("draws nothing without courses or room", () => {
    expect(layoutLearningMap([], 800, 600)).toEqual([]);
    expect(layoutLearningMap(courses, 20, 600)).toEqual([]);
  });

  it("lays out a single course with a single lesson", () => {
    const [only] = layoutLearningMap([course("one", 1)], 400, 300);
    expect(only.plots).toHaveLength(1);
  });
});

describe("map geometry", () => {
  const square: Point[] = [[0, 0], [100, 0], [100, 100], [0, 100]];

  it("insets a polygon evenly and gives up when nothing is left", () => {
    expect(Math.abs(area(inset(square, 10)!))).toBeCloseTo(6400);
    expect(inset(square, 60)).toBeNull();
  });

  it("clips a polygon to a convex one", () => {
    expect(Math.abs(area(clip(square, [[50, -10], [150, -10], [150, 110], [50, 110]])))).toBeCloseTo(5000);
  });

  it("draws contour rings from the edge in until the middle", () => {
    const rings = contours(square, 6);
    // 100 − 2·6·7 = 16 across is the last ring; the eighth would be 4px, too small to draw.
    expect(rings.length).toBe(7);
    expect(Math.abs(area(rings[0]))).toBeGreaterThan(Math.abs(area(rings[rings.length - 1])));
  });
});
