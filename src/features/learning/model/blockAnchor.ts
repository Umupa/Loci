import { headingsAt, textIndex, type TextIndex } from "./textAnchor";
import type { BlockRef, TextAnchor } from "./types";

/*
 * Whole blocks of a rendered Markdown text (a table, a diagram, a code block,
 * a picture) kept as one mark. The renderer writes each block's Markdown onto
 * its element; a mark remembers that source and which block of its kind it
 * was, and finds it again by the source, so it follows the block when other
 * text moves and becomes an orphan when the block itself is rewritten.
 */

export type BlockKind = "table" | "mermaid" | "code" | "image" | "mindmap";
export const BLOCK_SELECTOR = "[data-block-source]";

/** The longest source kept in a mark. A longer block is found by its start. */
export const BLOCK_SOURCE_MAX = 60 * 1024;
/** Words of a block's rendered text a link quotes, to find and flash it. */
const LEAD_MAX = 120;

export type ReadingBlock = {
  element: HTMLElement;
  kind: BlockKind;
  /** The block as Markdown: a fenced code block, a table, `![alt](src)`. */
  source: string;
  /** Which block of its kind it is in the reader, from 0. */
  index: number;
};

/** The blocks shown in a reader, in reading order. A block inside another (a picture in a table) is its own. */
export function readingBlocks(root: ParentNode): ReadingBlock[] {
  const counts = new Map<string, number>();
  const blocks: ReadingBlock[] = [];
  for (const element of root.querySelectorAll<HTMLElement>(BLOCK_SELECTOR)) {
    const kind = element.dataset.blockKind as BlockKind | undefined;
    const source = element.dataset.blockSource ?? "";
    if (!kind || !source.trim()) continue;
    const index = counts.get(kind) ?? 0;
    counts.set(kind, index + 1);
    blocks.push({ element, kind, source, index });
  }
  return blocks;
}

/** The block an element is in, when it is in one. */
export function blockAt(root: HTMLElement, target: Element | null): ReadingBlock | null {
  const element = target?.closest<HTMLElement>(BLOCK_SELECTOR);
  if (!element || !root.contains(element)) return null;
  return readingBlocks(root).find((block) => block.element === element) ?? null;
}

/** Where a block starts in the reader's text, so it sorts among passages: its first text, or the text after it. */
function blockOffset(index: TextIndex, element: Element): number {
  for (const piece of index.pieces) {
    if (element.contains(piece.node)) return piece.start;
    if (element.compareDocumentPosition(piece.node) & 4 /* FOLLOWING */) return piece.start;
  }
  return index.text.length;
}

/** The opening words of a block's rendered text (a table's header, a code block's first line); empty for a picture or a diagram. */
export function blockLead(index: TextIndex, element: Element): string {
  const inside = index.pieces.filter((piece) => element.contains(piece.node));
  if (!inside.length) return "";
  const last = inside[inside.length - 1];
  const text = index.text.slice(inside[0].start, last.start + last.node.data.length).trim();
  return Array.from(text).slice(0, LEAD_MAX).join("").trimEnd();
}

/** An anchor for a whole block: its source as the words, with its kind and place among blocks of that kind. */
export function blockAnchor(root: HTMLElement, block: ReadingBlock, index = textIndex(root)): TextAnchor {
  const start = blockOffset(index, block.element);
  const lead = blockLead(index, block.element);
  const headings = headingsAt(root, index, start);
  const ref: BlockRef = { kind: block.kind, index: block.index, ...(lead ? { lead } : {}) };
  return { exact: block.source.slice(0, BLOCK_SOURCE_MAX), prefix: "", suffix: "", start, end: start,
    ...(headings.length ? { headings } : {}), block: ref };
}

const loose = (text: string) => text.replace(/\s+/g, " ").trim();

/**
 * The block a mark is on now: one of its kind with the same source, the one
 * nearest its old place among repeats; else the same with white space
 * ignored. Null when no block has that source any more (an orphan).
 */
export function resolveBlock(blocks: readonly ReadingBlock[], anchor: TextAnchor): ReadingBlock | null {
  const ref = anchor.block;
  if (!ref) return null;
  const ofKind = blocks.filter((block) => block.kind === ref.kind);
  const cut = anchor.exact.length >= BLOCK_SOURCE_MAX;
  const same = (source: string, exact: string) => cut ? source.startsWith(exact) : source === exact;
  const nearest = (found: ReadingBlock[]) => found.sort((a, b) => Math.abs(a.index - ref.index) - Math.abs(b.index - ref.index))[0] ?? null;
  const exact = ofKind.filter((block) => same(block.source, anchor.exact));
  if (exact.length) return nearest(exact);
  const wanted = loose(anchor.exact);
  return nearest(ofKind.filter((block) => same(loose(block.source), wanted)));
}

/** A fenced code block as Markdown, with a fence longer than any run of backticks inside it. */
export function fencedSource(language: string, meta: string, code: string): string {
  const body = code.replace(/\r\n?/g, "\n").replace(/\n$/, "");
  const longest = Math.max(0, ...Array.from(body.matchAll(/`+/g), (run) => run[0].length));
  const fence = "`".repeat(Math.max(3, longest + 1));
  const info = [language, meta].map((part) => part.trim()).filter(Boolean).join(" ");
  return `${fence}${info}\n${body}\n${fence}`;
}

/** A picture as Markdown. Brackets in the alt text and spaces in the address are escaped so the link stays whole. */
export function imageSource(alt: string, src: string): string {
  const text = alt.replace(/[\r\n]+/g, " ").replace(/([[\]\\])/g, "\\$1");
  const address = /[\s()<>]/.test(src) ? `<${src.replace(/[<>]/g, encodeURIComponent)}>` : src;
  return `![${text}](${address})`;
}

/** What a reader calls a block, for a note's title or a list. */
export function blockLabel(kind: string): string {
  return kind === "table" ? "Table" : kind === "mermaid" ? "Diagram" : kind === "code" ? "Code" : kind === "image" ? "Picture" : kind === "mindmap" ? "Mind map" : kind === "area" ? "Area" : "Block";
}
