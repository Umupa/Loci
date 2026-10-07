import { describe, expect, it } from "vitest";
import { leaf, newTab, type WorkspaceTab } from "./layout";
import { familyOrder, foldFamilies, linkFamilies } from "./tabFamily";
import { spawnerOf, type Tab } from "./tabSummary";

const PARENT = "11111111-2222-3333-4444-555555555555";
function tab(id: string, over: Partial<Tab> = {}): Tab {
  return { id, title: id, project: "p", more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], status: "idle", ...over };
}
function holding(id: string, session: string): WorkspaceTab {
  return { ...newTab(session), id, layout: leaf(session) };
}

describe("spawnerOf", () => {
  it("reads the parent session out of an agent-started session's id", () => {
    expect(spawnerOf(`app-${PARENT}-review_1`)).toBe(PARENT);
    expect(spawnerOf(`app-app-${PARENT}-x-${PARENT}-y`)).toBeUndefined();
    expect(spawnerOf("0f0e0d0c-0000-0000-0000-000000000000")).toBeUndefined();
    expect(spawnerOf("app-not-a-uuid-1")).toBeUndefined();
  });
});

describe("linkFamilies", () => {
  const workspace = [holding("t-parent", PARENT), holding("t-kid", "app-x"), holding("t-kid2", "app-y"), holding("t-solo", "solo")];

  it("connects a spawned tab to the open tab of its spawner and rolls its state up", () => {
    const linked = linkFamilies([
      tab("t-parent"),
      tab("t-kid", { spawnedBy: PARENT, status: "busy" }),
      tab("t-kid2", { spawnedBy: PARENT, status: "approval" }),
      tab("t-solo"),
    ], workspace);
    const byId = Object.fromEntries(linked.map((t) => [t.id, t]));
    expect(byId["t-kid"].parentId).toBe("t-parent");
    expect(byId["t-parent"]).toMatchObject({ descendantCount: 2, descendantStatus: "approval" });
    expect(byId["t-solo"].parentId).toBeUndefined();
    expect(byId["t-solo"].descendantCount).toBeUndefined();
  });

  it("treats a tab as ordinary once its spawner is no longer open", () => {
    const linked = linkFamilies([tab("t-kid", { spawnedBy: PARENT })], [holding("t-kid", "app-x")]);
    expect(linked[0].parentId).toBeUndefined();
  });

  it("counts grandchildren in the grandparent and never loops", () => {
    const g = "99999999-2222-3333-4444-555555555555";
    const ws = [holding("a", PARENT), holding("b", g), holding("c", "leaf")];
    const linked = linkFamilies([tab("a"), tab("b", { spawnedBy: PARENT }), tab("c", { spawnedBy: g, status: "done" })], ws);
    expect(linked.find((t) => t.id === "a")).toMatchObject({ descendantCount: 2, descendantStatus: "done" });
    const loop = linkFamilies([tab("a", { spawnedBy: g }), tab("b", { spawnedBy: PARENT })], ws);
    expect(loop.some((t) => t.parentId === "a") && loop.some((t) => t.parentId === "b")).toBe(false);
  });
});

describe("foldFamilies", () => {
  const family = [
    tab("p"),
    tab("c1", { parentId: "p" }),
    tab("c2", { parentId: "p" }),
    tab("g1", { parentId: "c1" }),
    tab("other"),
  ];
  const shown = (expanded: string[], active = "other") => foldFamilies(family, new Set(expanded), active).map(({ tab: t, depth }) => `${"-".repeat(depth)}${t.id}`);

  it("hides what a folded parent started", () => {
    expect(shown([])).toEqual(["p", "other"]);
  });

  it("shows children in order under an unfolded parent, nested by depth", () => {
    expect(shown(["p"])).toEqual(["p", "-c1", "-c2", "other"]);
    expect(shown(["p", "c1"])).toEqual(["p", "-c1", "--g1", "-c2", "other"]);
  });

  it("always shows the tab in view and the path to it", () => {
    expect(shown([], "g1")).toEqual(["p", "-c1", "--g1", "-c2", "other"]);
  });

  it("lists every family member in order when asked for the whole", () => {
    expect(familyOrder(family).map(({ tab: t }) => t.id)).toEqual(["p", "c1", "g1", "c2", "other"]);
  });
});
