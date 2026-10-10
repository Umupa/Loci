import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { documentLeaf, findLeaf, leafIds, newTab, placeLayout, splitPane, type WorkspaceTab, } from "./layout";
import {} from "../../projects/model/projectReturn";
import type { Session } from "../../sessions/model/session";
import { applyDetachPaneToTab, applyMoveWorkspacePane, applyPlaceTabOnPane, applyPlaceSessionOnPane, filterTabsForProject, findOpenSessionTab, findTabForProject, planWorkspaceTabClose, replaceGroupInTabOrder, switchSessionInTab, workspaceTabProject, focusedWorkspaceTabCwd, workspaceTabCwd, } from "./workspaceTabGroups";
function session(id: string, cwd: string): Session {
    return {
        id,
        cwd,
        harness: "claude",
        title: "",
        blocks: [],
        busy: false,
        model: "",
    };
}
function tab(id: string, sessionId: string): WorkspaceTab {
    return { ...newTab(sessionId), id };
}
describe("focusedWorkspaceTabCwd", () => {
    it("prefers the focused chat over the first chat", () => {
        const mixed = {
            ...tab("mixed", "first"),
            layout: splitPane(newTab("first").layout, "first", "right", "second"),
            focusedId: "second",
        };
        expect(focusedWorkspaceTabCwd(mixed, [
            session("first", "/alpha"),
            session("second", "/beta"),
        ])).toBe("/beta");
    });
    it("retains the tab fallback when the focused pane has no cwd", () => {
        const mixed = { ...tab("mixed", "chat"), focusedId: "missing" };
        expect(focusedWorkspaceTabCwd(mixed, [session("chat", "/alpha")])).toBe("/alpha");
        expect(focusedWorkspaceTabCwd(mixed, [])).toBeNull();
    });
});
describe("agent workspace project context", () => {
    beforeEach(() => {
        vi.stubGlobal("localStorage", {
            getItem: (key: string) => key === "loci:agent-roster"
                ? JSON.stringify([{ id: "agent-1", sessionId: "agent-chat", projects: [] }]) : null,
        });
    });
    afterEach(() => vi.unstubAllGlobals());
    it("keeps an agent-only tab in the project where it was opened", () => {
        const workspace = { ...tab("agent-tab", "agent-chat"), cwd: "/projects/loci" };
        const sessions = [session("agent-chat", "/Users/me")];
        expect(workspaceTabCwd(workspace, sessions)).toBe("/projects/loci");
        expect(focusedWorkspaceTabCwd(workspace, sessions)).toBe("/projects/loci");
        expect(filterTabsForProject([workspace], sessions, "/projects/loci")).toEqual([workspace]);
        expect(filterTabsForProject([workspace], sessions, "/Users/me")).toEqual([]);
    });
    it("ignores the focused agent's home cwd beside a project session", () => {
        const workspace = {
            ...tab("mixed", "agent-chat"),
            layout: splitPane(newTab("agent-chat").layout, "agent-chat", "right", "project-chat"),
            cwd: "/projects/previous",
        };
        const sessions = [session("agent-chat", "/Users/me"), session("project-chat", "/projects/loci")];
        expect(workspaceTabCwd(workspace, sessions)).toBe("/projects/loci");
        expect(focusedWorkspaceTabCwd(workspace, sessions)).toBe("/projects/loci");
        expect(focusedWorkspaceTabCwd({ ...workspace, focusedId: "project-chat" }, sessions)).toBe("/projects/loci");
    });
    it("keeps the resolved project when an agent is detached from a project session", () => {
        const workspace = {
            ...tab("mixed", "project-chat"),
            layout: splitPane(newTab("project-chat").layout, "project-chat", "right", "agent-chat"),
        };
        const sessions = [session("agent-chat", "/Users/me"), session("project-chat", "/projects/loci")];
        const next = applyDetachPaneToTab({ tabs: [workspace], sessions, paneId: "agent-chat", targetTabId: workspace.id, position: "after" })!;
        expect(focusedWorkspaceTabCwd(next.tabs[1], sessions)).toBe("/projects/loci");
        expect(next.tabs[1].cwd).toBe("/projects/loci");
    });
    it("keeps the destination project when moving an agent across tabs", () => {
        const sessions = [session("agent-chat", "/Users/me"), session("project-chat", "/projects/loci")];
        const source = { ...tab("agent-tab", "agent-chat"), cwd: "/projects/previous" };
        const destination = tab("project-tab", "project-chat");
        const next = applyMoveWorkspacePane([source, destination], "agent-chat", "project-chat", "right", sessions)!;
        expect(next).toHaveLength(1);
        expect(next[0].cwd).toBe("/projects/loci");
        expect(focusedWorkspaceTabCwd(next[0], sessions)).toBe("/projects/loci");
    });
    it("keeps the source project when its project session moves away from an agent", () => {
        const sessions = [session("agent-chat", "/Users/me"), session("project-chat", "/projects/loci"), session("target-chat", "/projects/other")];
        const source = {
            ...tab("mixed", "project-chat"),
            layout: splitPane(newTab("project-chat").layout, "project-chat", "right", "agent-chat"),
        };
        const destination = tab("target-tab", "target-chat");
        const next = applyMoveWorkspacePane([source, destination], "project-chat", "target-chat", "right", sessions)!;
        expect(next[0].cwd).toBe("/projects/loci");
        expect(focusedWorkspaceTabCwd(next[0], sessions)).toBe("/projects/loci");
    });
});
describe("findOpenSessionTab", () => {
    it("does not focus a ghost tab whose session has been parked", () => {
        const ghost = tab("ghost-tab", "parked-session");
        expect(findOpenSessionTab([ghost], [], "parked-session")).toBeUndefined();
        expect(findOpenSessionTab([ghost], [session("parked-session", "/workspace")], "parked-session")).toBe(ghost);
    });
});
describe("switchSessionInTab", () => {
    it("replaces the focused session while keeping the tab and its other panes", () => {
        const split = {
            ...tab("current-tab", "current"),
            layout: splitPane(newTab("current").layout, "current", "right", "other"),
        };
        const [next] = switchSessionInTab([split], split.id, "current", "target")!;
        expect(next.id).toBe(split.id);
        expect(leafIds(next.layout)).toEqual(["target", "other"]);
        expect(next.focusedId).toBe("target");
    });
    it("focuses a session already in the current tab", () => {
        const split = {
            ...tab("current-tab", "current"),
            layout: splitPane(newTab("current").layout, "current", "right", "target"),
        };
        const [next] = switchSessionInTab([split], split.id, "current", "target")!;
        expect(leafIds(next.layout)).toEqual(["current", "target"]);
        expect(next.focusedId).toBe("target");
    });
    it("swaps sessions across tabs instead of mounting one twice", () => {
        const current = tab("current-tab", "current");
        const other = tab("other-tab", "target");
        const next = switchSessionInTab([current, other], current.id, "current", "target")!;
        expect(next.map((entry) => entry.id)).toEqual(["current-tab", "other-tab"]);
        expect(next.map((entry) => leafIds(entry.layout))).toEqual([
            ["target"],
            ["current"],
        ]);
        expect(next.map((entry) => entry.focusedId)).toEqual(["target", "current"]);
    });
    it("ignores a switch after the focused session has changed", () => {
        const current = tab("current-tab", "new-focus");
        expect(switchSessionInTab([current], current.id, "old-focus", "target")).toBeNull();
    });
});
describe("workspaceTabProject", () => {
    it("reads project from the tab session cwd", () => {
        const workspace = tab("t1", "s1");
        const sessions = [session("s1", "/Users/me/agent-terminal")];
        expect(workspaceTabProject(workspace, sessions)).toBe("agent-terminal");
    });
});
describe("findTabForProject", () => {
    it("matches a tab by project path, ignoring trailing slashes", () => {
        const tabs = [tab("t1", "s1"), tab("t2", "s2")];
        const sessions = [
            session("s1", "/tmp/alpha"),
            session("s2", "/tmp/beta"),
        ];
        expect(findTabForProject(tabs, sessions, "/tmp/beta/")?.id).toBe("t2");
    });
    it("returns undefined when no open tab belongs to the project", () => {
        const tabs = [tab("t1", "s1")];
        const sessions = [session("s1", "/tmp/alpha")];
        expect(findTabForProject(tabs, sessions, "/tmp/beta")).toBeUndefined();
    });
});
describe("filterTabsForProject", () => {
    it("keeps only tabs that belong to the project", () => {
        const tabs = [tab("t1", "s1"), tab("t2", "s2"), tab("t3", "s3")];
        const sessions = [
            session("s1", "/tmp/alpha"),
            session("s2", "/tmp/beta"),
            session("s3", "/tmp/beta"),
        ];
        expect(filterTabsForProject(tabs, sessions, "/tmp/beta").map((tab) => tab.id)).toEqual(["t2", "t3"]);
    });
});
describe("planWorkspaceTabClose", () => {
    const sessions = [
        session("m1", "/projects/loci"),
        session("r1", "/projects/ruler"),
        session("m2", "/projects/loci"),
    ];
    const tabs = [tab("tm1", "m1"), tab("tr1", "r1"), tab("tm2", "m2")];
    it("uses the global neighbor in workspace scope", () => {
        expect(planWorkspaceTabClose({
            tabs,
            sessions,
            closingTabId: "tm2",
            scope: "workspace",
        })).toEqual({ action: "close", nextActiveTabId: "tr1" });
    });
    it("prefers the previous same-project tab in project scope", () => {
        expect(planWorkspaceTabClose({
            tabs,
            sessions,
            closingTabId: "tm2",
            scope: "project",
        })).toEqual({ action: "close", nextActiveTabId: "tm1" });
    });
    it("uses the next same-project tab when none exists to the left", () => {
        expect(planWorkspaceTabClose({
            tabs,
            sessions,
            closingTabId: "tm1",
            scope: "project",
        })).toEqual({ action: "close", nextActiveTabId: "tm2" });
    });
    it("keeps the last tab of a project instead of jumping to another", () => {
        expect(planWorkspaceTabClose({
            tabs: tabs.slice(0, 2),
            sessions,
            closingTabId: "tm1",
            scope: "project",
        })).toEqual({ action: "keep" });
    });
    it("still jumps across projects in workspace scope when a project is emptied", () => {
        expect(planWorkspaceTabClose({
            tabs: tabs.slice(0, 2),
            sessions,
            closingTabId: "tm1",
            scope: "workspace",
        })).toEqual({ action: "close", nextActiveTabId: "tr1" });
    });
    it("uses the global neighbor for a projectless tab", () => {
        const projectlessSessions = [
            ...sessions,
            session("blank1", "~"),
            session("blank2", "~"),
        ];
        expect(planWorkspaceTabClose({
            tabs: [tab("projectless", "blank1"), tabs[1]],
            sessions: projectlessSessions,
            closingTabId: "projectless",
            scope: "project",
        })).toEqual({ action: "close", nextActiveTabId: "tr1" });
        expect(planWorkspaceTabClose({
            tabs: [tab("blank1", "blank1"), tabs[1], tab("blank2", "blank2")],
            sessions: projectlessSessions,
            closingTabId: "blank2",
            scope: "project",
        })).toEqual({ action: "close", nextActiveTabId: "tr1" });
    });
    it("keeps the sole tab or an unknown tab", () => {
        expect(planWorkspaceTabClose({
            tabs: [tabs[0]],
            sessions,
            closingTabId: "tm1",
            scope: "workspace",
        })).toEqual({ action: "keep" });
        expect(planWorkspaceTabClose({
            tabs,
            sessions,
            closingTabId: "missing",
            scope: "project",
        })).toEqual({ action: "keep" });
    });
});
describe("applyPlaceSessionOnPane", () => {
    const sessions = [
        session("m1", "/projects/loci"),
        session("m2", "/projects/loci"),
        session("r1", "/projects/ruler"),
    ];
    function replacementFrom(seed: Session | undefined): Session {
        return session("replacement", seed?.cwd ?? "/tmp/fallback");
    }
    it("splits the target pane toward the drop edge", () => {
        const next = applyPlaceSessionOnPane({
            tabs: [tab("tm1", "m1")],
            sessions,
            sessionId: "m2",
            targetId: "m1",
            edge: "right",
            replaceTarget: false,
            scope: "workspace",
            createReplacement: replacementFrom,
        });
        expect(next?.activeTabId).toBe("tm1");
        expect(next?.tabs[0]?.focusedId).toBe("m2");
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["m1", "m2"]);
    });
    it("replaces a blank target instead of splitting it", () => {
        const blank = session("blank", "/projects/loci");
        const next = applyPlaceSessionOnPane({
            tabs: [tab("tm1", "blank")],
            sessions: [...sessions, blank],
            sessionId: "m2",
            targetId: "blank",
            edge: "right",
            replaceTarget: true,
            scope: "workspace",
            createReplacement: replacementFrom,
        });
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["m2"]);
        expect(next?.sessions.map((entry) => entry.id)).toEqual([
            "m1",
            "m2",
            "r1",
        ]);
    });
    it("relocates a session from another tab and closes that tab", () => {
        const next = applyPlaceSessionOnPane({
            tabs: [tab("tm1", "m1"), tab("tm2", "m2")],
            sessions,
            sessionId: "m2",
            targetId: "m1",
            edge: "left",
            replaceTarget: false,
            scope: "workspace",
            createReplacement: replacementFrom,
        });
        expect(next?.tabs.map((entry) => entry.id)).toEqual(["tm1"]);
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["m2", "m1"]);
    });
    it("keeps the last tab of a project and fills it with a replacement", () => {
        const next = applyPlaceSessionOnPane({
            tabs: [tab("tr1", "r1"), tab("tm1", "m1")],
            sessions,
            sessionId: "m1",
            targetId: "r1",
            edge: "right",
            replaceTarget: false,
            scope: "project",
            createReplacement: replacementFrom,
        });
        expect(next?.tabs.map((entry) => entry.id)).toEqual(["tr1", "tm1"]);
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["r1", "m1"]);
        expect(next?.tabs[1]?.focusedId).toBe("replacement");
    });
});
describe("applyPlaceTabOnPane", () => {
    const sessions = [
        session("target", "/projects/loci"),
        session("source", "/projects/loci"),
        session("other", "/projects/loci"),
    ];
    it("turns a separate tab into a split beside the target pane", () => {
        const next = applyPlaceTabOnPane({
            tabs: [tab("target-tab", "target"), tab("source-tab", "source")],
            sessions,
            sourceTabId: "source-tab",
            targetId: "target",
            edge: "left",
            replaceTarget: false,
        });
        expect(next?.activeTabId).toBe("target-tab");
        expect(next?.tabs.map((entry) => entry.id)).toEqual(["target-tab"]);
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["source", "target"]);
        expect(next?.tabs[0]?.focusedId).toBe("source");
    });
    it("replaces a blank target without leaving its session mounted", () => {
        const blank = session("blank", "/projects/loci");
        const next = applyPlaceTabOnPane({
            tabs: [tab("target-tab", "blank"), tab("source-tab", "source")],
            sessions: [...sessions, blank],
            sourceTabId: "source-tab",
            targetId: blank.id,
            edge: "bottom",
            replaceTarget: true,
        });
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["source"]);
        expect(next?.sessions.some((entry) => entry.id === blank.id)).toBe(false);
    });
});
describe("applyDetachPaneToTab", () => {
    it("turns one chat pane into a separate tab at the drop position", () => {
        const source: WorkspaceTab = {
            ...tab("source-tab", "first"),
            layout: splitPane(newTab("first").layout, "first", "right", "second"),
            focusedId: "second",
        };
        const target = tab("target-tab", "third");
        const next = applyDetachPaneToTab({
            tabs: [source, target],
            paneId: "second",
            targetTabId: target.id,
            position: "before",
            createTabId: () => "detached-tab",
        });
        expect(next?.activeTabId).toBe("detached-tab");
        expect(next?.focusedId).toBe("second");
        expect(next?.tabs.map((entry) => entry.id)).toEqual([
            "source-tab",
            "detached-tab",
            "target-tab",
        ]);
        expect(leafIds(next!.tabs[0]!.layout)).toEqual(["first"]);
        expect(leafIds(next!.tabs[1]!.layout)).toEqual(["second"]);
    });
    it("does not detach the only pane in a tab", () => {
        expect(applyDetachPaneToTab({
            tabs: [tab("source-tab", "only")],
            paneId: "only",
            targetTabId: "source-tab",
            position: "after",
        })).toBeNull();
    });
    it("keeps a document's contents and project when it becomes a separate tab", () => {
        const document = documentLeaf({ id: "network", title: "Network policy", body: "# Policy" }, "agent-1");
        if (document.type !== "leaf") throw new Error("Expected a document leaf");
        const source = { ...tab("source-tab", "first"), layout: placeLayout(newTab("first").layout, document, "first", "right") };
        const next = applyDetachPaneToTab({ tabs: [source], sessions: [session("first", "/projects/loci")], paneId: document.id, targetTabId: source.id, position: "after" })!;
        expect(findLeaf(next.tabs[1].layout, document.id)).toEqual(document);
        expect(next.tabs[1].cwd).toBe("/projects/loci");
    });
});
describe("replaceGroupInTabOrder", () => {
    it("swaps a contiguous slice of ids", () => {
        expect(replaceGroupInTabOrder(["a", "b", "c", "d"], 1, 2, ["d", "c"])).toEqual([
            "a",
            "d",
            "c",
            "d",
        ]);
    });
});
