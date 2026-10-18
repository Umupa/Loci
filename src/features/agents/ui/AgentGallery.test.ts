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

it("offers each ready-made agent with its Soul, and a blank one", async () => {
  const onPick = vi.fn(), onClose = vi.fn();
  await act(async () => root.render(createElement(AgentGallery, { onPick, onClose })));
  const cards = [...document.querySelectorAll<HTMLElement>("[data-agent-template]")];
  expect(cards.map((card) => card.dataset.agentTemplate)).toEqual(["learning-guide", "repo-lens", "market-brief"]);
  expect(AGENT_TEMPLATES.every((template) => template.soul.startsWith("# Soul"))).toBe(true);

  const lens = cards[1];
  await act(async () => [...lens.querySelectorAll("button")].find((button) => button.textContent === "Read Soul")!.click());
  expect(lens.querySelector("pre")?.textContent).toContain("Repo Lens");
  await act(async () => lens.querySelector<HTMLButtonElement>('[aria-label="Add Lens"]')!.click());
  expect(onPick).toHaveBeenCalledWith(AGENT_TEMPLATES[1]);
  expect(onClose).toHaveBeenCalledOnce();

  await act(async () => [...document.querySelectorAll("button")].find((button) => button.textContent?.includes("Blank agent"))!.click());
  expect(onPick).toHaveBeenLastCalledWith(null);
});
