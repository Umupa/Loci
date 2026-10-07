import { fuzzyMatch } from "../../../shared/lib/fuzzy";
import { sameProjectPath } from "../../projects/model/recents";
import type { ClosedTab } from "./closedTabs";
import { familyOrder } from "./tabFamily";
import type { Tab } from "./tabSummary";

export type SwitcherRow =
  | { kind: "tab"; key: string; tab: Tab; current: boolean; /** How far down a family of started tabs this one sits. */ depth: number }
  | { kind: "closed"; key: string; closed: ClosedTab; /** Other tabs that were closed with it. */ alsoClosed: number };

export type SwitcherSection = { id: string; label: string; rows: SwitcherRow[] };

export type SwitcherInput = {
  tabs: readonly Tab[];
  activeId: string;
  /** The project in view: its tabs come first. */
  projectPath: string;
  /** Tab ids, most recently used first. */
  recent: readonly string[];
  closed: readonly ClosedTab[];
  query: string;
};

const MAX_CLOSED_SHOWN = 5;
const MAX_PARKED_SHOWN = 8;
const TITLE_BONUS = 400;
const PROJECT_BONUS = 150;

/** Most recently used first; tabs never used keep their strip order after them. */
export function byRecency(tabs: readonly Tab[], recent: readonly string[]): Tab[] {
  const rank = new Map(recent.map((id, index) => [id, index]));
  return tabs
    .map((tab, order) => ({ tab, order }))
    .sort((a, b) => (rank.get(a.tab.id) ?? Infinity) - (rank.get(b.tab.id) ?? Infinity) || a.order - b.order)
    .map(({ tab }) => tab);
}

function tabRow(tab: Tab, activeId: string, depth = 0): SwitcherRow {
  return { kind: "tab", key: `tab:${tab.id}`, tab, current: tab.id === activeId, depth };
}

function closedRows(closed: readonly ClosedTab[], shown = MAX_CLOSED_SHOWN): SwitcherRow[] {
  const rows: SwitcherRow[] = [];
  const seenBatches = new Map<number, number>();
  for (const entry of closed) seenBatches.set(entry.batch, (seenBatches.get(entry.batch) ?? 0) + 1);
  for (const entry of closed.slice(0, shown)) {
    rows.push({ kind: "closed", key: `closed:${entry.batch}:${entry.closedAt}:${rows.length}`, closed: entry, alsoClosed: (seenBatches.get(entry.batch) ?? 1) - 1 });
  }
  return rows;
}

function score(query: string, tab: Tab): number | null {
  const title = fuzzyMatch(query, tab.title || "New session");
  if (title) return title.score + TITLE_BONUS;
  const project = fuzzyMatch(query, tab.project);
  if (project) return project.score + PROJECT_BONUS;
  return fuzzyMatch(query, tab.preview ?? "")?.score ?? null;
}

/** What the switcher lists: what needs the user first, then this project, the rest, and what was closed. */
export function buildSwitcher(input: SwitcherInput): SwitcherSection[] {
  const { tabs, activeId, projectPath, recent, closed } = input;
  const query = input.query.trim();

  if (query) {
    const hits = tabs.flatMap((tab) => {
      const value = score(query, tab);
      return value === null ? [] : [{ tab, value }];
    }).sort((a, b) => b.value - a.value);
    const closedHits = closed.flatMap((entry) => {
      const hit = fuzzyMatch(query, entry.title || "New session");
      return hit ? [{ entry, value: hit.score }] : [];
    }).sort((a, b) => b.value - a.value);
    const sections: SwitcherSection[] = [];
    if (hits.length) sections.push({ id: "results", label: "Tabs", rows: hits.map(({ tab }) => tabRow(tab, activeId)) });
    const parkedHits = closedHits.filter(({ entry }) => entry.parked).map(({ entry }) => entry);
    const closedOnlyHits = closedHits.filter(({ entry }) => !entry.parked).map(({ entry }) => entry);
    if (parkedHits.length) sections.push({ id: "parked", label: "Parked", rows: closedRows(parkedHits, MAX_PARKED_SHOWN) });
    if (closedOnlyHits.length) sections.push({ id: "closed", label: "Recently closed", rows: closedRows(closedOnlyHits) });
    return sections;
  }

  const ordered = byRecency(tabs, recent);
  const needsYou = ordered
    .filter((tab) => tab.id !== activeId && (tab.status === "approval" || tab.status === "done"))
    .sort((a, b) => Number(b.status === "approval") - Number(a.status === "approval"));
  const flagged = new Set(needsYou.map((tab) => tab.id));
  const rest = ordered.filter((tab) => !flagged.has(tab.id));
  const here = rest.filter((tab) => tab.projectPath && sameProjectPath(tab.projectPath, projectPath));
  const elsewhere = rest.filter((tab) => !here.includes(tab));

  const sections: SwitcherSection[] = [];
  if (needsYou.length) sections.push({ id: "attention", label: "Needs you", rows: needsYou.map((tab) => tabRow(tab, activeId)) });
  // Tabs an agent started follow the tab that started them, indented.
  if (here.length) sections.push({ id: "here", label: "This project", rows: familyOrder(here).map(({ tab, depth }) => tabRow(tab, activeId, depth)) });
  const projects = new Map<string, Tab[]>();
  for (const tab of elsewhere) projects.set(tab.project, [...(projects.get(tab.project) ?? []), tab]);
  for (const [project, group] of projects) {
    sections.push({ id: `project:${project}`, label: project || "No project", rows: group.map((tab) => tabRow(tab, activeId)) });
  }
  const parked = closedRows(closed.filter((entry) => entry.parked), MAX_PARKED_SHOWN);
  if (parked.length) sections.push({ id: "parked", label: "Parked", rows: parked });
  const reopen = closedRows(closed.filter((entry) => !entry.parked));
  if (reopen.length) sections.push({ id: "closed", label: "Recently closed", rows: reopen });
  return sections;
}

export function flattenSwitcher(sections: readonly SwitcherSection[]): SwitcherRow[] {
  return sections.flatMap((section) => section.rows);
}

/**
 * The row to highlight when the switcher opens: the tab to flip back to, as in
 * an app switcher, rather than the one already in view.
 */
export function initialSelection(rows: readonly SwitcherRow[]): number {
  const index = rows.findIndex((row) => row.kind === "tab" && !row.current);
  return index >= 0 ? index : 0;
}
