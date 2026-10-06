import { describe, expect, it } from "vitest";
import { closeLeaf, layoutLeaves, layoutSashes, leaf, newTab, resetTabToSession, movePane, paneEdgeFromPoint, placePane, splitPane, splitSizesAtBoundary, type WorkspaceTab, } from "./layout";
describe("splitSizesAtBoundary", () => {
    it("moves only the adjacent panes and preserves their total", () => {
        const result = splitSizesAtBoundary([0.2, 0.3, 0.5], 1, 0.7);
        expect(result[0]).toBe(0.2);
        expect(result[1]).toBeCloseTo(0.5);
        expect(result[2]).toBeCloseTo(0.3);
    });
    it("clamps both panes to the minimum size", () => {
        const right = splitSizesAtBoundary([0.5, 0.5], 0, 0.99);
        expect(right[0]).toBeCloseTo(0.92);
        expect(right[1]).toBeCloseTo(0.08);
        const left = splitSizesAtBoundary([0.5, 0.5], 0, 0.01);
        expect(left[0]).toBeCloseTo(0.08);
        expect(left[1]).toBeCloseTo(0.92);
    });
    it("leaves invalid boundaries unchanged", () => {
        const sizes = [0.5, 0.5];
        expect(splitSizesAtBoundary(sizes, 2, 0.5)).toBe(sizes);
    });
});
describe("layoutLeaves", () => {
    it("keeps a single pane filling the tab", () => {
        const leaves = layoutLeaves(leaf("a"));
        expect(leaves).toEqual([
            { id: "a", rect: { x: 0, y: 0, w: 1, h: 1 }, axis: "x" },
        ]);
    });
    it("places a right split side by side without changing leaf ids", () => {
        const tree = splitPane(leaf("a"), "a", "right", "b");
        const leaves = layoutLeaves(tree);
        expect(leaves.map((pane) => pane.id)).toEqual(["a", "b"]);
        expect(leaves[0].rect).toEqual({ x: 0, y: 0, w: 0.5, h: 1 });
        expect(leaves[1].rect).toEqual({ x: 0.5, y: 0, w: 0.5, h: 1 });
    });
});
describe("layoutSashes", () => {
    it("puts a sash on the shared edge of a right split", () => {
        const tree = splitPane(leaf("a"), "a", "right", "b");
        const sashes = layoutSashes(tree);
        expect(sashes).toHaveLength(1);
        expect(sashes[0]?.index).toBe(0);
        expect(sashes[0]?.dir).toBe("right");
        expect(sashes[0]?.group).toEqual({ x: 0, y: 0, w: 1, h: 1 });
    });
});
describe("closeLeaf", () => {
    it("returns null when closing the last remaining pane", () => {
        expect(closeLeaf(newTab("session-a"), "session-a")).toBeNull();
    });
});
describe("resetTabToSession", () => {
    it("keeps id and group, replaces contents with one session leaf", () => {
        const tab = {
            ...newTab("session-a"),
            groupId: "group-1",
        };
        const next = resetTabToSession(tab, "session-b");
        expect(next.id).toBe(tab.id);
        expect(next.groupId).toBe("group-1");
        expect(next.layout).toEqual(leaf("session-b"));
        expect(next.focusedId).toBe("session-b");
    });
});
describe("paneEdgeFromPoint", () => {
    const rect = { left: 0, top: 0, width: 100, height: 100 };
    it("picks the nearest edge from the pane center", () => {
        expect(paneEdgeFromPoint(20, 50, rect)).toBe("left");
        expect(paneEdgeFromPoint(80, 50, rect)).toBe("right");
        expect(paneEdgeFromPoint(50, 20, rect)).toBe("top");
        expect(paneEdgeFromPoint(50, 80, rect)).toBe("bottom");
    });
});
describe("movePane", () => {
    it("reorders siblings along a horizontal split", () => {
        const tree = splitPane(leaf("a"), "a", "right", "b");
        const next = movePane(tree, "a", "b", "right");
        const leaves = layoutLeaves(next);
        expect(leaves.map((pane) => pane.id)).toEqual(["b", "a"]);
        expect(leaves[0]?.rect).toEqual({ x: 0, y: 0, w: 0.5, h: 1 });
        expect(leaves[1]?.rect).toEqual({ x: 0.5, y: 0, w: 0.5, h: 1 });
    });
    it("stacks a dragged pane under its sibling", () => {
        const tree = splitPane(leaf("a"), "a", "right", "b");
        const next = movePane(tree, "b", "a", "bottom");
        const leaves = layoutLeaves(next);
        expect(leaves.map((pane) => pane.id)).toEqual(["a", "b"]);
        expect(leaves[0]?.rect).toEqual({ x: 0, y: 0, w: 1, h: 0.5 });
        expect(leaves[1]?.rect).toEqual({ x: 0, y: 0.5, w: 1, h: 0.5 });
    });
    it("nests a pane under one column of a row", () => {
        const row = splitPane(splitPane(leaf("a"), "a", "right", "b"), "b", "right", "c");
        const next = movePane(row, "c", "a", "bottom");
        const leaves = layoutLeaves(next);
        expect(leaves.map((pane) => pane.id)).toEqual(["a", "c", "b"]);
        expect(leaves[0]?.rect).toEqual({ x: 0, y: 0, w: 0.5, h: 0.5 });
        expect(leaves[1]?.rect).toEqual({ x: 0, y: 0.5, w: 0.5, h: 0.5 });
        expect(leaves[2]?.rect).toEqual({ x: 0.5, y: 0, w: 0.5, h: 1 });
    });
    it("inserts into an existing vertical split on a matching edge", () => {
        const stacked = splitPane(leaf("a"), "a", "down", "b");
        const row = splitPane(stacked, "a", "right", "c");
        const next = movePane(row, "c", "a", "bottom");
        const leaves = layoutLeaves(next);
        expect(leaves.map((pane) => pane.id)).toEqual(["a", "c", "b"]);
        expect(leaves[0]?.rect).toEqual({ x: 0, y: 0, w: 1, h: 0.25 });
        expect(leaves[1]?.rect).toEqual({ x: 0, y: 0.25, w: 1, h: 0.25 });
        expect(leaves[2]?.rect).toEqual({ x: 0, y: 0.5, w: 1, h: 0.5 });
    });
});
describe("placePane", () => {
    it("splits a lone pane toward the drop edge", () => {
        const right = layoutLeaves(placePane(leaf("a"), "b", "a", "right"));
        expect(right.map((pane) => pane.id)).toEqual(["a", "b"]);
        expect(right[0]?.rect).toEqual({ x: 0, y: 0, w: 0.5, h: 1 });
        expect(right[1]?.rect).toEqual({ x: 0.5, y: 0, w: 0.5, h: 1 });
        const left = layoutLeaves(placePane(leaf("a"), "b", "a", "left"));
        expect(left.map((pane) => pane.id)).toEqual(["b", "a"]);
        const below = layoutLeaves(placePane(leaf("a"), "b", "a", "bottom"));
        expect(below.map((pane) => pane.id)).toEqual(["a", "b"]);
        expect(below[1]?.rect).toEqual({ x: 0, y: 0.5, w: 1, h: 0.5 });
    });
    it("inserts into an existing row on a matching edge", () => {
        const row = splitPane(leaf("a"), "a", "right", "b");
        const next = placePane(row, "c", "a", "right");
        expect(layoutLeaves(next).map((pane) => pane.id)).toEqual(["a", "c", "b"]);
    });
    it("nests onto one column of a row", () => {
        const row = splitPane(leaf("a"), "a", "right", "b");
        const next = placePane(row, "c", "a", "bottom");
        const leaves = layoutLeaves(next);
        expect(leaves.map((pane) => pane.id)).toEqual(["a", "c", "b"]);
        expect(leaves[0]?.rect).toEqual({ x: 0, y: 0, w: 0.5, h: 0.5 });
        expect(leaves[1]?.rect).toEqual({ x: 0, y: 0.5, w: 0.5, h: 0.5 });
        expect(leaves[2]?.rect).toEqual({ x: 0.5, y: 0, w: 0.5, h: 1 });
    });
    it("moves an existing pane instead of duplicating it", () => {
        const row = splitPane(leaf("a"), "a", "right", "b");
        const next = placePane(row, "a", "b", "right");
        expect(layoutLeaves(next).map((pane) => pane.id)).toEqual(["b", "a"]);
    });
    it("ignores a missing target or a drop onto itself", () => {
        const tree = leaf("a");
        expect(placePane(tree, "b", "missing", "right")).toBe(tree);
        expect(placePane(tree, "a", "a", "right")).toBe(tree);
    });
});
