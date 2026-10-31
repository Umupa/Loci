import { beforeEach, expect, it, vi } from "vitest";
import { newSession } from "../../features/sessions/model/session";

const store = vi.hoisted(() => ({
  loadWorkspaceSnapshot: vi.fn(),
  listInFlightSessions: vi.fn(),
  getSession: vi.fn(),
  upsertSession: vi.fn(),
}));
vi.mock("../../features/sessions/data/sessionStore", async (original) => ({
  ...(await original<
    typeof import("../../features/sessions/data/sessionStore")
  >()),
  ...store,
}));
vi.mock("../../integrations/harness/core/registry", () => ({}));
vi.mock("../../integrations/harness/core/child", () => ({}));

const sessions = Array.from({ length: 3 }, (_, index) => ({
  ...newSession("codex", "/repo"),
  id: `session-${index}`,
  blocks: [{ id: `user-${index}`, role: "user" as const, text: "Hello" }],
}));

beforeEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  store.listInFlightSessions.mockResolvedValue([]);
  store.upsertSession.mockResolvedValue(null);
  // A layout saved by an earlier version is ignored.
  store.loadWorkspaceSnapshot.mockResolvedValue({ tabs: [{ id: "old" }], sessions: [], activeTabId: "old", projectCwd: "/repo" });
  store.getSession.mockImplementation(async (id: string) => sessions.find((session) => session.id === id) ?? null);
});

it("restores nothing but interrupted turns, ignoring an old tab layout", async () => {
  const { loadResumedWorkspace } = await import("./appLifecycle");
  expect(await loadResumedWorkspace()).toBeNull();
  expect(store.loadWorkspaceSnapshot).not.toHaveBeenCalled();
  expect(store.upsertSession).not.toHaveBeenCalled();
});

it("persists the interruption marker for each recovered running turn, in order", async () => {
  store.listInFlightSessions.mockResolvedValue([
    { sessionId: sessions[2].id, cwd: "/repo" },
    { sessionId: sessions[0].id, cwd: "/repo" },
    { sessionId: "gone", cwd: "/repo" },
  ]);
  const { loadResumedWorkspace } = await import("./appLifecycle");
  const restored = await loadResumedWorkspace();
  expect(restored?.sessions.map((session) => session.id)).toEqual([sessions[2].id, sessions[0].id]);
  expect(store.upsertSession).toHaveBeenCalledTimes(2);
  expect(restored?.sessions[0].blocks.at(-1)?.notice).toBe("interrupt");
});
