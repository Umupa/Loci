import { describe, expect, it } from "vitest";
import { MAX_CLOSED_TABS, latestBatch, pushClosed, withoutBatch, type ClosedTab } from "./closedTabs";

function tab(id: string, batch: number): ClosedTab {
  return { layout: { type: "leaf", id }, focusedId: id, title: id, project: "p", closedAt: batch, batch };
}

describe("closed tab history", () => {
  it("keeps the newest first and the tabs of one close in their original order", () => {
    const history = pushClosed(pushClosed([], [tab("a", 1)]), [tab("b", 2), tab("c", 2)]);
    expect(history.map((entry) => entry.title)).toEqual(["c", "b", "a"]);
    expect(latestBatch(history).map((entry) => entry.title)).toEqual(["b", "c"]);
    expect(withoutBatch(history, 2).map((entry) => entry.title)).toEqual(["a"]);
  });

  it("forgets the oldest tabs past the limit", () => {
    const many = Array.from({ length: MAX_CLOSED_TABS + 5 }, (_, index) => tab(`t${index}`, index));
    const history = pushClosed([], many);
    expect(history).toHaveLength(MAX_CLOSED_TABS);
    expect(history[0].title).toBe(`t${MAX_CLOSED_TABS + 4}`);
  });

  it("has nothing to reopen from an empty history", () => {
    expect(latestBatch([])).toEqual([]);
  });
});
