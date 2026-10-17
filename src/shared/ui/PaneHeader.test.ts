// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { PaneHeader, PaneHeaderChrome } from "./PaneHeader";
import { AgentView } from "../../features/agents/ui/AgentView";

let host: HTMLDivElement;
let root: Root;
const drag = vi.fn();
const click = vi.fn();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.clearAllMocks();
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
});

function render(chrome: { windowTop: boolean; leadingInset: number } | null) {
  act(() => root.render(createElement(PaneHeaderChrome.Provider, { value: chrome },
    createElement(PaneHeader, { onPaneDragStart: drag },
      createElement("h2", null, "Network strategy"),
      createElement("button", { onClick: click }, "Details")))));
}
function pointer(target: Element, button = 0) {
  act(() => target.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, button })));
}

it("leaves window dragging to the background and pane dragging to the grip", () => {
  render({ windowTop: true, leadingInset: 142 });
  const header = host.querySelector("header")!;
  const grip = host.querySelector("[data-pane-drag-handle]")!;
  expect(header.dataset.tauriDragRegion).toBe("deep");
  expect(grip.getAttribute("data-tauri-drag-region")).toBe("false");
  pointer(header);
  pointer(host.querySelector("h2")!);
  pointer(host.querySelector("button")!);
  expect(drag).not.toHaveBeenCalled();
  pointer(grip, 2);
  expect(drag).not.toHaveBeenCalled();
  pointer(grip);
  expect(drag).toHaveBeenCalledOnce();
  act(() => host.querySelector<HTMLButtonElement>("button")!.click());
  expect(click).toHaveBeenCalledOnce();
});

it("keeps the grip behavior after a pane moves below the window titlebar", () => {
  render({ windowTop: false, leadingInset: 0 });
  const header = host.querySelector("header")!;
  expect(header.hasAttribute("data-tauri-drag-region")).toBe(false);
  expect(header.classList.contains("h-9")).toBe(true);
  pointer(header);
  expect(drag).not.toHaveBeenCalled();
  pointer(host.querySelector("[data-pane-drag-handle]")!);
  expect(drag).toHaveBeenCalledOnce();
});

it("preserves title dragging in workspaces with a separate window toolbar", () => {
  render(null);
  expect(host.querySelector("[data-tauri-drag-region]")).toBeNull();
  pointer(host.querySelector("h2")!);
  expect(drag).toHaveBeenCalledOnce();
  pointer(host.querySelector("button")!);
  expect(drag).toHaveBeenCalledOnce();
});

it("keeps readers inside agent Details out of the window titlebar", () => {
  act(() => root.render(createElement(PaneHeaderChrome.Provider, { value: { windowTop: true, leadingInset: 92 } },
    createElement(AgentView, {
      agent: { id: "agent", name: "Ada", avatar: "luna", color: "#66aacc", projects: [] },
      state: { status: "idle" }, detailsOpen: true, focused: true, onFocus: vi.fn(), onToggleDetails: vi.fn(),
      children: createElement(PaneHeader, { "aria-label": "Inline reader" }, "Source excerpt"),
      details: createElement(PaneHeader, { "aria-label": "Library reader" }, "Network strategy"),
    }))));
  expect(host.querySelectorAll("[data-window-titlebar]")).toHaveLength(1);
  for (const label of ["Library reader", "Inline reader"]) {
    const reader = host.querySelector<HTMLElement>(`[aria-label="${label}"]`)!;
    expect(reader.hasAttribute("data-tauri-drag-region")).toBe(false);
    expect(reader.style.paddingLeft).toBe("");
    expect(reader.classList.contains("h-9")).toBe(true);
  }
});
