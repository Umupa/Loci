import type { TextAnchor } from "./types";

/**
 * Text anchors: a passage remembered by its words rather than by its place in
 * the DOM, so a highlight survives a re-render, a revised document or a few
 * changed lines. Offsets are kept only as a hint for choosing between repeats.
 */

const CONTEXT = 32;
const HEADING_MAX = 200;
const HEADINGS_KEPT = 3;
/** Rendered chrome that is not the text being read: buttons, pictures, the duplicate MathML of a formula. */
const SKIP = "[data-anchor-skip], .katex-mathml, svg, button, script, style, textarea, input, select";

type Piece = { node: Text; start: number };
export type TextIndex = { text: string; pieces: Piece[] };

function skipped(node: Node, root: Node): boolean {
  for (let element = node.parentElement; element && element !== root; element = element.parentElement)
    if (element.matches(SKIP)) return true;
  return false;
}

/** The reader's text in document order, with where each text node starts in it. */
export function textIndex(root: Node): TextIndex {
  const document = root.ownerDocument ?? (root as Document);
  const walker = document.createTreeWalker(root, 4 /* NodeFilter.SHOW_TEXT */);
  const pieces: Piece[] = [];
  let text = "";
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    if (skipped(node, root)) continue;
    pieces.push({ node, start: text.length });
    text += node.data;
  }
  return { text, pieces };
}

/** Where a range boundary falls in the index's text. */
function boundaryOffset(index: TextIndex, container: Node, offset: number, end: boolean): number | null {
  if (container.nodeType === 3) {
    const piece = index.pieces.find((entry) => entry.node === container);
    if (piece) return piece.start + Math.min(offset, piece.node.data.length);
  }
  // A boundary between nodes, or inside a skipped one: a start moves to the
  // next text node, an end back to the end of the one before.
  const document = container.ownerDocument ?? (container as Document);
  const point = document.createRange();
  try { point.setStart(container, offset); } catch { return null; }
  if (!end) {
    for (const piece of index.pieces) if (point.comparePoint(piece.node, 0) >= 0) return piece.start;
    return index.text.length;
  }
  let before = 0;
  for (const piece of index.pieces) {
    if (point.comparePoint(piece.node, piece.node.data.length) > 0) break;
    before = piece.start + piece.node.data.length;
  }
  return before;
}

/** The headings above an offset, outermost first, as a chain of levels: ["Pod lifecycle", "Pod phase"]. */
export function headingsAt(root: ParentNode, index: TextIndex, offset: number): string[] {
  const stack: { level: number; text: string }[] = [];
  for (const heading of root.querySelectorAll<HTMLElement>("h1, h2, h3, h4, h5, h6")) {
    if (heading.closest("blockquote, li, [data-footnotes]") || skipped(heading, root as Node)) continue;
    const first = index.pieces.find((piece) => heading.contains(piece.node));
    if (!first || first.start > offset) break;
    const level = Number(heading.tagName.slice(1));
    while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
    const text = (heading.textContent ?? "").replace(/\s+/g, " ").trim().slice(0, HEADING_MAX);
    if (text) stack.push({ level, text });
  }
  return stack.slice(-HEADINGS_KEPT).map((entry) => entry.text);
}

/** An anchor for characters `start..end` of a text, trimmed of surrounding white space. */
export function anchorInText(text: string, start: number, end: number, extra: Pick<TextAnchor, "headings" | "lines"> = {}): TextAnchor | null {
  while (start < end && /\s/.test(text[start])) start++;
  while (end > start && /\s/.test(text[end - 1])) end--;
  if (end <= start) return null;
  return {
    exact: text.slice(start, end),
    prefix: text.slice(Math.max(0, start - CONTEXT), start),
    suffix: text.slice(end, end + CONTEXT),
    start, end,
    ...(extra.headings?.length ? { headings: extra.headings } : {}),
    ...(extra.lines ? { lines: extra.lines } : {}),
  };
}

/** Describe a selection inside `root`; null when it holds no readable text. */
export function describeRange(root: HTMLElement, range: Range, extra: Pick<TextAnchor, "lines"> = {}): TextAnchor | null {
  const index = textIndex(root);
  const start = boundaryOffset(index, range.startContainer, range.startOffset, false);
  const end = boundaryOffset(index, range.endContainer, range.endOffset, true);
  if (start == null || end == null || end <= start) return null;
  const anchor = anchorInText(index.text, start, end, extra);
  if (!anchor) return null;
  const headings = headingsAt(root, index, anchor.start);
  return headings.length ? { ...anchor, headings } : anchor;
}

