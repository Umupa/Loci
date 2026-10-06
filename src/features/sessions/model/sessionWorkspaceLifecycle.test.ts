import { describe,expect,it } from "vitest";
import {
leaf,
newTab,
type WorkspaceTab
} from "../../workspace/model/layout";
import { newSession,type Session } from "./session";
import {
removeSessionFromWorkspace,
type SessionWorkspaceRemoval,
} from "./sessionWorkspaceLifecycle";

function session(id: string, cwd = "/projects/loci"): Session {
  return { ...newSession("codex", cwd), id };
}

function tab(id: string, sessionId: string): WorkspaceTab {
  return { ...newTab(sessionId), id };
}

function remove(input: {
  tabs: WorkspaceTab[];
  sessions: Session[];
  sessionId: string;
  activeTabId: string;
  scope?: "project" | "workspace";
}): SessionWorkspaceRemoval {
  return removeSessionFromWorkspace({
    ...input,
    scope: input.scope ?? "workspace",
    createReplacement: (seed) => session("replacement", seed?.cwd),
  });
}

describe("removeSessionFromWorkspace", () => {
  it("closes the sole-session tab and selects the remaining tab", () => {
    const result = remove({ tabs: [tab("closing", "s1"), tab("other", "s2")], sessions: [session("s1"), session("s2", "/projects/other")], sessionId: "s1", activeTabId: "closing" });
    expect(result.closedTabs.map((entry) => entry.id)).toEqual(["closing"]);
    expect(result.tabs.map((entry) => entry.id)).toEqual(["other"]);
    expect(result.sessions.map((entry) => entry.id)).toEqual(["s2"]);
    expect(result.activeTabId).toBe("other");
  });

  it("retains another conversation in a shared split layout", () => {
    const shared: WorkspaceTab = { ...tab("shared", "s1"), layout: { type: "split", id: "split", dir: "right", children: [leaf("s1"), leaf("s2")], sizes: [0.5, 0.5] } };
    const result = remove({ tabs: [shared], sessions: [session("s1"), session("s2")], sessionId: "s1", activeTabId: "shared" });
    expect(result.closedTabs).toEqual([]);
    expect(result.tabs).toHaveLength(1);
    expect(result.tabs[0]?.layout).toEqual(leaf("s2"));
    expect(result.sessions.map((entry) => entry.id)).toEqual(["s2"]);
  });

  it("replaces the final project tab with a blank session", () => {
    const result = remove({
      tabs: [tab("only", "s1")],
      sessions: [session("s1")],
      sessionId: "s1",
      activeTabId: "only",
      scope: "project",
    });

    expect(result.closedTabs.map((entry) => entry.id)).toEqual(["only"]);
    expect(result.tabs[0]?.id).toBe("only");
    expect(result.tabs[0]?.focusedId).toBe("replacement");
    expect(result.sessions.map((entry) => entry.id)).toEqual(["replacement"]);
  });

  it("does not leave the project when closing its final tab in project scope", () => {
    const result = remove({
      tabs: [tab("ruler", "r1"), tab("loci", "s1")],
      sessions: [session("r1", "/projects/ruler"), session("s1")],
      sessionId: "s1",
      activeTabId: "loci",
      scope: "project",
    });

    expect(result.tabs.map((entry) => entry.id)).toEqual(["ruler", "loci"]);
    expect(result.activeTabId).toBe("loci");
    expect(result.tabs[1]?.focusedId).toBe("replacement");
  });
});
