import { useCallback, useEffect, useRef, useState } from "react";
import { agentForSession, findAgent } from "../../features/agents/model/agent";
import type { Session } from "../../features/sessions/model/session";
import { firstLeafId, layoutLeaves, leaf, leafIds, placeLayout, type LayoutNode, type WorkspaceTab } from "../../features/workspace/model/layout";

export type AgentWorkspaceLayout = {
  agentId: string;
  sessionId: string;
  layout: LayoutNode;
  focusedId: string;
};

const STORAGE_KEY = "loci:agent-workspaces.v1";

function pruneLayout(node: LayoutNode, keep: (node: Extract<LayoutNode, { type: "leaf" }>) => boolean): LayoutNode | null {
  if (node.type === "leaf") return keep(node) ? node : null;
  const kept = node.children.flatMap((child, index) => {
    const layout = pruneLayout(child, keep);
    return layout ? [{ layout, size: node.sizes[index] }] : [];
  });
  if (!kept.length) return null;
  if (kept.length === 1) return kept[0].layout;
  const total = kept.reduce((sum, entry) => sum + entry.size, 0);
  return {
    ...node, children: kept.map((entry) => entry.layout),
    sizes: kept.map((entry) => total > 0 ? entry.size / total : 1 / kept.length),
  };
}

/** Move legacy agent panes out of project tabs, preserving the artifacts around them. */
export function separateAgentWorkspaces(tabs: readonly WorkspaceTab[]): { tabs: WorkspaceTab[]; layouts: AgentWorkspaceLayout[] } {
  const layouts = new Map<string, AgentWorkspaceLayout>();
  const remaining: WorkspaceTab[] = [];
  for (const tab of tabs) {
    const leaves = layoutLeaves(tab.layout);
    const agentOwners = new Map(leaves.flatMap((pane) => {
      const agent = pane.kind === "session" ? agentForSession(pane.id)
        : (pane.kind === "document" || pane.kind === "course" || pane.kind === "note") && pane.agentId ? findAgent(pane.agentId) : undefined;
      return agent?.sessionId ? [[agent.id, agent.sessionId] as const] : [];
    }));
    const firstAgentId = agentOwners.keys().next().value as string | undefined;
    if (!firstAgentId) { remaining.push(tab); continue; }
    const hasProjectSession = leaves.some((pane) => pane.kind === "session" && !agentForSession(pane.id));
    const ownerOf = (pane: Extract<LayoutNode, { type: "leaf" }>) => {
      if (!pane.leafKind) return agentForSession(pane.id)?.id;
      if ((pane.leafKind === "document" || pane.leafKind === "course" || pane.leafKind === "note") && pane.agentId && agentOwners.has(pane.agentId)) return pane.agentId;
      return hasProjectSession ? undefined : firstAgentId;
    };
    for (const [agentId, sessionId] of agentOwners) {
      let layout = pruneLayout(tab.layout, (pane) => ownerOf(pane) === agentId);
      if (!layout) continue;
      if (!leafIds(layout).includes(sessionId)) layout = placeLayout(layout, leaf(sessionId), firstLeafId(layout), "left");
      const existing = layouts.get(agentId);
      if (existing) {
        const ids = new Set(leafIds(existing.layout));
        const incoming = pruneLayout(layout, (pane) => !ids.has(pane.id));
        if (incoming) layouts.set(agentId, {
          ...existing, layout: placeLayout(existing.layout, incoming, existing.focusedId, "right"),
        });
      } else {
        layouts.set(agentId, {
          agentId, sessionId, layout,
          focusedId: leafIds(layout).includes(tab.focusedId) ? tab.focusedId : sessionId,
        });
      }
    }
    const layout = pruneLayout(tab.layout, (pane) => !ownerOf(pane));
    if (layout) remaining.push({ ...tab, layout,
      focusedId: leafIds(layout).includes(tab.focusedId) ? tab.focusedId : firstLeafId(layout),
    });
  }
  return { tabs: remaining, layouts: [...layouts.values()] };
}

/**
 * An agent's workspace is its conversation alone: whatever it reads opens in
 * the overview beside it and replaces what was there, so panes never pile up.
 */
