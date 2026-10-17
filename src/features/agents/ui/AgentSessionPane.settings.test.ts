// @vitest-environment happy-dom
import { readFileSync } from "node:fs";
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { saveTranscriptAnchor, saveTranscriptLayout } from "../../settings/model/appearance";
import { saveComposerRunner } from "../../settings/model/settings";
import { newSession, type Session } from "../../sessions/model/session";
import type { SessionPane } from "../../sessions/ui/SessionPane";
import { AgentSessionPane } from "./AgentSessionPane";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async () => []),
  isTauri: () => false,
  convertFileSrc: (path: string) => path,
}));
vi.mock("@tauri-apps/api/webview", () => ({
  getCurrentWebview: () => ({ onDragDropEvent: async () => () => {} }),
}));
vi.mock("./AgentDetails", () => ({ AgentDetails: () => null }));

let root: Root;
let host: HTMLDivElement;
let styles: HTMLStyleElement;
const agent = { id: "agent", name: "Ada", avatar: "ember", color: "#f28c28", projects: [] };
const onSubmit = vi.fn(() => true);
const onDeleteQueuedMessage = vi.fn();
const onEditQueuedMessage = vi.fn();
const onQueuedMessageEditingChange = vi.fn();
const onSteerQueuedMessage = vi.fn();
const onResumeQueue = vi.fn();

async function render(extra: Partial<Session> = {}, look = agent) {
  const session = {
    ...newSession("codex", "/home/me", "codex:test"),
    id: "agent-chat", busy: true,
    blocks: [{ id: "u1", role: "user" as const, text: "Inspect the build", startedAt: 1000 },
      { id: "a1", role: "assistant" as const, text: "I will inspect it." }],
    ...extra,
  };
  const sessionPaneProps: ComponentProps<typeof SessionPane> = {
    session, visible: true, focused: true, inSplit: true, composerFocused: true, recents: [],
    onFocus: vi.fn(), onClose: vi.fn(), onCwdChange: vi.fn(), onModelChange: vi.fn(),
    onModelSettingsChange: vi.fn(), onRuntimeModeChange: vi.fn(), onSubmit,
    onSaveDraft: vi.fn(), onRemoveDraft: vi.fn(), onStop: vi.fn(), onCompactContext: vi.fn(() => true),
    onPlaceSessionInFolder: vi.fn(), onDeleteQueuedMessage, onEditQueuedMessage,
    onQueuedMessageEditingChange, onSteerQueuedMessage, onResumeQueue,
    onUsageLimitResume: vi.fn(), onUsageLimitResumeAtReset: vi.fn(), onUsageLimitDismiss: vi.fn(),
    onApproval: vi.fn(), onQuestionReply: vi.fn(), onOpenFile: vi.fn(),
  };
  await act(async () => root.render(createElement(AgentSessionPane, {
    agent: look, state: { status: "working" }, sessionPaneProps, detailsOpen: false,
    onToggleDetails: vi.fn(), onReset: vi.fn(), onDelete: vi.fn(), onPickFolders: vi.fn(async () => []),
  })));
}

beforeEach(() => {
  localStorage.clear();
  vi.clearAllMocks();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("matchMedia", () => ({ matches: true }));
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  saveComposerRunner(false);
  // Exercise the actual agent-specific selectors, including layout overrides.
  const css = readFileSync("src/styles/index.css", "utf8");
  styles = document.createElement("style");
  styles.textContent = [...css.matchAll(/\[data-agent-view\][^{]+\{[^}]+\}/g)].map(([rule]) => rule).join("\n");
  document.head.append(styles);
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  styles.remove();
  vi.unstubAllGlobals();
});

