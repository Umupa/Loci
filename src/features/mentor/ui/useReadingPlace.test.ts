// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from "vitest";
import { measurePlace, selectionPlace } from "./useReadingPlace";

function box(element: Element, top: number, bottom: number) {
  vi.spyOn(element, "getBoundingClientRect").mockReturnValue(new DOMRect(0, top, 600, bottom - top));
}
afterEach(() => { vi.restoreAllMocks(); window.getSelection()?.removeAllRanges(); });

it("finds the first paragraph on screen and the headings above it", () => {
  const root = document.createElement("main");
  root.innerHTML = `<div data-reading-text><h1>Pods</h1><p>Off screen.</p><h2>Pod phase</h2><p>A Pod's status field.</p><p>Later.</p></div>`;
  document.body.replaceChildren(root);
  box(root, 100, 700);
  const [h1, first, h2, visible, later] = root.querySelectorAll("h1, p, h2");
  box(h1, -300, -260); box(first, -250, -100); box(h2, -90, 50); box(visible, 120, 200); box(later, 210, 300);
  expect(measurePlace(root)).toEqual({ paragraph: "A Pod's status field.", section: ["Pods", "Pod phase"] });
});

it("reports a PDF's most visible page", () => {
  const root = document.createElement("main");
  root.innerHTML = `<div data-reading-text><div data-page-number="3"></div><div data-page-number="4"></div></div>`;
  document.body.replaceChildren(root);
  box(root, 0, 800);
  const [three, four] = root.querySelectorAll("[data-page-number]");
  box(three, -900, 100); box(four, 110, 1100);
  expect(measurePlace(root).page).toBe(4);
});

it("gives a selection in a file excerpt its file lines, and nothing once focus leaves the reader", () => {
  const root = document.createElement("main");
  root.innerHTML = `<div data-reading-text data-reading-lines-from="20"><pre><code>one\ntwo\nthree</code></pre></div>`;
  const outside = document.createElement("textarea");
  document.body.replaceChildren(root, outside);
  const text = root.querySelector("code")!.firstChild!;
  const range = document.createRange(); range.setStart(text, 4); range.setEnd(text, 9);
  window.getSelection()!.addRange(range);
  expect(selectionPlace(root)).toEqual({ text: "two\nt", lines: [21, 22] });
  window.getSelection()!.removeAllRanges();
  const elsewhere = document.createRange(); elsewhere.selectNodeContents(outside);
  window.getSelection()!.addRange(elsewhere);
  expect(selectionPlace(root)).toBeUndefined();
});
