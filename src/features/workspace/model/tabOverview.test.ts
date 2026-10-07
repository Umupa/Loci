import { describe, expect, it } from "vitest";
import { defaultScope, moveInGrid, overviewCards } from "./tabOverview";
import type { Tab } from "./tabSummary";

function tab(id: string, over: Partial<Tab> = {}): Tab {
  return { id, title: id, project: "loci", projectPath: "/p/loci", more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], status: "idle", ...over };
}
const ids = (cards: ReturnType<typeof overviewCards>) => cards.map(({ tab: t, depth }) => `${"-".repeat(depth)}${t.id}`);
const base = { scope: "all" as const, projectPath: "/p/loci", query: "", recent: ["c", "a"] };

describe("overviewCards", () => {
  const tabs = [tab("a"), tab("b", { status: "busy" }), tab("c"), tab("d", { status: "approval" }), tab("e", { status: "done" })];

  it("puts what wants the user first, then what is working, then the rest by recency", () => {
    expect(ids(overviewCards({ ...base, tabs }))).toEqual(["d", "e", "b", "c", "a"]);
  });

  it("limits itself to the project in view, unless asked for everything", () => {
    const mixed = [...tabs, tab("x", { project: "papers", projectPath: "/p/papers" })];
    expect(ids(overviewCards({ ...base, tabs: mixed, scope: "project" }))).not.toContain("x");
    expect(ids(overviewCards({ ...base, tabs: mixed }))).toContain("x");
    expect(defaultScope(mixed, "/p/papers")).toBe("project");
    expect(defaultScope(tabs, "/p/elsewhere")).toBe("all");
  });

  it("keeps started tabs right after their parent, and lets a busy child lift its parent", () => {
    const family = [tab("a"), tab("p"), tab("k1", { parentId: "p" }), tab("k2", { parentId: "p", status: "approval" }), tab("z")];
    // p has no urgency of its own, but what it started wants the user.
    const withRollup = family.map((t) => (t.id === "p" ? { ...t, descendantCount: 2, descendantStatus: "approval" as const } : t));
    expect(ids(overviewCards({ ...base, tabs: withRollup, recent: [] }))).toEqual(["p", "-k1", "-k2", "a", "z"]);
  });

  it("ranks matches flat when searching, by title first", () => {
    const named = [tab("1", { title: "Release notes" }), tab("2", { title: "Other", preview: "release the build" }), tab("3", { title: "Unrelated" })];
    expect(ids(overviewCards({ ...base, tabs: named, query: "release" }))).toEqual(["1", "2"]);
  });
});

describe("moveInGrid", () => {
  it("moves by row and column, staying inside the grid", () => {
    expect(moveInGrid(0, "ArrowDown", 3, 8)).toBe(3);
    expect(moveInGrid(7, "ArrowDown", 3, 8)).toBe(7);
    expect(moveInGrid(1, "ArrowUp", 3, 8)).toBe(1);
    expect(moveInGrid(4, "ArrowUp", 3, 8)).toBe(1);
    expect(moveInGrid(2, "ArrowRight", 3, 8)).toBe(3);
    expect(moveInGrid(7, "ArrowRight", 3, 8)).toBe(7);
    expect(moveInGrid(0, "ArrowLeft", 3, 8)).toBe(0);
    expect(moveInGrid(0, "ArrowDown", 3, 0)).toBe(0);
  });
});
