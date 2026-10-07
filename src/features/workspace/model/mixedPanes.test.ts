import { describe, expect, it } from "vitest";
import { newSession } from "../../sessions/model/session";
import { canvasLeaf, fileLeaf, filePaneId, findLeaf, layoutLeaves, placeFileOnPane, rebaseFilePanes, showCanvasInTab, showFileInTab, leaf, leafIds, newTab, placeLayout, setSplitRatio, showCanvasBeside, showCanvasForSession, splitPane, type WorkspaceTab } from "./layout";
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

  it("previews files in one reused pane until a file is pinned", () => {
    const chat = { ...newTab("chat"), id: "chat-tab" };
    const first = showFileInTab(chat, "/project/a.md", false);
    expect(layoutLeaves(first.layout).map((pane) => [pane.id, pane.kind, !!pane.preview])).toEqual([["chat", "session", false], [filePaneId("/project/a.md"), "file", true]]);
    expect(first.focusedId).toBe(filePaneId("/project/a.md"));

    // The next single click takes over the preview pane instead of splitting again.
    const second = showFileInTab(first, "/project/b.pdf", false);
    expect(leafIds(second.layout)).toEqual(["chat", filePaneId("/project/b.pdf")]);

    // Pinning keeps that pane, so the following preview opens beside it.
    const pinned = showFileInTab(second, "/project/b.pdf", true);
    expect(findLeaf(pinned.layout, filePaneId("/project/b.pdf"))).toEqual(fileLeaf("/project/b.pdf"));
    const third = showFileInTab(pinned, "/project/c.png", false);
    expect(leafIds(third.layout)).toEqual(["chat", filePaneId("/project/b.pdf"), filePaneId("/project/c.png")]);

    // Reopening a pinned file only focuses it; it never becomes a preview again.
    const again = showFileInTab(third, "/project/b.pdf", false);
    expect(again.layout).toBe(third.layout);
    expect(again.focusedId).toBe(filePaneId("/project/b.pdf"));
  });

  it("places a dragged file on a pane edge and moves its pane when it is already open", () => {
    const chat = { ...newTab("chat"), id: "chat-tab" };
    const preview = showFileInTab(chat, "/project/a.md", false);
    const placed = placeFileOnPane(preview, "/project/a.md", "chat", "left");
    expect(layoutLeaves(placed.layout).map((pane) => [pane.id, !!pane.preview])).toEqual([[filePaneId("/project/a.md"), false], ["chat", false]]);
    expect(placeFileOnPane(placed, "/project/a.md", filePaneId("/project/a.md"), "top")).toBe(placed);
  });

  it("keeps file panes on a renamed folder's files and leaves other panes alone", () => {
    const tab = showFileInTab({ ...newTab("chat"), id: "chat-tab" }, "/project/papers/a.pdf", true);
    const rebase = (path: string) => path.replace("/project/papers", "/project/reading");
    const moved = rebaseFilePanes(tab, rebase);
    expect(leafIds(moved.layout)).toEqual(["chat", filePaneId("/project/reading/a.pdf")]);
    expect(moved.focusedId).toBe(filePaneId("/project/reading/a.pdf"));
    expect(rebaseFilePanes(moved, rebase)).toBe(moved);
  });

  it("opens a sidebar drawing in the tab's canvas pane and restores file panes with their preview state", () => {
    const session = { ...newSession("codex", "/project"), id: "chat" };
    const chat = { ...newTab("chat"), id: "chat-tab", cwd: "/project" };
    const first = showCanvasInTab(chat, "first");
    const second = showCanvasInTab(first, "second");
    expect(layoutLeaves(second.layout).map((pane) => [pane.id, pane.kind])).toEqual([["chat", "session"], ["second", "canvas"]]);
    expect(second.focusedId).toBe("second");

    const withFile = showFileInTab(second, "/project/a.md", false);
    const snapshot = collectWorkspaceSnapshot([withFile], [session], "chat-tab", "/project", new Map());
    const restored = hydrateWorkspaceSnapshot(JSON.parse(JSON.stringify(snapshot)), new Map())!;
    expect(restored.tabs[0].layout).toEqual(withFile.layout);
    expect(restored.sessions.map((entry) => entry.id)).toEqual(["chat"]);
  });

  it("keeps a pinned tab pinned across a restart, and only that tab", () => {
    const session = { ...newSession("codex", "/project"), id: "chat" };
    const other = { ...newSession("codex", "/project"), id: "other" };
    const pinned = { ...newTab("chat"), id: "pinned-tab", cwd: "/project", pinned: true };
    const plain = { ...newTab("other"), id: "plain-tab", cwd: "/project" };
    const snapshot = collectWorkspaceSnapshot([pinned, plain], [session, other], "plain-tab", "/project", new Map());
    const restored = hydrateWorkspaceSnapshot(JSON.parse(JSON.stringify(snapshot)), new Map())!;
    expect(restored.tabs.map((tab) => [tab.id, tab.pinned === true])).toEqual([["pinned-tab", true], ["plain-tab", false]]);
  });
});
