// @vitest-environment happy-dom
import { act, createElement, StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { XCapture } from "../model/feedContext";
import { XFeedPane } from "./XFeedPane";

const { invoke, openUrl } = vi.hoisted(() => ({ invoke: vi.fn(), openUrl: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl }));
const capture: XCapture = { url: "https://x.com/a/status/1", title: "A post / X", selection: "selected text", posts: [] };
let container: HTMLDivElement;
let root: Root;
const onSendToAgent = vi.fn();
const onSaveNote = vi.fn();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  invoke.mockReset().mockResolvedValue(undefined);
  openUrl.mockReset().mockResolvedValue(undefined);
  onSendToAgent.mockReset();
  onSaveNote.mockReset().mockResolvedValue(undefined);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});
const mount = () => act(async () => root.render(createElement(StrictMode, null,
  createElement(XFeedPane, { onSendToAgent, onSaveNote }))));
async function click(label: string) {
  const button = [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent?.includes(label));
  if (!button) throw new Error(`Missing button: ${label}`);
  await act(async () => button.click());
}

describe("X capture lifecycle", () => {
  it.each(["Send to agent", "Save as note", "Open in browser"])("ignores a pending %s capture after the panel unmounts", async (label) => {
    let resolve!: (value: XCapture) => void;
    const pending = new Promise<XCapture>((yes) => { resolve = yes; });
    invoke.mockImplementation((command: string) => command === "x_feed_capture" ? pending : Promise.resolve());
    await mount();
    await click(label);
    expect(invoke).toHaveBeenCalledWith("x_feed_capture");
    await act(async () => root.render(null));
    expect(invoke).toHaveBeenCalledWith("x_feed_hide", undefined);
    await act(async () => resolve(capture));
    expect(onSendToAgent).not.toHaveBeenCalled();
    expect(onSaveNote).not.toHaveBeenCalled();
    expect(openUrl).not.toHaveBeenCalled();

    // A new mounted panel still performs the requested action.
    invoke.mockImplementation((command: string) => command === "x_feed_capture" ? Promise.resolve(capture) : Promise.resolve());
    await mount();
    await click(label);
    if (label === "Send to agent") expect(onSendToAgent).toHaveBeenCalledExactlyOnceWith(capture);
    else if (label === "Save as note") expect(onSaveNote).toHaveBeenCalledOnce();
    else expect(openUrl).toHaveBeenCalledExactlyOnceWith(capture.url);
  });
});
