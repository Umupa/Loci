import { leafIds, type WorkspaceTab } from "./layout";
import type { Tab, TabStatus } from "./tabSummary";

const URGENCY: Record<TabStatus, number> = { approval: 3, done: 2, busy: 1, idle: 0 };

/**
 * Connect tabs an agent started to the tab that started them. A tab is a child
 * when its conversation was spawned by a session that is open in another tab;
 * once that tab is closed it is just a tab again.
 */
export function linkFamilies(tabs: readonly Tab[], workspace: readonly WorkspaceTab[]): Tab[] {
  const holder = new Map<string, string>();
  for (const tab of workspace) for (const id of leafIds(tab.layout)) holder.set(id, tab.id);

  const parentOf = new Map<string, string>();
  for (const tab of tabs) {
    const parent = tab.spawnedBy ? holder.get(tab.spawnedBy) : undefined;
    if (parent && parent !== tab.id) parentOf.set(tab.id, parent);
  }
  // A tab can never descend from itself, however ids were reused.
  for (const id of [...parentOf.keys()]) {
    const seen = new Set([id]);
    for (let at = parentOf.get(id); at; at = parentOf.get(at)) {
      if (seen.has(at)) { parentOf.delete(id); break; }
      seen.add(at);
    }
  }

  const byId = new Map(tabs.map((tab) => [tab.id, tab]));
  const count = new Map<string, number>();
  const urgent = new Map<string, TabStatus>();
  for (const tab of tabs) {
    for (let at = parentOf.get(tab.id); at; at = parentOf.get(at)) {
      count.set(at, (count.get(at) ?? 0) + 1);
      const status = tab.status ?? "idle";
      const known = urgent.get(at) ?? "idle";
      if (URGENCY[status] > URGENCY[known]) urgent.set(at, status);
    }
  }
  return tabs.map((tab) => {
    const parent = parentOf.get(tab.id);
    const descendants = count.get(tab.id);
    return {
      ...tab,
      ...(parent && byId.has(parent) ? { parentId: parent } : {}),
      ...(descendants ? { descendantCount: descendants, descendantStatus: urgent.get(tab.id) ?? "idle" } : {}),
    };
  });
}

export type FoldedTab = { tab: Tab; depth: number };

/**
 * What the strip shows of a family: each parent followed by its children, with
 * the children of a folded parent left out. The tab in view always shows, and
 * so does every tab it descends from, so the path to it is never hidden.
 */
export function foldFamilies(tabs: readonly Tab[], expanded: ReadonlySet<string>, activeId: string): FoldedTab[] {
  const ids = new Set(tabs.map((tab) => tab.id));
  const children = new Map<string, Tab[]>();
  const roots: Tab[] = [];
  for (const tab of tabs) {
    if (tab.parentId && ids.has(tab.parentId)) children.set(tab.parentId, [...(children.get(tab.parentId) ?? []), tab]);
    else roots.push(tab);
  }
  const open = new Set(expanded);
  const byId = new Map(tabs.map((tab) => [tab.id, tab]));
  for (let at = byId.get(activeId)?.parentId; at; at = byId.get(at)?.parentId) open.add(at);

  const out: FoldedTab[] = [];
  const walk = (tab: Tab, depth: number) => {
    out.push({ tab, depth });
    if (!open.has(tab.id)) return;
    for (const child of children.get(tab.id) ?? []) walk(child, depth + 1);
  };
  for (const root of roots) walk(root, 0);
  return out;
}

/** Every tab in family order, folded or not: a parent, then what it started. */
export function familyOrder(tabs: readonly Tab[]): FoldedTab[] {
  const all = new Set(tabs.map((tab) => tab.id));
  return foldFamilies(tabs, all, "");
}
