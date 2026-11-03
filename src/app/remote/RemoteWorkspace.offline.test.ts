// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { RemoteSessionClient, RemoteSessionsState } from "./remoteSessions";
import { ReadOnly } from "../../shared/ui/ReadOnly";
import { ConnectionBar } from "./RemoteWorkspace";

let root: Root;
let container: HTMLDivElement;
let state: RemoteSessionsState;
const listeners = new Set<() => void>();
const client = {
  subscribe: (listener: () => void) => { listeners.add(listener); return () => listeners.delete(listener); },
  getSnapshot: () => state,
  connect: vi.fn(async () => undefined),
} as unknown as RemoteSessionClient;

function setStatus(status: RemoteSessionsState["status"]) {
  state = { ...state, status };
  act(() => { for (const listener of listeners) listener(); });
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  state = { status: { state: "connected" }, sessions: [], earlier: new Map(), error: null };
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  act(() => root.render(createElement("div", null,
    createElement(ConnectionBar, { client }),
    createElement(OfflineComposer))));
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

function OfflineComposer() {
  const offline = client.getSnapshot().status.state === "disconnected";
  return createElement(ReadOnly, { readOnly: offline }, createElement("textarea", { "aria-label": "Message" }), createElement("button", null, "Send"));
}

it("says the host is offline and the window read-only, and offers to reconnect", () => {
  expect(container.textContent).toContain("Connected to the host");
  expect([...container.querySelectorAll("button")].some((button) => button.textContent === "Reconnect")).toBe(false);
  setStatus({ state: "disconnected", error: "The tunnel closed" });
  act(() => root.render(createElement("div", null, createElement(ConnectionBar, { client }), createElement(OfflineComposer))));
  const bar = container.querySelector("[data-remote-connection]")!;
  expect(bar.textContent).toContain("The host is offline");
  expect(bar.textContent).toContain("read-only");
  expect(bar.getAttribute("title")).toBe("The tunnel closed");
  const reconnect = [...bar.querySelectorAll("button")].find((button) => button.textContent === "Reconnect")!;
  act(() => reconnect.click());
  expect(client.connect).toHaveBeenCalledOnce();

  // Everything that sends or changes is switched off while offline.
  const fieldset = container.querySelector("fieldset")!;
  expect(fieldset.disabled).toBe(true);
  expect(fieldset.contains(container.querySelector("textarea"))).toBe(true);

  setStatus({ state: "connected" });
  act(() => root.render(createElement("div", null, createElement(ConnectionBar, { client }), createElement(OfflineComposer))));
  expect(container.querySelector("fieldset")!.disabled).toBe(false);
});
