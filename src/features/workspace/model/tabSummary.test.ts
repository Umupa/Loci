import { describe, expect, it } from "vitest";
import { newSession, type Block } from "../../sessions/model/session";
import { canvasLeaf, newTab, placeLayout } from "./layout";
import { sessionPreview, shortAge, summarizeTab, tabStatusLabel, type TabSummaryContext } from "./tabSummary";

function block(role: Block["role"], text: string, extra: Partial<Block> = {}): Block {
  return { id: `${role}-${text.length}-${Math.random()}`, role, text, ...extra };
}

const context = (over: Partial<TabSummaryContext> = {}): TabSummaryContext => ({
  sessions: [],
  canvasTitle: () => undefined,
  needsInput: new Set(),
  unseenFinished: new Set(),
  fallbackCwd: "/p/home",
  ...over,
});

describe("sessionPreview", () => {
  it("shows the latest reply as one plain line, without markdown", () => {
    const session = { blocks: [block("user", "do it"), block("assistant", "## Done\n\nI **fixed** the [bug](http://x).\n```ts\ncode\n```")] };
    expect(sessionPreview(session)).toBe("Done I fixed the bug.");
  });

  it("falls back to the last thing the user said, and skips unsent drafts", () => {
    expect(sessionPreview({ blocks: [block("user", "first"), block("user", "unsent", { draft: true })] })).toBe("first");
    expect(sessionPreview({ blocks: [] })).toBe("");
  });

  it("stays short for a long reply", () => {
    expect(sessionPreview({ blocks: [block("assistant", "word ".repeat(400))] }).length).toBeLessThanOrEqual(240);
  });
});

describe("summarizeTab", () => {
  const session = { ...newSession("claude", "/p/loci"), id: "s1", title: "Fix the tab bar" };
  const tab = { ...newTab("s1"), id: "t1" };

  it("reports the most urgent thing happening in the tab", () => {
    const busy = { ...session, busy: true, blocks: [block("user", "go", { startedAt: 1000 })] };
    expect(summarizeTab(tab, context({ sessions: [busy] })).status).toBe("busy");
    expect(summarizeTab(tab, context({ sessions: [busy], unseenFinished: new Set(["s1"]) })).status).toBe("busy");
    expect(summarizeTab(tab, context({ sessions: [busy], needsInput: new Set(["s1"]) })).status).toBe("approval");
    expect(summarizeTab(tab, context({ sessions: [session], unseenFinished: new Set(["s1"]) })).status).toBe("done");
    expect(summarizeTab(tab, context({ sessions: [session] })).status).toBe("idle");
  });

  it("names the tab after its project, title and pinned state", () => {
    const summary = summarizeTab({ ...tab, pinned: true }, context({ sessions: [session] }));
    expect(summary).toMatchObject({ project: "loci", projectPath: "/p/loci", title: "Fix the tab bar", pinned: true });
  });

  it("titles a tab by its focused drawing or file", () => {
    const withCanvas = { ...tab, layout: placeLayout(tab.layout, canvasLeaf("c1"), "s1", "right"), focusedId: "c1" };
    expect(summarizeTab(withCanvas, context({ sessions: [session], canvasTitle: () => "System sketch" }))).toMatchObject({ title: "System sketch", paneKind: "canvas", multiPane: true });
  });
});

describe("tabStatusLabel", () => {
  it("describes each state in words", () => {
    const now = 10 * 60_000;
    expect(tabStatusLabel({ status: "approval" }, now)).toBe("Needs your approval");
    expect(tabStatusLabel({ status: "busy", busySince: now - 135_000 }, now)).toBe("Working · 2m 15s");
    expect(tabStatusLabel({ status: "done" }, now)).toBe("Finished · not yet seen");
    expect(tabStatusLabel({ status: "idle", activityAt: 3_600_000 }, 4 * 3_600_000)).toBe("Idle · 3h ago");
    expect(tabStatusLabel({ status: "idle", blank: true }, now)).toBe("New session");
  });

  it("shortens ages", () => {
    expect([shortAge(10_000), shortAge(5 * 60_000), shortAge(3 * 3_600_000), shortAge(50 * 3_600_000)]).toEqual(["now", "5m", "3h", "2d"]);
  });
});
