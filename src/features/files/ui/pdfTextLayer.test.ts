// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { attachTextLayer, detachTextLayer, snapSelectionToWords, snapToWords } from "./pdfTextLayer";

const LAYERS: HTMLElement[] = [];

function layerWith(...lines: string[]): HTMLElement {
  const layer = document.createElement("div");
  layer.className = "textLayer";
  lines.forEach((text, index) => {
    const span = document.createElement("span");
    span.textContent = text;
    span.style.top = `${10 + index * 3}%`;
    layer.append(span);
  });
  document.body.append(layer);
  LAYERS.push(layer);
  return layer;
}

afterEach(() => {
  for (const layer of LAYERS.splice(0)) {
    detachTextLayer(layer);
    layer.remove();
  }
  window.getSelection()?.removeAllRanges();
});

function select(node: Node, start: number, end: number): Selection {
  const range = document.createRange();
  range.setStart(node, start);
  range.setEnd(node, end);
  const selection = window.getSelection()!;
  selection.removeAllRanges();
  selection.addRange(range);
  return selection;
}

describe("word snapping", () => {
  it("widens both ends of a selection to whole words", () => {
    expect(snapToWords("the quick brown fox", 5, 12)).toEqual([4, 15]);
  });

  it("leaves a selection that already starts and ends between words alone", () => {
    expect(snapToWords("the quick brown fox", 4, 15)).toEqual([4, 15]);
    expect(snapToWords("the quick brown fox", 4, 9)).toEqual([4, 9]);
  });

  it("follows the segmenter for punctuation and CJK", () => {
    expect(snapToWords("Firecracker's jailer", 2, 16)).toEqual([0, 20]);
    expect(snapToWords("我们选择了这个方案。", 1, 4)).toEqual([0, 4]);
  });

  it("does nothing to a collapsed range", () => {
    expect(snapToWords("the quick brown fox", 6, 6)).toEqual([6, 6]);
  });

  it("snaps a live selection inside a text layer", () => {
    const layer = layerWith("the quick brown fox");
    attachTextLayer(layer);
    const text = layer.querySelector("span")!.firstChild!;
    select(text, 5, 12);
    expect(snapSelectionToWords()).toBe(true);
    expect(window.getSelection()!.toString()).toBe("quick brown");
  });

  it("does not join a word to the last word of the line above", () => {
    const layer = layerWith("chose", "the");
    attachTextLayer(layer);
    const second = layer.querySelectorAll("span")[1]!.firstChild!;
    select(second, 1, 2);
    expect(snapSelectionToWords()).toBe(true);
    expect(window.getSelection()!.toString()).toBe("the");
  });

  it("snaps a boundary that falls between an element's text nodes", () => {
    const layer = layerWith("quick");
    const span = layer.querySelector("span")!;
    span.replaceChildren(document.createTextNode("qui"), document.createTextNode("ck"));
    attachTextLayer(layer);
    const range = document.createRange();
    range.setStart(span.firstChild!, 1);
    range.setEnd(span, 1);
    const selection = window.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);
    expect(snapSelectionToWords()).toBe(true);
    expect(selection.toString()).toBe("quick");
  });

  it("leaves selections outside a text layer untouched", () => {
    const paragraph = document.createElement("p");
    paragraph.textContent = "halfword rest";
    document.body.append(paragraph);
    select(paragraph.firstChild!, 4, 11);
    expect(snapSelectionToWords()).toBe(false);
    expect(window.getSelection()!.toString()).toBe("word re");
  });

  it("snaps when the pointer is released", () => {
    const layer = layerWith("the quick brown fox");
    attachTextLayer(layer);
    select(layer.querySelector("span")!.firstChild!, 5, 12);
    document.dispatchEvent(new Event("pointerup"));
    expect(window.getSelection()!.toString()).toBe("quick brown");
  });
});

describe("text layer selection state", () => {
  let layer: HTMLElement;

  beforeEach(() => {
    layer = layerWith("hello ", "world");
    attachTextLayer(layer);
  });

  afterEach(() => {
    detachTextLayer(layer);
    layer.remove();
    window.getSelection()?.removeAllRanges();
  });

  it("keeps the marker at the end of the layer until a selection starts", () => {
    const end = layer.querySelector(".endOfContent")!;
    expect(end).toBe(layer.lastElementChild);
  });

  it("marks the layer while the pointer is down", () => {
    layer.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
    expect(layer.classList.contains("selecting")).toBe(true);
    document.dispatchEvent(new Event("pointerup"));
    expect(layer.classList.contains("selecting")).toBe(false);
  });

  it("moves the marker beside the text being selected and puts it back after", () => {
    document.dispatchEvent(new Event("pointerdown"));
    const first = layer.querySelector("span")!.firstChild!;
    select(first, 1, 5);
    document.dispatchEvent(new Event("selectionchange"));
    const end = layer.querySelector(".endOfContent")!;
    expect(layer.classList.contains("selecting")).toBe(true);
    expect(end).not.toBe(layer.lastElementChild);
    document.dispatchEvent(new Event("pointerup"));
    expect(layer.classList.contains("selecting")).toBe(false);
    expect(end).toBe(layer.lastElementChild);
  });

  it("ignores a selection change after the gesture ended", () => {
    document.dispatchEvent(new Event("pointerdown"));
    document.dispatchEvent(new Event("pointerup"));
    select(layer.querySelector("span")!.firstChild!, 1, 5);
    document.dispatchEvent(new Event("selectionchange"));
    expect(layer.classList.contains("selecting")).toBe(false);
  });

  it("removes the marker when the layer goes away", () => {
    detachTextLayer(layer);
    expect(layer.querySelector(".endOfContent")).toBeNull();
    expect(layer.classList.contains("selecting")).toBe(false);
  });
});

describe("a selection across pages", () => {
  let first: HTMLElement;
  let second: HTMLElement;

  beforeEach(() => {
    first = layerWith("the quick");
    second = layerWith("brown fox");
    attachTextLayer(first);
    attachTextLayer(second);
  });

  afterEach(() => {
    detachTextLayer(first);
    detachTextLayer(second);
    first.remove();
    second.remove();
    window.getSelection()?.removeAllRanges();
  });

  it("marks every layer the range touches and snaps both ends", () => {
    const range = document.createRange();
    range.setStart(first.querySelector("span")!.firstChild!, 5);
    range.setEnd(second.querySelector("span")!.firstChild!, 3);
    const selection = window.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);

    document.dispatchEvent(new Event("pointerdown"));
    document.dispatchEvent(new Event("selectionchange"));
    expect(first.classList.contains("selecting")).toBe(true);
    expect(second.classList.contains("selecting")).toBe(true);

    expect(snapSelectionToWords()).toBe(true);
    expect(window.getSelection()!.toString()).toBe("quickbrown");

    document.dispatchEvent(new Event("pointerup"));
    expect(first.classList.contains("selecting")).toBe(false);
    expect(second.classList.contains("selecting")).toBe(false);
  });
});
