// @vitest-environment happy-dom
import { act, createElement, useRef, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { useFileSelection, type FileSelection } from "./useFileSelection";

let container: HTMLDivElement;
let root: Root;
let seen: FileSelection | null = null;
let show: (value: boolean) => void = () => {};

/** A viewer whose text mounts later, as a file's does once it has loaded. */
function Viewer() {
  const ref = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);
  show = setLoaded;
  seen = useFileSelection(ref, true).selection;
  return loaded ? createElement("div", { ref, id: "text" }, "some text to select") : createElement("p", null, "Opening…");
}

beforeEach(() => {
  vi.spyOn(Range.prototype, "getClientRects").mockReturnValue([new DOMRect(0, 0, 40, 16)] as unknown as DOMRectList);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.restoreAllMocks(); });

it("reports a selection in text that mounted after the viewer did", async () => {
  await act(async () => root.render(createElement(Viewer)));
  await act(async () => show(true));
  const text = document.getElementById("text")!;
  await act(async () => {
    text.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
    const range = document.createRange();
    range.setStart(text.firstChild!, 0);
    range.setEnd(text.firstChild!, 4);
    window.getSelection()!.removeAllRanges();
    window.getSelection()!.addRange(range);
    text.dispatchEvent(new PointerEvent("pointerup", { bubbles: true }));
    await new Promise((resolve) => requestAnimationFrame(() => resolve(null)));
  });
  expect(seen?.text).toBe("some");
});
