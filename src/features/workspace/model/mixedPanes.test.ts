import { describe, expect, it } from "vitest";
import { newSession } from "../../sessions/model/session";
import { canvasLeaf, findLeaf, layoutLeaves, leaf, leafIds, newTab, placeLayout, setSplitRatio, showCanvasBeside, showCanvasForSession, splitPane, type WorkspaceTab } from "./layout";
import { applyDetachPaneToTab, applyMoveWorkspacePane, applyPlaceTabOnPane, filterTabsForProject } from "./workspaceTabGroups";
import { collectWorkspaceSnapshot, hydrateWorkspaceSnapshot } from "./workspaceSnapshot";

function canvasTab(): WorkspaceTab {
  return { ...newTab("drawing"), id: "drawing-tab", cwd: "/project", layout: canvasLeaf("drawing") };
}

describe("mixed workspace panes", () => {
  it("lists a canvas-only tab in its project without a fabricated session", () => {
    expect(filterTabsForProject([canvasTab()], [], "/project")).toHaveLength(1);
    expect(filterTabsForProject([canvasTab()], [], "/other")).toHaveLength(0);
  });

  it("moves a canvas tab beside a chat, resizes it, and detaches it with its type and project intact", () => {
    const session = { ...newSession("codex", "/project"), id: "chat" };
    const chatTab = { ...newTab(session.id), id: "chat-tab" };
    const merged = applyPlaceTabOnPane({ tabs: [chatTab, canvasTab()], sessions: [session], sourceTabId: "drawing-tab", targetId: "chat", edge: "right", replaceTarget: false })!;
    expect(layoutLeaves(merged.tabs[0].layout).map((pane) => pane.kind)).toEqual(["session", "canvas"]);
    const layout = merged.tabs[0].layout;
    expect(layout.type).toBe("split");
    const resized = setSplitRatio(layout, layout.id, 0, 0.35);
    expect(layoutLeaves(resized)[1].rect.w).toBeCloseTo(0.65);
    const detached = applyDetachPaneToTab({ tabs: [{ ...merged.tabs[0], layout: resized }], paneId: "drawing", targetTabId: "chat-tab", position: "after" })!;
    expect(detached.tabs[1].layout).toEqual(canvasLeaf("drawing"));
    expect(detached.tabs[1].cwd).toBe("/project");
    expect(filterTabsForProject(detached.tabs, [session], "/project")).toHaveLength(2);
  });

  it("shows an agent's drawing beside its session, reusing the tab's canvas pane and keeping focus", () => {
    const chat = { ...newTab("chat"), id: "chat-tab" };
    const shown = showCanvasBeside(chat, "first", "chat");
    expect(layoutLeaves(shown.layout).map((pane) => [pane.id, pane.kind])).toEqual([["chat", "session"], ["first", "canvas"]]);
    expect(layoutLeaves(shown.layout)[1].rect.x).toBeCloseTo(0.5);
    expect(shown.focusedId).toBe("chat");
    // A second drawing takes the first one's place rather than a third pane.
    const next = showCanvasBeside(shown, "second", "chat");
    expect(leafIds(next.layout)).toEqual(["chat", "second"]);
    expect(findLeaf(next.layout, "second")).toEqual(canvasLeaf("second"));
    // If the user was working in the replaced drawing, focus follows the new one.
    expect(showCanvasBeside({ ...shown, focusedId: "first" }, "second", "chat").focusedId).toBe("second");
    // Already visible, or the session lives in another tab: nothing moves.
    expect(showCanvasBeside(next, "second", "chat")).toBe(next);
    expect(showCanvasBeside(chat, "first", "elsewhere")).toBe(chat);
    // Other panes of a split tab are untouched.
    const split = { ...chat, layout: splitPane(chat.layout, "chat", "down", "other-chat") };
    expect(layoutLeaves(showCanvasBeside(split, "first", "chat").layout).map((pane) => pane.id).sort()).toEqual(["chat", "first", "other-chat"]);
  });

  it("brings a drawing that is open in another tab to the session being watched", () => {
    const claude = showCanvasBeside({ ...newTab("claude"), id: "claude-tab" }, "drawing", "claude");
    const codex = { ...newTab("codex"), id: "codex-tab" };
    const alone = canvasTab();
    // Codex draws on it while its tab is in front: the single pane moves there.
    const moved = showCanvasForSession([claude, codex], "codex-tab", "drawing", "codex");
    expect(moved.map((tab) => leafIds(tab.layout))).toEqual([["claude"], ["codex", "drawing"]]);
    expect(moved[1].focusedId).toBe("codex");
    // A tab that held only the drawing closes rather than staying empty.
    expect(showCanvasForSession([alone, codex], "codex-tab", "drawing", "codex").map((tab) => tab.id)).toEqual(["codex-tab"]);
    // A session working in the background does not rearrange what the user is looking at.
    const tabs = [claude, codex];
    expect(showCanvasForSession(tabs, "claude-tab", "drawing", "codex")).toBe(tabs);
    expect(showCanvasForSession(tabs, "claude-tab", "drawing", "claude")).toBe(tabs);
    expect(showCanvasForSession(tabs, "codex-tab", "drawing", "unknown")).toBe(tabs);
    // Not open anywhere: it opens beside the session even in a background tab.
    expect(showCanvasForSession([codex], "other-tab", "new-drawing", "codex").map((tab) => leafIds(tab.layout))).toEqual([["codex", "new-drawing"]]);
  });

  it("moves a canvas pane between tabs without replacing its kind", () => {
    const incoming = canvasLeaf("drawing");
    const source = { ...canvasTab(), layout: placeLayout(incoming, leaf("left"), "drawing", "left") };
    const target = { ...newTab("right"), id: "target", cwd: "/project" };
    const moved = applyMoveWorkspacePane([source, target], "drawing", "right", "bottom")!;
    expect(leafIds(moved[0].layout)).toEqual(["left"]);
    expect(findLeaf(moved[1].layout, "drawing")).toEqual(incoming);
    const reordered = applyMoveWorkspacePane(moved, "drawing", "right", "left")!;
    expect(findLeaf(reordered[1].layout, "drawing")).toEqual(incoming);
  });

  it("round-trips mixed panes and canvas-only tabs without hydrating fake conversations", () => {
    const session = { ...newSession("codex", "/project"), id: "chat" };
    const mixed = { ...newTab("chat"), cwd: "/project", layout: placeLayout(leaf("chat"), canvasLeaf("second-drawing"), "chat", "right") };
    const snapshot = collectWorkspaceSnapshot([mixed, canvasTab()], [session], "drawing-tab", "/project", new Map());
    const resumed = hydrateWorkspaceSnapshot(JSON.parse(JSON.stringify(snapshot)), new Map())!;
    expect(resumed.tabs.map((tab) => tab.layout)).toEqual([mixed.layout, canvasLeaf("drawing")]);
    expect(resumed.sessions.map((entry) => entry.id)).toEqual(["chat"]);
    expect(resumed.tabs[1].cwd).toBe("/project");
  });
});
