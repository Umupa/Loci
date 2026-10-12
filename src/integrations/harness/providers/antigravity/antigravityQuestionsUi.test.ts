// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetHarnessModelOverlays } from "../../../../features/sessions/model/models";
import { newSession, type Session } from "../../../../features/sessions/model/session";
import { QuestionCard } from "../../../../features/sessions/ui/QuestionCard";
import { QuestionForm } from "../../../../features/sessions/ui/QuestionForm";
import { applyHarnessEvent } from "../../core/apply";
import type { HarnessEvent } from "../../core/types";

const transport = vi.hoisted(() => ({
  listeners: new Map<string, (line: string) => void>(),
  sent: [] as Array<{
    thread: string;
    id?: number;
    method?: string;
    result?: unknown;
  }>,
}));

vi.mock("../../../../platform/tauri/fs", () => ({
  homeDir: async () => "/home/test",
}));
vi.mock("../../core/child", () => ({
  resolveAntigravityBinary: async () => ({ path: "/fake/agy_acp_server.par", args: [] }),
  spawnChild: async () => undefined,
  killChild: async (id: string) => transport.listeners.delete(id),
  unwatchChild: (id: string) => transport.listeners.delete(id),
  watchChild: (id: string, listener: (line: string) => void) => {
    transport.listeners.set(id, listener);
  },
  writeChild: async (thread: string, line: string) => {
    const message = JSON.parse(line);
    transport.sent.push({ thread, ...message });
    if (message.id == null || !message.method || message.method === "session/prompt") return;
    const result = message.method === "session/new"
      ? { sessionId: "provider-ui-session" }
      : {};
    queueMicrotask(() => transport.listeners.get(thread)?.(
      JSON.stringify({ jsonrpc: "2.0", id: message.id, result }),
    ));
  },
}));

const { antigravityAdapter } = await import("./antigravityAdapter");

const requestId = 901;
const questionTitle = "你学习 Linux FUSE 最核心要解决的工程目标是什么？";
// AGY 1.3's ask-user bridge preserves IDs and labels, marking every option
// allow_once except deny/dont_trust/block. It supports one original choice.
const choices = [
  { optionId: "goal_fs", name: "开发用户态文件系统", kind: "allow_once" },
  { optionId: "goal_kernel", name: "深入内核机制与驱动原理", kind: "allow_once" },
  { optionId: "deny", name: "以上都不是", kind: "reject_once" },
  { optionId: "goal_other", name: "Other", kind: "allow_once" },
];

describe.each([
  { name: "chat card", component: QuestionCard },
  { name: "composer form", component: QuestionForm },
])("Antigravity clarification in the real $name", ({ name, component }) => {
  let container: HTMLDivElement;
  let root: Root;
  let session: Session;
  let turn: Promise<void>;

  const listener = () => [...transport.listeners.values()].at(-1)!;
  const response = () => transport.sent.find(
    (message) => message.id === requestId && !message.method,
  )?.result;

  function render(event: HarnessEvent) {
    session = applyHarnessEvent(session, event);
    root.render(session.pendingQuestion
      ? createElement(component, {
          prompt: session.pendingQuestion,
          onReply: (id, reply) => antigravityAdapter.respondQuestion!(session.id, id, reply),
        })
      : null);
  }

  function option(label: string): HTMLButtonElement {
    const match = Array.from(container.querySelectorAll<HTMLButtonElement>(
      "button[aria-checked], button[aria-pressed]",
    )).find((button) => button.textContent?.includes(label));
    if (!match) throw new Error(`No choice labelled ${label}`);
    return match;
  }

  function button(label: string): HTMLButtonElement {
    const match = Array.from(container.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.trim() === label,
    );
    if (!match) throw new Error(`No button labelled ${label}`);
    return match;
  }

  function expectOriginalChoicesOnly() {
    expect(container.querySelector("input, textarea")).toBeNull();
    expect(container.textContent).not.toContain("Multi-select");
    expect(container.textContent).not.toContain("type your own");
  }

  beforeEach(async () => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    transport.sent.length = 0;
    transport.listeners.clear();
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
    session = newSession("antigravity", "/repo", "antigravity:m1", "full-access");
    session.id = "antigravity-question-ui";
    session.busy = true;
    await act(async () => {
      turn = antigravityAdapter.sendTurn({
        sessionId: session.id,
        cwd: session.cwd,
        model: session.model,
        runtimeMode: session.runtimeMode,
        text: "我想要学习 Linux FUSE",
        onEvent: render,
      });
      await vi.waitFor(() => expect(transport.sent.some(
        (message) => message.method === "session/prompt",
      )).toBe(true));
      listener()(JSON.stringify({
        jsonrpc: "2.0",
        id: requestId,
        method: "session/request_permission",
        params: {
          sessionId: "provider-ui-session",
          toolCall: {
            toolCallId: "interaction_3814c9e9",
            title: questionTitle,
            rawInput: {},
            status: "pending",
          },
          options: choices,
        },
      }));
    });
  });

  afterEach(async () => {
    await act(async () => {
      const prompt = transport.sent.findLast((message) => message.method === "session/prompt");
      if (prompt) listener()(JSON.stringify({
        jsonrpc: "2.0", id: prompt.id, result: { stopReason: "end_turn" },
      }));
      await turn;
      await antigravityAdapter.forgetSession!(session.id);
      root.unmount();
    });
    container.remove();
    resetHarnessModelOverlays();
    vi.unstubAllGlobals();
  });

  it.each([
    choices[1],
    choices[2],
    choices[3],
  ])("waits for the user's $name choice and returns its original ID", async (choice) => {
    expect(container.textContent).toContain(questionTitle);
    expect(response()).toBeUndefined();
    expectOriginalChoicesOnly();
    await act(async () => option(choice.name).click());
    expectOriginalChoicesOnly();
    if (name === "composer form") {
      expect(response()).toBeUndefined();
      expect(button("Continue").disabled).toBe(false);
      await act(async () => button("Continue").click());
    }
    expect(response()).toEqual({
      outcome: { outcome: "selected", optionId: choice.optionId },
    });
    expect(session.pendingQuestion).toBeUndefined();
    expect(container.textContent).not.toContain(questionTitle);
  });

  it("cancels the ACP interaction when the user skips", async () => {
    expect(container.textContent).toContain(questionTitle);
    expect(response()).toBeUndefined();
    await act(async () => {
      const skip = name === "chat card"
        ? container.querySelector<HTMLButtonElement>('button[aria-label="Skip this question"]')!
        : button("Skip");
      skip.click();
    });
    expect(response()).toEqual({ outcome: { outcome: "cancelled" } });
    expect(session.pendingQuestion).toBeUndefined();
    expect(container.textContent).not.toContain(questionTitle);
  });
});
