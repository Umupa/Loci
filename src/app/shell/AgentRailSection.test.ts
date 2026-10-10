// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Agent, AgentState } from "../../features/agents/model/agent";
import { AgentRailSection } from "./AgentRailSection";

const roster: Agent[] = ["Ada", "Bea", "Cy", "Dee", "Eli", "Fay"].map((name, index) => ({
  id: `agent-${index}`,
  name,
  avatar: "ember",
  color: "#66aacc",
  projects: [],
}));
const onOpen = vi.fn();
const onOpenDetails = vi.fn();
const onCreate = vi.fn();
const onDelete = vi.fn();
let root: Root;
let container: HTMLDivElement;

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class {
    observe() {}
    disconnect() {}
  });
  vi.clearAllMocks();
  localStorage.clear();
  // Use the real subscriptions with synthetic data; no App, provider or IPC.
  localStorage.setItem("loci:agent-roster", JSON.stringify(roster));
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  localStorage.clear();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function render(props: Partial<ComponentProps<typeof AgentRailSection>> = {}) {
  act(() => root.render(createElement(AgentRailSection, {
    states: new Map<string, AgentState>(),
    onOpen,
    onOpenDetails,
    onCreate,
    onDelete,
    ...props,
  })));
}

function row(index = 0) {
  return container.querySelector<HTMLElement>(`[data-agent-id="agent-${index}"]`)!;
}

function chatButton(index = 0) {
  return row(index).querySelector<HTMLButtonElement>(`button[aria-label^="${roster[index].name},"]`)!;
}

function signal(index = 0) {
  return row(index).querySelector<HTMLElement>("[data-agent-rail-signal]");
}

it("distinguishes activity signals and sweeps a highlight only across working agent names", () => {
  render({
    states: new Map<string, AgentState>([
      ["agent-0", { status: "working", activity: "Thinking" }],
      ["agent-1", { status: "working", activity: "Run npm test" }],
      ["agent-2", { status: "working", activity: "Writing a reply" }],
      ["agent-3", { status: "needs-you", activity: "Waiting for approval" }],
      ["agent-4", { status: "idle" }],
    ]),
    unseenIds: new Set(["agent-4"]),
  });

  expect(container.querySelector("[data-agent-rail]")).not.toBeNull();
  expect(roster.map((_, index) => row(index).dataset.agentRailPhase)).toEqual([
    "thinking", "working", "responding", "needs-you", "updated", "idle",
  ]);
  expect(signal(0)?.title).toBe("Thinking");
  expect(signal(1)?.title).toBe("Working");
  expect(signal(2)?.title).toBe("Replying");
  expect(signal(3)?.title).toBe("Needs you");
  expect(signal(4)?.title).toBe("New update");
  expect(chatButton(5).getAttribute("aria-label")).toContain("Idle");
  expect(chatButton(1).getAttribute("aria-label")).toContain("Run npm test");
  for (const index of [0, 1, 2]) {
    expect(row(index).querySelector(".shimmer-text")?.textContent).toBe(roster[index].name);
  }
  for (const index of [3, 4, 5]) {
    expect(row(index).querySelector(".shimmer-text")).toBeNull();
    expect(chatButton(index).textContent).toContain(roster[index].name);
  }
  expect(container.querySelector("[data-work-model], [data-work-provider]")).toBeNull();
});

it("keeps a request for the user prominent even when that agent also has an unread update", () => {
  render({
    states: new Map([["agent-0", { status: "needs-you", activity: "Approve npm test" }]]),
    unseenIds: new Set(["agent-0"]),
  });

  expect(row().dataset.agentRailPhase).toBe("needs-you");
  expect(signal()?.title).toBe("Needs you");
  expect(chatButton().getAttribute("aria-label")).toContain("Needs you");
  expect(chatButton().getAttribute("aria-label")).toContain("Approve npm test");
});

it("clears the unread signal and accessible update hint when the agent is selected", () => {
  const unseenIds = new Set(["agent-0"]);
  render({ unseenIds });
  expect(row().dataset.agentRailPhase).toBe("updated");
  expect(chatButton().getAttribute("aria-label")).toContain("New update");

  render({ unseenIds, activeId: "agent-0" });
  expect(row().dataset.agentRailPhase).toBe("idle");
  expect(signal()?.title).not.toBe("New update");
  expect(chatButton().getAttribute("aria-label")).not.toContain("New update");
  expect(chatButton().getAttribute("aria-current")).toBe("true");
});

it("opens the conversation from its row while the options menu keeps actions separate", () => {
  render();
  act(() => chatButton().click());
  expect(onOpen).toHaveBeenCalledExactlyOnceWith("agent-0");
  onOpen.mockClear();

  const options = row().querySelector<HTMLButtonElement>('button[aria-label="Ada options"]')!;
  act(() => options.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, button: 0 })));
  act(() => options.click());
  expect(onOpen).not.toHaveBeenCalled();
  const menu = document.querySelector('[role="menu"][aria-label="Ada options"]')!;
  expect(menu).not.toBeNull();
  const details = [...menu.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')]
    .find((button) => button.textContent?.trim() === "Details")!;
  act(() => details.click());
  expect(onOpenDetails).toHaveBeenCalledExactlyOnceWith("agent-0");
  expect(onOpen).not.toHaveBeenCalled();
});

it("removes the live signal when work settles and leaves idle avatars without animation timers", () => {
  render({ states: new Map([["agent-0", { status: "working", activity: "Thinking" }]]) });
  const before = row();
  expect(before.dataset.agentRailPhase).toBe("thinking");
  expect(before.querySelector(".shimmer-text")?.textContent).toBe("Ada");

  render({ states: new Map([["agent-0", { status: "idle" }]]) });
  expect(row()).toBe(before);
  expect(row().dataset.agentRailPhase).toBe("idle");
  expect(signal()?.title).not.toBe("Thinking");
  expect(row().querySelector(".shimmer-text")).toBeNull();
  expect(container.querySelector(".agent-avatar-preview")).toBeNull();
  expect(vi.getTimerCount()).toBe(0);
  act(() => vi.advanceTimersByTime(60_000));
  expect(vi.getTimerCount()).toBe(0);
  expect(container.querySelector("[data-blinking]")).toBeNull();
});
