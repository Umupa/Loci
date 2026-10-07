import { describe, expect, it } from "vitest";
import { FLOOR_TITLE_TAB_WIDTH, MAX_TITLE_TAB_WIDTH, MIN_ICON_TAB_WIDTH, tabStripLayout } from "./tabStripLayout";

describe("tabStripLayout", () => {
  it("lets tabs share the strip while every title stays readable", () => {
    expect(tabStripLayout({ count: 5, pinned: 0, available: 900 }).crowded).toBe(false);
    expect(tabStripLayout({ count: 1, pinned: 0, available: 100 }).crowded).toBe(false);
  });

  it("folds idle tabs to icons rather than shrinking every title into a sliver", () => {
    const layout = tabStripLayout({ count: 13, pinned: 0, available: 900 });
    expect(layout.crowded).toBe(true);
    // 12 icon tabs and gaps use 456px; the active tab gets the rest, up to its natural width.
    expect(layout.activeWidth).toBe(MAX_TITLE_TAB_WIDTH);
    const tight = tabStripLayout({ count: 13, pinned: 0, available: 580 });
    expect(tight.activeWidth).toBe(580 - 12 * 38 - 2);
    expect(tight.iconWidth).toBe(36);
    // Tighter still: the active tab holds its floor and the icons narrow to fit.
    const squeezed = tabStripLayout({ count: 13, pinned: 0, available: 480 });
    expect(squeezed.activeWidth).toBe(FLOOR_TITLE_TAB_WIDTH);
    expect(squeezed.iconWidth).toBeLessThan(36);
    expect(squeezed.iconWidth).toBeGreaterThanOrEqual(MIN_ICON_TAB_WIDTH);
    // Narrower than icons can ever be: they stop at their minimum and the strip scrolls.
    expect(tabStripLayout({ count: 13, pinned: 0, available: 200 }).iconWidth).toBe(MIN_ICON_TAB_WIDTH);
  });

  it("gives an active tab that started others room for its chip too", () => {
    const plain = tabStripLayout({ count: 13, pinned: 0, available: 480 });
    const withChip = tabStripLayout({ count: 13, pinned: 0, available: 480, activeExtra: 30 });
    expect(withChip.activeWidth).toBe(plain.activeWidth + 30);
    expect(tabStripLayout({ count: 13, pinned: 0, available: 900, activeExtra: 30 }).activeWidth).toBe(MAX_TITLE_TAB_WIDTH + 30);
  });

  it("counts pinned tabs as icons from the start", () => {
    expect(tabStripLayout({ count: 8, pinned: 4, available: 710 }).crowded).toBe(false);
    expect(tabStripLayout({ count: 12, pinned: 4, available: 640 }).crowded).toBe(true);
    expect(tabStripLayout({ count: 4, pinned: 4, available: 100 }).crowded).toBe(false);
  });
});
