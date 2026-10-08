// @vitest-environment happy-dom
import { act, createElement, type RefObject } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { appendCanvasText } from "../../features/canvas/saveToCanvas";
import type { Canvas } from "../../features/canvas/canvas";
import { SelectCanvasDialog } from "../../features/canvas/ui/SelectCanvasDialog";
import { useSaveToCanvas } from "./useSaveToCanvas";
import { leaf, canvasLeaf, type WorkspaceTab } from "../../features/workspace/model/layout";

vi.mock("../../features/canvas/saveToCanvas", () => ({ appendCanvasText: vi.fn() }));
const canvas = (id: string, cwd = "/project"): Canvas => ({ id, cwd, title: id, tags: [], dataJson: '{"elements":[]}', createdAt: 1, updatedAt: 1 });
let root: Root;
let container: HTMLDivElement;
let save: (text: string) => Promise<void>;
let currentSelection: ReturnType<typeof useSaveToCanvas>["selection"];
const workspaceRef = { current: {
  tabsRef: { current: [{ kind: "session", id: "chat", focusedId: "chat", layout: leaf("chat") } as WorkspaceTab] },
  activeTabIdRef: { current: "chat" }, projectCwdRef: { current: "/project" },
} };
const appendToCanvasRef: RefObject<Map<string, (text: string) => void>> = { current: new Map() };
function Harness({ canvases }: { canvases: Canvas[] }) {
  const options = { canvases, workspaceRef, appendToCanvasRef };
  const result = useSaveToCanvas(options);
  save = result.saveToCanvas;
  currentSelection = result.selection;
  return result.selection ? createElement(SelectCanvasDialog, {
    canvases: result.selection.canvases, onSelect: result.selection.resolver,
    onCancel: () => result.selection!.rejecter(new DOMException("Cancelled", "AbortError")),
  }) : null;
}
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.spyOn(Element.prototype, "scrollIntoView").mockImplementation(() => {});
  vi.mocked(appendCanvasText).mockReset().mockResolvedValue(canvas("saved"));
  workspaceRef.current.projectCwdRef.current = "/project";
  workspaceRef.current.tabsRef.current[0].layout = leaf("chat");
  appendToCanvasRef.current.clear();
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount()); container.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals();
});
const render = (canvases: Canvas[]) => act(async () => root.render(createElement(Harness, { canvases })));

it("saves to the only project canvas even when its editor is not mounted", async () => {
  await render([canvas("only"), canvas("other", "/other")]);
  await act(async () => save("reply"));
  expect(appendCanvasText).toHaveBeenCalledWith("only", "reply");
  expect(currentSelection).toBeNull();
});
it("offers multiple saved canvases and writes only to the selected one", async () => {
  await render([canvas("first"), canvas("second")]);
  let pending!: Promise<void>;
  await act(async () => { pending = save("reply"); void pending.catch(() => {}); });
  expect(document.querySelector('[role="dialog"]')).not.toBeNull();
  expect(document.querySelector('[role="dialog"]')!.textContent).toContain("second");
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => {
    const button = [...document.querySelectorAll<HTMLButtonElement>("button")].find((b) => b.textContent?.includes("second"))!;
    button.click(); await pending;
  });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "reply");
  expect(currentSelection).toBeNull();
});
it("still asks when multiple canvases are mounted beside the chat", async () => {
  const append = vi.fn();
  appendToCanvasRef.current.set("first", append);
  appendToCanvasRef.current.set("second", append);
  workspaceRef.current.tabsRef.current[0].layout = { type: "split", id: "split", dir: "right", sizes: [0.34, 0.33, 0.33], children: [leaf("chat"), canvasLeaf("first"), canvasLeaf("second")] };
  await render([canvas("first"), canvas("second")]);
  let pending!: Promise<void>;
  await act(async () => { pending = save("reply"); void pending.catch(() => {}); });
  expect(document.querySelector('[role="dialog"]')).not.toBeNull();
  expect(append).not.toHaveBeenCalled();
  await act(async () => { currentSelection!.resolver("second"); await pending; });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "reply");
});
