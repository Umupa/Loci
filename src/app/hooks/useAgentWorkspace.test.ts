// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AgentDocument } from "../../features/sessions/model/cards";
import { newSession } from "../../features/sessions/model/session";
import {
  canvasLeaf, documentLeaf, documentPaneId, leaf, leafIds, newTab,
  placeLayout, setSplitRatio, type WorkspaceTab,
} from "../../features/workspace/model/layout";
import { separateAgentWorkspaces, useAgentWorkspace, type AgentWorkspaceLayout } from "./useAgentWorkspace";

const document: AgentDocument = { id: "policy", title: "Network policy", body: "# Policy" };
const documentId = documentPaneId(document.id, "agent-a");
const onClose = vi.fn();
let root: Root | undefined;
let container: HTMLDivElement | undefined;
let workspace: ReturnType<typeof useAgentWorkspace>;

function chat(id: string) { return { ...newSession("codex", "/home/me"), id }; }

async function mount(options: { initialLayouts?: AgentWorkspaceLayout[]; initialAgentId?: string } = {}) {
  if (root) await act(async () => root!.unmount());
  container?.remove();
  container = globalThis.document.createElement("div");
  globalThis.document.body.append(container);
  root = createRoot(container);
  function Harness() { workspace = useAgentWorkspace({ onClose, ...options }); return null; }
  await act(async () => root!.render(createElement(Harness)));
}

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  onClose.mockClear();
});

afterEach(async () => {
  if (root) await act(async () => root!.unmount());
  root = undefined;
  container?.remove();
});

describe("agent conversations", () => {
  it("gives each agent its conversation alone, and returns to it", async () => {
    await mount();
    act(() => workspace.open("agent-a", chat("a")));
    expect(leafIds(workspace.layout!)).toEqual(["a"]);
    expect(workspace.currentRef.current).toBe(workspace.current);
    act(() => workspace.open("agent-b", chat("b")));
    expect(leafIds(workspace.layout!)).toEqual(["b"]);
    act(() => workspace.open("agent-a", chat("a")));
    expect(leafIds(workspace.layout!)).toEqual(["a"]);
    expect(workspace.focusedId).toBe("a");
    expect(workspace).not.toHaveProperty("tabs");
  });

  it("hides the agent when closing its conversation", async () => {
    await mount();
    act(() => workspace.open("agent-a", chat("a")));
    act(() => workspace.closePane("elsewhere"));
    expect(onClose).not.toHaveBeenCalled();
    act(() => workspace.closePane("a"));
    expect(workspace.current).toBeNull();
    expect(workspace.currentRef.current).toBeNull();
    expect(onClose).toHaveBeenCalledOnce();
  });

  it("replaces a reset conversation in place and removes a deleted agent workspace", async () => {
    await mount();
    act(() => workspace.open("agent-a", chat("old")));
    act(() => workspace.replaceSession("old", chat("fresh")));
    expect(leafIds(workspace.layout!)).toEqual(["fresh"]);
    expect(workspace.focusedId).toBe("fresh");
    act(() => workspace.forgetSession("fresh"));
    expect(workspace.current).toBeNull();
    expect(onClose).toHaveBeenCalledOnce();
    act(() => workspace.open("agent-a", chat("next")));
    expect(leafIds(workspace.layout!)).toEqual(["next"]);
  });

  it("keeps only the conversation of a saved or imported arrangement", async () => {
    const imported: AgentWorkspaceLayout = {
      agentId: "agent-a", sessionId: "a", layout: placeLayout(leaf("a"), documentLeaf(document, "agent-a"), "a", "right"), focusedId: documentId,
    };
    await mount({ initialLayouts: [imported], initialAgentId: "agent-a" });
    expect(leafIds(workspace.layout!)).toEqual(["a"]);
    expect(workspace.focusedId).toBe("a");
    const layout = placeLayout(placeLayout(leaf("b"), leaf("project"), "b", "right"), canvasLeaf("drawing"), "b", "bottom");
    localStorage.setItem("loci:agent-workspaces.v1", JSON.stringify([
      { agentId: "agent-b", sessionId: "b", layout, focusedId: "drawing" },
      { agentId: "broken" },
    ]));
    await mount({ initialAgentId: "agent-b" });
    expect(leafIds(workspace.layout!)).toEqual(["b"]);
    localStorage.setItem("loci:agent-workspaces.v1", "bad json");
    await mount();
    act(() => workspace.open("agent-a", chat("a")));
    expect(leafIds(workspace.layout!)).toEqual(["a"]);
  });
});

