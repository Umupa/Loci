// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { TranscriptBlockActions } from "./TranscriptBlockActions";

const DIAGRAM = "```mermaid\ngraph LR\n  A --> B\n```";

let host: HTMLDivElement; let root: Root; let scroller: HTMLDivElement;
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  scroller = document.createElement("div");
  scroller.innerHTML = `<div data-selectable-agent-response="reply-1"><div data-block-kind="mermaid"><svg></svg><span>A</span></div></div>`;
  scroller.querySelector("[data-block-kind]")!.setAttribute("data-block-source", DIAGRAM);
  document.body.append(scroller);
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockImplementation(function (this: Element) {
    return this.hasAttribute("data-block-kind") ? new DOMRect(100, 100, 400, 200) : new DOMRect(0, 0, 800, 800);
  });
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); scroller.remove(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

it("highlights, saves or asks about a diagram in a reply as its Markdown", async () => {
  const onKeep = vi.fn(); const onSaveNote = vi.fn(); const onAddToChat = vi.fn();
  await act(async () => root.render(createElement(TranscriptBlockActions, { scroller, onKeep, onSaveNote, onAddToChat })));
  const open = async () => {
    await act(async () => scroller.querySelector("span")!.dispatchEvent(new PointerEvent("pointerover", { bubbles: true })));
    await act(async () => document.querySelector<HTMLButtonElement>("[data-block-handle]")!.click());
    return document.querySelector('[aria-label="Diagram actions"]')!;
  };
  const press = async (label: string) => {
    const bar = await open();
    await act(async () => [...bar.querySelectorAll("button")].find((entry) => entry.textContent === label)!.click());
  };
  expect([...(await open()).querySelectorAll("button")].map((entry) => entry.textContent)).toEqual(["Highlight", "Save as note", "Ask"]);
  await press("Highlight");
  await press("Save as note");
  await press("Ask");
  expect(onKeep).toHaveBeenCalledWith(DIAGRAM);
  expect(onSaveNote).toHaveBeenCalledWith(DIAGRAM);
  expect(onAddToChat).toHaveBeenCalledWith(DIAGRAM, "reply-1");
});
