// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const menu = vi.hoisted(() => ({ handlers: new Map<string, () => void>() }));
vi.mock("../../platform/transport", () => ({
  transport: { listen: vi.fn(async (event: string, handler: () => void) => { menu.handlers.set(event, handler); return () => menu.handlers.delete(event); }) },
}));
vi.mock("../../platform/tauri/platform", () => ({ IS_MAC: true, IS_WIN: false, IS_LINUX: false, MOD: "⌘", ALT: "⌥", SHIFT: "⇧", HAS_NATIVE_GLASS: true }));

import { useWindowCommands } from "./useWindowCommands";

let root: Root;
const open = vi.fn();
const toggleSearch = vi.fn();
function Harness() { useWindowCommands({ openSettings: open, toggleSearch }); return null; }

beforeEach(async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  open.mockClear();
  toggleSearch.mockClear();
  root = createRoot(document.createElement("div"));
  await act(async () => root.render(createElement(Harness)));
});
afterEach(() => { act(() => root.unmount()); vi.unstubAllGlobals(); });

it("opens Settings with ⌘, and from the menu, as a window of this device does", () => {
  window.dispatchEvent(new KeyboardEvent("keydown", { key: ",", code: "Comma", metaKey: true }));
  expect(open).toHaveBeenCalledOnce();
  window.dispatchEvent(new KeyboardEvent("keydown", { key: ",", code: "Comma" }));
  expect(open).toHaveBeenCalledOnce();
  menu.handlers.get("open_settings")!();
  menu.handlers.get("sidebar_opacity")!();
  expect(open).toHaveBeenCalledTimes(3);
});

it("opens and closes search with ⌘K and from the menu", () => {
  window.dispatchEvent(new KeyboardEvent("keydown", { key: "k", code: "KeyK", metaKey: true }));
  expect(toggleSearch).toHaveBeenCalledOnce();
  menu.handlers.get("open_search")!();
  expect(toggleSearch).toHaveBeenCalledTimes(2);
  expect(open).not.toHaveBeenCalled();
});
