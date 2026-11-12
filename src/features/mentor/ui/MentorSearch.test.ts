// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Agent } from "../../agents/model/agent";
import type { Note } from "../../notes";
import { MentorSearch } from "./MentorSearch";

const agents: Agent[] = [{ id: "sandbox", sessionId: "chat-s", name: "Sandbox", avatar: "loci", color: "#123456" }];
const sources = {
  agents, courses: [], documents: new Map(),
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

it("is a combobox in a modal palette that announces its results and keeps Tab inside", async () => {
  const onPick = vi.fn();
  const onClose = vi.fn();
  await act(async () => root.render(createElement(MentorSearch, { sources, onPick, onClose })));
  const dialog = container.querySelector<HTMLElement>('[role="dialog"]')!;
  expect(dialog.getAttribute("aria-modal")).toBe("true");
  const input = () => container.querySelector<HTMLInputElement>('input[aria-label="Search"]')!;
  const status = () => dialog.querySelector<HTMLElement>('[role="status"]')!;
  expect(input().getAttribute("role")).toBe("combobox");
  expect(input().getAttribute("aria-autocomplete")).toBe("list");
  expect(input().getAttribute("aria-expanded")).toBe("true");
  expect(status().textContent).toBe("1 result");
  const option = container.querySelector<HTMLElement>('[role="option"]')!;
  option.focus();
  key(option, { key: "Tab" });
  expect(document.activeElement).toBe(input());
  key(input(), { key: "Tab", shiftKey: true });
  expect(document.activeElement).toBe(option);
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
    setter.call(input(), "nothing here");
    input().dispatchEvent(new Event("input", { bubbles: true }));
  });
  expect(status().textContent).toBe("Nothing matches.");
  expect(input().getAttribute("aria-expanded")).toBe("false");
});

it("closes on Escape without opening anything", async () => {
  const onPick = vi.fn();
  const onClose = vi.fn();
  await act(async () => root.render(createElement(MentorSearch, { sources, onPick, onClose })));
  key(container.querySelector('input[aria-label="Search"]')!, { key: "Escape" });
  expect(onClose).toHaveBeenCalledOnce();
  expect(onPick).not.toHaveBeenCalled();
});

it("finds words in the text of the library and opens the source at them", async () => {
  vi.useFakeTimers();
  try {
    const onPick = vi.fn();
    const searchText = vi.fn(async () => [
      { agentId: "sandbox", kind: "source", id: "virtio", title: "Virtio spec", snippet: "…the driver puts [descriptors] in the ring…" },
      { agentId: "gone", kind: "note", id: "x", title: "Orphan", snippet: "[descriptors]" },
    ]);
    await act(async () => root.render(createElement(MentorSearch, { sources, onPick, onClose: vi.fn(), searchText })));
    const input = container.querySelector<HTMLInputElement>('input[aria-label="Search"]')!;
    await act(async () => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
      setter.call(input, "descriptors");
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await act(async () => { await vi.advanceTimersByTimeAsync(200); });
    expect(searchText).toHaveBeenCalledWith("descriptors");
    const rows = [...container.querySelectorAll<HTMLElement>('[role="option"]')];
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain("Virtio spec");
    expect(rows[0].querySelector(".text-accent-text")?.textContent).toBe("descriptors");
    key(input, { key: "Enter" });
    expect(onPick).toHaveBeenCalledWith(expect.objectContaining({ quote: "descriptors", page: expect.objectContaining({ kind: "document" }) }));
  } finally { vi.useRealTimers(); }
});
