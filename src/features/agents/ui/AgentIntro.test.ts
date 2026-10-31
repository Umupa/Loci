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

it("starts a blank agent from a sentence without asking the user to configure it", () => {
  act(() => root.render(createElement(AgentIntro, { agent })));
  expect(host.textContent).toContain("What would you like help with?");
  expect(host.textContent).toContain("A sentence is enough.");
  expect(host.querySelector("button, input, select, textarea")).toBeNull();
});

it("lets Tutor start from a topic without presenting folders as projects", () => {
  act(() => root.render(createElement(AgentIntro, {
    agent: { ...agent, role: "tutor", projects: ["/projects/Study"] },
  })));
  expect(host.textContent).toContain("What would you like to learn?");
  expect(host.textContent).toContain("A topic is enough.");
  expect(host.textContent).not.toContain("Works on");
  expect(host.querySelector("button, input, select, textarea")).toBeNull();
});
