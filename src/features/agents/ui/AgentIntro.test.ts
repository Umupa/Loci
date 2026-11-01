// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AgentIntro } from "./AgentIntro";

let root: Root;
let host: HTMLDivElement;
const agent = { id: "agent", name: "Ada", avatar: "ember", color: "#f28c28", projects: [] };

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.clearAllMocks();
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
});

it("starts every mentor with the learning greeting and no setup controls", () => {
  act(() => root.render(createElement(AgentIntro, { agent })));
  expect(host.textContent).toContain("What do you want to learn?");
  expect(host.textContent).toContain("Name a topic and what you already know.");
  expect(host.querySelector("button, input, select, textarea")).toBeNull();
});

it("keeps the greeting when the agent's free-text role says tutor", () => {
  act(() => root.render(createElement(AgentIntro, {
    agent: { ...agent, role: "tutor", projects: ["/projects/Study"] },
  })));
  expect(host.textContent).toContain("What do you want to learn?");
  expect(host.textContent).toContain("set up a course with you.");
  expect(host.querySelector("button, input, select, textarea")).toBeNull();
});
