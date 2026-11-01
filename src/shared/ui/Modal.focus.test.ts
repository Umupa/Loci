// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { Modal } from "./Modal";

let root: Root;
let host: HTMLDivElement;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
});

function open(props: { minimalHeader?: boolean } = {}) {
  act(() => root.render(createElement(Modal, { title: "Agent settings", onClose: vi.fn(), ...props },
    createElement("button", { type: "button" }, "General"),
    createElement("button", { type: "button" }, "Soul"),
  )));
  return document.querySelector<HTMLElement>('[role="dialog"]')!;
}

/** Tabs from whatever holds focus, the way the browser would before the handler runs. */
function tab(shiftKey = false) {
  const from = document.activeElement ?? document.body;
  const event = new KeyboardEvent("keydown", { key: "Tab", shiftKey, bubbles: true, cancelable: true });
  act(() => { from.dispatchEvent(event); });
  return event;
}

it("focuses the panel when a minimal header has no close button to land on", () => {
  const opener = document.createElement("button");
  document.body.append(opener);
  opener.focus();
  const panel = open({ minimalHeader: true });
  expect(document.activeElement).toBe(panel);
  opener.remove();
});

it("keeps Tab inside the dialog and wraps at both ends", () => {
  const panel = open({ minimalHeader: true });
  const controls = panel.querySelectorAll<HTMLButtonElement>("button");
  const close = controls[0];
  const last = controls[2];
  expect(close.getAttribute("aria-label")).toBe("Close");

  last.focus();
  const forward = tab();
  expect(forward.defaultPrevented).toBe(true);
  expect(document.activeElement).toBe(close);

  close.focus();
  const backward = tab(true);
  expect(backward.defaultPrevented).toBe(true);
  expect(document.activeElement).toBe(last);
});

it("pulls Tab in from behind the dialog and returns focus to the opener on close", () => {
  const opener = document.createElement("button");
  document.body.append(opener);
  opener.focus();

  act(() => root.render(createElement(Modal, { title: "Agent settings", onClose: vi.fn() },
    createElement("button", { type: "button" }, "General"),
    createElement("button", { type: "button" }, "Soul"),
  )));
  const panel = document.querySelector<HTMLElement>('[role="dialog"]')!;
  // The close button takes focus on open, as before.
  expect(document.activeElement).toBe(panel.querySelector('button[aria-label="Close"]'));

  act(() => root.render(createElement("div", null, "closed")));
  expect(document.activeElement).toBe(opener);
  opener.remove();
});

it("leaves Tab alone for a dialog stacked on top of it", () => {
  const panel = open({ minimalHeader: true });
  const nested = document.createElement("div");
  nested.setAttribute("role", "dialog");
  const nestedButton = document.createElement("button");
  nested.append(nestedButton);
  panel.append(nested);
  nestedButton.focus();

  const event = tab();
  expect(event.defaultPrevented).toBe(false);
});

it("keeps the focused dialog out of the Tab order until it is opened", () => {
  const panel = open({ minimalHeader: true });
  expect(panel.getAttribute("tabindex")).toBe("-1");
});

it("leaves focus with a control inside that asked for it", () => {
  act(() => root.render(createElement(Modal, { title: "Sign in", onClose: vi.fn(), minimalHeader: true },
    createElement("button", {
      type: "button",
      ref: (node: HTMLButtonElement | null) => node?.focus(),
    }, "Sign in"),
  )));
  const panel = document.querySelector<HTMLElement>('[role="dialog"]')!;
  expect(document.activeElement).toBe(panel.querySelectorAll("button")[1]);
});
