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
  /** Some tabs fold to icons because not every tab can keep a readable title. */
  crowded: boolean;
  /** How many unpinned tabs can keep their title; the rest fold to icons. */
  titledCount: number;
  /** Width of a tab that keeps its title while the strip is crowded. */
  titledWidth: number;
  /** The active tab's width: a titled tab's, plus room for what it carries. */
  activeWidth: number;
  /** Width of an icon tab; narrower than usual when even icons are tight. */
  iconWidth: number;
};

/** An icon tab never gets narrower than this: its glyph still has to be hit. */
export const MIN_ICON_TAB_WIDTH = 26;

/**
 * How a strip of tabs spends its width. Every unpinned tab keeps a readable
 * title for as long as they all fit. Past that, tabs fold to icons only as
 * many as it takes: as many as the room allows keep their title, and share
 * what is left, so a wide strip never sits half empty beside a row of icons.
 * When even one titled tab will not fit, it holds a floor and the icons narrow
 * before the strip gives in and scrolls.
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
  const base = available - fixed;
  if (regular <= 1 || regular * (MIN_TITLE_TAB_WIDTH + TAB_GAP) + activeExtra <= base) {
    return { crowded: false, titledCount: regular, titledWidth: MAX_TITLE_TAB_WIDTH, activeWidth: MAX_TITLE_TAB_WIDTH, iconWidth: ICON_TAB_WIDTH };
  }
  const iconCost = ICON_TAB_WIDTH + TAB_GAP;
  const fit = Math.floor((base - regular * iconCost - activeExtra) / (MIN_TITLE_TAB_WIDTH - ICON_TAB_WIDTH));
  if (fit >= 1) {
    const titledCount = Math.min(fit, regular - 1);
    const room = base - (regular - titledCount) * iconCost - activeExtra - titledCount * TAB_GAP;
    const titledWidth = Math.floor(Math.min(MAX_TITLE_TAB_WIDTH, room / titledCount));
    return { crowded: true, titledCount, titledWidth, activeWidth: titledWidth + activeExtra, iconWidth: ICON_TAB_WIDTH };
  }
  // One titled tab holds its floor and every icon gives up a little width.
  const floor = FLOOR_TITLE_TAB_WIDTH + activeExtra;
  const icons = count - 1;
  const iconWidth = Math.floor((available - divider - floor - TAB_GAP * count) / icons);
  return {
    crowded: true,
    titledCount: 1,
    titledWidth: FLOOR_TITLE_TAB_WIDTH,
    activeWidth: floor,
    iconWidth: Math.max(MIN_ICON_TAB_WIDTH, Math.min(ICON_TAB_WIDTH, iconWidth)),
  };
}

/**
 * Which tabs keep their title in a crowded strip: the one in view, and then the
 * ones used most recently. The choice is sticky, so moving between tabs that
 * already have titles never reshuffles the strip; only a tab coming from
 * outside that group takes the place of the one used longest ago.
 */
export function chooseTitled({ ids, activeId, recent, capacity, previous }: {
  /** Unpinned tabs in strip order. */
  ids: readonly string[];
  activeId: string;
  /** Tab ids, most recently used first. */
  recent: readonly string[];
  capacity: number;
  /** The last choice, most recently used first. */
  previous: readonly string[];
}): string[] {
  const live = new Set(ids);
  const chosen: string[] = [];
  const add = (id: string) => {
    if (live.has(id) && !chosen.includes(id)) chosen.push(id);
  };
  add(activeId);
  previous.forEach(add);
  recent.forEach(add);
  ids.forEach(add);
  return chosen.slice(0, Math.max(0, capacity));
}
