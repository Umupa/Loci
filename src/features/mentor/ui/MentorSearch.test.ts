// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Agent } from "../../agents/model/agent";
import type { Note } from "../../notes";
import { MentorSearch } from "./MentorSearch";

const agents: Agent[] = [{ id: "sandbox", sessionId: "chat-s", name: "Sandbox", avatar: "loci", color: "#123456", projects: [] }];
const sources = {
  agents, courses: [], documents: new Map(), canvases: [],
  notes: [{ id: "n1", title: "Jailer notes", agentId: "sandbox", body: "", tags: [] } as unknown as Note],
};
let root: Root;
let container: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

const key = (target: Element, init: KeyboardEventInit) => act(() => { target.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init })); });

it("lists mentors at first, filters as you type and opens the chosen result with Enter", async () => {
  const onPick = vi.fn();
  const onClose = vi.fn();
  await act(async () => root.render(createElement(MentorSearch, { sources, onPick, onClose })));
  const options = () => [...container.querySelectorAll<HTMLElement>('[role="option"]')];
  expect(options().map((option) => option.dataset.searchKind)).toEqual(["mentor"]);
  const input = container.querySelector<HTMLInputElement>('input[aria-label="Search"]')!;
  expect(document.activeElement).toBe(input);
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
    setter.call(input, "jail");
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  expect(options().map((option) => option.dataset.searchKind)).toEqual(["note"]);
  expect(options()[0].textContent).toContain("Sandbox");
  key(input, { key: "Enter" });
  expect(onPick).toHaveBeenCalledWith(expect.objectContaining({ id: "note:n1", page: { kind: "note", id: "n1" } }));
  expect(onClose).toHaveBeenCalledOnce();
});

it("closes on Escape without opening anything", async () => {
  const onPick = vi.fn();
  const onClose = vi.fn();
  await act(async () => root.render(createElement(MentorSearch, { sources, onPick, onClose })));
  key(container.querySelector('input[aria-label="Search"]')!, { key: "Escape" });
  expect(onClose).toHaveBeenCalledOnce();
  expect(onPick).not.toHaveBeenCalled();
});
