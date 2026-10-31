// @vitest-environment happy-dom
import { act, createElement, useRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { anchorInText } from "../model/textAnchor";
import type { Annotation } from "../model/types";
import { useTextHighlights } from "./useTextHighlights";

const TEXT = "Pods move through phases. Pending comes first.";
function mark(id: string, quote: string): Annotation {
  const start = TEXT.indexOf(quote);
  const anchor = anchorInText(TEXT, Math.max(start, 0), Math.max(start, 0) + quote.length)!;
  if (start < 0) anchor.exact = quote;
  return { id, documentId: "", target: { kind: "file", path: "/a.md" }, anchor, anchors: [], note: "", discussions: [], createdAt: 1, updatedAt: 1,
    source: { id: `s-${id}`, kind: "file", path: "/a.md", title: "a.md", quote } };
}

let host: HTMLDivElement; let root: Root;
const seen: { orphans?: ReadonlySet<string> } = {};
const painted = new Map<string, unknown[]>();
beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  class Highlight { ranges: Range[]; constructor(...ranges: Range[]) { this.ranges = ranges; } }
  vi.stubGlobal("Highlight", Highlight);
  vi.stubGlobal("CSS", { highlights: { set: (name: string, value: Highlight) => painted.set(name, value.ranges), delete: (name: string) => painted.delete(name) } });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); painted.clear(); });

function Reader({ annotations, onOpen, selectedId }: { annotations: Annotation[]; onOpen?: (annotation: Annotation) => void; selectedId?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  seen.orphans = useTextHighlights(ref, annotations, { onOpen, selectedId }).orphans;
  return createElement("div", { ref }, createElement("p", null, TEXT));
}

it("paints the marks it finds, the selected one apart, and reports the ones whose words are gone", async () => {
  const marks = [mark("a", "phases"), mark("b", "Pending"), mark("gone", "no longer here")];
  await act(async () => root.render(createElement(Reader, { annotations: marks, selectedId: "b" })));
  expect((painted.get("loci-mark") as Range[]).map(String)).toEqual(["phases"]);
  expect((painted.get("loci-mark-selected") as Range[]).map(String)).toEqual(["Pending"]);
  expect([...seen.orphans!]).toEqual(["gone"]);
});

it("opens the mark under a click", async () => {
  const onOpen = vi.fn();
  await act(async () => root.render(createElement(Reader, { annotations: [mark("a", "phases")], onOpen })));
  const text = host.querySelector("p")!.firstChild!;
  (document as unknown as { caretRangeFromPoint: () => Range }).caretRangeFromPoint = () => {
    const range = document.createRange(); range.setStart(text, TEXT.indexOf("phases") + 2); return range;
  };
  await act(async () => host.querySelector("div")!.dispatchEvent(new MouseEvent("click", { bubbles: true, clientX: 5, clientY: 5 })));
  expect(onOpen).toHaveBeenCalledOnce();
  expect(onOpen.mock.calls[0][0].id).toBe("a");
});
