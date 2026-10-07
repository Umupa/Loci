type Pinnable = { id: string; pinned?: boolean };

/** Pinned tabs first, every tab otherwise staying where it was. */
export function pinnedFirst<T extends Pinnable>(tabs: readonly T[]): T[] {
  const pinned = tabs.filter((tab) => tab.pinned);
  return pinned.length === 0 || pinned.length === tabs.length
    ? [...tabs]
    : [...pinned, ...tabs.filter((tab) => !tab.pinned)];
}

/**
 * Pin or unpin one tab. A newly pinned tab joins the end of the pinned block,
 * and a newly unpinned one the start of the rest, so it stays next to where
 * it was on screen.
 */
export function setTabPinned<T extends Pinnable>(tabs: readonly T[], id: string, pinned: boolean): T[] {
  const target = tabs.find((tab) => tab.id === id);
  if (!target || !!target.pinned === pinned) return [...tabs];
  const changed = { ...target, pinned: pinned || undefined } as T;
  if (!pinned) delete changed.pinned;
  const others = tabs.filter((tab) => tab.id !== id);
  const pinnedCount = others.filter((tab) => tab.pinned).length;
  const at = pinnedCount;
  return [...others.slice(0, at), changed, ...others.slice(at)];
}
