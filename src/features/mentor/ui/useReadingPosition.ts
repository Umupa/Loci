import { useEffect, useRef, type RefObject } from "react";
import type { MentorLesson, MentorPage } from "../model/mentorPage";
import { loadPositions, placeRequested, positionKey, recalledPosition, rememberPosition, type ReadingPosition } from "../model/readingPositions";
import { BLOCKS } from "./useReadingPlace";

/**
 * Each reader marks the element that scrolls its text with
 * `data-reading-scroll`. The position is read off that element's DOM, the
 * same marks `useReadingPlace` reads: `data-page-number` for a PDF's pages,
 * `data-reading-lines-from` for code, `data-reading-text` for prose.
 */
export const READING_SCROLL = "[data-reading-scroll]";

/** How often a scroll is measured while it goes on. */
const MEASURE_MS = 250;
/** How long a restore keeps trying while the page loads and lays out. */
const RESTORE_MS = 4000;
/** A restore is done once the place has held this long. */
const SETTLE_MS = 500;
const TICK_MS = 100;
/** How long a paragraph is looked for before the restore settles for the share of the height. */
const ANCHOR_WAIT_MS = 1500;
/** A link asks for its place just before the page opens. */
const EXPLICIT_SLACK_MS = 2000;

const round = (value: number) => Math.round(Math.min(1, Math.max(0, value)) * 10000) / 10000;
const keyOf = (text: string) => text.replace(/\s+/g, " ").trim().slice(0, 80);

/** The element scrolling the reader's text: the one that can scroll, else the one on screen. */
export function readingScroller(root: HTMLElement): HTMLElement | undefined {
  const marked = [...root.querySelectorAll<HTMLElement>(READING_SCROLL)];
  return marked.find((element) => element.scrollHeight > element.clientHeight + 1) ?? marked.find((element) => element.clientHeight > 0);
}

/** Code shown alone, as one block of lines: its `<pre>`, the first line's number and the line height. */
function codeIn(scroller: HTMLElement): { pre: HTMLElement; from: number; lines: number; top: number; height: number } | undefined {
  const marked = scroller.querySelectorAll<HTMLElement>("[data-reading-lines-from]");
  // Prose beside it, or several excerpts (a comparison), are read by their blocks instead.
  if (marked.length !== 1 || scroller.querySelector("[data-reading-text]:not([data-reading-lines-from])")) return undefined;
  const pre = marked[0].querySelector<HTMLElement>("pre");
  const from = Number(marked[0].dataset.readingLinesFrom);
  if (!pre || !Number.isInteger(from) || from < 1) return undefined;
  const lines = (pre.textContent ?? "").split("\n").length;
  const style = getComputedStyle(pre);
  const padTop = parseFloat(style.paddingTop) || 0;
  const rect = pre.getBoundingClientRect();
  // Code does not wrap, so every line is as tall as the next.
  const height = (rect.height - padTop - (parseFloat(style.paddingBottom) || 0)) / lines;
  return height > 0 ? { pre, from, lines, top: rect.top + padTop, height } : undefined;
}

/** The prose blocks a page shows, outermost only, as `useReadingPlace` finds them. */
function blocksIn(scroller: HTMLElement): { element: HTMLElement; key: string }[] {
  return [...scroller.querySelectorAll<HTMLElement>(BLOCKS)]
    .filter((block) => block.closest("[data-reading-text]") && (!block.parentElement?.closest(BLOCKS) || block.matches("li")))
    .map((element) => ({ element, key: keyOf(element.textContent ?? "") }))
    .filter((block) => block.key && block.element.getBoundingClientRect().height > 0);
}

/** Where the reader is in what `scroller` shows. */
export function measurePosition(scroller: HTMLElement): ReadingPosition {
  const max = scroller.scrollHeight - scroller.clientHeight;
  const position: ReadingPosition = { ratio: max > 0 ? round(scroller.scrollTop / max) : 0 };
  const view = scroller.getBoundingClientRect().top;
  const pages = [...scroller.querySelectorAll<HTMLElement>("[data-page-number]")];
  if (pages.length) {
    const page = pages.find((element) => element.getBoundingClientRect().bottom > view + 1);
    const rect = page?.getBoundingClientRect();
    if (page && rect && rect.height > 0) { position.page = Number(page.dataset.pageNumber); position.within = round((view - rect.top) / rect.height); }
    return position;
  }
  const code = codeIn(scroller);
  if (code) {
    position.line = code.from + Math.min(code.lines - 1, Math.max(0, Math.floor((view - code.top + 1) / code.height)));
    return position;
  }
  const blocks = blocksIn(scroller);
  const at = blocks.findIndex((block) => block.element.getBoundingClientRect().bottom > view + 1);
  if (at >= 0) {
    const { element, key } = blocks[at];
    const rect = element.getBoundingClientRect();
    position.anchor = { text: key, index: blocks.slice(0, at).filter((block) => block.key === key).length, within: round((view - rect.top) / rect.height) };
  }
  return position;
}

