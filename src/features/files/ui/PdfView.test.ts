// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPdfAnnotation } from "../../learning/model/pdfAnnotations";
import { PdfView } from "./PdfView";

const pdf = vi.hoisted(() => {
  const page = { getViewport: ({ scale }: { scale: number }) => ({ width: 100 * scale, height: 100 * scale }), render: () => ({ promise: Promise.resolve(), cancel: vi.fn() }), streamTextContent: () => "Readable PDF text" };
  const document = { numPages: 2, fingerprints: ["same-document", null], getPage: vi.fn(async () => page) };
  return { document, destroy: vi.fn(async () => {}), page };
});
vi.mock("pdfjs-dist/legacy/build/pdf.mjs", () => ({
  PDFWorker: class { destroy = vi.fn(); },
  getDocument: () => ({ promise: Promise.resolve(pdf.document), destroy: pdf.destroy }),
  TextLayer: class {
    container: HTMLElement; text: string;
    constructor({ container, textContentSource }: { container: HTMLElement; textContentSource: string }) { this.container = container; this.text = textContentSource; }
    async render() { const span = document.createElement("span"); span.textContent = this.text; this.container.append(span); }
    cancel() {}
  },
}));
vi.mock("pdfjs-dist/legacy/build/pdf.worker.mjs?worker", () => ({ default: class {} }));

describe("PDF reading with annotations", () => {
  let host: HTMLDivElement;
  let root: Root;
  beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    vi.stubGlobal("IntersectionObserver", class {
      callback: (entries: Array<{ isIntersecting: boolean }>) => void;
      constructor(callback: (entries: Array<{ isIntersecting: boolean }>) => void) { this.callback = callback; }
      observe() { this.callback([{ isIntersecting: true }]); }
      disconnect() {}
    });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    pdf.document.getPage.mockClear(); pdf.destroy.mockClear();
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

  it("reports document identity and paints marks without covering selectable text", async () => {
    const annotation = createPdfAnnotation({ id: "doc", path: "/book.pdf", title: "Book", fingerprint: "same-document", createdAt: 1, updatedAt: 1 }, "passage", [{ page: 1, rects: [{ x: 0.1, y: 0.2, width: 0.4, height: 0.1 }] }]);
    const onDocument = vi.fn(); const onAnnotationClick = vi.fn();
    await act(async () => root.render(createElement(PdfView, { bytes: new Uint8Array([1, 2, 3]), onError: vi.fn(), onDocument, annotations: [annotation], onAnnotationClick })));
    expect(onDocument).toHaveBeenCalledWith({ document: pdf.document, fingerprint: "same-document" });
    const mark = host.querySelector<HTMLElement>(`[data-pdf-annotation="${annotation.id}"]`)!;
    expect(mark.style.left).toBe("10%"); expect(mark.style.top).toBe("20%");
    expect(mark.parentElement!.className).toContain("pointer-events-none");
    const textLayer = host.querySelector(".textLayer")!;
    expect(textLayer.textContent).toBe("Readable PDF text");
    const page = host.querySelector<HTMLElement>('[data-page-number="1"]')!;
    vi.spyOn(page, "getBoundingClientRect").mockReturnValue(new DOMRect(100, 200, 200, 200));
    await act(async () => textLayer.dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: 130, clientY: 250 })));
    expect(onAnnotationClick).toHaveBeenCalledWith(annotation, expect.any(DOMRect));
    const selected = document.createRange(); selected.selectNodeContents(textLayer);
    window.getSelection()!.addRange(selected); onAnnotationClick.mockClear();
    await act(async () => textLayer.dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: 130, clientY: 250 })));
    expect(onAnnotationClick).not.toHaveBeenCalled();
    window.getSelection()!.removeAllRanges();
  });

  it("shows the requested page and consumes its placement after layout", async () => {
    const onPlaced = vi.fn();
    vi.spyOn(HTMLElement.prototype, "offsetTop", "get").mockImplementation(function (this: HTMLElement) { return this.dataset.pageNumber === "2" ? 300 : 0; });
    await act(async () => root.render(createElement(PdfView, { bytes: new Uint8Array([1]), onError: vi.fn(), place: { page: 2, token: 1 }, onPlaced })));
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 30)); });
    expect(host.querySelector(".loci-pdf")!.scrollTop).toBe(284);
    expect(onPlaced).toHaveBeenCalledOnce();
    expect(onPlaced).toHaveBeenCalledWith({ page: 2, token: 1 }, expect.any(DOMRect));
  });

  it("opens a saved mark at its passage rather than leaving it below the viewport", async () => {
    const mark = createPdfAnnotation({ id: "doc", path: "/book.pdf", title: "Book", fingerprint: "same-document", createdAt: 1, updatedAt: 1 }, "passage near the end", [{ page: 2, rects: [{ x: 0.1, y: 0.8, width: 0.4, height: 0.1 }] }]);
    vi.spyOn(HTMLElement.prototype, "offsetTop", "get").mockImplementation(function (this: HTMLElement) { return this.dataset.pageNumber === "2" ? 300 : 0; });
    vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(100);
    await act(async () => root.render(createElement(PdfView, { bytes: new Uint8Array([1]), onError: vi.fn(), annotations: [mark], place: { page: 2, token: 1, annotationId: mark.id } })));
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 30)); });
    expect(host.querySelector(".loci-pdf")!.scrollTop).toBe(364);
  });
});
