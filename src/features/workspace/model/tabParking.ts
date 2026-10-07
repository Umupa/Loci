import { getComposerDraft } from "../../sessions/model/draftCache";
import { sessionDraftBlock, type Session } from "../../sessions/model/session";
import { getFileDraft } from "../../files/model/fileDrafts";
import { filePanePath, layoutLeaves, type WorkspaceTab } from "./layout";
import type { Tab } from "./tabSummary";

/**
 * Tabs holding something the user has not finished with and that closing
 * would quietly lose track of: a half-written message, a follow-up waiting in
 * the queue, an unsent draft turn, or an unsaved edit to a file.
 */
export function heldTabIds(tabs: readonly WorkspaceTab[], sessions: readonly Session[]): Set<string> {
  const held = new Set<string>();
  for (const tab of tabs) {
    for (const pane of layoutLeaves(tab.layout)) {
      if (pane.kind === "file") {
        if (getFileDraft(filePanePath(pane.id))) held.add(tab.id);
        continue;
      }
      if (pane.kind !== "session") continue;
      const session = sessions.find((entry) => entry.id === pane.id);
      if (!session) continue;
      if (getComposerDraft(session.id)?.trim() || session.queuedMessages?.length || sessionDraftBlock(session) || session.noteCard) {
        held.add(tab.id);
      }
    }
  }
  return held;
}

/** A tab that can be put away without anyone noticing it was gone. */
export function isParkable(tab: Tab, activeId: string, held: ReadonlySet<string>): boolean {
  // A parent whose started tabs are busy or waiting is still part of live work.
  return tab.id !== activeId && !tab.pinned && !tab.blank && (tab.status ?? "idle") === "idle"
    && (tab.descendantStatus ?? "idle") === "idle" && !held.has(tab.id);
}

/** Every tab "Close Idle Tabs" would take, in strip order. */
export function idleTabIds(tabs: readonly Tab[], activeId: string, held: ReadonlySet<string>): string[] {
  return tabs.filter((tab) => isParkable(tab, activeId, held)).map((tab) => tab.id);
}

/**
 * The tabs to put away so a project is back at its limit: only idle ones,
 * the longest untouched first. Tabs not seen this session are older than any
 * that were, and keep their strip order among themselves.
 */
export function parkingCandidates({ tabs, activeId, recent, held, limit }: {
  tabs: readonly Tab[];
  activeId: string;
  /** Tab ids, most recently used first. */
  recent: readonly string[];
  held: ReadonlySet<string>;
  limit: number;
}): string[] {
  const over = limit > 0 ? tabs.length - limit : 0;
  if (over <= 0) return [];
  const rank = new Map(recent.map((id, index) => [id, index]));
  return tabs
    .map((tab, order) => ({ tab, order }))
    .filter(({ tab }) => isParkable(tab, activeId, held))
    .sort((a, b) => (rank.get(b.tab.id) ?? Infinity) - (rank.get(a.tab.id) ?? Infinity) || a.order - b.order)
    .slice(0, over)
    .map(({ tab }) => tab.id);
}

/** Tabs that want the user, the most urgent first: approvals, then finished. */
export function attentionOrder(tabs: readonly Tab[], activeId: string): string[] {
  const wanting = tabs.filter((tab) => tab.id !== activeId && (tab.status === "approval" || tab.status === "done"));
  return [
    ...wanting.filter((tab) => tab.status === "approval"),
    ...wanting.filter((tab) => tab.status === "done"),
  ].map((tab) => tab.id);
}

export type TabCountMark = { project: string; count: number };

/**
 * Whether a project's tab count has grown since it was last looked at. The
 * first look, a change of project, and a count that holds or shrinks are not
 * growth: only a tab opened in the project being viewed can put it over limit.
 */
export function trackTabGrowth(before: TabCountMark | null, project: string, count: number): { mark: TabCountMark; grew: boolean } {
  return { mark: { project, count }, grew: before !== null && before.project === project && count > before.count };
}