describe("legacy agent pane migration", () => {
  beforeEach(() => {
    localStorage.setItem("loci:agent-roster", JSON.stringify([
      { id: "agent-a", sessionId: "a", projects: [] },
      { id: "agent-b", sessionId: "b", projects: [] },
    ]));
  });

  function tab(id: string, layout: WorkspaceTab["layout"], focusedId: string): WorkspaceTab {
    return { ...newTab(focusedId), id, layout, focusedId };
  }

  it("moves an agent-only tab and all its artifacts into an independent workspace", () => {
    const layout = placeLayout(placeLayout(leaf("a"), documentLeaf(document, "agent-a"), "a", "right"), canvasLeaf("drawing"), "a", "bottom");
    const resized = setSplitRatio(layout, layout.type === "split" ? layout.id : "", 0, 0.65);
    const result = separateAgentWorkspaces([tab("legacy", resized, "drawing")]);
    expect(result.tabs).toEqual([]);
    expect(result.layouts).toEqual([{ agentId: "agent-a", sessionId: "a", layout: resized, focusedId: "drawing" }]);
  });

  it("keeps project sessions and canvases while extracting each agent's conversation and documents", () => {
    const all = [leaf("project"), leaf("a"), documentLeaf(document, "agent-a"), leaf("b"), documentLeaf(document, "agent-b"), canvasLeaf("project-canvas")];
    const layout: WorkspaceTab["layout"] = { type: "split", id: "group", dir: "right", children: all, sizes: all.map(() => 1 / all.length) };
    const result = separateAgentWorkspaces([tab("project-tab", layout, "a")]);
    expect(result.tabs).toHaveLength(1);
    expect(result.tabs[0].id).toBe("project-tab");
    expect(leafIds(result.tabs[0].layout)).toEqual(["project", "project-canvas"]);
    expect(result.tabs[0].focusedId).toBe("project");
    expect(result.layouts.map((entry) => [entry.agentId, leafIds(entry.layout)])).toEqual([
      ["agent-a", ["a", documentId]], ["agent-b", ["b", documentPaneId(document.id, "agent-b")]],
    ]);
  });

  it("combines legacy panes for the same agent without duplicating its conversation", () => {
    const first = placeLayout(leaf("a"), documentLeaf(document, "agent-a"), "a", "right");
    const second = placeLayout(leaf("a"), canvasLeaf("drawing"), "a", "right");
    const result = separateAgentWorkspaces([tab("one", first, "a"), tab("two", second, "drawing")]);
    expect(result.tabs).toEqual([]);
    expect(result.layouts).toHaveLength(1);
    expect(leafIds(result.layouts[0].layout)).toEqual(["a", "drawing", documentId]);
  });

  it("preserves ownerless project tabs and moves an agent document without a loaded chat", () => {
    const projectTab = tab("project", placeLayout(leaf("project"), canvasLeaf("project-canvas"), "project", "right"), "project");
    const documentTab = tab("document", documentLeaf(document, "agent-a"), documentId);
    const result = separateAgentWorkspaces([projectTab, documentTab]);
    expect(result.tabs).toEqual([projectTab]);
    expect(leafIds(result.layouts[0].layout)).toEqual(["a", documentId]);
    expect(result.layouts[0].focusedId).toBe(documentId);
  });
});