function conversationOnly(agentId: string, sessionId: string): AgentWorkspaceLayout {
  return { agentId, sessionId, layout: leaf(sessionId), focusedId: sessionId };
}

function loadLayouts(initial: readonly AgentWorkspaceLayout[]): Map<string, AgentWorkspaceLayout> {
  const layouts = new Map<string, AgentWorkspaceLayout>();
  try {
    const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]") as unknown;
    if (Array.isArray(raw)) for (const item of raw) {
      if (!item || typeof item !== "object") continue;
      const value = item as Record<string, unknown>;
      if (typeof value.agentId !== "string" || !value.agentId || typeof value.sessionId !== "string" || !value.sessionId) continue;
      layouts.set(value.agentId, conversationOnly(value.agentId, value.sessionId));
    }
  } catch {
    // An unreadable saved layout does not prevent the agent's conversation from opening.
  }
  for (const workspace of initial) if (!layouts.has(workspace.agentId)) layouts.set(workspace.agentId, conversationOnly(workspace.agentId, workspace.sessionId));
  return layouts;
}

type Options = {
  onClose: () => void;
  initialLayouts?: readonly AgentWorkspaceLayout[];
  initialAgentId?: string;
};

/** Each agent keeps its conversation independently of project/session tabs. */
export function useAgentWorkspace(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const [layouts, setLayouts] = useState(() => loadLayouts(options.initialLayouts ?? []));
  const layoutsRef = useRef(layouts);
  const [activeAgentId, setActiveAgentId] = useState<string | null>(() =>
    options.initialAgentId && layouts.has(options.initialAgentId) ? options.initialAgentId : null);
  const activeAgentIdRef = useRef(activeAgentId);
  const currentRef = useRef<AgentWorkspaceLayout | null>(activeAgentId ? layouts.get(activeAgentId) ?? null : null);
  const [composerFocusToken, focusComposer] = useState(0);

  const updateLayouts = useCallback((update: (current: Map<string, AgentWorkspaceLayout>) => Map<string, AgentWorkspaceLayout>) => {
    const next = update(layoutsRef.current);
    layoutsRef.current = next;
    currentRef.current = activeAgentIdRef.current ? next.get(activeAgentIdRef.current) ?? null : null;
    setLayouts(next);
  }, []);

  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify([...layouts.values()])); }
    catch { /* The arrangement stays available for this app session if storage is full. */ }
  }, [layouts]);

  const open = useCallback((agentId: string, session: Session) => {
    updateLayouts((current) => new Map(current).set(agentId, conversationOnly(agentId, session.id)));
    activeAgentIdRef.current = agentId;
    currentRef.current = layoutsRef.current.get(agentId)!;
    setActiveAgentId(agentId);
    focusComposer((token) => token + 1);
  }, [updateLayouts]);

  const hide = useCallback(() => {
    activeAgentIdRef.current = null;
    currentRef.current = null;
    setActiveAgentId(null);
  }, []);

  const focusPane = useCallback(() => focusComposer((token) => token + 1), []);

  const closePane = useCallback((id: string) => {
    const current = activeAgentIdRef.current && layoutsRef.current.get(activeAgentIdRef.current);
    if (!current || id !== current.sessionId) return;
    hide();
    latest.current.onClose();
  }, [hide]);

  const replaceSession = useCallback((previousId: string, fresh: Session) => {
    updateLayouts((current) => new Map([...current].map(([id, workspace]) => [id,
      workspace.sessionId === previousId ? conversationOnly(workspace.agentId, fresh.id) : workspace])));
  }, [updateLayouts]);

  const forgetSession = useCallback((id: string) => {
    const agentId = [...layoutsRef.current.values()].find((workspace) => workspace.sessionId === id)?.agentId;
    if (!agentId) return;
    updateLayouts((current) => { const next = new Map(current); next.delete(agentId); return next; });
    if (activeAgentIdRef.current === agentId) {
      hide();
      latest.current.onClose();
    }
  }, [hide, updateLayouts]);

  const current = activeAgentId ? layouts.get(activeAgentId) ?? null : null;
  currentRef.current = current;
  return {
    activeAgentId, current, currentRef, layout: current?.layout, focusedId: current?.focusedId,
    composerFocusToken, open, hide, focusPane, closePane, replaceSession, forgetSession,
  };
}
