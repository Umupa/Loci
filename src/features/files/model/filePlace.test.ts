// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { consumeFilePlace, lineOffset, lineRange, requestFilePlace, textareaOffsetTop, useFilePlace } from "./filePlace";
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";

const text = ["first", "second line", "third", "", "fifth"].join("\n");

describe("lines of a text", () => {
  it("finds where a line starts, and clamps past the end", () => {
    expect([1, 2, 3, 4, 5].map((line) => lineOffset(text, line))).toEqual([0, 6, 18, 24, 25]);
    expect(lineOffset(text, 99)).toBe(25);
    expect(lineOffset("", 3)).toBe(0);
  });

  it("covers a range of lines without the last line break", () => {
    expect(lineRange(text, 2, 3)).toEqual([6, 23]);
    expect(text.slice(...lineRange(text, 2, 3))).toBe("second line\nthird");
    expect(text.slice(...lineRange(text, 1, 1))).toBe("first");
    // The last line has no break to cut, and an empty line is an empty range.
    expect(text.slice(...lineRange(text, 5, 9))).toBe("fifth");
    expect(lineRange(text, 4, 4)).toEqual([24, 24]);
    expect(text.slice(...lineRange(text, 4, 5))).toBe("\nfifth");
  });
});

describe("requests for a place in a file", () => {
  afterEach(() => vi.restoreAllMocks());

  async function watch(path: string) {
    const seen: Array<ReturnType<typeof useFilePlace>> = [];
    const host = document.createElement("div");
    const root = createRoot(host);
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    function Probe() { seen.push(useFilePlace(path)); return null; }
    await act(async () => root.render(createElement(Probe)));
    return { seen, stop: () => act(async () => root.unmount()) };
  }

  it("reaches the pane for that file, replaced by a newer request, and is gone once shown", async () => {
    const { seen, stop } = await watch("/p/a.md");
    expect(seen.at(-1)).toBeUndefined();
    await act(async () => requestFilePlace("/p/a.md", { lines: [3, 4] }));
    const first = seen.at(-1)!;
    expect(first.place).toEqual({ lines: [3, 4] });
    await act(async () => requestFilePlace("/p/other.md", { page: 2 }));
    expect(seen.at(-1)).toBe(first);
    await act(async () => requestFilePlace("/p/a.md", { lines: [3, 4] }));
    const second = seen.at(-1)!;
    // The same place asked for again is a new request, so the pane scrolls again.
    expect(second.token).toBeGreaterThan(first.token);
    // An old request cannot clear a newer one; the current one can.
    await act(async () => consumeFilePlace("/p/a.md", first.token));
    expect(seen.at(-1)).toBe(second);
    await act(async () => consumeFilePlace("/p/a.md", second.token));
    expect(seen.at(-1)).toBeUndefined();
    await act(async () => consumeFilePlace("/p/other.md", 1));
    await stop();
    consumeFilePlace("/p/other.md", seen.length);
  });
});

describe("the offset of a line in a textarea", () => {
  it("lays the text before it out in a copy with the same box and font", () => {
    const area = document.createElement("textarea");
    area.value = "one\ntwo\nthree";
    document.body.append(area);
    // happy-dom does no layout: the copy must exist while measuring and be gone after.
    const before = document.body.children.length;
    expect(typeof textareaOffsetTop(area, 8)).toBe("number");
    expect(document.body.children.length).toBe(before);
    area.remove();
  });
});
