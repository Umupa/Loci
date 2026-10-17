import { expect, it } from "vitest";
import { courseLeaf, coursePaneId, findLeaf, layoutLeaves, leafIds, newTab, showCourseInTab } from "./layout";
import { collectWorkspaceSnapshot, hydrateWorkspaceSnapshot, sanitizeLayout } from "./workspaceSnapshot";
import { newSession } from "../../sessions/model/session";
import { summarizeTab } from "./tabSummary";

const course = { courseId: "kubernetes", agentId: "agent-a", title: "Kubernetes", sourceSessionId: "chat" };

it("reuses a course pane, isolates owners and restores it without creating a session for it", () => {
  const chat = { ...newSession("codex", "/project"), id: "chat" };
  const first = showCourseInTab({ ...newTab(chat.id), id: "tab", cwd: chat.cwd }, course);
  const revised = { ...course, title: "Kubernetes Deep Dive" };
  const second = showCourseInTab(first, revised);
  const other = showCourseInTab(second, { ...course, agentId: "agent-b" });
  expect(leafIds(other.layout)).toEqual(["chat", coursePaneId(course.courseId, "agent-a"), coursePaneId(course.courseId, "agent-b")]);
  expect(findLeaf(other.layout, coursePaneId(course.courseId, "agent-a"))?.course).toEqual(revised);
  expect(layoutLeaves(other.layout).filter((entry) => entry.kind === "course")).toHaveLength(2);

  const snapshot = collectWorkspaceSnapshot([other], [chat], other.id, chat.cwd, new Map());
  const restored = hydrateWorkspaceSnapshot(JSON.parse(JSON.stringify(snapshot)), new Map())!;
  expect(restored.tabs[0]).toEqual(other);
  expect(restored.sessions.map((entry) => entry.id)).toEqual(["chat"]);
});

it("rejects malformed restored courses and rebuilds their scoped pane identity", () => {
  expect(sanitizeLayout({ type: "leaf", id: "arbitrary", leafKind: "course", course })).toEqual({
    type: "leaf", id: coursePaneId(course.courseId, course.agentId), leafKind: "course", course, agentId: course.agentId,
  });
  for (const invalid of [{ ...course, agentId: "" }, { ...course, courseId: "../bad" }, { ...course, title: null }, undefined]) {
    expect(sanitizeLayout({ type: "leaf", id: "course", leafKind: "course", course: invalid })).toBeNull();
  }
});

it("uses the focused course title in the tab summary", () => {
  const tab = showCourseInTab(newTab("chat"), course);
  expect(summarizeTab(tab, {
    sessions: [], needsInput: new Set(), unseenFinished: new Set(), fallbackCwd: "/project", canvasTitle: () => undefined,
  })).toMatchObject({ title: "Kubernetes", paneKind: "course", sessionCount: 0, blank: false });
});


it("preserves the chosen lesson through workspace persistence", () => {
  const detail = { courseId: "reading", agentId: "agent-a", title: "Reading", itemId: "lesson-two" };
  expect(sanitizeLayout(courseLeaf(detail))).toMatchObject({ course: detail });
});
