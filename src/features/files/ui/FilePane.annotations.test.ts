// @vitest-environment happy-dom
import { act, createElement, useEffect } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { FilePane } from "./FilePane";
import { ADD_TO_CHAT_EVENT, type AddToChatRequest } from "../../sessions/model/quoteDraft";
import * as learning from "../../learning/model/learningStore";
import { readDocumentFile, readTextFile } from "../../../platform/tauri/fs";
import { open } from "@tauri-apps/plugin-dialog";
import type { LoadedPdf } from "./PdfView";
import type { PdfAnnotation } from "../../learning/model/types";
import { rangeAt, textIndex } from "../../learning/model/textAnchor";

vi.mock("../../../platform/tauri/fs", () => ({ basename: (path: string) => path.split("/").pop(), readDocumentFile: vi.fn(), readBinaryFile: vi.fn(), readTextFile: vi.fn(), writeTextFile: vi.fn(), openPathWithDefaultApp: vi.fn(), revealPath: vi.fn() }));
vi.mock("../model/fileWatch", () => ({ watchFile: () => () => {}, syncWatchedMtime: vi.fn() }));
vi.mock("@tauri-apps/plugin-dialog", () => ({ open: vi.fn() }));
vi.mock("../../learning/model/learningStore", () => ({
  registerReadingDocument: vi.fn(), getReadingDocumentByPath: vi.fn(), relocateReadingDocument: vi.fn(), listPdfAnnotations: vi.fn(), registerLearningSource: vi.fn(),
  upsertPdfAnnotation: vi.fn(), deletePdfAnnotation: vi.fn(), listAnnotations: vi.fn(async () => []), upsertAnnotation: vi.fn(), deleteAnnotation: vi.fn(), subscribeLearningChanges: () => () => {},
}));
vi.mock("./PdfView", () => ({
  readPdfFingerprint: async () => "document-fingerprint",
  PdfView: function Preview({ onDocument }: { onDocument?: (loaded: LoadedPdf) => void }) {
    useEffect(() => onDocument?.({ document: {} as LoadedPdf["document"], fingerprint: "document-fingerprint" }), [onDocument]);
    return createElement("div", { "data-page-number": "1" }, createElement("div", { className: "textLayer" }, createElement("span", null, "Selectable passage")));
  },
}));

