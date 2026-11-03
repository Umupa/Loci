/// <reference lib="es2022.intl" />
/**
 * Selection behaviour for pdf.js text layers. pdf.js's own viewer keeps an
 * `.endOfContent` marker in every layer and moves it under the pointer, so a
 * drag across the blank space between lines stops at the text instead of
 * snapping to the next block. The marker's CSS is in `index.css`; this module
 * supplies the DOM and the listener it assumes.
 */

/** Word segmentation is absent only on WebViews older than the app's targets; there is no snapping then. */
const WORD_SEGMENTER = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(undefined, { granularity: "word" }) : null;

type Word = { start: number; end: number };

/** The word `offset` falls inside, or null when the point is already between words. */
function wordAt(text: string, offset: number): Word | null {
  if (!WORD_SEGMENTER) return null;
  for (const part of WORD_SEGMENTER.segment(text)) {
    const end = part.index + part.segment.length;
    if (part.isWordLike && part.index < offset && offset < end) return { start: part.index, end };
  }
  return null;
}

/**
 * `start..end` widened to the whole words its ends fall in. A boundary already
 * between words stays put, so selecting "we chose" never takes "our" with it.
 */
export function snapToWords(text: string, start: number, end: number): [number, number] {
  if (end <= start) return [start, end];
  const first = wordAt(text, start);
  const last = wordAt(text, end);
  return [first ? first.start : start, last ? last.end : end];
}

type Piece = { node: Text; start: number; end: number };
type LayerText = { text: string; pieces: Piece[] };

/**
 * A layer's text in reading order. Text runs sit in absolutely placed spans,
 * one per PDF text item; a run on another line starts a new line here, so a
 * word at the end of one line cannot join the word that begins the next.
 */
