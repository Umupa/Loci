import { describe, expect, it } from "vitest";
import {
  FAMILY_CHIP_WIDTH,
  FLOOR_TITLE_TAB_WIDTH,
  ICON_TAB_WIDTH,
  MAX_TITLE_TAB_WIDTH,
  MIN_ICON_TAB_WIDTH,
  MIN_TITLE_TAB_WIDTH,
  TAB_GAP,
  chooseTitled,
  tabStripLayout,
} from "./tabStripLayout";

/** Width the layout actually spends, to prove it never promises more than there is. */
function spent(layout: ReturnType<typeof tabStripLayout>, count: number, pinned: number, extra = 0) {
  const regular = count - pinned;
  const titled = layout.titledCount;
  const divider = pinned > 0 && regular > 0 ? 9 : 0;
  return pinned * (layout.iconWidth + TAB_GAP) + divider + (regular - titled) * (layout.iconWidth + TAB_GAP)
    + (titled - 1) * (layout.titledWidth + TAB_GAP) + layout.titledWidth + extra + TAB_GAP;
}

describe("tabStripLayout", () => {
  it("lets tabs share the strip while every title stays readable", () => {
    expect(tabStripLayout({ count: 5, pinned: 0, available: 900 }).crowded).toBe(false);
    expect(tabStripLayout({ count: 1, pinned: 0, available: 100 }).crowded).toBe(false);
  });

  it("folds only as many tabs as it takes, so the room that is left keeps titles", () => {
    // 14 tabs, a strip of 840: every title cannot fit, but there is room for three.
    const layout = tabStripLayout({ count: 14, pinned: 0, available: 840 });
    expect(layout.crowded).toBe(true);
    expect(layout.titledCount).toBe(3);
    expect(layout.titledWidth).toBeGreaterThanOrEqual(MIN_TITLE_TAB_WIDTH);
    expect(layout.titledWidth).toBeLessThanOrEqual(MAX_TITLE_TAB_WIDTH);
    expect(spent(layout, 14, 0)).toBeLessThanOrEqual(840);
    // And the room is used: another titled tab would not have fit.
    expect(spent({ ...layout, titledCount: 4, titledWidth: MIN_TITLE_TAB_WIDTH }, 14, 0)).toBeGreaterThan(840);
  });

  it("gives more tabs a title as the strip widens, and stops once all of them fit", () => {
    const counts = [600, 800, 1000, 1200, 1400, 1800].map((available) => tabStripLayout({ count: 10, pinned: 0, available }).titledCount);
    expect(counts).toEqual([...counts].sort((a, b) => a - b));
    expect(counts[0]).toBeGreaterThanOrEqual(1);
    expect(tabStripLayout({ count: 10, pinned: 0, available: 1800 }).crowded).toBe(false);
  });

  it("spends the whole strip: what cannot make another title goes to the titles it has", () => {
    for (const available of [700, 840, 1000, 1300]) {
      const layout = tabStripLayout({ count: 14, pinned: 0, available });
      expect(layout.titledWidth).toBeGreaterThanOrEqual(MIN_TITLE_TAB_WIDTH);
      expect(layout.titledWidth).toBeLessThanOrEqual(MAX_TITLE_TAB_WIDTH);
      // Less than one more tab's worth is left over.
      expect(available - spent(layout, 14, 0)).toBeLessThan(MIN_TITLE_TAB_WIDTH + TAB_GAP);
    }
  });

  it("never claims more room than the strip has, across widths and pinned counts", () => {
    for (const pinned of [0, 2, 4]) {
      for (let available = 400; available <= 1600; available += 37) {
        const layout = tabStripLayout({ count: 14, pinned, available });
        if (!layout.crowded) continue;
        if (layout.iconWidth === ICON_TAB_WIDTH) expect(spent(layout, 14, pinned)).toBeLessThanOrEqual(available);
      }
    }
  });

  it("gives an active tab that carries a chip room for it", () => {
    const plain = tabStripLayout({ count: 13, pinned: 0, available: 700 });
    const chip = tabStripLayout({ count: 13, pinned: 0, available: 700, activeExtra: FAMILY_CHIP_WIDTH });
    expect(chip.activeWidth).toBe(chip.titledWidth + FAMILY_CHIP_WIDTH);
    expect(plain.activeWidth).toBe(plain.titledWidth);
    expect(spent(chip, 13, 0, FAMILY_CHIP_WIDTH)).toBeLessThanOrEqual(700);
  });

  it("counts pinned tabs as icons from the start", () => {
    expect(tabStripLayout({ count: 8, pinned: 4, available: 710 }).crowded).toBe(false);
    expect(tabStripLayout({ count: 12, pinned: 4, available: 640 }).crowded).toBe(true);
    expect(tabStripLayout({ count: 4, pinned: 4, available: 100 }).crowded).toBe(false);
  });

  it("holds one titled tab at its floor and narrows the icons when even that is tight", () => {
    const squeezed = tabStripLayout({ count: 13, pinned: 0, available: 480 });
    expect(squeezed.titledCount).toBe(1);
    expect(squeezed.activeWidth).toBe(FLOOR_TITLE_TAB_WIDTH);
    expect(squeezed.iconWidth).toBeLessThan(ICON_TAB_WIDTH);
    expect(squeezed.iconWidth).toBeGreaterThanOrEqual(MIN_ICON_TAB_WIDTH);
    expect(tabStripLayout({ count: 13, pinned: 0, available: 200 }).iconWidth).toBe(MIN_ICON_TAB_WIDTH);
  });
});

describe("chooseTitled", () => {
  const ids = ["a", "b", "c", "d", "e", "f"];
  const choose = (over: Partial<Parameters<typeof chooseTitled>[0]> = {}) =>
    chooseTitled({ ids, activeId: "a", recent: [], capacity: 3, previous: [], ...over });

  it("starts with the tab in view, then the most recently used, then strip order", () => {
    expect(choose({ recent: ["a", "d", "c"] })).toEqual(["a", "d", "c"]);
    expect(choose()).toEqual(["a", "b", "c"]);
  });

  it("does not reshuffle while moving between tabs that already have titles", () => {
    const first = choose({ recent: ["a", "d", "c"] });
    expect(choose({ activeId: "c", recent: ["c", "a", "d"], previous: first })).toEqual(["c", "a", "d"]);
  });

  it("replaces the one used longest ago when a tab from outside comes into view", () => {
    expect(choose({ activeId: "f", recent: ["f", "a", "d", "c"], previous: ["a", "d", "c"] })).toEqual(["f", "a", "d"]);
  });

  it("forgets tabs that closed and fills the gap", () => {
    expect(choose({ ids: ["a", "c", "e"], previous: ["a", "d", "c"] })).toEqual(["a", "c", "e"]);
  });

  it("makes room for more as the strip grows, and fewer as it shrinks", () => {
    expect(choose({ capacity: 5, previous: ["a", "b", "c"] })).toEqual(["a", "b", "c", "d", "e"]);
    expect(choose({ capacity: 1, previous: ["a", "b", "c"] })).toEqual(["a"]);
    expect(choose({ capacity: 0 })).toEqual([]);
  });
});
