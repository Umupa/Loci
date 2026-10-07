import { describe, expect, it } from "vitest";
import { pinnedFirst, setTabPinned } from "./tabPins";

type T = { id: string; pinned?: boolean };
const ids = (tabs: T[]) => tabs.map((tab) => `${tab.id}${tab.pinned ? "*" : ""}`);

describe("tab pins", () => {
  it("pins to the end of the pinned block and unpins to the start of the rest", () => {
    const tabs: T[] = [{ id: "a", pinned: true }, { id: "b" }, { id: "c" }, { id: "d" }];
    const pinned = setTabPinned(tabs, "c", true);
    expect(ids(pinned)).toEqual(["a*", "c*", "b", "d"]);
    expect(ids(setTabPinned(pinned, "a", false))).toEqual(["c*", "a", "b", "d"]);
  });

  it("leaves tabs alone when the pin state already matches or the tab is unknown", () => {
    const tabs: T[] = [{ id: "a", pinned: true }, { id: "b" }];
    expect(ids(setTabPinned(tabs, "a", true))).toEqual(["a*", "b"]);
    expect(ids(setTabPinned(tabs, "x", true))).toEqual(["a*", "b"]);
  });

  it("keeps pinned tabs ahead after a reorder, otherwise preserving order", () => {
    expect(ids(pinnedFirst([{ id: "b" }, { id: "a", pinned: true }, { id: "c" }, { id: "d", pinned: true }]))).toEqual(["a*", "d*", "b", "c"]);
    const same: T[] = [{ id: "x" }, { id: "y" }];
    expect(ids(pinnedFirst(same))).toEqual(["x", "y"]);
  });
});