it("applies transcript layout and anchor settings live in the resident conversation", async () => {
  await render();
  const transcript = host.querySelector<HTMLElement>("[data-transcript-layout]")!;
  const row = host.querySelector<HTMLElement>("[data-prompt-anchor='u1']")!;
  const bubble = row.querySelector<HTMLElement>(".user-message-bubble")!;
  expect(transcript.dataset.transcriptLayout).toBe("chat");
  expect(row.classList.contains("items-end")).toBe(true);
  expect(bubble.className).toContain("max-w-[min(100%,36rem)]");
  expect(host.querySelector(".transcript-turn-anchor")).not.toBeNull();

  await act(async () => saveTranscriptLayout("full"));
  expect(transcript.dataset.transcriptLayout).toBe("full");
  expect(row.classList.contains("items-end")).toBe(false);
  expect(bubble.className).not.toContain("max-w-[min(100%,36rem)]");
  expect(host.querySelector(".transcript-turn-anchor")).not.toBeNull();

  await act(async () => saveTranscriptAnchor(false));
  expect(host.querySelector(".transcript-turn-anchor")).toBeNull();

  await act(async () => saveTranscriptLayout("chat"));
  expect(bubble.className).toContain("max-w-[min(100%,36rem)]");
  expect(host.querySelector(".transcript-turn-anchor")).toBeNull();

  await act(async () => saveTranscriptAnchor(true));
  expect(host.querySelector(".transcript-turn-anchor")).not.toBeNull();
});

it("uses the agent's face and color in the animation and responds to its switch live", async () => {
  saveComposerRunner(true);
  await render();
  const face = () => document.querySelector<SVGSVGElement>(".composer-runner .mascot-active svg")!;
  expect(face().dataset.agentAvatar).toBe(agent.avatar);
  expect(face().style.color).toBe(agent.color);
  const originalArtwork = face().innerHTML;

  await render({}, { ...agent, avatar: "wisp", color: "#7a82ff" });
  expect(face().dataset.agentAvatar).toBe("wisp");
  expect(face().innerHTML).not.toBe(originalArtwork);
  expect(face().style.color).toBe("#7a82ff");
  await act(async () => saveComposerRunner(false));
  expect(document.querySelector(".composer-runner")).toBeNull();
  await act(async () => saveComposerRunner(true));
  expect(face().style.color).toBe("#7a82ff");
});

it("keeps follow-up submission and queue actions connected to the agent session", async () => {
  await render({ queuedMessages: [{ id: "queued", text: "Check tests too", attachments: [] }], queueStatus: "paused" });
  expect(host.querySelector("[data-message-queue]")?.textContent).toContain("Check tests too");
  const click = (label: string) => act(() => host.querySelector<HTMLButtonElement>(`[aria-label='${label}']`)!.click());
  click("Edit queued message");
  expect(onQueuedMessageEditingChange).toHaveBeenCalledWith("agent-chat", "queued");
  const queuedDraft = host.querySelector<HTMLTextAreaElement>("[aria-label='Edit queued message']")!;
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(queuedDraft, "Check the integration tests too");
    queuedDraft.dispatchEvent(new Event("input", { bubbles: true }));
  });
  click("Save queued message");
  expect(onEditQueuedMessage).toHaveBeenCalledWith("agent-chat", "queued", "Check the integration tests too");
  const button = (text: string) => [...host.querySelectorAll<HTMLButtonElement>("button")].find((entry) => entry.textContent?.trim() === text)!;
  act(() => { button("Steer").click(); button("Resume").click(); });
  expect(onSteerQueuedMessage).toHaveBeenCalledWith("agent-chat", "queued");
  expect(onResumeQueue).toHaveBeenCalledWith("agent-chat");
  click("Remove queued message");
  expect(onDeleteQueuedMessage).toHaveBeenCalledWith("agent-chat", "queued");

  const textarea = host.querySelector<HTMLTextAreaElement>("textarea:not([aria-label='Edit queued message'])")!;
  await act(async () => {
    textarea.value = "One more thing";
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () => textarea.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })));
  expect(onSubmit).toHaveBeenCalledWith("agent-chat", "One more thing", [], expect.any(Object));
});

it("lets an empty split pane start from one ordinary sentence without setup controls", async () => {
  await render({ busy: false, blocks: [] });
  const intro = host.querySelector("[data-agent-intro]")!;
  expect(intro.textContent).toContain("A sentence is enough.");
  expect(intro.querySelector("button, input, select, textarea")).toBeNull();
  const textarea = host.querySelector<HTMLTextAreaElement>("textarea")!;
  expect(textarea.value).toBe("");
  expect(onSubmit).not.toHaveBeenCalled();
  await act(async () => {
    textarea.value = "我想练英语口语";
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () => textarea.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })));
  expect(onSubmit).toHaveBeenCalledWith("agent-chat", "我想练英语口语", [], expect.any(Object));
});
