// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AgentDocument } from "../../features/sessions/model/cards";
import { newSession } from "../../features/sessions/model/session";
import {
  canvasLeaf, documentLeaf, documentPaneId, findLeaf, layoutLeaves, leaf, leafIds, newTab,
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

describe("independent agent pane layouts", () => {
  it("gives each agent its own conversation and artifact arrangement", async () => {
    await mount();
    act(() => {
      workspace.open("agent-a", chat("a"));
      workspace.showDocument(document);
      workspace.showCanvas("drawing");
    });
    const firstLayout = workspace.layout;
    expect(leafIds(workspace.layout!)).toEqual(["a", documentId, "drawing"]);
    expect(workspace.currentRef.current).toBe(workspace.current);
    act(() => workspace.open("agent-b", chat("b")));
    expect(leafIds(workspace.layout!)).toEqual(["b"]);
    act(() => workspace.open("agent-a", chat("a")));
    expect(workspace.layout).toEqual(firstLayout);
    expect(workspace.focusedId).toBe("a");
    expect(workspace).not.toHaveProperty("tabs");
  });

  it("reuses a document pane and keeps multiple documents alongside the chat", async () => {
    await mount();
    act(() => {
      workspace.open("agent-a", chat("a"));
      workspace.showDocument(document);
      workspace.showDocument({ ...document, id: "other" });
      workspace.showDocument({ ...document, body: "Revised" });
    });
    expect(leafIds(workspace.layout!)).toEqual(["a", documentId, documentPaneId("other", "agent-a")]);
    expect(findLeaf(workspace.layout!, documentId)?.document?.body).toBe("Revised");
    expect(workspace.focusedId).toBe(documentId);
    act(() => workspace.closePane(documentId));
    expect(leafIds(workspace.layout!)).toEqual(["a", documentPaneId("other", "agent-a")]);
    expect(leafIds(workspace.layout!)).toContain(workspace.focusedId);
    expect(onClose).not.toHaveBeenCalled();
  });

  it("hides the agent when closing its conversation and restores its panes on return", async () => {
    await mount();
    act(() => { workspace.open("agent-a", chat("a")); workspace.showDocument(document); });
    const layout = workspace.layout;
    act(() => workspace.closePane("a"));
    expect(workspace.current).toBeNull();
    expect(workspace.currentRef.current).toBeNull();
    expect(onClose).toHaveBeenCalledOnce();
    act(() => workspace.open("agent-a", chat("a")));
    expect(workspace.layout).toEqual(layout);
  });

  it("restores pane moves and sash sizes, with the agent's current conversation", async () => {
    await mount();
    act(() => {
      workspace.open("agent-a", chat("old"));
      workspace.showDocument(document);
      workspace.showCanvas("drawing");
      workspace.movePane(documentId, "old", "bottom");
    });
    const layout = workspace.layout!;
    expect(layout.type).toBe("split");
    if (layout.type !== "split") throw new Error("Expected a split layout");
    act(() => workspace.setRatio(layout.id, 0, 0.7));
    const saved = workspace.layout;
    await mount();
    expect(workspace.current).toBeNull();
    act(() => workspace.open("agent-a", chat("fresh")));
    expect(leafIds(workspace.layout!)).toEqual(["fresh", documentId, "drawing"]);
    expect(workspace.layout?.type === "split" && workspace.layout.sizes).toEqual(saved?.type === "split" && saved.sizes);
    expect(workspace.layout?.type === "split" && workspace.layout.sizes[0]).toBeCloseTo(0.7);
    expect(findLeaf(workspace.layout!, documentId)?.document).toEqual(document);
    expect(saved?.type === "split" && workspace.layout?.type === "split" && workspace.layout.id).toBe(saved.id);
  });

  it("replaces a reset conversation in place and removes a deleted agent workspace", async () => {
    await mount();
    act(() => { workspace.open("agent-a", chat("old")); workspace.showDocument(document); });
    const original = workspace.layout;
    act(() => workspace.replaceSession("old", chat("fresh")));
    expect(leafIds(workspace.layout!)).toEqual(["fresh", documentId]);
    expect(workspace.layout?.type === "split" && workspace.layout.id).toBe(original?.type === "split" && original.id);
    expect(workspace.focusedId).toBe(documentId);
    act(() => workspace.forgetSession("fresh"));
    expect(workspace.current).toBeNull();
    expect(onClose).toHaveBeenCalledOnce();
    act(() => workspace.open("agent-a", chat("next")));
    expect(leafIds(workspace.layout!)).toEqual(["next"]);
  });

  it("shows generated canvases beside their agent without changing the selected pane", async () => {
    await mount();
    act(() => { workspace.open("agent-a", chat("a")); workspace.showDocument(document); });
    act(() => workspace.showCanvasForSession("first", "a"));
    expect(workspace.focusedId).toBe(documentId);
    expect(workspace.isCanvasOpen("first")).toBe(true);
    act(() => workspace.open("agent-b", chat("b")));
    act(() => workspace.showCanvasForSession("second", "a"));
    expect(leafIds(workspace.layout!)).toEqual(["b"]);
    act(() => workspace.open("agent-a", chat("a")));
    expect(layoutLeaves(workspace.layout!).filter((pane) => pane.kind === "canvas").map((pane) => pane.id)).toEqual(["second"]);
  });

  it("imports the legacy active agent only once and keeps a saved layout on later boots", async () => {
    const imported: AgentWorkspaceLayout = {
      agentId: "agent-a", sessionId: "a", layout: placeLayout(leaf("a"), documentLeaf(document, "agent-a"), "a", "right"), focusedId: documentId,
    };
    await mount({ initialLayouts: [imported], initialAgentId: "agent-a" });
    expect(workspace.current).toEqual(imported);
    act(() => workspace.showCanvas("drawing"));
    const saved = workspace.layout;
    await mount({ initialLayouts: [imported], initialAgentId: "agent-a" });
    expect(workspace.layout).toEqual(saved);
  });

  it("sanitizes restored layout data and excludes unrelated session panes", async () => {
    const layout = placeLayout(placeLayout(leaf("a"), leaf("project"), "a", "right"), documentLeaf(document, "agent-a"), "a", "bottom");
    localStorage.setItem("loci:agent-workspaces.v1", JSON.stringify([
      { agentId: "agent-a", sessionId: "a", layout, focusedId: "missing" },
      { agentId: "broken", sessionId: "broken", layout: { type: "split" } },
    ]));
    await mount({ initialAgentId: "agent-a" });
    expect(leafIds(workspace.layout!)).toEqual(["a", documentId]);
    expect(workspace.focusedId).toBe("a");
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
