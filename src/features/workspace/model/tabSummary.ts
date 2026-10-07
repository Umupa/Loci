import { basename } from "../../../platform/tauri/fs";
import { projectName } from "../../../shared/lib/paths";
import { isBlankSession } from "../../projects/model/projectReturn";
import { sessionDisplayTitle, type HarnessId, type Session } from "../../sessions/model/session";
import { filePanePath, findLeaf, leafIds, type WorkspaceTab } from "./layout";

/** What a tab is waiting on, most urgent first. */
export type TabStatus = "approval" | "busy" | "done" | "idle";

export type Tab = {
  id: string;
  /** Project folder name, e.g. `my-project`. */
  project: string;
  /** Project folder this tab belongs to; absent before any project is picked. */
  projectPath?: string;
  /** Focused conversation title; empty for a fresh session. */
  title: string;
  /** Other conversation titles in this tab, focused session omitted. */
  more: string[];
  sessionCount: number;
  paneKind?: "canvas" | "file";
  harnesses: HarnessId[];
  /** Harnesses with an in-flight turn in this tab. */
  busyHarnesses: HarnessId[];
  /** Harnesses with a finished response that has not been focused yet. */
  doneHarnesses?: HarnessId[];
  /** Split layout with more than one pane in this tab. */
  multiPane?: boolean;
  /** The sole pane is a fresh conversation with no user turn. */
  blank?: boolean;
  /** Explicit tab group; absent means ungrouped. */
  groupId?: string;
  /** Kept at the left as an icon, and spared by the bulk close actions. */
  pinned?: boolean;
  status?: TabStatus;
  /** The latest thing said in the tab, for the hover card and the switcher. */
  preview?: string;
  /** When the current turn started, while it is running. */
  busySince?: number;
  /** When the tab last did something, if known. */
  activityAt?: number;
  /** The session that started this tab's conversation, when an agent did. */
  spawnedBy?: string;
  /** The open tab holding the session that started this one. */
  parentId?: string;
  /** Tabs started, directly or further down, from this one. */
  descendantCount?: number;
  /** The most urgent state among those tabs, for a parent that folds them away. */
  descendantStatus?: TabStatus;
};

export type TabSummaryContext = {
  sessions: readonly Session[];
  canvasTitle: (canvasId: string) => string | undefined;
  /** Sessions waiting on an approval or an answer. */
  needsInput: ReadonlySet<string>;
  /** Sessions that finished while nobody was looking. */
  unseenFinished: ReadonlySet<string>;
  /** Project of tabs that have no session of their own. */
  fallbackCwd: string;
};

const PREVIEW_CHARS = 240;
const PREVIEW_SOURCE_CHARS = 700;