function layerText(layer: HTMLElement): LayerText {
  const pieces: Piece[] = [];
  let text = "";
  let top: string | null = null;

  const addText = (node: Text, lineTop: string | null) => {
    if (!node.data) return;
    if (text && top !== null && lineTop !== null && lineTop !== top && !text.endsWith("\n")) text += "\n";
    pieces.push({ node, start: text.length, end: text.length + node.data.length });
    text += node.data;
    if (lineTop !== null) top = lineTop;
  };

  const visit = (node: Node, lineTop: string | null) => {
    if (node.nodeType === Node.TEXT_NODE) {
      addText(node as Text, lineTop);
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    const element = node as Element;
    if (element.classList.contains("endOfContent")) return;
    if (element.tagName === "BR") {
      if (text && !text.endsWith("\n")) text += "\n";
      return;
    }
    const ownTop = element instanceof HTMLElement && element.style.top ? element.style.top : lineTop;
    for (const child of element.childNodes) visit(child, ownTop);
  };

  for (const child of layer.childNodes) visit(child, null);
  return { text, pieces };
}

function firstText(node: Node): Text | null {
  if (node.nodeType === Node.TEXT_NODE) return node as Text;
  for (const child of node.childNodes) {
    const found = firstText(child);
    if (found) return found;
  }
  return null;
}

function lastText(node: Node): Text | null {
  if (node.nodeType === Node.TEXT_NODE) return node as Text;
  for (let index = node.childNodes.length - 1; index >= 0; index--) {
    const found = lastText(node.childNodes[index]!);
    if (found) return found;
  }
  return null;
}

function nextTextAfter(node: Node, root: Node): Text | null {
  let current: Node | null = node;
  while (current && current !== root) {
    const next = current.nextSibling;
    if (next) {
      const found = firstText(next);
      if (found) return found;
    }
    current = current.parentNode;
  }
  return null;
}

function previousTextBefore(node: Node, root: Node): Text | null {
  let current: Node | null = node;
  while (current && current !== root) {
    const previous = current.previousSibling;
    if (previous) {
      const found = lastText(previous);
      if (found) return found;
    }
    current = current.parentNode;
  }
  return null;
}

/** The text position a range boundary sits at, walking elements as well as text nodes. */
function boundaryText(layer: HTMLElement, container: Node, offset: number, end: boolean): { node: Text; offset: number } | null {
  if (container.nodeType === Node.TEXT_NODE) return { node: container as Text, offset };
  if (container.nodeType !== Node.ELEMENT_NODE || !layer.contains(container)) return null;
  if (offset < 0 || offset > container.childNodes.length) return null;
  if (!end) {
    for (let index = offset; index < container.childNodes.length; index++) {
      const found = firstText(container.childNodes[index]!);
      if (found) return { node: found, offset: 0 };
    }
    const next = nextTextAfter(container, layer);
    return next ? { node: next, offset: 0 } : null;
  }
  for (let index = offset - 1; index >= 0; index--) {
    const found = lastText(container.childNodes[index]!);
    if (found) return { node: found, offset: found.data.length };
  }
  const previous = previousTextBefore(container, layer);
  return previous ? { node: previous, offset: previous.data.length } : null;
}

function offsetInIndex(index: LayerText, node: Text, offset: number): number | null {
  const piece = index.pieces.find((entry) => entry.node === node);
  return piece ? piece.start + Math.max(0, Math.min(offset, node.data.length)) : null;
}

/** The text position of `offset`; a point inside a synthetic line break moves off it. */
function positionAt(index: LayerText, offset: number, end: boolean): { node: Text; offset: number } | null {
  if (!end) {
    const piece = index.pieces.find((entry) => entry.end > offset);
    return piece ? { node: piece.node, offset: Math.max(0, Math.min(piece.node.data.length, offset - piece.start)) } : null;
  }
  for (let at = index.pieces.length - 1; at >= 0; at--) {
    const piece = index.pieces[at]!;
    if (piece.start < offset) return { node: piece.node, offset: Math.max(0, Math.min(piece.node.data.length, offset - piece.start)) };
  }
  return null;
}

function layerOf(node: Node): HTMLElement | null {
  const element = node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement;
  return element?.closest<HTMLElement>(".textLayer") ?? null;
}

/** A copy of `range` whose start and end sit on whole words inside their text layers. */
function snapRangeToWords(range: Range): Range {
  const snapped = range.cloneRange();
  const startLayer = layerOf(range.startContainer);
  const endLayer = layerOf(range.endContainer);
  if (startLayer) {
    const index = layerText(startLayer);
    const point = boundaryText(startLayer, range.startContainer, range.startOffset, false);
    const offset = point ? offsetInIndex(index, point.node, point.offset) : null;
    const word = offset === null ? null : wordAt(index.text, offset);
    const at = word ? positionAt(index, word.start, false) : null;
    if (at) snapped.setStart(at.node, at.offset);
  }
  if (endLayer) {
    const index = layerText(endLayer);
    const point = boundaryText(endLayer, range.endContainer, range.endOffset, true);
    const offset = point ? offsetInIndex(index, point.node, point.offset) : null;
    const word = offset === null ? null : wordAt(index.text, offset);
    const at = word ? positionAt(index, word.end, true) : null;
    if (at) snapped.setEnd(at.node, at.offset);
  }
  return snapped;
}

/** Widen a finished selection to whole words; true when a boundary moved. */
export function snapSelectionToWords(selection = window.getSelection()): boolean {
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return false;
  const range = selection.getRangeAt(0);
  const snapped = snapRangeToWords(range);
  if (snapped.startContainer === range.startContainer && snapped.startOffset === range.startOffset
    && snapped.endContainer === range.endContainer && snapped.endOffset === range.endOffset) return false;
  selection.removeAllRanges();
  selection.addRange(snapped);
  return true;
}

type Registered = { end: HTMLElement; abort: AbortController };

const LAYERS = new Map<HTMLElement, Registered>();
let selectionListener: AbortController | null = null;
let handlesSelectionNatively: boolean | null = null;

/**
 * Firefox and Chromium 148+ place a selection's focus themselves; moving the
 * marker there would fight the browser, so the official viewer leaves it to
 * them and so do we.
 */
function browserHandlesSelection(layer: HTMLElement): boolean {
  if (handlesSelectionNatively === null) {
    handlesSelectionNatively = getComputedStyle(layer).getPropertyValue("-moz-user-select") === "none";
    if (!handlesSelectionNatively) {
      const navigatorWithBrands = navigator as Navigator & { userAgentData?: { brands: { brand: string; version: string }[] } };
      const version = navigatorWithBrands.userAgentData?.brands.find(({ brand }) => brand === "Chromium")?.version
        ?? /\bChrome\/(\d+)\b/.exec(navigator.userAgent)?.[1];
      handlesSelectionNatively = !!version && Number.parseInt(version, 10) >= 148;
    }
  }
  return handlesSelectionNatively;
}

function listenForSelection(): void {
  if (selectionListener) return;
  selectionListener = new AbortController();
  const { signal } = selectionListener;
  let pointerDown = false;
  let keyboard = false;
  let previous: Range | null = null;

  const reset = (layer: HTMLElement, end: HTMLElement) => {
    layer.append(end);
    end.style.width = "";
    end.style.height = "";
    layer.classList.remove("selecting");
  };
  const resetAll = () => { for (const [layer, entry] of LAYERS) reset(layer, entry.end); };

  document.addEventListener("pointerdown", () => { pointerDown = true; previous = null; }, { signal });
  document.addEventListener("pointerup", () => {
    pointerDown = false;
    // Snap before the marker goes home: the selection may end on it, and a
    // range that points at words no longer moves with the marker.
    snapSelectionToWords();
    resetAll();
  }, { signal });
  window.addEventListener("blur", () => { pointerDown = false; keyboard = false; resetAll(); }, { signal });
  document.addEventListener("keydown", () => { keyboard = true; }, { signal });
  document.addEventListener("keyup", () => { keyboard = false; if (!pointerDown) resetAll(); }, { signal });
  document.addEventListener("selectionchange", () => {
    const selection = document.getSelection();
    if (!selection || selection.rangeCount === 0) {
      resetAll();
      return;
    }
    const active = new Set<HTMLElement>();
    for (let index = 0; index < selection.rangeCount; index++) {
      const range = selection.getRangeAt(index);
      for (const layer of LAYERS.keys()) {
        if (!active.has(layer) && range.intersectsNode(layer)) active.add(layer);
      }
    }
    // Only an ongoing gesture needs the marker under the pointer. A selection
    // that we widen after pointerup also fires this event; it must not revive it.
    const selecting = pointerDown || keyboard;
    for (const [layer, entry] of LAYERS) {
      if (selecting && active.has(layer)) layer.classList.add("selecting");
      else reset(layer, entry.end);
    }
    const first = LAYERS.keys().next().value;
    if (!selecting || !first || browserHandlesSelection(first)) return;

    const range = selection.getRangeAt(0);
    const changesStart = previous !== null && previous.startContainer.isConnected
      && (range.compareBoundaryPoints(Range.END_TO_END, previous) === 0
        || range.compareBoundaryPoints(Range.START_TO_END, previous) === 0);
    let anchor: Node = changesStart ? range.startContainer : range.endContainer;
    if (anchor.nodeType === Node.TEXT_NODE) anchor = anchor.parentNode ?? anchor;
    if (anchor instanceof Element && anchor.classList.contains("highlight")) anchor = anchor.parentNode ?? anchor;
    if (!changesStart && range.endOffset === 0) {
      for (;;) {
        while (!anchor.previousSibling && anchor.parentNode) anchor = anchor.parentNode;
        if (!anchor.previousSibling) break;
        anchor = anchor.previousSibling;
        if (anchor.childNodes.length) break;
      }
    }
    const parent = anchor.parentElement;
    const layer = parent?.closest<HTMLElement>(".textLayer") ?? null;
    const end = layer ? LAYERS.get(layer)?.end : undefined;
    if (parent && layer && end) {
      end.style.width = layer.style.width;
      end.style.height = layer.style.height;
      end.style.userSelect = "text";
      parent.insertBefore(end, changesStart ? anchor : anchor.nextSibling);
    }
    previous = range.cloneRange();
  }, { signal });
}

/** Add the marker pdf.js expects at the end of a rendered text layer. */
export function attachTextLayer(layer: HTMLElement): void {
  if (LAYERS.has(layer)) return;
  const end = layer.ownerDocument.createElement("div");
  end.className = "endOfContent";
  layer.append(end);
  const abort = new AbortController();
  layer.addEventListener("mousedown", () => layer.classList.add("selecting"), { signal: abort.signal });
  LAYERS.set(layer, { end, abort });
  listenForSelection();
}

/** Stop tracking a layer that is being removed or rendered again. */
export function detachTextLayer(layer: HTMLElement): void {
  const entry = LAYERS.get(layer);
  if (!entry) return;
  LAYERS.delete(layer);
  entry.abort.abort();
  entry.end.remove();
  layer.classList.remove("selecting");
  if (LAYERS.size === 0) {
    selectionListener?.abort();
    selectionListener = null;
  }
}
