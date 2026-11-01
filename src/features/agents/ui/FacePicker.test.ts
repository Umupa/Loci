// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AGENT_AVATARS } from "../model/agentAvatars";
import { FacePicker } from "./agentPanelParts";

let root: Root;
let host: HTMLDivElement;
const onPick = vi.fn();

function render(current = "dew", color = "#7a82ff") {
  act(() => root.render(createElement(FacePicker, { current, color, onPick })));
}

function faces() {
  return [...host.querySelectorAll<SVGSVGElement>('[role="radiogroup"][aria-label="Face"] svg')];
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  onPick.mockClear();
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
});

it("shows every face once, with the saved one chosen", () => {
  render("dew");
  expect(host.querySelectorAll('[role="radiogroup"]')).toHaveLength(1);
  expect(faces()).toHaveLength(AGENT_AVATARS.length);
  expect(host.querySelector('[role="radio"][aria-checked="true"] svg')?.getAttribute("data-agent-avatar")).toBe("dew");
});

it("shows a face saved under the earlier neutral name as its own face", () => {
  render("neutral-tide");
  expect(host.querySelectorAll('[aria-checked="true"]')).toHaveLength(1);
  expect(host.querySelector('[aria-checked="true"] svg')?.getAttribute("data-agent-avatar")).toBe("tide");
});

it("picks a face in the agent's color and follows a new color", () => {
  render();
  for (const face of faces()) expect(face.style.color).toBe("#7a82ff");
  act(() => host.querySelector<HTMLButtonElement>('[role="radio"][aria-label="Luna"]')!.click());
  expect(onPick).toHaveBeenCalledExactlyOnceWith("luna");
  render("luna", "#f28c28");
  expect(host.querySelector('[aria-checked="true"] svg')?.getAttribute("data-agent-avatar")).toBe("luna");
  for (const face of faces()) expect(face.style.color).toBe("#f28c28");
});
