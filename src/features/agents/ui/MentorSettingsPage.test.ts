// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { newSession } from "../../sessions/model/session";
import type { AgentDetails } from "./AgentDetails";
import { MentorSettingsPage } from "./MentorSettingsPage";

const migrated = vi.hoisted(() => vi.fn());
let details: ComponentProps<typeof AgentDetails> | undefined;
vi.mock("./AgentDetails", () => ({
  AgentDetails: (props: ComponentProps<typeof AgentDetails>) => {
    details = props;
    return createElement("div", { "data-test-details": true });
  },
}));
vi.mock("../model/agentAccess", () => ({ markAgentAccessMigrated: migrated }));
vi.mock("../../../app/shell/WindowControls", () => ({ WindowControls: () => null }));

const agent = { id: "agent", name: "Ada", avatar: "ember", color: "#fff", sessionId: "chat" };
const handlers = {
  onModelChange: vi.fn(), onModelSettingsChange: vi.fn(), onRuntimeModeChange: vi.fn(),
  onPickFolders: vi.fn(async () => []), onReset: vi.fn(), onDelete: vi.fn(),
};
let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.clearAllMocks();
  details = undefined;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

it("is a page of Settings named for the mentor, with nothing laid over the workspace", () => {
  const session = { ...newSession("codex", "/home/me", "codex:test", "auto"), id: "chat" };
  act(() => root.render(createElement(MentorSettingsPage, { agent, session, recents: [], ...handlers })));
  expect(container.querySelector("[data-mentor-settings='agent']")?.textContent).toContain("Ada");
  expect(container.querySelector(".modal-backdrop")).toBeNull();
  expect(document.querySelector(".modal-backdrop")).toBeNull();
  expect(container.querySelector("[data-test-details]")).not.toBeNull();
});

it("changes the mentor's own conversation and keeps a permission choice as its access", () => {
  const session = { ...newSession("codex", "/home/me", "codex:test", "auto"), id: "chat" };
  act(() => root.render(createElement(MentorSettingsPage, { agent, session, recents: [], ...handlers })));
  details!.onModelChange("codex", "codex:next");
  details!.onModelSettingsChange({ effort: "high" });
  details!.onRuntimeModeChange("full-access");
  expect(handlers.onModelChange).toHaveBeenCalledWith("chat", "codex", "codex:next");
  expect(handlers.onModelSettingsChange).toHaveBeenCalledWith("chat", { effort: "high" });
  expect(handlers.onRuntimeModeChange).toHaveBeenCalledWith("chat", "full-access");
  expect(migrated).toHaveBeenCalledWith("agent");
  expect(details!.onReset).toBe(handlers.onReset);
  expect(details!.onDelete).toBe(handlers.onDelete);
});

it("waits for the conversation before showing its controls", () => {
  act(() => root.render(createElement(MentorSettingsPage, { agent, recents: [], ...handlers })));
  expect(container.querySelector("[data-test-details]")).toBeNull();
  expect(container.querySelector("[role='status']")?.textContent).toBe("Opening…");
});
