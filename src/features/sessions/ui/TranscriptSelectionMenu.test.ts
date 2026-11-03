// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TranscriptSelectionMenu } from "./TranscriptSelectionMenu";

const platform = vi.hoisted(() => ({ isMac: true }));
vi.mock("../../../platform/tauri/platform", () => ({ get IS_MAC() { return platform.isMac; } }));

let container: HTMLDivElement;
let root: Root;
const selection = { text: "Keep this", rect: new DOMRect(10, 20, 100, 20), blockId: "b1" };

beforeEach(() => {
  platform.isMac = true;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  document.querySelectorAll("[data-test-editable]").forEach((element) => element.remove());
  vi.unstubAllGlobals();
});

const render = (props: Partial<ComponentProps<typeof TranscriptSelectionMenu>>) => act(() => root.render(createElement(TranscriptSelectionMenu, {
  selection, onDismiss: vi.fn(), ...props,
})));
const buttons = () => [...document.querySelectorAll<HTMLButtonElement>('[role="toolbar"] button')];
const button = (label: string) => buttons().find((entry) => entry.textContent === label)!;
const key = async (options: KeyboardEventInit, target: EventTarget = window) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...options });
  await act(async () => target.dispatchEvent(event));
  return event;
};

describe("TranscriptSelectionMenu", () => {
  it("is the reader's bar: Highlight and Ask, nothing asking which note", () => {
    render({ onKeep: vi.fn(), onAddToChat: vi.fn() });
    expect(buttons().map((entry) => entry.textContent)).toEqual(["Highlight", "Ask"]);
    expect(document.querySelector('[role="menu"]')).toBeNull();
  });

  it("keeps the passage in the mentor's highlights and goes away", async () => {
    const onKeep = vi.fn(async () => undefined);
    const onDismiss = vi.fn();
    render({ onKeep, onDismiss });
    await act(async () => button("Highlight").click());
    expect(onKeep).toHaveBeenCalledWith("Keep this");
    expect(onDismiss).toHaveBeenCalledOnce();
  });

  it("quotes the passage in the reply with its block", async () => {
    const onAddToChat = vi.fn();
    render({ onAddToChat, onKeep: vi.fn() });
    await act(async () => button("Ask").click());
    expect(onAddToChat).toHaveBeenCalledWith("Keep this", "b1");
  });

  it("keeps the selection and says why when keeping it fails", async () => {
    let rejectKeep!: (reason: Error) => void;
    const onDismiss = vi.fn();
    render({ onKeep: () => new Promise((_resolve, reject) => { rejectKeep = reject; }), onDismiss });
    await act(async () => button("Highlight").click());
    expect(button("Highlight").disabled).toBe(true);
    await act(async () => rejectKeep(new Error("Disk full")));
    expect(document.querySelector('[role="alert"]')?.textContent).toContain("Disk full");
    expect(button("Highlight").disabled).toBe(false);
    expect(onDismiss).not.toHaveBeenCalled();
  });

  it("highlights with H and asks with ⌘L, but leaves typing alone", async () => {
    const onKeep = vi.fn();
    const onAddToChat = vi.fn();
    render({ onKeep, onAddToChat });
    const input = document.createElement("input");
    input.dataset.testEditable = "true";
    document.body.append(input);
    expect((await key({ code: "KeyH", key: "h" }, input)).defaultPrevented).toBe(false);
    expect(onKeep).not.toHaveBeenCalled();
    expect((await key({ code: "KeyH", key: "h" })).defaultPrevented).toBe(true);
    expect(onKeep).toHaveBeenCalledWith("Keep this");
    render({ onKeep, onAddToChat });
    expect((await key({ code: "KeyL", key: "l", metaKey: true })).defaultPrevented).toBe(true);
    expect(onAddToChat).toHaveBeenCalledWith("Keep this", "b1");
  });

  it("shows only what the conversation offers", () => {
    render({ onAddToChat: vi.fn() });
    expect(buttons().map((entry) => entry.textContent)).toEqual(["Ask"]);
  });
});
