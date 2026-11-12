import { describe, expect, it } from "vitest";
import type { CourseWithProgress } from "../../learning/model/course";
import { anythingWritten, inkTree, LEAF_TILT_MAX, leafAngle, treeCourse } from "./knowledgeTree";

const lesson = (id: string, document?: string) => ({ id, title: id.toUpperCase(), ...(document ? { document } : {}) });
const course = (chapters: CourseWithProgress["data"]["chapters"], bodies: string[] = [], read: string[] = []): CourseWithProgress => ({
  id: "k8s", agentId: "a", title: "Kubernetes", updatedAt: 1,
  data: { engine: "reading", chapters }, bodies: new Set(bodies), progress: new Map(read.map((id) => [id, "mastered" as const])),
});

describe("the knowledge tree", () => {
  it("tells read, reading, unread and planned lessons apart", () => {
    const base = course([{ title: "Base", lessons: [lesson("a"), lesson("b"), lesson("c", "spec")] }, { title: "Next", lessons: [lesson("d")] }], ["a", "b"], ["a"]);
    base.progress.set("b", "learning");
    const tree = treeCourse(base);
    expect(tree.chapters[0].lessons.map((entry) => entry.state)).toEqual(["read", "reading", "unread"]);
    expect(tree.chapters[1].lessons.map((entry) => entry.state)).toEqual(["planned"]);
    expect(anythingWritten([tree])).toBe(true);
    expect(anythingWritten([treeCourse(course([{ title: "Base", lessons: [lesson("a")] }]))])).toBe(false);
  });

  it("stands a chapter on the one before it unless it names others, and forks where two stand on one", () => {
    const tree = treeCourse(course([
      { id: "loop", title: "Control loop", lessons: [lesson("a")] },
      { title: "Pods", lessons: [lesson("b")] },
      { id: "net", title: "Networking", after: ["loop"], lessons: [lesson("c")] },
      { title: "Interview", after: ["net", "loop"], lessons: [lesson("d")] },
      { title: "Loose", after: [], lessons: [lesson("e")] },
    ]));
    expect(tree.chapters.map((chapter) => chapter.parents)).toEqual([[], [0], [0], [2, 0], []]);
    const drawn = inkTree(tree, "b");
    const leafOf = (id: string) => drawn.leaves.find((leaf) => leaf.id === id)!;
    // The first chapter is the lowest bough; Pods and Networking fork from one height to either side.
    const label = (title: string) => drawn.labels.find((entry) => entry.title === title)!;
    expect(label("Control loop").y).toBeGreaterThan(label("Pods").y);
    expect(label("Pods").y).toBe(label("Networking").y);
    expect(Math.sign(label("Pods").x)).not.toBe(Math.sign(label("Networking").x));
    // The last chapter is the crown, above every bough.
    expect(label("Loose").y).toBeLessThan(label("Interview").y);
    expect(leafOf("b").next).toBe(true);
    expect(drawn.leaves).toHaveLength(5);
  });

  it("inks the wood as far as reading has reached, and keeps every leaf in its box", () => {
    const many = Array.from({ length: 10 }, (_, at) => lesson(`l${at}`));
    const unread = inkTree(treeCourse(course([{ title: "Long", lessons: many }, { title: "Short", lessons: [lesson("z")] }], many.map((entry) => entry.id))));
    expect(unread.trunk.ink).toBeUndefined();
    expect(unread.limbs.some((limb) => limb.tone === "ink")).toBe(false);
    const begun = inkTree(treeCourse(course([{ title: "Long", lessons: many }, { title: "Short", lessons: [lesson("z")] }], many.map((entry) => entry.id), ["l0", "l1"])));
    expect(begun.trunk.ink).toBeDefined();
    expect(begun.limbs.filter((limb) => limb.tone === "ink")).toHaveLength(1);
    // A chapter with nothing written is a dashed bough.
    expect(begun.limbs.some((limb) => limb.tone === "dash")).toBe(true);
    const { box } = begun;
    for (const leaf of begun.leaves) {
      expect(leaf.cx).toBeGreaterThan(box.x);
      expect(leaf.cx).toBeLessThan(box.x + box.width);
      expect(leaf.cy).toBeGreaterThan(box.y);
      expect(leaf.cy).toBeLessThan(box.y + box.height);
    }
  });

  it("keeps every leaf upright and leaning at most 35 degrees, a lone crown leaf flat", () => {
    expect(leafAngle(90)).toBe(LEAF_TILT_MAX);
    expect(leafAngle(-150)).toBe(30);
    expect(leafAngle(200)).toBe(20);
    expect(leafAngle(-60)).toBe(-35);
    const small = inkTree(treeCourse(course([{ title: "Map", lessons: [lesson("a"), lesson("b")] }, { title: "Devices", lessons: [lesson("c")] }], ["a", "b"])));
    expect(small.leaves.find((leaf) => leaf.id === "c")?.angle).toBe(0);
    for (const leaf of small.leaves) expect(Math.abs(leaf.angle)).toBeLessThanOrEqual(LEAF_TILT_MAX);
  });

  it("grows taller between its boughs to fill a tall room, without changing its width", () => {
    const tree = treeCourse(course([{ title: "Map", lessons: [lesson("a"), lesson("b")] }, { title: "Devices", lessons: [lesson("c")] }], ["a", "b"]));
    const natural = inkTree(tree);
    const tall = inkTree(tree, undefined, 1);
    expect(Math.abs(tall.box.width - natural.box.width)).toBeLessThan(natural.box.width * 0.02);
    expect(tall.box.height).toBeGreaterThan(natural.box.height);
    // As tall as the room asks for: width over height is the room's.
    expect(tall.box.width / tall.box.height).toBeCloseTo(1, 1);
    // A room wider than the tree changes nothing.
    expect(inkTree(tree, undefined, 10).box.height).toBe(natural.box.height);
  });
});
