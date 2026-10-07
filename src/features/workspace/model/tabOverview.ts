import { fuzzyMatch } from "../../../shared/lib/fuzzy";
import { sameProjectPath } from "../../projects/model/recents";
import { byRecency } from "./tabSwitcher";
import type { Tab, TabStatus } from "./tabSummary";

export type OverviewScope = "project" | "all";
export type OverviewCard = { tab: Tab; /** How far down a family of started tabs this card sits. */ depth: number };

const URGENCY: Record<TabStatus, number> = { approval: 3, done: 2, busy: 1, idle: 0 };

/** How much a card, with everything its family is doing, wants the user. */
function urgency(tab: Tab): number {
  return Math.max(URGENCY[tab.status ?? "idle"], URGENCY[tab.descendantStatus ?? "idle"]);
}

/** Whether a project has tabs to show, so the overview can open on the scope that is not empty. */
export function defaultScope(tabs: readonly Tab[], projectPath: string): OverviewScope {
  return tabs.some((tab) => tab.projectPath && sameProjectPath(tab.projectPath, projectPath)) ? "project" : "all";
}

/**
 * The cards of the overview. Without a search: what wants the user first, then
 * what is working, then the rest by recency, every tab followed by the tabs it
 * started. With a search: the best matches, flat.
 */
export function overviewCards({ tabs, scope, projectPath, query, recent }: {
  tabs: readonly Tab[];
  scope: OverviewScope;
  projectPath: string;
  query: string;
  recent: readonly string[];
}): OverviewCard[] {
  const inScope = scope === "all" ? [...tabs] : tabs.filter((tab) => tab.projectPath && sameProjectPath(tab.projectPath, projectPath));
  const needle = query.trim();
  if (needle) {
    return inScope.flatMap((tab) => {
      const hit = fuzzyMatch(needle, tab.title || "New session")?.score
        ?? fuzzyMatch(needle, tab.project)?.score
        ?? fuzzyMatch(needle, tab.preview ?? "")?.score;
      return hit === undefined ? [] : [{ card: { tab, depth: 0 }, hit }];
    }).sort((a, b) => b.hit - a.hit).map(({ card }) => card);
  }

  const ordered = byRecency(inScope, recent);
  const ids = new Set(ordered.map((tab) => tab.id));
  const kids = new Map<string, Tab[]>();
  const roots: Tab[] = [];
  for (const tab of ordered) {
    if (tab.parentId && ids.has(tab.parentId)) kids.set(tab.parentId, [...(kids.get(tab.parentId) ?? []), tab]);
    else roots.push(tab);
  }
  // Stable: equal urgency keeps the recency order.
  const ranked = roots.map((tab, order) => ({ tab, order })).sort((a, b) => urgency(b.tab) - urgency(a.tab) || a.order - b.order);
  const out: OverviewCard[] = [];
  const walk = (tab: Tab, depth: number) => {
    out.push({ tab, depth });
    for (const child of kids.get(tab.id) ?? []) walk(child, depth + 1);
  };
  for (const { tab } of ranked) walk(tab, 0);
  return out;
}

/** The card to move to from `index` for an arrow key, in a grid `columns` wide. */
export function moveInGrid(index: number, key: "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight", columns: number, count: number): number {
  if (count === 0) return 0;
  const step = key === "ArrowLeft" ? -1 : key === "ArrowRight" ? 1 : key === "ArrowUp" ? -columns : columns;
  const next = index + step;
  // Off the top or bottom stays put; sideways wraps onto the neighbouring row.
  if (key === "ArrowUp" || key === "ArrowDown") return next < 0 || next >= count ? index : next;
  return Math.min(count - 1, Math.max(0, next));
}
