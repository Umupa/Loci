// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { agentCanvasScope } from "../../features/agents/model/agent";
import { appendCanvasText } from "../../features/canvas/saveToCanvas";
import type { Canvas } from "../../features/canvas/canvas";
import { SelectCanvasDialog } from "../../features/canvas/ui/SelectCanvasDialog";
import { useSaveToCanvas } from "./useSaveToCanvas";

vi.mock("../../features/canvas/saveToCanvas", () => ({ appendCanvasText: vi.fn() }));
const canvas = (id: string, cwd = agentCanvasScope("agent-a")): Canvas => ({ id, cwd, title: id, tags: [], dataJson: '{"elements":[]}', createdAt: 1, updatedAt: 1 });
let root: Root;
let container: HTMLDivElement;
let save: ReturnType<typeof useSaveToCanvas>["saveToCanvas"];
let currentSelection: ReturnType<typeof useSaveToCanvas>["selection"];
function Harness({ canvases }: { canvases: Canvas[] }) {
  const result = useSaveToCanvas({ canvases });
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
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount()); container.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals();
});
const render = (canvases: Canvas[]) => act(async () => root.render(createElement(Harness, { canvases })));

it("saves to the only agent library canvas even when its editor is not mounted", async () => {
  await render([canvas("only"), canvas("other-agent", agentCanvasScope("agent-b")), canvas("project", "/project")]);
  await act(async () => expect(save("reply", "agent-a")).resolves.toBe("only"));
  expect(appendCanvasText).toHaveBeenCalledWith("only", "reply");
  expect(currentSelection).toBeNull();
});
it("offers multiple saved canvases and writes only to the selected one", async () => {
  await render([canvas("first"), canvas("second")]);
  let pending!: Promise<string>;
  await act(async () => { pending = save("reply", "agent-a"); void pending.catch(() => {}); });
  expect([...document.querySelectorAll("button")].map((button) => button.textContent?.trim())).toEqual(["first", "second"]);
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => {
    const button = [...document.querySelectorAll<HTMLButtonElement>("button")].find((b) => b.textContent?.includes("second"))!;
    button.click(); await pending;
  });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "reply");
  expect(currentSelection).toBeNull();
});
it("offers only the named agent's canvases, excluding other libraries and projects", async () => {
  await render([
    canvas("first"), canvas("second"),
    canvas("other-agent", agentCanvasScope("agent-b")),
    canvas("similar-agent", agentCanvasScope("agent-ab")),
    canvas("project", "/project"),
    { ...canvas("unscoped"), cwd: undefined },
  ]);
  let pending!: Promise<string>;
  await act(async () => { pending = save("reply", "agent-a"); void pending.catch(() => {}); });
  expect([...document.querySelectorAll("button")].map((button) => button.textContent?.trim())).toEqual(["first", "second"]);
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => { currentSelection!.resolver("second"); await pending; });
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second", "reply");
});

it("reports an empty library and does not save to another agent or project's drawing", async () => {
  await render([canvas("other-agent", agentCanvasScope("agent-b")), canvas("project", "/project")]);
  await expect(save("reply", "agent-a")).rejects.toThrow("No available Canvas in this agent's library");
  expect(appendCanvasText).not.toHaveBeenCalled();
});
it("uses the agent named by each save request", async () => {
  await render([canvas("first-agent"), canvas("second-agent", agentCanvasScope("agent-b"))]);
  await expect(save("reply", "agent-b")).resolves.toBe("second-agent");
  expect(appendCanvasText).toHaveBeenCalledExactlyOnceWith("second-agent", "reply");
});
it("cancels with Escape and permits a fresh save afterward", async () => {
  await render([canvas("first"), canvas("second")]);
  let pending!: Promise<string>;
  let cancelled!: Promise<unknown>;
  await act(async () => { pending = save("cancelled reply", "agent-a"); cancelled = pending.catch((error) => error); });
  await act(async () => { document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); });
  expect(await cancelled).toMatchObject({ name: "AbortError" });
  expect(currentSelection).toBeNull();
  expect(appendCanvasText).not.toHaveBeenCalled();
  await act(async () => { pending = save("new reply", "agent-a"); });
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
  const saving = save("reply", "agent-a").finally(() => { settled = true; });
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
  await act(async () => { cancelled = save("reply", "agent-a").catch((error) => error); });
  await act(async () => root.unmount());
  expect(await cancelled).toMatchObject({ name: "AbortError" });
  expect(appendCanvasText).not.toHaveBeenCalled();
  root = createRoot(container);
});
