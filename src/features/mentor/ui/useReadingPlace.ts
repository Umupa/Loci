import { useEffect, type RefObject } from "react";
import { setAgentReadingPlace, type ReadingPlace } from "../../agents/model/agentReading";
import { headingsAt, linesOf, textIndex } from "../../learning/model/textAnchor";

/**
 * Where the reader is, read off the reader column's DOM. Each reader marks the
 * text it shows with `data-reading-text` (and, for a file's lines,
 * `data-reading-lines-from` with the first line shown); PDFs mark pages with
 * `data-page-number`. Nothing here knows which reader it is.
 */

const BLOCKS = "p, li, pre, blockquote, h1, h2, h3, h4, h5, h6, td, dd";
const TEXT = "[data-reading-text]";

function codeOf(element: Element | null): Element | null {
  const pre = element?.closest("pre");
  return pre?.querySelector("code") ?? pre ?? null;
}
function offsetIn(container: Node, node: Node, at: number): number {
  const before = document.createRange();
  before.selectNodeContents(container);
  before.setEnd(node, at);
  return before.toString().length;
}
function linesFrom(text: HTMLElement): number | undefined {
  const value = Number(text.dataset.readingLinesFrom);
  return Number.isInteger(value) && value > 0 ? value : undefined;
}
function caretAt(x: number, y: number): { node: Node; offset: number } | null {
  const doc = document as Document & { caretRangeFromPoint?: (x: number, y: number) => Range | null; caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null };
  const position = doc.caretPositionFromPoint?.(x, y);
  if (position) return { node: position.offsetNode, offset: position.offset };
  const range = doc.caretRangeFromPoint?.(x, y);
  return range ? { node: range.startContainer, offset: range.startOffset } : null;
}

type Measured = Pick<ReadingPlace, "part" | "page" | "lines" | "section" | "paragraph">;

/**
 * The page, lines, section and paragraph at the top of what the reader
 * shows. In a comparison (parts marked `data-compare-part`) they are read
 * in the part at the top of the view, which is named.
 */
export function measurePlace(root: HTMLElement): Measured {
  const view = root.getBoundingClientRect();
  const top = Math.max(view.top, 0);
  const bottom = Math.min(view.bottom, window.innerHeight || view.bottom);
  const place: Measured = {};
  const part = [...root.querySelectorAll<HTMLElement>("[data-compare-part]")].find((element) => {
    const rect = element.getBoundingClientRect();
    return rect.bottom > top + 24 && rect.top < bottom;
  });
  if (part) {
    place.part = part.dataset.comparePart;
    root = part;
  }

  let best = 0;
  for (const page of root.querySelectorAll<HTMLElement>("[data-page-number]")) {
    const rect = page.getBoundingClientRect();
    const visible = Math.min(rect.bottom, bottom) - Math.max(rect.top, top);
    if (visible > best) { best = visible; place.page = Number(page.dataset.pageNumber); }
  }

  for (const text of root.querySelectorAll<HTMLElement>(TEXT)) {
    const from = linesFrom(text);
    if (from) {
      const code = codeOf(text.matches("pre") ? text : text.querySelector("pre"));
      const box = (code ?? text).getBoundingClientRect();
      const first = caretAt(box.left + 8, Math.max(box.top, top) + 4);
      const last = caretAt(box.left + 8, Math.min(box.bottom, bottom) - 4);
      if (code && first && last && code.contains(first.node) && code.contains(last.node)) {
        const content = code.textContent ?? "";
        const [a] = linesOf(content, offsetIn(code, first.node, first.offset), offsetIn(code, first.node, first.offset) + 1);
        const [, b] = linesOf(content, offsetIn(code, last.node, last.offset), offsetIn(code, last.node, last.offset) + 1);
        place.lines = [a + from - 1, Math.max(a, b) + from - 1];
      }
    }
    const blocks = [...text.querySelectorAll<HTMLElement>(BLOCKS)].filter((block) => !block.parentElement?.closest(BLOCKS) || block.matches("li"));
    const visible = blocks.find((block) => {
      const rect = block.getBoundingClientRect();
      return rect.bottom > top + 4 && rect.top < bottom && (block.textContent ?? "").trim();
    });
    if (!visible || from) continue;
    place.paragraph = (visible.textContent ?? "").replace(/\s+/g, " ").trim();
    const index = textIndex(text);
    const piece = index.pieces.find((entry) => visible.contains(entry.node));
    const section = piece ? headingsAt(text, index, piece.start) : [];
    if (section.length) place.section = section;
    break;
  }
  return place;
}

/** The selected text in a reader, with its page or lines; null for none; undefined when focus left the reader. */
export function selectionPlace(root: HTMLElement): ReadingPlace["selection"] | null | undefined {
  const native = window.getSelection();
  const range = native && native.rangeCount ? native.getRangeAt(0) : null;
  const node = range?.commonAncestorContainer;
  const element = node instanceof Element ? node : node?.parentElement;
  const text = element?.closest<HTMLElement>(TEXT);
  if (!range || !text || !root.contains(text)) return undefined;
  const quote = native!.toString().trim();
  if (native!.isCollapsed || !quote) return null;
  const selection: NonNullable<ReadingPlace["selection"]> = { text: quote };
  const start = range.startContainer instanceof Element ? range.startContainer : range.startContainer.parentElement;
  const page = Number(start?.closest<HTMLElement>("[data-page-number]")?.dataset.pageNumber);
  if (page > 0) selection.page = page;
  const from = linesFrom(text);
  const code = from ? codeOf(start ?? null) : null;
  if (from && code && code.contains(range.endContainer)) {
    const [a, b] = linesOf(code.textContent ?? "", offsetIn(code, range.startContainer, range.startOffset), offsetIn(code, range.endContainer, range.endOffset));
    selection.lines = [a + from - 1, b + from - 1];
  }
  return selection;
}

/** Keep the mentor's reading place current while the reader column is on screen. */
export function useReadingPlace(root: RefObject<HTMLElement | null>, agentId: string, pageKey: string): void {
  useEffect(() => {
    const element = root.current;
    if (!element) return;
    let timer = 0;
    const measure = () => {
      timer = 0;
      const place = measurePlace(element);
      setAgentReadingPlace(agentId, { part: place.part, page: place.page, lines: place.lines, section: place.section, paragraph: place.paragraph });
    };
    const later = (delay = 300) => { window.clearTimeout(timer); timer = window.setTimeout(measure, delay); };
    const scroll = (event: Event) => { if (event.target instanceof Node && element.contains(event.target)) later(); };
    const select = () => {
      const selection = selectionPlace(element);
      // Focus moving to the composer keeps the selection; a click in the reader clears it.
      if (selection !== undefined) setAgentReadingPlace(agentId, { selection: selection ?? undefined });
    };
    const observer = new MutationObserver(() => later(500));
    observer.observe(element, { childList: true, subtree: true });
    document.addEventListener("scroll", scroll, true);
    const resize = () => later();
    window.addEventListener("resize", resize);
    document.addEventListener("selectionchange", select);
    later(400);
    return () => {
      window.clearTimeout(timer);
      observer.disconnect();
      document.removeEventListener("scroll", scroll, true);
      window.removeEventListener("resize", resize);
      document.removeEventListener("selectionchange", select);
    };
  }, [root, agentId, pageKey]);
}
