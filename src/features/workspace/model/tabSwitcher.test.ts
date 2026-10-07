import { describe, expect, it } from "vitest";
import type { ClosedTab } from "./closedTabs";
import { buildSwitcher, byRecency, flattenSwitcher, initialSelection } from "./tabSwitcher";
import type { Tab } from "./tabSummary";

function tab(id: string, title: string, over: Partial<Tab> = {}): Tab {
  return { id, title, project: "loci", projectPath: "/p/loci", more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], status: "idle", ...over };
}
function closedTab(title: string, batch: number): ClosedTab {
  return { layout: { type: "leaf", id: title }, focusedId: title, title, project: "loci", closedAt: batch, batch };
}
const labels = (sections: ReturnType<typeof buildSwitcher>) => sections.map((section) => section.label);
const names = (sections: ReturnType<typeof buildSwitcher>) => flattenSwitcher(sections).map((row) => row.kind === "tab" ? row.tab.title : `closed:${row.closed.title}`);

const tabs = [
  tab("a", "Fix the tab bar"),
  tab("b", "Write release notes", { status: "approval" }),
  tab("c", "Survey", { project: "papers", projectPath: "/p/papers" }),
  tab("d", "Refactor sessions", { status: "done" }),
  tab("e", "Explore search"),
];
const base = { tabs, activeId: "a", projectPath: "/p/loci", recent: ["a", "e", "c"], closed: [] as ClosedTab[], query: "" };

describe("buildSwitcher", () => {
  it("puts what needs the user first, then this project by recency, then other projects", () => {
    const sections = buildSwitcher(base);
    expect(labels(sections)).toEqual(["Needs you", "This project", "papers"]);
    expect(names(sections)).toEqual(["Write release notes", "Refactor sessions", "Fix the tab bar", "Explore search", "Survey"]);
  });

  it("never flags the tab already in view as needing the user", () => {
    const sections = buildSwitcher({ ...base, activeId: "b" });
    expect(sections[0]).toMatchObject({ label: "Needs you" });
    expect(sections[0].rows).toHaveLength(1);
    expect(names(sections)[0]).toBe("Refactor sessions");
    expect(sections[1].rows.some((row) => row.kind === "tab" && row.tab.id === "b" && row.current)).toBe(true);
  });

  it("lists approvals ahead of finished tabs", () => {
    const rows = buildSwitcher(base)[0].rows;
    expect(rows.map((row) => row.kind === "tab" && row.tab.status)).toEqual(["approval", "done"]);
  });

  it("selects the tab to flip back to, not the one in view", () => {
    const rows = flattenSwitcher(buildSwitcher({ ...base, tabs: tabs.filter((t) => t.id !== "b" && t.id !== "d") }));
    expect(rows[initialSelection(rows)]).toMatchObject({ tab: { id: "e" } });
  });

  it("finds tabs by title, project or preview, best title match first", () => {
    expect(names(buildSwitcher({ ...base, query: "release" }))).toEqual(["Write release notes"]);
    expect(names(buildSwitcher({ ...base, query: "papers" }))).toEqual(["Survey"]);
    const withPreview = [...tabs, tab("f", "Untitled", { preview: "migrated the database schema" })];
    expect(names(buildSwitcher({ ...base, tabs: withPreview, query: "schema" }))).toEqual(["Untitled"]);
    expect(buildSwitcher({ ...base, query: "zzzz" })).toEqual([]);
  });

  it("offers recently closed tabs, saying how many closed with each", () => {
    const closed = [closedTab("Old chat", 2), closedTab("Other", 2), closedTab("Ancient", 1)];
    const sections = buildSwitcher({ ...base, closed });
    expect(labels(sections).at(-1)).toBe("Recently closed");
    const rows = sections.at(-1)!.rows;
    expect(rows[0]).toMatchObject({ kind: "closed", alsoClosed: 1 });
    expect(rows[2]).toMatchObject({ kind: "closed", alsoClosed: 0 });
    expect(names(buildSwitcher({ ...base, closed, query: "old" }))).toEqual(["closed:Old chat"]);
  });
});

describe("started tabs", () => {
  it("follow the tab that started them, indented", () => {
    const family = [tab("a", "Parent"), tab("z", "Elsewhere"), tab("k", "Child", { parentId: "a" })];
    const sections = buildSwitcher({ ...base, tabs: family, recent: ["a", "z", "k"], activeId: "z" });
    const rows = sections[0].rows.map((row) => row.kind === "tab" ? [row.tab.title, row.depth] : null);
    expect(rows).toEqual([["Parent", 0], ["Child", 1], ["Elsewhere", 0]]);
  });
});

describe("parked tabs", () => {
  const parked: ClosedTab = { ...closedTab("Quiet chat", 5), parked: true };

  it("get their own section ahead of recently closed, and are found by search", () => {
    const sections = buildSwitcher({ ...base, closed: [closedTab("Old chat", 2), parked] });
    expect(labels(sections).slice(-2)).toEqual(["Parked", "Recently closed"]);
    expect(names(buildSwitcher({ ...base, closed: [closedTab("Old chat", 2), parked], query: "quiet" }))).toEqual(["closed:Quiet chat"]);
    expect(labels(buildSwitcher({ ...base, closed: [parked], query: "quiet" }))).toEqual(["Parked"]);
  });
});

describe("byRecency", () => {
  it("orders by last use and keeps unused tabs in strip order", () => {
    expect(byRecency(tabs, ["c", "a"]).map((t) => t.id)).toEqual(["c", "a", "b", "d", "e"]);
  });
});
