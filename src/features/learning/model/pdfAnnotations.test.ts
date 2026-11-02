// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { createPdfAnnotation, cropBox, isPdfArea, normalizePdfRect, pdfAnnotationAt, pdfAreaAnchor, pdfSelectionAnchors, textInPdfRect, textItemRect, type PdfTextItem } from "./pdfAnnotations";

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

describe("PDF areas", () => {
  // A US Letter page at scale 1: PDF space has y up from the bottom, the viewport y down from the top.
  const viewport = { width: 612, height: 792, transform: [1, 0, 0, -1, 0, 792] };
  const run = (str: string, x: number, baseline: number, width: number, size = 10, hasEOL = false): PdfTextItem =>
    ({ str, transform: [size, 0, 0, size, x, 792 - baseline], width, height: size, hasEOL });

  it("places a run of text on the page from its baseline up by its font size", () => {
    const box = textItemRect(run("Figure 3", 61.2, 89.2, 122.4, 10), viewport)!;
    expect(box.x).toBeCloseTo(0.1);
    expect(box.y).toBeCloseTo(79.2 / 792);
    expect(box.width).toBeCloseTo(0.2);
    expect(box.height).toBeCloseTo(10 / 792);
    // A page shown at twice the size gives the same fractions.
    const zoomed = textItemRect(run("Figure 3", 61.2, 89.2, 122.4, 10), { width: 1224, height: 1584, transform: [2, 0, 0, -2, 0, 1584] })!;
    expect(zoomed.x).toBeCloseTo(box.x);
    expect(zoomed.y).toBeCloseTo(box.y);
    expect(textItemRect({ ...run("", 0, 0, 0), width: 0 }, viewport)).toBeNull();
  });

  it("takes the words mostly inside an area, in reading order, a new line where the text skipped", () => {
    const items = [
      run("Body text left of the figure", 40, 100, 200),
      run("Table 2: phases", 320, 100, 120, 10, true),
      run("Pending", 320, 120, 50), run(" ", 370, 120, 4), run("accepted", 374, 120, 60, 10, true),
      run("Running", 320, 140, 50), run("  started   ", 370, 140, 60, 10, true),
      run("half cut", 520, 160, 80),
      run("Body text below", 40, 300, 200),
    ];
    // The right half of the page from y 80 to 150, to x 560.
    const area = { x: 300 / 612, y: 80 / 792, width: 260 / 612, height: 70 / 792 };
    expect(textInPdfRect(items, viewport, area)).toBe("Table 2: phases\nPending accepted\nRunning started");
    // Most of "half cut" lies outside; widening the area takes it, after a break.
    expect(textInPdfRect(items, viewport, { ...area, width: 312 / 612, height: 90 / 792 })).toBe("Table 2: phases\nPending accepted\nRunning started\nhalf cut");
    expect(textInPdfRect(items, viewport, { x: 0.9, y: 0.9, width: 0.05, height: 0.05 })).toBe("");
  });

  it("cuts whole pixels from the drawn page, clamped to it", () => {
    expect(cropBox({ x: 0.25, y: 0.5, width: 0.5, height: 0.25 }, 800, 1000)).toEqual({ x: 200, y: 500, width: 400, height: 250 });
    expect(cropBox({ x: 0.333, y: 0, width: 0.333, height: 1.2 }, 100, 100)).toEqual({ x: 33, y: 0, width: 34, height: 100 });
    expect(cropBox({ x: 1, y: 0, width: 0.1, height: 0.1 }, 100, 100)).toBeNull();
  });

  it("keeps an area's highlight as a whole block, named by its words or its page", () => {
    expect(pdfAreaAnchor(3, " Table 2 ")).toMatchObject({ exact: "Table 2", block: { kind: "area", index: 0 } });
    expect(pdfAreaAnchor(3, "").exact).toBe("Area on page 3");
    expect(isPdfArea({ anchor: pdfAreaAnchor(3, "") })).toBe(true);
    expect(isPdfArea({ anchor: { exact: "x", prefix: "", suffix: "", start: 0, end: 1 } })).toBe(false);
    expect(isPdfArea({})).toBe(false);
  });
});
