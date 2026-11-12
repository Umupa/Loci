// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";
import {
  notifySession,
  saveNotificationsEnabled,
  setWindowFocused,
} from "./notifications";
import { newSession } from "../../sessions/model/session";

const { invoke, play } = vi.hoisted(() => ({ invoke: vi.fn(), play: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("cuelume", () => ({ play, setEnabled: vi.fn(), setVolume: vi.fn() }));
beforeEach(() => {
  localStorage.clear();
  invoke.mockReset();
  play.mockClear();
  invoke.mockResolvedValue(undefined);
  saveNotificationsEnabled(true);
  setWindowFocused(false);
});

it("announces a chat outside any project, such as an agent's in the home folder", async () => {
  const sent = await notifySession(
    newSession("claude", "/"),
    "finished",
    false,
  );

  expect(sent).toBe(true);
  expect(
    invoke.mock.calls.filter(([command]) => command === "show_notification"),
  ).toHaveLength(1);
});
