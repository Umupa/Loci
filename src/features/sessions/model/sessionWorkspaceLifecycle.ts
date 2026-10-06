import {
  closeLeaf,
  leafIds,
  type WorkspaceTab,
} from "../../workspace/model/layout";
import type { Session } from "./session";
import {
  planWorkspaceTabClose,
  type WorkspaceTabCloseScope,
} from "../../workspace/model/workspaceTabGroups";

export type SessionWorkspaceRemoval = {
  tabs: WorkspaceTab[];
  sessions: Session[];
  activeTabId: string;
  closedTabs: WorkspaceTab[];
};

export function removeSessionFromWorkspace({
  tabs,
  sessions,
  sessionId,
  activeTabId,
  scope,
  createReplacement,
  canCloseTab = () => true,
}: {
  tabs: WorkspaceTab[];
  sessions: Session[];
  sessionId: string;
  activeTabId: string;
  scope: WorkspaceTabCloseScope;
  createReplacement: (seed: Session | undefined) => Session;
  /** Preserve panes changed while an asynchronous close was pending. */
  canCloseTab?: (tab: WorkspaceTab) => boolean;
}): SessionWorkspaceRemoval {
  const seed = sessions.find((session) => session.id === sessionId);
  let nextTabs = [...tabs];
  let nextSessions = sessions.filter((session) => session.id !== sessionId);
  const remainingSessionIds = new Set(
    nextSessions.map((session) => session.id),
  );
  let nextActiveTabId = activeTabId;
  const closedTabs: WorkspaceTab[] = [];

  for (const original of tabs) {
    const hadSession = leafIds(original.layout).includes(sessionId);
    const index = nextTabs.findIndex((tab) => tab.id === original.id);
    if (index < 0) continue;

    if (!hadSession) continue;
    const tab = original;
    const remainingConversations = leafIds(tab.layout).some((id) =>
      remainingSessionIds.has(id),
    );

    if (remainingConversations || !canCloseTab(original)) {
      const next = closeLeaf(tab, sessionId);
      if (next) nextTabs[index] = next;
      if (next) continue;
    }

    closedTabs.push(original);
    const closePlan = planWorkspaceTabClose({
      tabs: nextTabs,
      sessions,
      closingTabId: tab.id,
      scope,
    });
    if (closePlan.action === "close") {
      nextTabs = nextTabs.filter((entry) => entry.id !== tab.id);
      if (tab.id === nextActiveTabId && closePlan.nextActiveTabId) {
        nextActiveTabId = closePlan.nextActiveTabId;
      }
      continue;
    }

    const replacement = createReplacement(seed);
    remainingSessionIds.add(replacement.id);
    nextSessions = [...nextSessions, replacement];
    nextTabs[index] = {
      ...tab,
      layout: { type: "leaf", id: replacement.id },
      focusedId: replacement.id,
    };
  }

  return {
    tabs: nextTabs,
    sessions: nextSessions,
    activeTabId: nextActiveTabId,
    closedTabs,
  };
}
