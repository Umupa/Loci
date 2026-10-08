// @vitest-environment happy-dom
import { act, createElement } from "react";
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
function Harness({ canvases }: { canvases: Canvas[] }) {
  const options = { canvases, workspaceRef };
  const result = useSaveToCanvas(options);
  save = result.saveToCanvas;
  currentSelection = result.selection;
  return result.selection ? createElement(SelectCanvasDialog, {
    canvases: result.selection.canvases, onSelect: result.selection.resolver,
    anchor: { x: 100, y: 100 },
    onCancel: () => result.selection!.rejecter(new DOMException("Cancelled", "AbortError")),
  }) : null;
}
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.spyOn(Element.prototype, "scrollIntoView").mockImplementation(() => {});
  vi.mocked(appendCanvasText).mockReset().mockResolvedValue(canvas("saved"));
  workspaceRef.current.projectCwdRef.current = "/project";
  workspaceRef.current.tabsRef.current[0].layout = leaf("chat");
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
  expect([...document.querySelectorAll("button")].map((button) => button.textContent?.trim())).toEqual(["first", "second"]);
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => {
    const button = [...document.querySelectorAll<HTMLButtonElement>("button")].find((b) => b.textContent?.includes("second"))!;
    button.click(); await pending;
  });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "reply");
  expect(currentSelection).toBeNull();
});
it("does not automatically choose a canvas in the active tab's layout", async () => {
  workspaceRef.current.tabsRef.current[0].layout = { type: "split", id: "split", dir: "right", sizes: [0.34, 0.33, 0.33], children: [leaf("chat"), canvasLeaf("first"), canvasLeaf("second")] };
  await render([canvas("first"), canvas("second")]);
  let pending!: Promise<void>;
  await act(async () => { pending = save("reply"); void pending.catch(() => {}); });
  expect([...document.querySelectorAll("button")].map((button) => button.textContent?.trim())).toEqual(["first", "second"]);
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => { currentSelection!.resolver("second"); await pending; });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "reply");
});

it("reports an empty project and does not save to another project's drawing", async () => {
  await render([canvas("other", "/other")]);
  await expect(save("reply")).rejects.toThrow("Create a drawing in this project first");
  expect(appendCanvasText).not.toHaveBeenCalled();
});
it("cancels with Escape and permits a fresh save afterward", async () => {
  await render([canvas("first"), canvas("second")]);
  let pending!: Promise<void>;
  let cancelled!: Promise<unknown>;
  await act(async () => { pending = save("cancelled reply"); cancelled = pending.catch((error) => error); });
  await act(async () => { document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); });
  expect(await cancelled).toMatchObject({ name: "AbortError" });
  expect(currentSelection).toBeNull();
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => { pending = save("new reply"); });
  await act(async () => {
    document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
  });
  expect(document.activeElement?.textContent).toContain("second");
  await act(async () => {
    document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    await pending;
  });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "new reply");
});
it("waits for persistence and propagates storage errors", async () => {
  let fail!: (error: Error) => void;
  vi.mocked(appendCanvasText).mockReturnValueOnce(new Promise((_resolve, reject) => { fail = reject; }));
  await render([canvas("only")]);
  let settled = false;
  const saving = save("reply").finally(() => { settled = true; });
  const failed = expect(saving).rejects.toThrow("disk full");
  await Promise.resolve();
  expect(settled).toBe(false);
  fail(new Error("disk full"));
  await failed;
  expect(settled).toBe(true);
});
it("settles the pending selection when the workspace unmounts", async () => {
  await render([canvas("first"), canvas("second")]);
  let cancelled!: Promise<unknown>;
  await act(async () => { cancelled = save("reply").catch((error) => error); });
  await act(async () => root.unmount());
  expect(await cancelled).toMatchObject({ name: "AbortError" });
  expect(appendCanvasText).not.toHaveBeenCalled();
  root = createRoot(container);
});
