// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AGENT_TEMPLATES } from "../templates";
import { AgentGallery } from "./AgentGallery";

let root: Root;
let host: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
});

it("offers each ready-made mentor with its Soul, and a blank one", async () => {
  const onPick = vi.fn(), onClose = vi.fn();
  await act(async () => root.render(createElement(AgentGallery, { onPick, onClose })));
  // The user sees mentors, not agents.
  expect(document.querySelector('[role="dialog"]')?.textContent).toContain("New mentor");
  expect(document.body.textContent).not.toMatch(/New agent|Blank agent/);
  const cards = [...document.querySelectorAll<HTMLElement>("[data-agent-template]")];
  expect(cards.map((card) => card.dataset.agentTemplate)).toEqual(["learning-guide", "repo-lens"]);
  expect(AGENT_TEMPLATES.every((template) => template.soul.startsWith("# Soul"))).toBe(true);

  const lens = cards[1];
  await act(async () => [...lens.querySelectorAll("button")].find((button) => button.textContent === "Read Soul")!.click());
  expect(lens.querySelector("pre")?.textContent).toContain("You read an open-source repository");
  // The gallery's filled action follows the app's primary treatment, not a fixed accent fill.
  expect(lens.querySelector<HTMLElement>('[aria-label="Add Lens"]')!.className).toContain("primary-action");
  await act(async () => lens.querySelector<HTMLButtonElement>('[aria-label="Add Lens"]')!.click());
  expect(onPick).toHaveBeenCalledWith(AGENT_TEMPLATES[1]);
  expect(onClose).toHaveBeenCalledOnce();

  await act(async () => [...document.querySelectorAll("button")].find((button) => button.textContent?.includes("Blank mentor"))!.click());
  expect(onPick).toHaveBeenLastCalledWith(null);
});
