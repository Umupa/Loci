// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PdfAnnotationPopover, PdfAnnotationsList } from "./PdfAnnotations";
import { createPdfAnnotation } from "../model/pdfAnnotations";
import { OPEN_LEARNING_DISCUSSION_EVENT } from "../model/navigation";

describe("reading notes and discussions", () => {
  let host: HTMLDivElement; let root: Root;
  const annotation = { ...createPdfAnnotation({ id: "doc", title: "Book", path: "/book.pdf", fingerprint: "book", createdAt: 1, updatedAt: 1 }, "A useful passage", [{ page: 3, rects: [{ x: 0.1, y: 0.2, width: 0.3, height: 0.1 }] }]), note: "Read again", discussions: [{ sessionId: "session", blockId: "block" }] };
  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });

  it("lists the saved passage and its note, and selects its page anchor", async () => {
    const select = vi.fn();
    await act(async () => root.render(createElement(PdfAnnotationsList, { annotations: [annotation], onSelect: select, onClose: vi.fn() })));
    expect(host.textContent).toContain("Page 3"); expect(host.textContent).toContain("Read again"); expect(host.textContent).toContain("1 discussion");
    const entry = [...host.querySelectorAll("button")].find((button) => button.textContent?.includes("A useful passage"))!;
    await act(async () => entry.click());
    expect(select).toHaveBeenCalledWith(annotation);
  });

  it("orders passages by page and position without rearranging the stored list", async () => {
    const pageOne = { ...annotation, id: "page-one", anchors: [{ page: 1, rects: [{ x: 0.1, y: 0.5, width: 0.3, height: 0.1 }] }] };
    const pageThreeTop = { ...annotation, id: "page-three-top", anchors: [{ page: 3, rects: [{ x: 0.1, y: 0.1, width: 0.3, height: 0.1 }] }] };
    const annotations = [annotation, pageThreeTop, pageOne];
    await act(async () => root.render(createElement(PdfAnnotationsList, { annotations, selectedId: pageThreeTop.id, onSelect: vi.fn(), onClose: vi.fn() })));
    const entries = [...host.querySelectorAll<HTMLButtonElement>("button[aria-pressed]")];
    expect(entries.map((entry) => entry.querySelector(".pdf-annotations__page")?.textContent)).toEqual(["Page 1", "Page 3", "Page 3"]);
    expect(entries.map((entry) => entry.getAttribute("aria-pressed"))).toEqual(["false", "true", "false"]);
    expect(annotations.map((entry) => entry.id)).toEqual([annotation.id, pageThreeTop.id, pageOne.id]);
  });

  it("saves an edited note and prepares a question from the existing annotation", async () => {
    const onSave = vi.fn(async () => {}); const onAsk = vi.fn();
    await act(async () => root.render(createElement(PdfAnnotationPopover, { annotation, anchor: new DOMRect(100, 100, 10, 10), onAsk, onSave, onDelete: vi.fn(async () => {}), onDismiss: vi.fn() })));
    const save = [...document.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Save note")!;
    expect(save.disabled).toBe(true);
    const note = document.querySelector<HTMLTextAreaElement>('[aria-label="Annotation note"]')!;
    await act(async () => {
      Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(note, "How does this compare with the experiment?");
      note.dispatchEvent(new Event("input", { bubbles: true }));
    });
    expect(save.disabled).toBe(false);
    await act(async () => save.click());
    expect(onSave).toHaveBeenCalledWith(annotation, "How does this compare with the experiment?");
    const ask = [...document.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Ask agent")!;
    await act(async () => ask.click());
    expect(onAsk).toHaveBeenCalledWith(annotation);
  });

  it("reopens the linked discussion and removes a mark through its visible controls", async () => {
    const onDelete = vi.fn(async () => {}); const onDismiss = vi.fn();
    const confirm = vi.fn(() => true); vi.stubGlobal("confirm", confirm);
    const receive = vi.fn(); window.addEventListener(OPEN_LEARNING_DISCUSSION_EVENT, receive);
    await act(async () => root.render(createElement(PdfAnnotationPopover, { annotation, anchor: new DOMRect(100, 100, 10, 10), onAsk: vi.fn(), onSave: vi.fn(async () => {}), onDelete, onDismiss })));
    const discussion = [...document.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Open discussion 1")!;
    await act(async () => discussion.click());
    expect((receive.mock.calls[0][0] as CustomEvent).detail).toEqual({ sessionId: "session", blockId: "block" });
    await act(async () => document.querySelector<HTMLButtonElement>('[aria-label="Delete annotation"]')!.click());
    expect(confirm).toHaveBeenCalledWith("Delete this highlight and its note?");
    expect(onDelete).toHaveBeenCalledWith(annotation); expect(onDismiss).toHaveBeenCalledOnce();
    window.removeEventListener(OPEN_LEARNING_DISCUSSION_EVENT, receive);
  });

  it("keeps a highlight when deleting it is declined", async () => {
    const onDelete = vi.fn(async () => {}); const onDismiss = vi.fn();
    vi.stubGlobal("confirm", vi.fn(() => false));
    await act(async () => root.render(createElement(PdfAnnotationPopover, { annotation, anchor: new DOMRect(100, 100, 10, 10), onAsk: vi.fn(), onSave: vi.fn(async () => {}), onDelete, onDismiss })));
    await act(async () => document.querySelector<HTMLButtonElement>('[aria-label="Delete annotation"]')!.click());
    expect(onDelete).not.toHaveBeenCalled();
    expect(onDismiss).not.toHaveBeenCalled();
  });
});
