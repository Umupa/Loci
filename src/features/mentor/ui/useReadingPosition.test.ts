// @vitest-environment happy-dom
import { act, createElement, useRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { requestFilePlace } from "../../files/model/filePlace";
import type { MentorPage } from "../model/mentorPage";
import { recalledPosition, rememberPosition, resetPositionsForTests } from "../model/readingPositions";
import { measurePosition, positionTop, useReadingPosition } from "./useReadingPosition";

/** A scroller 1000px tall over `height` px of content; `place` lays each child out at a content offset. */
function scroller(html: string, height: number, place: (element: HTMLElement) => [number, number] | undefined) {
  const element = document.createElement("div");
  element.setAttribute("data-reading-scroll", "");
  element.innerHTML = html;
  let top = 0;
  Object.defineProperty(element, "scrollTop", { configurable: true, get: () => top, set: (value: number) => { top = Math.max(0, Math.min(value, height - 1000)); } });
  Object.defineProperty(element, "scrollHeight", { configurable: true, get: () => height });
  Object.defineProperty(element, "clientHeight", { configurable: true, get: () => 1000 });
  element.getBoundingClientRect = () => new DOMRect(0, 0, 600, 1000);
  for (const child of element.querySelectorAll<HTMLElement>("*")) {
    child.getBoundingClientRect = () => {
      const box = place(child);
      return box ? new DOMRect(0, box[0] - top, 600, box[1]) : new DOMRect(0, 0, 0, 0);
    };
  }
  return element;
}

const pdf = () => scroller(Array.from({ length: 10 }, (_, index) => `<div data-page-number="${index + 1}"></div>`).join(""), 10_000,
  (element) => element.dataset.pageNumber ? [(Number(element.dataset.pageNumber) - 1) * 1000, 1000] : undefined);

it("measures and finds a PDF page and how far down it the view is", () => {
  const element = pdf();
  element.scrollTop = 4250;
  const position = measurePosition(element);
  expect(position).toEqual({ page: 5, within: 0.25, ratio: 0.4722 });
  element.scrollTop = 0;
  expect(positionTop(element, position, false)).toBe(4250);
});

it("measures code by its first line on screen", () => {
  const lines = Array.from({ length: 200 }, (_, index) => `line ${index + 1}`).join("\n");
  // 20px lines, numbered from 41 (an excerpt).
  const element = scroller(`<div data-reading-text data-reading-lines-from="41"><pre></pre></div>`, 4000,
    (child) => child.matches("pre") ? [0, 4000] : child.matches("div") ? [0, 4000] : undefined);
  element.querySelector("pre")!.textContent = lines;
  element.scrollTop = 1010;
  const position = measurePosition(element);
  expect(position.line).toBe(41 + 50);
  element.scrollTop = 0;
  expect(positionTop(element, position, false)).toBe(1000);
});

it("measures prose by the paragraph at the top, and finds it again after the text above it changed", () => {
  const offsets: Record<string, [number, number]> = { a: [0, 400], b: [400, 400], c: [800, 400], d: [1200, 400] };
  const element = scroller(`<div data-reading-text><p id="a">Intro</p><p id="b">Same words</p><p id="c">Same words</p><p id="d">End</p></div>`, 3000,
    (child) => offsets[child.id]);
  element.scrollTop = 900;
  const position = measurePosition(element);
  expect(position.anchor).toEqual({ text: "Same words", index: 1, within: 0.25 });
  // A paragraph added above moves everything down by 300px.
  for (const id of "abcd") offsets[id] = [offsets[id][0] + 300, 400];
  element.scrollTop = 0;
  expect(positionTop(element, position, false)).toBe(1200);
  // A paragraph that is gone waits, then settles for the share of the height.
  expect(positionTop(element, { ratio: 0.5, anchor: { text: "Gone", index: 0, within: 0 } }, false)).toBeUndefined();
  expect(positionTop(element, { ratio: 0.5, anchor: { text: "Gone", index: 0, within: 0 } }, true)).toBe(1000);
});

let container: HTMLDivElement;
let root: Root;
let main: HTMLElement | null = null;
function Host({ page }: { page?: MentorPage }) {
  const ref = useRef<HTMLElement>(null);
  useReadingPosition(ref, "a", page, undefined);
  return createElement("main", { ref: (element: HTMLElement | null) => { ref.current = element; main = element; } });
}
const render = (page?: MentorPage) => act(async () => root.render(createElement(Host, { page })));
const wait = (ms: number) => act(async () => { await vi.advanceTimersByTimeAsync(ms); });
/** Opens `page` with a fresh reader, as the app does: the old reader is unmounted, a new one starts at the top. */
async function open(page: MentorPage, reader: () => HTMLElement): Promise<HTMLElement> {
  main?.replaceChildren();
  await render(page);
  const element = reader();
  main!.append(element);
  return element;
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  resetPositionsForTests();
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); vi.useRealTimers(); });

const paper: MentorPage = { kind: "file", path: "/papers/raft.pdf" };
const note: MentorPage = { kind: "note", id: "n1" };

it("comes back to the place read in a page after another page was open", async () => {
  let reader = await open(paper, pdf);
  await wait(5000);
  reader.scrollTop = 4250;
  reader.dispatchEvent(new Event("scroll"));
  await wait(300);
  expect(recalledPosition("a", "file:/papers/raft.pdf")).toMatchObject({ page: 5, within: 0.25 });

  await open(note, () => scroller("", 1000, () => undefined));
  reader = await open(paper, pdf);
  expect(reader.scrollTop).toBe(0);
  await wait(1000);
  expect(reader.scrollTop).toBe(4250);
});

it("does not take scrolling while the page loads as the place read", async () => {
  rememberPosition("a", "file:/papers/raft.pdf", { page: 5, within: 0.25, ratio: 0.47 });
  const reader = await open(paper, pdf);
  // The reader settles at its top before the restore runs.
  reader.dispatchEvent(new Event("scroll"));
  await wait(300);
  expect(recalledPosition("a", "file:/papers/raft.pdf")).toMatchObject({ page: 5 });
  expect(reader.scrollTop).toBe(4250);
});

it("stops restoring once the reader scrolls on their own", async () => {
  rememberPosition("a", "file:/papers/paxos.pdf", { page: 5, within: 0.25, ratio: 0.47 });
  const reader = await open({ kind: "file", path: "/papers/paxos.pdf" }, () => scroller("", 10_000, () => undefined)); // pages not laid out yet
  await wait(200);
  main!.dispatchEvent(new Event("wheel"));
  main!.replaceChildren(pdf());
  await wait(2000);
  expect((main!.firstElementChild as HTMLElement).scrollTop).toBe(0);
  expect(reader.isConnected).toBe(false);
});

it("lets a link to a place in the page win over the remembered place", async () => {
  rememberPosition("a", "file:/papers/raft.pdf", { page: 5, within: 0.25, ratio: 0.47 });
  await open(note, () => scroller("", 1000, () => undefined));
  requestFilePlace(paper.path, { page: 2 });
  const reader = await open(paper, pdf);
  await wait(2000);
  // The PDF view shows page 2 itself; the remembered page 5 must not pull it away.
  expect(reader.scrollTop).toBe(0);
});
