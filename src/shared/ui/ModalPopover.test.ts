// @vitest-environment happy-dom
import { act, createElement, useRef, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { Modal } from "./Modal";
import { Popover } from "./Popover";
import { LAYER } from "../lib/layers";

let host: HTMLDivElement, root: Root;
const close = vi.fn();
function Example({ layer }: { layer?: number }) {
  const anchor = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  return createElement(Modal, { title: "Settings", onClose: close, children: createElement("div", null,
    createElement("button", { ref: anchor, onClick: () => setOpen(true) }, "Choose appearance"),
    open ? createElement(Popover, { anchor, role: "menu", "aria-label": "Appearance", layer, onDismiss: () => setOpen(false), children: createElement("button", null, "Blue") }) : null,
  ) });
}
beforeEach(() => { vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true); close.mockClear(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); vi.unstubAllGlobals(); });
it.each([undefined, LAYER.submenu])("keeps a dialog's menu above the dialog and closes it first on Escape (layer %s)", async (layer) => {
  await act(async () => root.render(createElement(Example, { layer })));
  const trigger = [...document.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Choose appearance")!;
  await act(async () => { trigger.focus(); trigger.click(); });
  const popup = document.querySelector('[role="menu"][aria-label="Appearance"]')!.parentElement!;
  expect(Number(popup.style.zIndex)).toBeGreaterThan(LAYER.dialog);
  await act(async () => trigger.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(document.querySelector('[role="menu"]')).toBeNull();
  expect(close).not.toHaveBeenCalled();
  await act(async () => trigger.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(close).toHaveBeenCalledOnce();
});
