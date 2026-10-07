import { describe, expect, it } from "vitest";
import { MAX_CLOSED_TABS, MAX_PARKED_TABS, latestBatch, pushClosed, withoutBatch, type ClosedTab } from "./closedTabs";

function tab(id: string, batch: number, parked = false): ClosedTab {
  return { layout: { type: "leaf", id }, focusedId: id, title: id, project: "p", closedAt: batch, batch, ...(parked ? { parked } : {}) };
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

  it("keeps parked tabs apart from closed ones: more room, and never what a reopen brings back", () => {
    const parked = Array.from({ length: MAX_PARKED_TABS + 3 }, (_, index) => tab(`p${index}`, 100 + index, true));
    const history = pushClosed(pushClosed([], [tab("closed", 1)]), parked);
    expect(history.filter((entry) => entry.parked)).toHaveLength(MAX_PARKED_TABS);
    expect(history.filter((entry) => !entry.parked).map((entry) => entry.title)).toEqual(["closed"]);
    // Parking a lot of tabs does not push the user's own closed tabs out.
    expect(latestBatch(history).map((entry) => entry.title)).toEqual(["closed"]);
  });
});
