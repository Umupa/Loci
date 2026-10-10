import { sanitizeLayout } from "./workspaceSnapshot";
import type { LayoutNode } from "./layout";

/** A tab as it was when closed: enough to put it back, panes and all. */
export type ClosedTab = {
  layout: LayoutNode;
  focusedId: string;
  cwd?: string;
  pinned?: boolean;
  title: string;
  project: string;
  paneKind?: "canvas" | "file" | "document" | "widget";
  closedAt: number;
  /** Tabs closed by one action share a batch, and come back together. */
  batch: number;
  /** Put away because the project had too many tabs, not closed by the user. */
  parked?: boolean;
};

export const MAX_CLOSED_TABS = 20;
/** Parked tabs were never asked to go, so more of them are kept. */
export const MAX_PARKED_TABS = 30;
const STORAGE_KEY = "loci.closedTabs.v1";

/** Newest first, trimmed to the history that is worth keeping: closed and parked tabs each have their own room. */
export function pushClosed(history: readonly ClosedTab[], closed: readonly ClosedTab[]): ClosedTab[] {
  let closedRoom = MAX_CLOSED_TABS;
  let parkedRoom = MAX_PARKED_TABS;
  return [...[...closed].reverse(), ...history].filter((entry) => {
    if (entry.parked) return parkedRoom-- > 0;
    return closedRoom-- > 0;
  });
}

/** The tab ids a closed batch holds, for reopening the one the user last closed. */
function lastClosedBatch(history: readonly ClosedTab[]): number | undefined {
  return history.find((entry) => !entry.parked)?.batch;
}

/**
 * The most recently closed batch, in the order its tabs were open. Parked tabs
 * are left out: closing a tab and reopening it should not dredge up tabs that
 * were put away earlier.
 */
export function latestBatch(history: readonly ClosedTab[]): ClosedTab[] {
  const batch = lastClosedBatch(history);
  return batch === undefined ? [] : history.filter((entry) => entry.batch === batch).reverse();
}

export function withoutBatch(history: readonly ClosedTab[], batch: number): ClosedTab[] {
  return history.filter((entry) => entry.batch !== batch);
}

function parse(raw: string | null): ClosedTab[] {
  if (!raw) return [];
  try {
    const list = JSON.parse(raw) as unknown;
    if (!Array.isArray(list)) return [];
    return list.flatMap((item): ClosedTab[] => {
      if (!item || typeof item !== "object") return [];
      const value = item as Record<string, unknown>;
      const layout = sanitizeLayout(value.layout);
      if (!layout || typeof value.focusedId !== "string" || typeof value.batch !== "number") return [];
      return [{
        layout,
        focusedId: value.focusedId,
        title: typeof value.title === "string" ? value.title : "",
        project: typeof value.project === "string" ? value.project : "",
        closedAt: typeof value.closedAt === "number" ? value.closedAt : 0,
        batch: value.batch,
        ...(typeof value.cwd === "string" ? { cwd: value.cwd } : {}),
        ...(value.pinned === true ? { pinned: true } : {}),
        ...(value.parked === true ? { parked: true } : {}),
        ...(value.paneKind === "canvas" || value.paneKind === "file" || value.paneKind === "document" || value.paneKind === "widget" ? { paneKind: value.paneKind } : {}),
      }];
    });
  } catch {
    return [];
  }
}

/** What the "closed — Undo" toast announces. */
export type ClosedNotice = { batch: number; count: number; title: string; parked: boolean };

let history: ClosedTab[] = [];
let notice: ClosedNotice | null = null;
let batchCounter = Date.now();
const listeners = new Set<() => void>();

try {
  history = parse(localStorage.getItem(STORAGE_KEY));
  batchCounter = Math.max(batchCounter, ...history.map((entry) => entry.batch));
} catch {
  /* no storage: history lives for this session */
}

function emit() {
  for (const listener of listeners) listener();
}

function persist() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
  } catch {
    /* the history still works until the app closes */
  }
}

export const closedTabs = {
  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => { listeners.delete(listener); };
  },
  history: () => history,
  notice: () => notice,
  /** Remember tabs that were just closed together, and announce them. */
  record(tabs: readonly Omit<ClosedTab, "batch" | "closedAt" | "parked">[], { parked = false }: { parked?: boolean } = {}) {
    if (tabs.length === 0) return;
    batchCounter += 1;
    const batch = batchCounter;
    const closedAt = Date.now();
    history = pushClosed(history, tabs.map((tab) => ({ ...tab, batch, closedAt, ...(parked ? { parked: true } : {}) })));
    notice = { batch, count: tabs.length, title: tabs[0].title, parked };
    persist();
    emit();
  },
  /** Take a batch out of the history so it can be reopened. */
  take(batch: number | "latest"): ClosedTab[] {
    const wanted = batch === "latest" ? lastClosedBatch(history) : batch;
    if (wanted === undefined) return [];
    const taken = history.filter((entry) => entry.batch === wanted).reverse();
    history = withoutBatch(history, wanted);
    if (notice?.batch === wanted) notice = null;
    persist();
    emit();
    return taken;
  },
  /** Forget everything: for tests, and a clean slate. */
  clear() {
    history = [];
    notice = null;
    persist();
    emit();
  },
  dismissNotice() {
    if (!notice) return;
    notice = null;
    emit();
  },
};
