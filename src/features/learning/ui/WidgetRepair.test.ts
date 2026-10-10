// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { askAboutWidget } from "../model/widgetContext";
import type { StoredWidget } from "../model/types";
import { WidgetCard, WidgetHostContext } from "./WidgetCard";
import { WidgetFrame } from "./WidgetFrame";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../sessions/model/quoteDraft", () => ({ requestAddToChat: vi.fn() }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));
vi.mock("../model/widgetRuntime", async (importOriginal) => ({
  ...await importOriginal<typeof import("../model/widgetRuntime")>(),
  WIDGET_PROXY_URL: "about:blank",
}));

class TestPort {
  onmessage: ((event: MessageEvent) => void) | null = null;
  postMessage = vi.fn();
  start = vi.fn();
  close = vi.fn();
}
const ports: TestPort[] = [];
let container: HTMLDivElement;
let root: Root;
const broken = '---\nid: cache\n---\n<div>Cache</div><script>const example = "```js";</script>';

beforeEach(() => {
  vi.clearAllMocks();
  ports.length = 0;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("MessageChannel", class {
    port1 = new TestPort();
    port2 = new TestPort();
    constructor() { ports.push(this.port1); }
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });
const fixButton = () => [...container.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Prepare fix")!;

it("prepares malformed output for its original ordinary conversation only on a user click", async () => {
  await act(async () => root.render(createElement(WidgetHostContext.Provider, { value: { owner: { kind: "session", id: "session-owner" }, sourceSessionId: "original-chat" } }, createElement(WidgetCard, { source: broken, incomplete: false }))));
  expect(requestAddToChat).not.toHaveBeenCalled();
  await act(async () => fixButton().click());
  expect(requestAddToChat).toHaveBeenCalledWith(expect.stringContaining("````loci-widget\n" + broken + "\n````"), "plain", { targetSessionId: "original-chat" });
  expect(invoke).not.toHaveBeenCalled();
});

it("addresses a malformed resident explanation to the agent's current conversation", async () => {
  vi.mocked(findAgent).mockReturnValue({ id: "agent-owner", sessionId: "current-agent-chat", avatar: "", color: "", projects: [] });
  await act(async () => root.render(createElement(WidgetHostContext.Provider, { value: { owner: { kind: "agent", id: "agent-owner" }, sourceSessionId: "old-agent-chat" } }, createElement(WidgetCard, { source: broken, incomplete: false }))));
  await act(async () => fixButton().click());
  expect(requestAddToChat).toHaveBeenCalledWith(expect.any(String), "plain", { targetSessionId: "current-agent-chat" });
  expect(invoke).not.toHaveBeenCalled();
});

it("keeps standalone malformed source readable without offering an untargeted fix", async () => {
  await act(async () => root.render(createElement(WidgetCard, { source: broken, incomplete: false })));
  expect(fixButton()).toBeUndefined();
  expect(container.querySelector("pre")?.textContent).toBe(broken);
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("prepares a same-id runtime repair with state and error, without sending or invoking native commands", async () => {
  const widget: StoredWidget = { owner: { kind: "session", id: "owning-chat" }, id: "cache", title: "Cache explanation", html: "<div>Cache</div>", sourceIds: [], sourceSessionId: "owning-chat", sourceBlockId: "assistant-a", revision: 2, saved: false, state: { age: 22 }, createdAt: 1, updatedAt: 2 };
  await act(async () => root.render(createElement(WidgetFrame, { widget, onAsk: (text) => askAboutWidget(widget, text), onOpenSource: vi.fn() })));
  const iframe = container.querySelector("iframe")!;
  vi.spyOn(iframe.contentWindow!, "postMessage").mockImplementation(() => undefined);
  act(() => iframe.dispatchEvent(new Event("load")));
  act(() => ports[ports.length - 1].onmessage?.(new MessageEvent("message", { data: { type: "error", message: "renderStep is not defined" } })));
  expect(container.textContent).toContain("renderStep is not defined");
  expect(requestAddToChat).not.toHaveBeenCalled();
  await act(async () => fixButton().click());
  expect(requestAddToChat).toHaveBeenCalledWith(expect.stringContaining('沿用 id "cache"'), "plain", expect.objectContaining({ targetSessionId: "owning-chat", widgetContext: expect.objectContaining({ id: "cache", revision: 2, state: { age: 22 } }) }));
  expect(vi.mocked(requestAddToChat).mock.calls[0][0]).toContain("renderStep is not defined");
  expect(invoke).not.toHaveBeenCalled();
});

it("passes host presentation tokens to the sandbox and refreshes them without reloading its content", async () => {
  document.documentElement.style.setProperty("--color-background-base", "#fafafa");
  document.documentElement.style.setProperty("--color-content", "#222222");
  document.documentElement.style.setProperty("--font-sans", "Georgia");
  const widget: StoredWidget = { owner: { kind: "session", id: "theme-chat" }, id: "theme", title: "Theme", html: "<p>Theme</p>", sourceIds: [], sourceSessionId: "theme-chat", sourceBlockId: "reply", revision: 1, saved: false, state: { step: 2 }, createdAt: 1, updatedAt: 1 };
  try {
    await act(async () => root.render(createElement(WidgetFrame, { widget, onAsk: vi.fn(), onOpenSource: vi.fn() })));
    const iframe = container.querySelector("iframe")!;
    const initialize = vi.spyOn(iframe.contentWindow!, "postMessage").mockImplementation(() => undefined);
    act(() => iframe.dispatchEvent(new Event("load")));
    expect(initialize).toHaveBeenCalledWith(expect.objectContaining({ tokens: expect.objectContaining({ "--loci-background": "#fafafa", "--loci-text": "#222222", "--loci-font": "Georgia" }), state: { step: 2 } }), "*", expect.any(Array));
    await act(async () => { document.documentElement.style.setProperty("--color-background-base", "#242424"); });
    expect(ports[ports.length - 1].postMessage).toHaveBeenCalledWith(expect.objectContaining({ type: "theme", tokens: expect.objectContaining({ "--loci-background": "#242424" }) }));
    expect(container.querySelector("iframe")).toBe(iframe);
  } finally {
    for (const property of ["--color-background-base", "--color-content", "--font-sans"]) document.documentElement.style.removeProperty(property);
  }
});
