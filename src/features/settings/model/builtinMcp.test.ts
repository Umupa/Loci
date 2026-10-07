// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from "vitest";
import { CANVAS_MCP_ENABLED_KEY, loadCanvasMcpEnabled, saveCanvasMcpEnabled, subscribeCanvasMcpEnabled } from "./builtinMcp";

afterEach(() => {
  vi.restoreAllMocks();
  saveCanvasMcpEnabled(true);
  localStorage.clear();
});

it("defaults on and persists an off switch before notifying this window", () => {
  const listener = vi.fn(() => expect(loadCanvasMcpEnabled()).toBe(false));
  const unsubscribe = subscribeCanvasMcpEnabled(listener);
  expect(loadCanvasMcpEnabled()).toBe(true);
  saveCanvasMcpEnabled(false);
  expect(localStorage.getItem(CANVAS_MCP_ENABLED_KEY)).toBe("0");
  expect(listener).toHaveBeenCalledTimes(1);
  unsubscribe();
});

it("reads the off preference saved before the app starts", () => {
  localStorage.setItem(CANVAS_MCP_ENABLED_KEY, "0");
  expect(loadCanvasMcpEnabled()).toBe(false);
});

it("follows changes and resets from another window", () => {
  const listener = vi.fn();
  const unsubscribe = subscribeCanvasMcpEnabled(listener);
  localStorage.setItem(CANVAS_MCP_ENABLED_KEY, "0");
  window.dispatchEvent(new StorageEvent("storage", { key: CANVAS_MCP_ENABLED_KEY }));
  expect(loadCanvasMcpEnabled()).toBe(false);
  expect(listener).toHaveBeenCalledTimes(1);
  window.dispatchEvent(new StorageEvent("storage", { key: "unrelated" }));
  expect(listener).toHaveBeenCalledTimes(1);
  localStorage.clear();
  window.dispatchEvent(new StorageEvent("storage", { key: null }));
  expect(loadCanvasMcpEnabled()).toBe(true);
  expect(listener).toHaveBeenCalledTimes(2);
  unsubscribe();
});

it("still lets the user turn it off when storage rejects the write", () => {
  vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("quota"); });
  saveCanvasMcpEnabled(false);
  expect(loadCanvasMcpEnabled()).toBe(false);
});
