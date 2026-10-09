// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { consumeFilePlace, findHeading, headingAbove, lineOffset, lineRange, requestFilePlace, textareaOffsetTop, useFilePlace } from "./filePlace";
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

describe("the section a line of a Markdown file falls in", () => {
  const reading = [
    "---",                                  // 1
    "title: Pod 的生命周期",                 // 2
    "# not a heading: a comment in YAML",   // 3
    "---",                                  // 4
    "",                                     // 5
    "# Pod 的生命周期",                      // 6
    "正文。",                                // 7
    "## 容器探针",                           // 8
    "```sh",                                // 9
    "# 这是 shell 注释，不是标题",           // 10
    "kubectl get pods",                     // 11
    "```",                                  // 12
    "## 示例",                               // 13
    "第一个示例。",                          // 14
    "## `kubectl` 与 [探针](https://example.com/probe) ##", // 15
    "## 示例",                               // 16
    "第二个示例。",                          // 17
  ].join("\n");

  it("is the last heading at or above the line, and nothing above the first one", () => {
    expect(headingAbove(reading, 3)).toBeNull();
    expect(headingAbove(reading, 5)).toBeNull();
    expect(headingAbove(reading, 6)).toEqual({ text: "pod的生命周期", index: 0 });
    expect(headingAbove(reading, 7)).toEqual({ text: "pod的生命周期", index: 0 });
    // A comment inside a code block is not a heading.
    expect(headingAbove(reading, 11)).toEqual({ text: "容器探针", index: 0 });
    expect(headingAbove(reading, 14)).toEqual({ text: "示例", index: 0 });
    // Marks the preview does not show, and a link's address, take no part in the match.
    expect(headingAbove(reading, 15)).toEqual({ text: "kubectl与探针", index: 0 });
    // The second heading with the same words is told from the first.
    expect(headingAbove(reading, 17)).toEqual({ text: "示例", index: 1 });
    expect(headingAbove(reading, 999)).toEqual({ text: "示例", index: 1 });
    expect(headingAbove("no headings\nat all", 2)).toBeNull();
  });

  it("finds that heading in the rendered document", () => {
    const root = document.createElement("div");
    root.innerHTML = "<h1>Pod 的生命周期</h1><h2>容器探针</h2><h2 id='a'>示例</h2><h2><code>kubectl</code> 与 <a href='#'>探针</a></h2><h2 id='b'>示例</h2>";
    expect(findHeading(root, headingAbove(reading, 14)!)?.id).toBe("a");
    expect(findHeading(root, headingAbove(reading, 17)!)?.id).toBe("b");
    expect(findHeading(root, headingAbove(reading, 15)!)?.textContent).toBe("kubectl 与 探针");
    expect(findHeading(root, { text: "不存在", index: 0 })).toBeNull();
  });
});
