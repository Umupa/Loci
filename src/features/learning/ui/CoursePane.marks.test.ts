// @vitest-environment happy-dom
import { expect, it } from "vitest";
import { excerptLines } from "./CoursePane";

it("counts a selection in a lesson's code excerpt in the file's own lines", () => {
  const root = document.createElement("div");
  root.innerHTML = "<pre><code><span>let a = 1;\n</span><span>let b = 2;\n</span><span>let c = 3;</span></code></pre><p>Prose</p>";
  document.body.replaceChildren(root);
  const [, second, third] = root.querySelectorAll("span");
  const range = document.createRange();
  range.setStart(second.firstChild!, 4);
  range.setEnd(third.firstChild!, 5);
  expect(excerptLines(range, 40)).toEqual([41, 42]);
  const prose = document.createRange();
  prose.selectNodeContents(root.querySelector("p")!);
  expect(excerptLines(prose, 40)).toBeUndefined();
});