/** One readable line of what a session last said, with markdown noise removed. */
export function sessionPreview(session: Pick<Session, "blocks">): string {
  const clean = (text: string) => text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/^\s{0,3}(?:#{1,6}|[>*+-]|\d+\.)\s+/gm, "")
    .replace(/[*_`~]+/g, "")
    .replace(/\s+/g, " ")
    .trim();
  for (const role of ["assistant", "user"] as const) {
    for (let index = session.blocks.length - 1; index >= 0; index -= 1) {
      const block = session.blocks[index];
      if (block.role !== role || block.draft) continue;
      // Streaming replies are long; the opening is stable and all a preview needs.
      const text = clean(block.text.slice(0, PREVIEW_SOURCE_CHARS));
      if (text) return text.length > PREVIEW_CHARS ? `${text.slice(0, PREVIEW_CHARS - 1)}…` : text;
    }
  }
  return "";
}

/** When a session last did something: the end of its newest user turn. */
function sessionActivityAt(session: Pick<Session, "blocks">): number | undefined {
  for (let index = session.blocks.length - 1; index >= 0; index -= 1) {
    const block = session.blocks[index];
    if (block.role === "user" && block.startedAt) return block.startedAt + (block.durationMs ?? 0);
  }
  return undefined;
}

function busyStart(session: Pick<Session, "blocks">): number | undefined {
  for (let index = session.blocks.length - 1; index >= 0; index -= 1) {
    const block = session.blocks[index];
    if (block.role === "user" && block.startedAt) return block.startedAt;
  }
  return undefined;
}

const SPAWNED_ID = /^app-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-/i;

/** The session that started this one, read from the id an agent-started session is given. */
export function spawnerOf(sessionId: string): string | undefined {
  return SPAWNED_ID.exec(sessionId)?.[1];
}

const unique = <T,>(items: T[]): T[] => [...new Set(items)];

export function summarizeTab(tab: WorkspaceTab, context: TabSummaryContext): Tab {
  const entries = leafIds(tab.layout).flatMap((id) => context.sessions.find((session) => session.id === id) ?? []);
  const focusedSession = entries.find((entry) => entry.id === tab.focusedId) ?? entries[0];
  const focusedLeaf = findLeaf(tab.layout, tab.focusedId);
  const path = focusedSession?.cwd ?? tab.cwd ?? context.fallbackCwd;

  const approval = entries.filter((entry) => context.needsInput.has(entry.id));
  const busy = entries.filter((entry) => entry.busy);
  const done = entries.filter((entry) => context.unseenFinished.has(entry.id));
  const status: TabStatus = approval.length ? "approval" : busy.length ? "busy" : done.length ? "done" : "idle";
  // The preview comes from whichever conversation explains the tab's status.
  const subject = (approval[0] ?? busy[0] ?? done[0] ?? focusedSession) as Session | undefined;

  const title = focusedLeaf?.leafKind === "canvas" ? context.canvasTitle(focusedLeaf.id) ?? "Excalidraw"
    : focusedLeaf?.leafKind === "file" ? basename(filePanePath(focusedLeaf.id))
      : focusedSession ? sessionDisplayTitle(focusedSession.title, focusedSession.harness) : "";
  const activity = entries.map(sessionActivityAt).filter((at): at is number => at !== undefined);

  const spawnedBy = entries.map((entry) => spawnerOf(entry.id)).find((id): id is string => !!id);
  return {
    id: tab.id,
    project: projectName(path),
    projectPath: path,
    title,
    more: entries
      .filter((entry) => entry.id !== focusedSession?.id)
      .map((entry) => sessionDisplayTitle(entry.title, entry.harness)),
    sessionCount: entries.length,
    ...(focusedLeaf?.leafKind ? { paneKind: focusedLeaf.leafKind } : {}),
    harnesses: unique(entries.map((entry) => entry.harness)),
    busyHarnesses: unique(busy.map((entry) => entry.harness)),
    doneHarnesses: unique(done.map((entry) => entry.harness)),
    multiPane: leafIds(tab.layout).length > 1,
    blank: entries.length === 1 && leafIds(tab.layout).length === 1 && isBlankSession(focusedSession),
    ...(tab.groupId ? { groupId: tab.groupId } : {}),
    ...(tab.pinned ? { pinned: true } : {}),
    ...(spawnedBy ? { spawnedBy } : {}),
    status,
    ...(subject ? { preview: sessionPreview(subject) } : {}),
    ...(busy.length ? { busySince: busyStart(busy[0]) } : {}),
    ...(activity.length ? { activityAt: Math.max(...activity) } : {}),
  };
}

/** "now", "5m", "3h", "2d": how long ago, as short as it can be said. */
export function shortAge(ms: number): string {
  const minutes = Math.floor(Math.max(0, ms) / 60_000);
  if (minutes < 1) return "now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

function duration(ms: number): string {
  const seconds = Math.floor(Math.max(0, ms) / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  return minutes < 60 ? `${minutes}m ${seconds % 60}s` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

/** What a tab is up to, in words: the line under its title on the hover card. */
export function tabStatusLabel(tab: Pick<Tab, "status" | "busySince" | "activityAt" | "blank">, now: number): string {
  switch (tab.status) {
    case "approval":
      return "Needs your approval";
    case "busy":
      return tab.busySince ? `Working · ${duration(now - tab.busySince)}` : "Working";
    case "done":
      return "Finished · not yet seen";
    default:
      if (tab.blank) return "New session";
      return tab.activityAt ? `Idle · ${shortAge(now - tab.activityAt)} ago` : "Idle";
  }
}
