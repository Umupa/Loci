/**
 * Which library items a running turn just saved. A source, guide, course or
 * note that appears while the mentor works is marked "new" until the learner
 * opens it or the turn ends; earlier items never are.
 */
import type { MentorPage } from "./mentorPage";

export type NoveltyState = {
  busy: boolean;
  /** The items that existed when the turn started; null until a list is readable. */
  baseline: readonly string[] | null;
  marked: readonly string[];
  opened: readonly string[];
};

export function emptyNovelty(): NoveltyState {
  return { busy: false, baseline: null, marked: [], opened: [] };
}

/** The key an item is known by across the three listings. */
export function noveltyKey(
  kind: "document" | "course" | "note" | "canvas",
  id: string,
): string {
  return `${kind}:${id}`;
}

/** A turn started or ended; the next turn starts from what exists then. */
export function noveltyTurn(
  state: NoveltyState,
  busy: boolean,
  keys: readonly string[] | undefined,
): NoveltyState {
  if (busy === state.busy) return state;
  return {
    busy,
    baseline: keys ?? null,
    marked: [],
    opened: [],
  };
}

/** A listing arrived: while a turn runs, ids it did not start with are new. */
export function noveltyItems(
  state: NoveltyState,
  keys: readonly string[] | undefined,
): NoveltyState {
  if (!keys) return state;
  if (!state.busy) {
    return sameKeys(state.baseline, keys) ? state : { ...state, baseline: keys, marked: [] };
  }
  // The first listing of a turn is what the turn started with, even when it
  // arrives after the turn did (a window opened mid-turn).
  if (state.baseline === null) return { ...state, baseline: keys };
  const baseline = new Set(state.baseline);
  const opened = new Set(state.opened);
  const marked = new Set(state.marked);
  let changed = false;
  for (const key of keys) {
    if (baseline.has(key) || opened.has(key) || marked.has(key)) continue;
    marked.add(key);
    changed = true;
  }
  return changed ? { ...state, marked: [...marked] } : state;
}

/** The learner opened an item: its mark goes, and its revision later in the turn stays quiet. */
export function noveltyOpened(state: NoveltyState, key: string): NoveltyState {
  const opened = state.opened.includes(key)
    ? state.opened
    : [...state.opened, key];
  if (!state.marked.includes(key) && opened === state.opened) return state;
  return {
    ...state,
    marked: state.marked.filter((entry) => entry !== key),
    opened,
  };
}

/** Whether the item is new in the turn that is running now. */
export function noveltyIsNew(state: NoveltyState, key: string): boolean {
  return state.busy && state.marked.includes(key);
}

/** The library key of the page the reader shows, when it names one of these items. */
export function pageNoveltyKey(page: MentorPage | undefined): string | undefined {
  if (!page) return undefined;
  if (page.kind === "course") return noveltyKey("course", page.course.courseId);
  if (page.kind === "document") return noveltyKey("document", page.document.id);
  if (page.kind === "note") return noveltyKey("note", page.id);
  return undefined;
}

function sameKeys(a: readonly string[] | null, b: readonly string[]): boolean {
  if (!a || a.length !== b.length) return false;
  return a.every((key, index) => key === b[index]);
}
