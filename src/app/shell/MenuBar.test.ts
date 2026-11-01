// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { MenuBar } from "./MenuBar";

const native = vi.hoisted(() => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: native.invoke }));

let host: HTMLDivElement;
let root: Root;
const onOpenSettings = vi.fn();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  native.invoke.mockClear();
  onOpenSettings.mockClear();
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  const before = document.createElement("button");
  before.textContent = "Before";
  document.body.append(before);
  before.focus();
});
afterEach(async () => {
  await act(async () => root.unmount());
  document.body.replaceChildren();
  vi.unstubAllGlobals();
});

function mount() {
  act(() => root.render(createElement(MenuBar, {
    onNewMentor: vi.fn(), onCloseReader: vi.fn(), onPreviousMentor: vi.fn(), onNextMentor: vi.fn(),
    onToggleLibrary: vi.fn(), onToggleChat: vi.fn(), onOpenPdf: vi.fn(), onSearch: vi.fn(),
    onOpenSettings, onZoomIn: vi.fn(), onZoomOut: vi.fn(), onZoomReset: vi.fn(),
  })));
}
const tapAlt = () => {
  act(() => { window.dispatchEvent(new KeyboardEvent("keydown", { key: "Alt", bubbles: true })); });
  act(() => { window.dispatchEvent(new KeyboardEvent("keyup", { key: "Alt", bubbles: true })); });
};
const bar = () => document.querySelector<HTMLElement>('[role="menubar"]');
const barButton = (label: string) => [...document.querySelectorAll<HTMLButtonElement>('[role="menubar"] button')].find((button) => button.textContent === label);
const items = () => [...document.querySelectorAll<HTMLElement>('[role="menu"] [role="menuitem"]')];

it("opens over the window on File without moving the layout, and returns focus on Escape", async () => {
  mount();
  expect(bar()).toBeNull();
  tapAlt();
  expect(bar()).not.toBeNull();
  // Positioned over the window rather than in its column, so the workspace stays put.
  expect(bar()!.className).toContain("fixed");
  expect(document.activeElement).toBe(barButton("File"));
  act(() => { barButton("File")!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })); });
  expect(items().some((item) => item.textContent?.startsWith("Settings…"))).toBe(true);
  act(() => { window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); });
  expect(bar()).toBeNull();
  expect(document.querySelector('[role="menu"]')).toBeNull();
  expect(document.activeElement).toBe(document.querySelector("button")!);
});

it("moves between File and View with the arrow keys and opens Exit through the quit command", async () => {
  mount();
  tapAlt();
  act(() => { barButton("File")!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })); });
  expect(document.activeElement).toBe(barButton("View"));
  act(() => { barButton("View")!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true })); });
  expect(document.activeElement).toBe(barButton("File"));
  act(() => { barButton("File")!.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })); });
  const exit = items().find((item) => item.textContent === "Exit")!;
  expect(exit).toBeDefined();
  act(() => exit.click());
  expect(native.invoke).toHaveBeenCalledWith("quit_app");
  expect(bar()).toBeNull();
});
