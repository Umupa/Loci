// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { createPdfAnnotation, normalizePdfRect, pdfAnnotationAt, pdfSelectionAnchors } from "./pdfAnnotations";

afterEach(() => vi.restoreAllMocks());

describe("PDF selection anchors", () => {
  it("stores the same page fractions before and after zoom, clipped to page bounds", () => {
    const page = new DOMRect(100, 200, 200, 400);
    expect(normalizePdfRect(new DOMRect(140, 240, 80, 20), page)).toEqual({ x: 0.2, y: 0.1, width: 0.4, height: 0.05 });
    expect(normalizePdfRect(new DOMRect(280, 580, 160, 40), new DOMRect(200, 500, 400, 800)))
      .toEqual({ x: 0.2, y: 0.1, width: 0.4, height: 0.05 });
    expect(normalizePdfRect(new DOMRect(80, 190, 60, 40), page)).toEqual({ x: 0, y: 0, width: 0.2, height: 0.075 });
    expect(normalizePdfRect(new DOMRect(10, 10, 20, 20), page)).toBeNull();
    expect(normalizePdfRect(new DOMRect(0, 0, 10, 10), new DOMRect())).toBeNull();
  });

  it("captures partial text on both pages without their wrapper or margin boxes", () => {
    const root = document.createElement("div");
    root.innerHTML = '<div data-page-number="1"><div class="textLayer"><span>alpha beta</span></div></div><div data-page-number="2"><div class="textLayer"><span>gamma delta</span></div></div>';
    const [first, second] = [...root.querySelectorAll<HTMLElement>("[data-page-number]")];
    vi.spyOn(first, "getBoundingClientRect").mockReturnValue(new DOMRect(100, 200, 200, 400));
    vi.spyOn(second, "getBoundingClientRect").mockReturnValue(new DOMRect(100, 650, 200, 400));
    const selection = document.createRange();
    selection.setStart(first.querySelector("span")!.firstChild!, 6);
    selection.setEnd(second.querySelector("span")!.firstChild!, 5);
    const measured: string[] = [];
    vi.spyOn(Range.prototype, "getClientRects").mockImplementation(function (this: Range) {
      const text = this.toString(); measured.push(text);
      return (text === "beta" ? [new DOMRect(150, 240, 40, 10)] : [new DOMRect(130, 670, 50, 10)]) as unknown as DOMRectList;
    });
    expect(pdfSelectionAnchors(root, selection)).toEqual([
      { page: 1, rects: [{ x: 0.25, y: 0.1, width: 0.2, height: 0.025 }] },
      { page: 2, rects: [{ x: 0.15, y: 0.05, width: 0.25, height: 0.025 }] },
    ]);
    expect(measured).toEqual(["beta", "gamma"]);
  });

  it("keeps separate lines and merges adjacent selected spans on one line", () => {
    const root = document.createElement("div");
    root.innerHTML = '<div data-page-number="4"><div class="textLayer"><span>one</span><span>two</span><span>three</span></div></div>';
    const page = root.firstElementChild as HTMLElement;
    vi.spyOn(page, "getBoundingClientRect").mockReturnValue(new DOMRect(0, 0, 100, 100));
    const selection = document.createRange(); selection.selectNodeContents(page);
    vi.spyOn(Range.prototype, "getClientRects").mockImplementation(function (this: Range) {
      const positions: Record<string, DOMRect> = { one: new DOMRect(10, 10, 20, 5), two: new DOMRect(30, 10, 20, 5), three: new DOMRect(10, 20, 30, 5) };
      return [positions[this.toString()]] as unknown as DOMRectList;
    });
    expect(pdfSelectionAnchors(root, selection)).toEqual([{ page: 4, rects: [
      { x: 0.1, y: 0.1, width: 0.4, height: 0.05000000000000002 },
      { x: 0.1, y: 0.2, width: 0.3, height: 0.05 },
    ] }]);
  });

  it("leaves image-only pages without fabricated anchors", () => {
    const root = document.createElement("div"); root.innerHTML = '<div data-page-number="1"><canvas></canvas><div class="textLayer"></div></div>';
    const selection = document.createRange(); selection.selectNodeContents(root);
    expect(pdfSelectionAnchors(root, selection)).toEqual([]);
  });
});

describe("PDF annotations", () => {
  it("ties a saved mark and its source to the same document and annotation", () => {
    const mark = createPdfAnnotation({ id: "doc", fingerprint: "fingerprint", path: "/book.pdf", title: "Book", createdAt: 1, updatedAt: 1 }, "selected passage", [{ page: 2, rects: [{ x: 0.1, y: 0.2, width: 0.3, height: 0.05 }] }]);
    expect(mark.source).toMatchObject({ kind: "pdf", documentId: "doc", annotationId: mark.id, quote: "selected passage" });
    expect(pdfAnnotationAt([mark], 2, 0.2, 0.22)).toBe(mark);
    expect(pdfAnnotationAt([mark], 1, 0.2, 0.22)).toBeUndefined();
    expect(pdfAnnotationAt([mark], 2, 0.2, 0.7)).toBeUndefined();
  });
});