/** How many characters of `a`'s end match `b`'s end (or starts, with `fromStart`). */
function common(a: string, b: string, fromStart: boolean): number {
  let count = 0;
  const max = Math.min(a.length, b.length);
  while (count < max && (fromStart ? a[count] === b[count] : a[a.length - 1 - count] === b[b.length - 1 - count])) count++;
  return count;
}

function bestOccurrence(text: string, exact: string, anchor: Pick<TextAnchor, "prefix" | "suffix" | "start">): number {
  let best = -1;
  let bestScore = -Infinity;
  for (let at = text.indexOf(exact); at !== -1; at = text.indexOf(exact, at + 1)) {
    const score = common(text.slice(Math.max(0, at - anchor.prefix.length), at), anchor.prefix, false)
      + common(text.slice(at + exact.length, at + exact.length + anchor.suffix.length), anchor.suffix, true)
      - Math.min(Math.abs(at - anchor.start) / 2000, 8);
    if (score > bestScore) { bestScore = score; best = at; }
  }
  return best;
}

/** Whitespace runs collapsed to one space, with each kept character's original offset. */
function collapse(text: string): { text: string; map: number[] } {
  let out = "";
  const map: number[] = [];
  let space = false;
  for (let index = 0; index < text.length; index++) {
    const char = text[index];
    if (/\s/.test(char)) {
      if (!space && out) { out += " "; map.push(index); }
      space = true;
      continue;
    }
    space = false;
    out += char.toLowerCase();
    map.push(index);
  }
  return { text: out, map };
}

/**
 * Find an anchored passage in a text, as `[start, end)`: at its old place if it
 * is still there, else the repeat whose context fits best, else the same with
 * white space and case ignored. Null when the words are gone.
 */
export function findInText(text: string, anchor: TextAnchor): [number, number] | null {
  const { exact } = anchor;
  if (!exact) return null;
  if (text.slice(anchor.start, anchor.end) === exact) return [anchor.start, anchor.end];
  const at = bestOccurrence(text, exact, anchor);
  if (at >= 0) return [at, at + exact.length];
  const loose = collapse(text);
  const quote = collapse(exact).text.trim();
  if (!quote) return null;
  const looseAt = bestOccurrence(loose.text, quote, {
    prefix: collapse(anchor.prefix).text, suffix: collapse(anchor.suffix).text,
    start: loose.map.findIndex((offset) => offset >= anchor.start),
  });
  if (looseAt < 0) return null;
  return [loose.map[looseAt], loose.map[looseAt + quote.length - 1] + 1];
}

/** A quote someone typed (a mentor's link, a command), anchored where it best fits a text. */
export function quoteInText(text: string, quote: string, near = 0): TextAnchor | null {
  const probe = { exact: quote.trim(), prefix: "", suffix: "", start: near, end: near };
  const found = findInText(text, probe);
  return found ? anchorInText(text, found[0], found[1]) : null;
}

/** A DOM range for `[start, end)` of an index's text. */
export function rangeAt(index: TextIndex, start: number, end: number): Range | null {
  const first = index.pieces.find((piece) => start < piece.start + piece.node.data.length);
  let last: Piece | undefined;
  for (const piece of index.pieces) if (piece.start < end) last = piece;
  if (!first || !last) return null;
  const range = first.node.ownerDocument.createRange();
  range.setStart(first.node, Math.max(0, start - first.start));
  range.setEnd(last.node, Math.min(last.node.data.length, end - last.start));
  return range;
}

/** Where an anchored passage is in a rendered reader now, or null when it is gone (an orphan). */
export function resolveAnchor(root: HTMLElement, anchor: TextAnchor, index = textIndex(root)): Range | null {
  const found = findInText(index.text, anchor);
  return found ? rangeAt(index, found[0], found[1]) : null;
}

/** 1-based first and last line of `[start, end)` in a text. */
export function linesOf(text: string, start: number, end: number): [number, number] {
  const line = (offset: number) => text.slice(0, offset).split("\n").length;
  return [line(start), line(Math.max(start, end - 1))];
}