/**
 * The scroll offset that shows `position` in `scroller`, or nothing while
 * what it names is not on the page yet. `fallback` lets a paragraph that is
 * not found give way to the share of the height.
 */
export function positionTop(scroller: HTMLElement, position: ReadingPosition, fallback: boolean): number | undefined {
  const view = scroller.getBoundingClientRect().top;
  const max = scroller.scrollHeight - scroller.clientHeight;
  const byRatio = () => position.ratio === 0 ? 0 : max > 0 ? position.ratio * max : undefined;
  if (position.page) {
    const page = scroller.querySelector<HTMLElement>(`[data-page-number="${position.page}"]`);
    if (!page) return fallback && scroller.querySelector("[data-page-number]") ? byRatio() : undefined;
    const rect = page.getBoundingClientRect();
    return scroller.scrollTop + rect.top - view + (position.within ?? 0) * rect.height;
  }
  if (position.line) {
    const code = codeIn(scroller);
    if (!code) return fallback ? byRatio() : undefined;
    const line = Math.min(code.from + code.lines - 1, Math.max(code.from, position.line));
    return scroller.scrollTop + code.top + (line - code.from) * code.height - view;
  }
  if (position.anchor) {
    const { text, index, within } = position.anchor;
    const matches = blocksIn(scroller).filter((block) => block.key === text);
    const block = matches[Math.min(index, matches.length - 1)];
    if (!block) return fallback ? byRatio() : undefined;
    const rect = block.element.getBoundingClientRect();
    return scroller.scrollTop + rect.top - view + within * rect.height;
  }
  return byRatio();
}

/**
 * Remembers where the reader is in each page, per mentor, and takes the
 * reader back there when the page opens again: after another page, another
 * mentor or a restart. A link that names a place in the page wins.
 */
export function useReadingPosition(root: RefObject<HTMLElement | null>, agentId: string, page: MentorPage | undefined, lesson: MentorLesson | undefined): void {
  const key = positionKey(page, lesson);
  const pageRef = useRef(page);
  pageRef.current = page;
  useEffect(() => {
    const element = root.current;
    if (!element || !key) return;
    const opened = Date.now();
    let live = true;
    // Until the restore is over, scrolling is the page loading or the restore itself, not reading.
    let restoring = true;
    let restoreTimer = 0;
    let measureTimer = 0;
    let measuredAt = 0;
    const finish = () => { restoring = false; window.clearTimeout(restoreTimer); };
    const explicit = () => !!pageRef.current && placeRequested(agentId, pageRef.current, opened - EXPLICIT_SLACK_MS);

    const scroll = (event: Event) => {
      const target = event.target;
      if (restoring || measureTimer || !(target instanceof HTMLElement) || !element.contains(target) || !target.matches(READING_SCROLL)) return;
      measureTimer = window.setTimeout(() => {
        measureTimer = 0;
        measuredAt = Date.now();
        if (target.isConnected) rememberPosition(agentId, key, measurePosition(target));
      }, Math.max(0, MEASURE_MS - (Date.now() - measuredAt)));
    };
    // The reader moving on their own ends the restore.
    const interrupt = () => { if (restoring) finish(); };
    const inputs = ["wheel", "pointerdown", "keydown", "touchstart"] as const;
    for (const name of inputs) element.addEventListener(name, interrupt, { passive: true });
    document.addEventListener("scroll", scroll, true);

    void loadPositions().then(() => {
      if (!live || !restoring) return;
      const position = recalledPosition(agentId, key);
      if (!position) { finish(); return; }
      let heldSince = 0;
      const tick = () => {
        if (!live || !restoring) return;
        const elapsed = Date.now() - opened;
        if (elapsed > RESTORE_MS || explicit()) { finish(); return; }
        const scroller = readingScroller(element);
        const top = scroller ? positionTop(scroller, position, elapsed > ANCHOR_WAIT_MS) : undefined;
        if (scroller && top !== undefined) {
          // Pages and images still laying out move the place; keep putting it back until it holds.
          if (Math.abs(scroller.scrollTop - top) > 2) { scroller.scrollTop = top; heldSince = Date.now(); }
          else if (!heldSince) heldSince = Date.now();
          else if (Date.now() - heldSince >= SETTLE_MS) { finish(); return; }
        }
        restoreTimer = window.setTimeout(tick, TICK_MS);
      };
      tick();
    });

    return () => {
      live = false;
      window.clearTimeout(restoreTimer);
      window.clearTimeout(measureTimer);
      for (const name of inputs) element.removeEventListener(name, interrupt);
      document.removeEventListener("scroll", scroll, true);
    };
  }, [root, agentId, key]);
}
