import { useEffect, useRef, useState, type RefObject } from "react";
import { resolveAnchor, textIndex } from "../model/textAnchor";
import type { Annotation } from "../model/types";

/**
 * Painting text highlights. Readers render Markdown, code and plain text with
 * React and Streamdown, so the DOM is never touched: the marks are ranges given
 * to the CSS Custom Highlight API. Where it is missing nothing is painted, and
 * the list, Ask and jumps still work.
 */

type HighlightCtor = new (...ranges: Range[]) => unknown;
type Registry = { set(name: string, value: unknown): void; delete(name: string): void };

function registry(): { highlights: Registry; Highlight: HighlightCtor } | null {
  const css = (globalThis as { CSS?: { highlights?: Registry } }).CSS;
  const Highlight = (globalThis as { Highlight?: HighlightCtor }).Highlight;
  return css?.highlights && Highlight ? { highlights: css.highlights, Highlight } : null;
}

// Every reader on screen paints into the same named highlights.
const owners = new Map<symbol, { marks: Range[]; selected: Range[] }>();
function repaint() {
  const api = registry();
  if (!api) return;
  const marks = [...owners.values()].flatMap((entry) => entry.marks);
  const selected = [...owners.values()].flatMap((entry) => entry.selected);
  api.highlights.set("loci-mark", new api.Highlight(...marks));
  api.highlights.set("loci-mark-selected", new api.Highlight(...selected));
}

let flashTimer = 0;
/** Bring a passage into view and flash it once, as a link to it lands. */
export function flashRange(range: Range): void {
  const element = range.startContainer instanceof Element ? range.startContainer : range.startContainer.parentElement;
  const reduced = typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  element?.scrollIntoView?.({ block: "center", behavior: reduced ? "instant" : "smooth" });
  const api = registry();
  if (!api) return;
  api.highlights.set("loci-flash", new api.Highlight(range));
  window.clearTimeout(flashTimer);
  flashTimer = window.setTimeout(() => api.highlights.delete("loci-flash"), 1600);
}

function caretAt(x: number, y: number): { node: Node; offset: number } | null {
  const doc = document as Document & {
    caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null;
    caretRangeFromPoint?: (x: number, y: number) => Range | null;
  };
  const position = doc.caretPositionFromPoint?.(x, y);
  if (position) return { node: position.offsetNode, offset: position.offset };
  const range = doc.caretRangeFromPoint?.(x, y);
  return range ? { node: range.startContainer, offset: range.startOffset } : null;
}

/** The mark under a point, when one is. */
export function markAt(ranges: ReadonlyMap<string, Range>, x: number, y: number): string | undefined {
  const caret = caretAt(x, y);
  if (!caret) return undefined;
  for (const [id, range] of ranges) {
    try {
      if (range.isPointInRange(caret.node, caret.offset) && !(range.endContainer === caret.node && range.endOffset === caret.offset)) return id;
    } catch { /* another document */ }
  }
  return undefined;
}

type Options = {
  selectedId?: string;
  /** A mark was clicked: open it at the point. */
  onOpen?: (annotation: Annotation, at: DOMRect) => void;
  /** Off while the text is not shown as text (a Markdown source being edited). */
  enabled?: boolean;
};

/**
 * Resolve each mark's anchor in `root` and paint it. Resolution waits for the
 * text to settle (code highlighting and diagrams render after mount). Returns
 * the marks whose words are gone, and a way to find a mark's range.
 */
export function useTextHighlights(root: RefObject<HTMLElement | null>, annotations: readonly Annotation[], { selectedId, onOpen, enabled = true }: Options = {}) {
  const [orphans, setOrphans] = useState<ReadonlySet<string>>(() => new Set());
  const ranges = useRef(new Map<string, Range>());
  const owner = useRef(Symbol("reader"));
  const latest = useRef({ annotations, onOpen, selectedId });
  latest.current = { annotations, onOpen, selectedId };

  useEffect(() => {
    const element = root.current;
    const me = owner.current;
    if (!element || !enabled) {
      ranges.current = new Map();
      owners.delete(me);
      repaint();
      setOrphans((current) => current.size ? new Set() : current);
      return;
    }
    let timer = 0;
    const resolve = () => {
      timer = 0;
      const index = textIndex(element);
      const next = new Map<string, Range>();
      const gone = new Set<string>();
      for (const annotation of latest.current.annotations) {
        if (!annotation.anchor) continue;
        const range = resolveAnchor(element, annotation.anchor, index);
        if (range) next.set(annotation.id, range); else gone.add(annotation.id);
      }
      ranges.current = next;
      const selected = latest.current.selectedId;
      owners.set(me, { marks: [...next].filter(([id]) => id !== selected).map(([, range]) => range), selected: selected && next.get(selected) ? [next.get(selected)!] : [] });
      repaint();
      setOrphans((current) => current.size === gone.size && [...gone].every((id) => current.has(id)) ? current : gone);
    };
    resolve();
    const observer = new MutationObserver(() => {
      window.clearTimeout(timer);
      timer = window.setTimeout(resolve, 120);
    });
    observer.observe(element, { childList: true, subtree: true, characterData: true });
    const click = (event: MouseEvent) => {
      if (!window.getSelection()?.isCollapsed) return;
      const id = markAt(ranges.current, event.clientX, event.clientY);
      const annotation = id ? latest.current.annotations.find((entry) => entry.id === id) : undefined;
      if (annotation) latest.current.onOpen?.(annotation, new DOMRect(event.clientX, event.clientY, 1, 1));
    };
    element.addEventListener("click", click);
    return () => {
      observer.disconnect();
      window.clearTimeout(timer);
      element.removeEventListener("click", click);
      owners.delete(me);
      repaint();
    };
  }, [root, annotations, selectedId, enabled]);

  return { orphans, rangeOf: (id: string) => ranges.current.get(id) };
}
