import type { LearningSource, PdfAnchor, PdfAnnotation, PdfRect, ReadingDocument } from "./types";

type Rect = Pick<DOMRect, "left" | "top" | "right" | "bottom" | "width" | "height">;

/** Persist page fractions rather than screen pixels, so a mark follows zoom. */
export function normalizePdfRect(rect: Rect, page: Rect): PdfRect | null {
  if (page.width <= 0 || page.height <= 0) return null;
  const left = Math.max(page.left, rect.left);
  const top = Math.max(page.top, rect.top);
  const right = Math.min(page.right, rect.right);
  const bottom = Math.min(page.bottom, rect.bottom);
  if (right <= left || bottom <= top) return null;
  return { x: (left - page.left) / page.width, y: (top - page.top) / page.height,
    width: (right - left) / page.width, height: (bottom - top) / page.height };
}

function mergeLineRects(rects: PdfRect[]): PdfRect[] {
  const result: PdfRect[] = [];
  for (const rect of rects.sort((a, b) => a.y - b.y || a.x - b.x)) {
    const previous = result[result.length - 1];
    if (previous && Math.abs(previous.y - rect.y) < Math.min(previous.height, rect.height) * 0.3
      && rect.x <= previous.x + previous.width + 0.004) {
      const bottom = Math.max(previous.y + previous.height, rect.y + rect.height);
      previous.width = Math.max(previous.x + previous.width, rect.x + rect.width) - previous.x;
      previous.y = Math.min(previous.y, rect.y);
      previous.height = bottom - previous.y;
    } else result.push({ ...rect });
  }
  return result;
}

/**
 * Measure only selected text nodes. A Range spanning pages also reports large
 * container boxes; recording those would highlight whole pages and margins.
 */
export function pdfSelectionAnchors(root: ParentNode, selection: Range): PdfAnchor[] {
  const anchors: PdfAnchor[] = [];
  for (const page of root.querySelectorAll<HTMLElement>("[data-page-number]")) {
    const number = Number(page.dataset.pageNumber);
    const layer = page.querySelector(".textLayer");
    if (!layer || !Number.isInteger(number) || number < 1) continue;
    const pageRect = page.getBoundingClientRect();
    const walker = page.ownerDocument.createTreeWalker(layer, NodeFilter.SHOW_TEXT);
    const rects: PdfRect[] = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.textContent?.trim() || !selection.intersectsNode(node)) continue;
      const piece = page.ownerDocument.createRange();
      piece.selectNodeContents(node);
      if (selection.compareBoundaryPoints(Range.START_TO_START, piece) > 0)
        piece.setStart(selection.startContainer, selection.startOffset);
      if (selection.compareBoundaryPoints(Range.END_TO_END, piece) < 0)
        piece.setEnd(selection.endContainer, selection.endOffset);
      if (piece.collapsed) continue;
      for (const rect of piece.getClientRects()) {
        const normalized = normalizePdfRect(rect, pageRect);
        if (normalized) rects.push(normalized);
      }
    }
    if (rects.length) anchors.push({ page: number, rects: mergeLineRects(rects) });
  }
  return anchors;
}

export function pdfAnnotationAt(annotations: PdfAnnotation[], page: number, x: number, y: number): PdfAnnotation | undefined {
  return annotations.find((annotation) => annotation.anchors.some((anchor) => anchor.page === page
    && anchor.rects.some((rect) => x >= rect.x && x <= rect.x + rect.width && y >= rect.y && y <= rect.y + rect.height)));
}

export function pdfSelectionSource(document: ReadingDocument, quote: string, anchors: PdfAnchor[], annotationId?: string): LearningSource {
  return { id: crypto.randomUUID(), kind: "pdf", documentId: document.id, path: document.path,
    title: document.title, quote, anchors, ...(annotationId ? { annotationId } : {}) };
}

export function createPdfAnnotation(document: ReadingDocument, quote: string, anchors: PdfAnchor[]): PdfAnnotation {
  const id = crypto.randomUUID();
  const now = Date.now();
  return { id, documentId: document.id, source: pdfSelectionSource(document, quote, anchors, id),
    anchors, note: "", discussions: [], createdAt: now, updatedAt: now };
}
