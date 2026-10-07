/** Width of a tab shown as an icon alone: a pinned tab, or an idle one in a crowded strip. */
export const ICON_TAB_WIDTH = 36;
/** A tab with a title stops being readable below this. */
export const MIN_TITLE_TAB_WIDTH = 128;
export const MAX_TITLE_TAB_WIDTH = 224;
/** The active tab may be squeezed this far before the strip scrolls instead. */
export const FLOOR_TITLE_TAB_WIDTH = 96;
export const TAB_GAP = 2;
/** The rule between the pinned block and the rest, with the gaps around it. */
export const PINNED_DIVIDER_WIDTH = 9;
/** The thin line before a tab that was started from another, with the gap beside it. */
export const FAMILY_CONNECTOR_WIDTH = 5;
/** What the active tab spends on the chip that folds the tabs it started. */
export const FAMILY_CHIP_WIDTH = 34;

export type TabStripLayout = {
  /** Idle tabs collapse to icons so the active one can keep its title. */
  crowded: boolean;
  /** Width of the active tab while the strip is crowded. */
  activeWidth: number;
  /** Width of an icon tab; narrower than usual when even icons are tight. */
  iconWidth: number;
};

/** An icon tab never gets narrower than this: its glyph still has to be hit. */
export const MIN_ICON_TAB_WIDTH = 26;

/**
 * How a strip of tabs spends its width. While every unpinned tab can have a
 * readable title, they share the space as before. Past that point they do not
 * shrink further into unreadable slivers: all but the active one fold to
 * icons, and the active one takes what is left. When even that is too much,
 * the icons narrow before the strip gives in and scrolls.
 */
export function tabStripLayout({ count, pinned, available, activeExtra = 0 }: {
  count: number;
  pinned: number;
  /** Width of the strip's scrolling area, padding excluded. */
  available: number;
  /** Room the active tab needs beyond its title, such as the chip of the tabs it started. */
  activeExtra?: number;
}): TabStripLayout {
  const regular = Math.max(0, count - pinned);
  const divider = pinned > 0 && regular > 0 ? PINNED_DIVIDER_WIDTH : 0;
  const fixed = pinned * (ICON_TAB_WIDTH + TAB_GAP) + divider;
  const wanted = regular * (MIN_TITLE_TAB_WIDTH + TAB_GAP) + activeExtra;
  if (regular <= 1 || fixed + wanted <= available) {
    return { crowded: false, activeWidth: MAX_TITLE_TAB_WIDTH, iconWidth: ICON_TAB_WIDTH };
  }
  const others = (regular - 1) * (ICON_TAB_WIDTH + TAB_GAP);
  const room = available - fixed - others - TAB_GAP;
  const floor = FLOOR_TITLE_TAB_WIDTH + activeExtra;
  if (room >= floor) {
    return { crowded: true, activeWidth: Math.round(Math.min(MAX_TITLE_TAB_WIDTH + activeExtra, room)), iconWidth: ICON_TAB_WIDTH };
  }
  // The active tab holds its floor and every icon gives up a little width.
  const icons = count - 1;
  const iconWidth = Math.floor((available - divider - floor - TAB_GAP * count) / icons);
  return {
    crowded: true,
    activeWidth: floor,
    iconWidth: Math.max(MIN_ICON_TAB_WIDTH, Math.min(ICON_TAB_WIDTH, iconWidth)),
  };
}
