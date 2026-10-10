import { afterEach, describe, expect, it, vi } from "vitest";
import { MAX_CLOSED_TABS, MAX_PARKED_TABS, latestBatch, pushClosed, withoutBatch, type ClosedTab } from "./closedTabs";
import { documentLeaf } from "./layout";

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

describe("document tab history", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  it("restores a document's type and contents after the history is persisted", async () => {
    const storage = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => storage.set(key, value),
    });
    vi.resetModules();
    const { closedTabs } = await import("./closedTabs");
    const document = documentLeaf({ id: "network", title: "Network policy", body: "# Policy" }, "agent-1");
    if (document.type !== "leaf") throw new Error("Expected a document leaf");
    closedTabs.record([{ layout: document, focusedId: document.id, cwd: "/projects/loci", title: "Network policy", project: "loci", paneKind: "document" }]);
    vi.resetModules();
    const restored = await import("./closedTabs");
    expect(restored.closedTabs.take("latest")).toMatchObject([{
      layout: document, focusedId: document.id, cwd: "/projects/loci", title: "Network policy", paneKind: "document",
    }]);
    expect(restored.closedTabs.history()).toEqual([]);
  });
});
