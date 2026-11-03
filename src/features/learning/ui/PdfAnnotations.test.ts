// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AnnotationList, AnnotationToolbar } from "./PdfAnnotations";
import { createPdfAnnotation } from "../model/pdfAnnotations";
import { OPEN_LEARNING_DISCUSSION_EVENT } from "../model/navigation";

vi.mock("../model/learningStore", () => ({ registerLearningSource: vi.fn(async () => undefined) }));

describe("reading notes and discussions", () => {
  let host: HTMLDivElement; let root: Root;
  const annotation = { ...createPdfAnnotation({ id: "doc", title: "Book", path: "/book.pdf", fingerprint: "book", createdAt: 1, updatedAt: 1 }, "A useful passage", [{ page: 3, rects: [{ x: 0.1, y: 0.2, width: 0.3, height: 0.1 }] }]), note: "Read again", discussions: [{ sessionId: "session", blockId: "block" }] };
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });

  it("lists the saved passage and its note, and selects its page anchor", async () => {
    const select = vi.fn();
    await act(async () => root.render(createElement(AnnotationList, { annotations: [annotation], onSelect: select, onClose: vi.fn() })));
    expect(host.textContent).toContain("Page 3"); expect(host.textContent).toContain("Read again"); expect(host.textContent).toContain("1 discussion");
    const entry = [...host.querySelectorAll("button")].find((button) => button.textContent?.includes("A useful passage"))!;
    await act(async () => entry.click());
    expect(select).toHaveBeenCalledWith(annotation);
  });

  it("says how to start in one line, with no count, when nothing is marked", async () => {
    await act(async () => root.render(createElement(AnnotationList, { annotations: [], onSelect: vi.fn(), onClose: vi.fn() })));
    expect(host.querySelector(".pdf-annotations__empty")?.textContent).toBe("Select text to highlight it");
    expect(host.querySelector(".pdf-annotations__count")).toBeNull();
    expect(host.querySelector(".pdf-annotations__empty")?.children).toHaveLength(0);
  });

  it("orders passages by page and position without rearranging the stored list", async () => {
    const pageOne = { ...annotation, id: "page-one", anchors: [{ page: 1, rects: [{ x: 0.1, y: 0.5, width: 0.3, height: 0.1 }] }] };
    const pageThreeTop = { ...annotation, id: "page-three-top", anchors: [{ page: 3, rects: [{ x: 0.1, y: 0.1, width: 0.3, height: 0.1 }] }] };
    const annotations = [annotation, pageThreeTop, pageOne];
    await act(async () => root.render(createElement(AnnotationList, { annotations, selectedId: pageThreeTop.id, onSelect: vi.fn(), onClose: vi.fn() })));
    const entries = [...host.querySelectorAll<HTMLButtonElement>("button[aria-pressed]")];
    expect(entries.map((entry) => entry.querySelector(".pdf-annotations__page")?.textContent)).toEqual(["Page 1", "Page 3", "Page 3"]);
    expect(entries.map((entry) => entry.getAttribute("aria-pressed"))).toEqual(["false", "true", "false"]);
    expect(annotations.map((entry) => entry.id)).toEqual([annotation.id, pageThreeTop.id, pageOne.id]);
  });

  const bar = (props: Partial<Parameters<typeof AnnotationToolbar>[0]> = {}) => createElement(AnnotationToolbar, {
    annotation, anchor: new DOMRect(100, 100, 10, 10), askLabel: "Ask Kern",
    onAsk: vi.fn(), onSave: vi.fn(async () => {}), onDelete: vi.fn(async () => {}), onDismiss: vi.fn(), ...props,
  });
  const button = (label: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((entry) => (entry.textContent || entry.getAttribute("aria-label")) === label)!;
  const field = () => document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Note"]');
  const type = async (text: string) => act(async () => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(field()!, text);
    field()!.dispatchEvent(new Event("input", { bubbles: true }));
  });

  it("is a bar of actions with its note as a line under it, and the note field closed", async () => {
    await act(async () => root.render(bar()));
    const toolbar = document.querySelector('[role="toolbar"][aria-label="Highlight actions"]')!;
    expect([...toolbar.querySelectorAll(".reading-toolbar__actions button")].map((entry) => entry.textContent || entry.getAttribute("aria-label")))
      .toEqual(["Note", "Ask Kern", "Open discussion", "Delete highlight"]);
    expect(toolbar.querySelector("h2, blockquote")).toBeNull();
    expect(field()).toBeNull();
    expect(button("Read again").className).toContain("reading-toolbar__note");
  });

  it("opens the note field from Note, keeps it on Enter, and asks with the note as it stands", async () => {
    const onSave = vi.fn(async () => {}); const onAsk = vi.fn();
    await act(async () => root.render(bar({ onSave, onAsk })));
    await act(async () => button("Note").click());
    expect(document.activeElement).toBe(field());
    await type("How does this compare with the experiment?");
    await act(async () => field()!.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })));
    expect(onSave).toHaveBeenCalledWith(annotation, "How does this compare with the experiment?");
    expect(field()).toBeNull();
    await act(async () => button("Ask Kern").click());
    expect(onAsk).toHaveBeenCalledWith({ ...annotation, note: "How does this compare with the experiment?" });
  });

  it("keeps a typed note when the bar is dismissed or the passage is asked about", async () => {
    const onSave = vi.fn(async () => {}); const onAsk = vi.fn(); const onDismiss = vi.fn();
    await act(async () => root.render(bar({ onSave, onAsk, onDismiss })));
    await act(async () => button("Note").click());
    await type("A half-formed thought");
    await act(async () => window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(onSave).toHaveBeenCalledWith(annotation, "A half-formed thought");
    expect(onDismiss).toHaveBeenCalledOnce();
    onSave.mockClear(); onDismiss.mockClear();
    await type("Why does this hold?");
    await act(async () => button("Ask Kern").click());
    expect(onSave).toHaveBeenCalledWith(annotation, "Why does this hold?");
    expect(onAsk).toHaveBeenCalledWith({ ...annotation, note: "Why does this hold?" });
  });

  it("reopens the linked discussion and removes a mark through its visible controls", async () => {
    const onDelete = vi.fn(async () => {}); const onDismiss = vi.fn();
    const confirm = vi.fn(() => true); vi.stubGlobal("confirm", confirm);
    const receive = vi.fn(); window.addEventListener(OPEN_LEARNING_DISCUSSION_EVENT, receive);
    await act(async () => root.render(bar({ onDelete, onDismiss })));
    await act(async () => button("Open discussion").click());
    expect((receive.mock.calls[0][0] as CustomEvent).detail).toEqual({ sessionId: "session", blockId: "block" });
    await act(async () => button("Delete highlight").click());
    expect(confirm).toHaveBeenCalledWith("Delete this highlight and its note?");
    expect(onDelete).toHaveBeenCalledWith(annotation); expect(onDismiss).toHaveBeenCalledOnce();
    window.removeEventListener(OPEN_LEARNING_DISCUSSION_EVENT, receive);
  });

  it("keeps a highlight when deleting it and its note is declined, and asks nothing for a bare highlight", async () => {
    const onDelete = vi.fn(async () => {}); const onDismiss = vi.fn();
    const confirm = vi.fn(() => false); vi.stubGlobal("confirm", confirm);
    await act(async () => root.render(bar({ onDelete, onDismiss })));
    await act(async () => button("Delete highlight").click());
    expect(onDelete).not.toHaveBeenCalled();
    expect(onDismiss).not.toHaveBeenCalled();
    await act(async () => root.render(bar({ key: "bare", annotation: { ...annotation, note: "" }, onDelete, onDismiss })));
    confirm.mockClear();
    await act(async () => button("Delete highlight").click());
    expect(confirm).not.toHaveBeenCalled();
    expect(onDelete).toHaveBeenCalledOnce();
  });
});