describe("PDF passage workflows", () => {
  let host: HTMLDivElement; let root: Root;
  const registered = { id: "document", path: "/book.pdf", title: "book.pdf", fingerprint: "document-fingerprint", createdAt: 1, updatedAt: 1 };
  const onOpenFile = vi.fn();
  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    vi.mocked(readDocumentFile).mockReset().mockResolvedValue(new Uint8Array([1]));
    vi.mocked(learning.registerReadingDocument).mockReset().mockResolvedValue(registered);
    vi.mocked(learning.getReadingDocumentByPath).mockReset().mockResolvedValue(null);
    vi.mocked(learning.listPdfAnnotations).mockReset().mockResolvedValue([]);
    vi.mocked(learning.upsertPdfAnnotation).mockReset().mockImplementation(async (mark: PdfAnnotation) => mark);
    vi.mocked(learning.registerLearningSource).mockReset().mockImplementation(async (source) => source);
    vi.mocked(learning.relocateReadingDocument).mockReset().mockResolvedValue(registered);
    onOpenFile.mockClear();
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  });
  afterEach(async () => { window.getSelection()?.removeAllRanges(); await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });
  async function show() {
    await act(async () => root.render(createElement(FilePane, { path: "/book.pdf", cwd: "/", preview: false, focused: true, onFocus: vi.fn(), onPin: vi.fn(), onClose: vi.fn(), onOpenFile })));
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
  }
  async function selectPassage() {
    const page = host.querySelector<HTMLElement>("[data-page-number]")!;
    vi.spyOn(page, "getBoundingClientRect").mockReturnValue(new DOMRect(0, 0, 100, 100));
    vi.spyOn(Range.prototype, "getClientRects").mockReturnValue([new DOMRect(10, 20, 40, 10)] as unknown as DOMRectList);
    const range = document.createRange(); range.selectNodeContents(page.querySelector("span")!);
    window.getSelection()!.addRange(range);
    await act(async () => { document.dispatchEvent(new Event("selectionchange")); await new Promise((resolve) => setTimeout(resolve, 30)); });
  }
  const button = (label: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((entry) => entry.textContent?.trim() === label)!;

  it("registers identity and stages a grounded question without creating a mark or sending a turn", async () => {
    const requests: AddToChatRequest[] = [];
    const receive = (event: Event) => requests.push((event as CustomEvent<AddToChatRequest>).detail);
    window.addEventListener(ADD_TO_CHAT_EVENT, receive);
    await show(); await selectPassage();
    await act(async () => button("Ask").click());
    expect(learning.registerReadingDocument).toHaveBeenCalledWith("/book.pdf", "document-fingerprint", "book.pdf");
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({ text: "Explain this passage.", mode: "plain", sources: [{ kind: "pdf", documentId: "document", quote: "Selectable passage", anchors: [{ page: 1, rects: [{ x: 0.1, y: 0.2, width: 0.4, height: 0.1 }] }] }] });
    expect(learning.registerLearningSource).toHaveBeenCalledOnce();
    expect(learning.upsertPdfAnnotation).not.toHaveBeenCalled();
    window.removeEventListener(ADD_TO_CHAT_EVENT, receive);
  });

  it("names the mentor in the PDF selection menu, as reading its text does", async () => {
    const onOpenFile = vi.fn();
    await act(async () => root.render(createElement(FilePane, { path: "/book.pdf", cwd: "/", preview: false, focused: true, onFocus: vi.fn(), onPin: vi.fn(), onClose: vi.fn(), onOpenFile, askLabel: "Ask Ada" })));
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
    await selectPassage();
    expect(button("Ask Ada")).toBeDefined();
  });

  it("keeps a selected passage and opens its editable annotation", async () => {
    await show(); await selectPassage();
    await act(async () => button("Highlight").click());
    expect(learning.upsertPdfAnnotation).toHaveBeenCalledOnce();
    const mark = vi.mocked(learning.upsertPdfAnnotation).mock.calls[0][0];
    expect(mark.source).toMatchObject({ annotationId: mark.id, documentId: "document", quote: "Selectable passage" });
    expect(document.querySelector('[aria-label="Annotation note"]')).not.toBeNull();
    expect(window.getSelection()!.toString()).toBe("");
  });

  it("locates the same missing document and hands its updated path to the file opener", async () => {
    vi.mocked(learning.getReadingDocumentByPath).mockResolvedValue(registered);
    vi.mocked(readDocumentFile).mockRejectedValueOnce(new Error("No such file or directory")).mockResolvedValue(new Uint8Array([1]));
    vi.mocked(open).mockResolvedValue("/moved/book.pdf");
    await show();
    await act(async () => button("Locate file").click());
    expect(learning.relocateReadingDocument).toHaveBeenCalledWith("document", "/moved/book.pdf", "document-fingerprint");
    expect(onOpenFile).toHaveBeenCalledWith("/moved/book.pdf");
  });

  it("keeps a missing document's annotations attached to their identity when a different PDF is chosen", async () => {
    vi.mocked(learning.getReadingDocumentByPath).mockResolvedValue(registered);
    vi.mocked(readDocumentFile).mockRejectedValueOnce(new Error("No such file or directory")).mockResolvedValue(new Uint8Array([2]));
    vi.mocked(open).mockResolvedValue("/different.pdf");
    vi.mocked(learning.relocateReadingDocument).mockRejectedValue(new Error("The selected PDF does not match this document."));
    await show();
    await act(async () => button("Locate file").click());
    expect(onOpenFile).not.toHaveBeenCalled();
    expect(host.textContent).toContain("The selected PDF does not match this document.");
  });

  it("highlights lines of a text file on the file, with the lines it covers", async () => {
    vi.mocked(readTextFile).mockResolvedValue("fn main() {\n    run();\n}\n");
    vi.mocked(learning.upsertAnnotation).mockImplementation(async (mark) => mark);
    await act(async () => root.render(createElement(FilePane, { path: "/src/main.rs", cwd: "/src", preview: false, focused: true, onFocus: vi.fn(), onPin: vi.fn(), onClose: vi.fn(), onOpenFile })));
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
    const code = host.querySelector("pre code")!;
    const index = textIndex(code);
    const at = index.text.indexOf("run()");
    vi.spyOn(Range.prototype, "getClientRects").mockReturnValue([new DOMRect(10, 20, 40, 10)] as unknown as DOMRectList);
    const range = rangeAt(index, at, at + "run()".length)!;
    window.getSelection()!.addRange(range);
    await act(async () => { document.dispatchEvent(new Event("selectionchange")); await new Promise((resolve) => setTimeout(resolve, 30)); });
    await act(async () => button("Highlight").click());
    expect(learning.upsertAnnotation).toHaveBeenCalledWith(expect.objectContaining({
      target: { kind: "file", path: "/src/main.rs" },
      anchor: expect.objectContaining({ exact: "run()", lines: [2, 2] }),
      source: expect.objectContaining({ kind: "file", path: "/src/main.rs", lines: [2, 2] }),
    }));
  });
});
