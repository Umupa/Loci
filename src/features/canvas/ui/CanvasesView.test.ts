// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { CanvasesView } from "./CanvasesView";
import type { Canvas } from "../canvas";

vi.mock("./CanvasPane", () => ({ CanvasPane: ({ canvas }: { canvas: Canvas }) => createElement("div", { "data-current-canvas": canvas.id }, canvas.title) }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ isMaximized: async () => false, onResized: async () => () => {} }) }));
const canvasMcpProblem = vi.hoisted(() => vi.fn(async (): Promise<string | null> => null));
vi.mock("../mcpServer", () => ({ canvasMcpProblem }));
const base = { dataJson: "{}", tags: [], createdAt: 1, updatedAt: 1 };
const canvases: Canvas[] = [
  { ...base, id: "other", title: "Other drawing", cwd: "/work/B" },
  { ...base, id: "unassigned", title: "Unassigned drawing" },
  { ...base, id: "current", title: "Current drawing", cwd: "/work/A/" },
];
let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();
const props: ComponentProps<typeof CanvasesView> = { canvases, cwd: "/work/A", besideRail: true, compactRail: false, onClose: noop, onToggleSidebar: noop, onOpenCanvas: noop, onNewCanvas: vi.fn(), onTitleChange: noop, onDeleteCanvas: noop, onAddToChat: noop, onRegisterAppend: noop };
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount()); container.remove(); vi.unstubAllGlobals();
});
async function render(cwd = props.cwd) {
  await act(async () => root.render(createElement(CanvasesView, { ...props, cwd })));
}
function rows() { return [...container.querySelectorAll("li button")].map((button) => button.textContent); }
function selected() { return container.querySelector<HTMLElement>("[data-current-canvas]")?.dataset.currentCanvas; }
it("defaults the drawings list and editor to the active project", async () => {
  await render();
  expect(rows()).toHaveLength(1);
  expect(rows()[0]).toContain("Current drawing");
  expect(selected()).toBe("current");
  expect(container.querySelector('[aria-label^="Drawings project filter:"]')).toBeNull();
});
it("follows project changes automatically without a filter control", async () => {
  await render("~");
  expect(rows()).toHaveLength(3);
  await render("/work/B");
  expect(rows()).toHaveLength(1); expect(selected()).toBe("other");
  await render();
  expect(rows()).toHaveLength(1); expect(selected()).toBe("current");
});
it("searches within project scope and clears the editor when nothing matches", async () => {
  await render();
  const input = container.querySelector<HTMLInputElement>('[aria-label="Filter drawings"]')!;
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "Other drawing");
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  expect(rows()).toEqual([]); expect(selected()).toBeUndefined();
  await render("~"); expect(rows()).toHaveLength(1); expect(selected()).toBe("other");
});
it("shows all drawings without a project and an empty editor in an empty project", async () => {
  await render("~"); expect(rows()).toHaveLength(3);
  await render("/work/Empty"); expect(rows()).toEqual([]); expect(selected()).toBeUndefined();
});

it("says why agents cannot draw only when the built-in server cannot start", async () => {
  await render();
  expect(container.querySelector('[role="status"]')).toBeNull();
  await act(async () => root.unmount());
  root = createRoot(container);
  canvasMcpProblem.mockResolvedValueOnce("Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH.");
  await render();
  expect(container.querySelector('[role="status"]')?.textContent).toBe("Agents cannot draw yet. Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH.");
});
const slide = () => act(async () => { await new Promise((resolve) => setTimeout(resolve, 300)); });
const toggle = () => container.querySelector<HTMLButtonElement>('button[aria-label$="drawings list (Ctrl+Shift+B)"], button[aria-label$="drawings list (⌘⇧B)"]');
it("folds the drawings list away completely and brings it back from the same button", async () => {
  localStorage.clear();
  await render();
  expect(container.querySelector('aside[aria-label="Drawings"]')).not.toBeNull();
  expect(toggle()?.getAttribute("aria-pressed")).toBe("true");
  await act(async () => toggle()!.click());
  await slide();
  // Nothing is left behind: no list, no resize handle, and no strip for a reopen arrow.
  expect(container.querySelector('aside[aria-label="Drawings"]')).toBeNull();
  expect(container.querySelector('[aria-label="Resize drawings list"]')).toBeNull();
  expect(container.querySelector('[aria-label="Show drawings list"]')).toBeNull();
  expect(toggle()?.getAttribute("aria-pressed")).toBeNull();
  expect(selected()).toBe("current");
  await act(async () => toggle()!.click());
  expect(container.querySelector('aside[aria-label="Drawings"]')).not.toBeNull();
});
it("remembers the folded list and folds on the toggle shortcut", async () => {
  localStorage.clear();
  await render();
  await act(async () => { window.dispatchEvent(new Event("loci:toggle-secondary-sidebar")); });
  await slide();
  expect(container.querySelector('aside[aria-label="Drawings"]')).toBeNull();
  await act(async () => root.unmount());
  root = createRoot(container);
  await render();
  expect(container.querySelector('aside[aria-label="Drawings"]')).toBeNull();
  await act(async () => toggle()!.click());
  expect(container.querySelector('aside[aria-label="Drawings"]')).not.toBeNull();
});
