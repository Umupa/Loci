import { beforeEach, describe, expect, it } from "vitest";
import { loadPinnedSessionsCollapsed, savePinnedSessionsCollapsed } from "../../sessions/model/pinnedSessions";
import { rebaseProjectData } from "./projectData";

function mockBrowserStorage() {
  const data = new Map<string, string>();
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem: (key: string) => data.get(key) ?? null,
      setItem: (key: string, value: string) => data.set(key, value),
      removeItem: (key: string) => data.delete(key),
      clear: () => data.clear(),
      key: (index: number) => [...data.keys()][index] ?? null,
      get length() { return data.size; },
    },
  });
  Object.defineProperty(globalThis, "window", { configurable: true, value: new EventTarget() });
}
beforeEach(mockBrowserStorage);

describe("rebaseProjectData", () => {
  it("moves path-keyed folder settings to the renamed folder", () => {
    savePinnedSessionsCollapsed("/work/loci", true);
    rebaseProjectData("/work/loci", "/work/loci-personal");
    expect(loadPinnedSessionsCollapsed("/work/loci-personal")).toBe(true);
    expect(loadPinnedSessionsCollapsed("/work/loci")).toBe(false);
  });
});
