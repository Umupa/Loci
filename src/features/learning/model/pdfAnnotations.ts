import type { LearningSource, PdfAnchor, PdfAnnotation, PdfRect, ReadingDocument, TextAnchor } from "./types";

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
  return { id, documentId: document.id, target: { kind: "pdf", documentId: document.id }, source: pdfSelectionSource(document, quote, anchors, id),
    anchors, note: "", discussions: [], createdAt: now, updatedAt: now };
}

/*
 * An area drawn on a page (⌥-drag): a figure or a table kept, asked about or
 * saved as a whole, with the words pdf.js finds inside it and a picture of it.
 */

/** A run of text from pdf.js's `getTextContent`, in the page's own units. */
export type PdfTextItem = { str: string; transform: number[]; width: number; height: number; hasEOL?: boolean };
/** A page's viewport at scale 1: its size and the transform from PDF space. */
export type PdfViewportBox = { width: number; height: number; transform: number[] };

function multiply(m: number[], n: number[]): number[] {
  return [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]];
}

/** Where a run of text sits, as fractions of the page: from its baseline up by its font's height, as pdf.js lays out its text layer. */
export function textItemRect(item: PdfTextItem, viewport: PdfViewportBox): PdfRect | null {
  if (viewport.width <= 0 || viewport.height <= 0) return null;
  const [, , c, d, left, baseline] = multiply(viewport.transform, item.transform);
  const height = Math.hypot(c, d);
  const width = item.width * Math.hypot(viewport.transform[0], viewport.transform[1]);
  if (!(height > 0) || !(width > 0)) return null;
  return { x: left / viewport.width, y: (baseline - height) / viewport.height, width: width / viewport.width, height: height / viewport.height };
}

/**
 * The words inside an area, in pdf.js's reading order. A run counts when most
 * of it is inside: a caption half cut by the edge comes whole or not at all.
 * Runs that were not next to each other in the page's text start a new line.
 */
export function textInPdfRect(items: readonly PdfTextItem[], viewport: PdfViewportBox, area: PdfRect): string {
  let text = "";
  let previous = -2;
  items.forEach((item, index) => {
    const box = textItemRect(item, viewport);
    if (!box || !item.str) return;
    const width = Math.min(box.x + box.width, area.x + area.width) - Math.max(box.x, area.x);
    const height = Math.min(box.y + box.height, area.y + area.height) - Math.max(box.y, area.y);
    if (width <= 0 || height <= 0 || width * height < box.width * box.height * 0.5) return;
    if (text && previous !== index - 1 && !text.endsWith("\n")) text += "\n";
    text += item.str + (item.hasEOL ? "\n" : "");
    previous = index;
  });
  return text.split("\n").map((line) => line.replace(/[ \t]+/g, " ").trim()).filter(Boolean).join("\n");
}

/** The pixels of a canvas an area covers, whole pixels inside the canvas; null when it covers none. */
export function cropBox(area: PdfRect, width: number, height: number): { x: number; y: number; width: number; height: number } | null {
  const left = Math.max(0, Math.floor(area.x * width));
  const top = Math.max(0, Math.floor(area.y * height));
  const right = Math.min(width, Math.ceil((area.x + area.width) * width));
  const bottom = Math.min(height, Math.ceil((area.y + area.height) * height));
  return right > left && bottom > top ? { x: left, y: top, width: right - left, height: bottom - top } : null;
}

/** A PNG of an area, cut from the page as it is drawn now; null when the page is not drawn (scrolled far away). */
export async function pdfAreaPicture(root: ParentNode, page: number, area: PdfRect, name: string): Promise<File | null> {
  const canvas = root.querySelector<HTMLCanvasElement>(`[data-page-number="${page}"] .loci-pdf-canvas canvas`);
  const box = canvas ? cropBox(area, canvas.width, canvas.height) : null;
  if (!canvas || !box) return null;
  const crop = document.createElement("canvas");
  crop.width = box.width;
  crop.height = box.height;
  const context = crop.getContext("2d");
  if (!context) return null;
  context.drawImage(canvas, box.x, box.y, box.width, box.height, 0, 0, box.width, box.height);
  const blob = await new Promise<Blob | null>((resolve) => crop.toBlob(resolve, "image/png"));
  return blob ? new File([blob], name, { type: "image/png" }) : null;
}

/** The text anchor an area's highlight keeps: what it marks is a whole block, by its words when it has any. */
export function pdfAreaAnchor(page: number, text: string): TextAnchor {
  return { exact: text.trim().slice(0, 60 * 1024) || `Area on page ${page}`, prefix: "", suffix: "", start: 0, end: 0, block: { kind: "area", index: 0 } };
}

/** A highlight on an area of a page rather than on lines of text. */
export function isPdfArea(annotation: Pick<PdfAnnotation, "anchor">): boolean {
  return annotation.anchor?.block?.kind === "area";
}
