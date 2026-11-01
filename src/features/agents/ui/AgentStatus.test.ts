// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AgentStatus } from "./AgentStatus";
import type { AgentState } from "../model/agent";

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

function render(state: AgentState) {
  act(() => root.render(createElement(AgentStatus, { state })));
}

it("shows the step a working mentor is on as the header's one line", () => {
  render({ status: "working", activity: "Saved source: Virtio 1.2 — Virtqueues" });
  const line = container.querySelector("[data-agent-activity]")!;
  expect(line.textContent).toBe("Saved source: Virtio 1.2 — Virtqueues");
  expect(line.getAttribute("title")).toBe(
    "Working · Saved source: Virtio 1.2 — Virtqueues",
  );
  expect(line.querySelector("svg")).not.toBeNull();
});

it("keeps the short label while it needs you or is idle", () => {
  render({ status: "needs-you", activity: "Approve npm publish" });
  expect(container.textContent).toBe("Needs you");
  expect(container.querySelector("[data-agent-activity]")).toBeNull();

  render({ status: "idle" });
  expect(container.textContent).toBe("Idle");
});
