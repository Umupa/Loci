// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { newSession } from "../../sessions/model/session";
import type { SessionPane } from "../../sessions/ui/SessionPane";
import type { AgentDetails } from "./AgentDetails";
import { AgentSessionPane } from "./AgentSessionPane";

let conversation: ComponentProps<typeof SessionPane>;
let details: ComponentProps<typeof AgentDetails>;
vi.mock("../../sessions/ui/SessionPane", () => ({
  SessionPane: (props: ComponentProps<typeof SessionPane>) => {
    conversation = props;
    return createElement("div", { "data-test-conversation": true }, "Conversation", props.emptyIntro);
  },
}));
vi.mock("./AgentDetails", () => ({
  AgentDetails: (props: ComponentProps<typeof AgentDetails>) => {
    details = props;
    return createElement("aside", { "data-test-details": true }, "Agent settings");
  },
}));

const agent = { id: "agent", name: "Ada", avatar: "ember", color: "#fff", projects: [] };
let root: Root;
let container: HTMLDivElement;
const onFocus = vi.fn();
const onClose = vi.fn();
const onDrag = vi.fn();
const onToggleDetails = vi.fn();
const onModelChange = vi.fn();
const onModelSettingsChange = vi.fn();
const onRuntimeModeChange = vi.fn();
const onLoadEarlier = vi.fn();
const onReset = vi.fn();
const onDelete = vi.fn();
const onPickFolders = vi.fn(async () => []);

function render(detailsOpen = false, focused = false) {
  const sessionPaneProps = {
    session: { ...newSession("codex", "/home/me", "codex:test", "auto"), id: "chat" },
    visible: true, focused, inSplit: true, composerFocused: true, recents: [],
    onFocus, onClose, onPaneDragStart: onDrag, onModelChange, onModelSettingsChange, onRuntimeModeChange,
  } as unknown as ComponentProps<typeof SessionPane>;
  root.render(createElement(AgentSessionPane, {
    agent, state: { status: "idle" }, sessionPaneProps, detailsOpen, onToggleDetails,
    onReset, onDelete, onPickFolders, onLoadEarlier,
  }));
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.clearAllMocks();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

it("moves and focuses the agent with details available and no header close control", () => {
  act(() => render());
  const header = container.querySelector("header")!;
  expect(container.querySelector("[data-tauri-drag-region]")).toBeNull();
  act(() => header.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, button: 0 })));
  expect(onDrag).toHaveBeenCalledOnce();
  expect(onFocus).toHaveBeenCalledWith("chat");

  act(() => container.querySelector<HTMLButtonElement>("[aria-label='Details']")!.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, button: 0 })));
  expect(onDrag).toHaveBeenCalledOnce();
  act(() => container.querySelector<HTMLButtonElement>("[aria-label='Details']")!.click());
  expect(onToggleDetails).toHaveBeenCalledOnce();
  expect(header.querySelector("[aria-label='Close pane']")).toBeNull();
  expect(onClose).not.toHaveBeenCalled();
  act(() => [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Show archived history")!.click());
  expect(onLoadEarlier).toHaveBeenCalledOnce();
  expect(conversation).toMatchObject({ hidePaneHeader: true, hideProjectPicker: true, chatPlaceholder: "Message Ada", focused: false });
  expect(conversation.onClose).toBe(onClose);
});

it("keeps the agent's settings and actions associated with its conversation", () => {
  act(() => render(true, true));
  expect(container.querySelector("[data-test-details]")).not.toBeNull();
  details.onModelChange("codex", "codex:next");
  details.onModelSettingsChange({ effort: "high" });
  details.onRuntimeModeChange("full-access");
  expect(onModelChange).toHaveBeenCalledWith("chat", "codex", "codex:next");
  expect(onModelSettingsChange).toHaveBeenCalledWith("chat", { effort: "high" });
  expect(onRuntimeModeChange).toHaveBeenCalledWith("chat", "full-access");
  expect(details.onReset).toBe(onReset);
  expect(details.onDelete).toBe(onDelete);
  expect(details.onPickFolders).toBe(onPickFolders);
  details.onClose();
  expect(onToggleDetails).toHaveBeenCalledOnce();
  act(() => container.querySelector("[data-test-conversation]")!.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })));
  expect(onFocus).not.toHaveBeenCalled();
});

it("keeps the empty introduction free of profile and model controls", () => {
  act(() => render());
  const intro = container.querySelector("[data-agent-intro]")!;
  expect(intro.textContent).toContain("A sentence is enough.");
  expect(intro.querySelector("button, input, select, textarea")).toBeNull();
  expect(container.querySelector("[aria-label='Details']")).not.toBeNull();
});
