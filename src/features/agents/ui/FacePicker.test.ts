// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { FacePicker } from "./agentPanelParts";

let root: Root;
let host: HTMLDivElement;
const onPick = vi.fn();

function render(current = "dew", color = "#7a82ff") {
  act(() => root.render(createElement(FacePicker, { current, color, onPick })));
}

function styleButton(label: string) {
  return [...host.querySelectorAll<HTMLButtonElement>('[aria-label="Avatar style"] button')]
    .find((button) => button.textContent === label)!;
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

it.each([
  ["dew", "Bottts", false],
  ["neutral-dew", "Bottts Neutral", true],
] as const)("opens %s's series with only its ten faces mounted", (current, label, neutral) => {
  render(current);
  expect(styleButton(label).getAttribute("aria-pressed")).toBe("true");
  expect(host.querySelectorAll('[role="radiogroup"]')).toHaveLength(1);
  expect(host.querySelectorAll('[role="radio"]')).toHaveLength(10);
  expect(host.querySelectorAll("svg")).toHaveLength(10);
  expect(faces().every((face) => face.dataset.agentAvatar!.startsWith("neutral-") === neutral)).toBe(true);
  const selected = host.querySelector('[role="radio"][aria-checked="true"]')!;
  expect(selected.querySelector<SVGSVGElement>("svg")!.dataset.agentAvatar).toBe(current);
});

it("browses a series without selecting a face and preserves the color when choosing one", () => {
  render();
  act(() => styleButton("Bottts Neutral").click());
  expect(styleButton("Bottts Neutral").getAttribute("aria-pressed")).toBe("true");
  expect(styleButton("Bottts").getAttribute("aria-pressed")).toBe("false");
  expect(onPick).not.toHaveBeenCalled();
  expect(faces()).toHaveLength(10);
  expect(faces().every((face) => face.dataset.agentAvatar!.startsWith("neutral-"))).toBe(true);
  expect(host.querySelectorAll('[aria-checked="true"]')).toHaveLength(0);
  for (const face of faces()) expect(face.style.color).toBe("#7a82ff");

  const choice = host.querySelector<HTMLButtonElement>('[role="radio"][aria-label="Luna"]')!;
  act(() => choice.click());
  expect(onPick).toHaveBeenCalledExactlyOnceWith("neutral-luna");
  render("neutral-luna");
  expect(host.querySelector('[aria-checked="true"] svg')?.getAttribute("data-agent-avatar")).toBe("neutral-luna");
  for (const face of faces()) expect(face.style.color).toBe("#7a82ff");
});

it("keeps the browsed series when only the color changes, and follows a new saved face", () => {
  render();
  act(() => styleButton("Bottts Neutral").click());
  render("dew", "#f28c28");
  expect(styleButton("Bottts Neutral").getAttribute("aria-pressed")).toBe("true");
  for (const face of faces()) expect(face.style.color).toBe("#f28c28");
  expect(onPick).not.toHaveBeenCalled();

  render("moss", "#f28c28");
  expect(styleButton("Bottts").getAttribute("aria-pressed")).toBe("true");
  expect(faces()).toHaveLength(10);
  expect(host.querySelector('[aria-checked="true"] svg')?.getAttribute("data-agent-avatar")).toBe("moss");
  render("neutral-tide", "#f28c28");
  expect(styleButton("Bottts Neutral").getAttribute("aria-pressed")).toBe("true");
  expect(faces()).toHaveLength(10);
  expect(host.querySelector('[aria-checked="true"] svg')?.getAttribute("data-agent-avatar")).toBe("neutral-tide");
  expect(onPick).not.toHaveBeenCalled();
});
