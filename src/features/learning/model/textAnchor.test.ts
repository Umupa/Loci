// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import { describeRange, findInText, linesOf, quoteInText, resolveAnchor, textIndex } from "./textAnchor";

function render(html: string): HTMLElement {
  const root = document.createElement("div");
  root.innerHTML = html;
  document.body.replaceChildren(root);
  return root;
}
function select(root: HTMLElement, text: string, occurrence = 0): Range {
  const index = textIndex(root);
  let at = -1;
  for (let i = 0; i <= occurrence; i++) at = index.text.indexOf(text, at + 1);
  const range = document.createRange();
  const startPiece = [...index.pieces].reverse().find((piece) => piece.start <= at)!;
  const end = at + text.length;
  const endPiece = [...index.pieces].reverse().find((piece) => piece.start < end)!;
  range.setStart(startPiece.node, at - startPiece.start);
  range.setEnd(endPiece.node, end - endPiece.start);
  return range;
}

const DOC = `<h1>Pod lifecycle</h1><p>Intro text.</p><h2>Pod phase</h2><p>A Pod's <code>status</code> field has a phase.</p>
  <h3>Pending</h3><p>The Pod has been accepted. The Pod has been accepted again.</p><h2>Container states</h2><p>Waiting.</p>`;

describe("text anchors", () => {
  it("describe a selection with its context and the headings above it", () => {
    const root = render(DOC);
    const anchor = describeRange(root, select(root, "status field"))!;
    expect(anchor.exact).toBe("status field");
    expect(anchor.prefix.endsWith("A Pod's ")).toBe(true);
    expect(anchor.suffix.startsWith(" has a phase")).toBe(true);
    expect(anchor.headings).toEqual(["Pod lifecycle", "Pod phase"]);
    const deeper = describeRange(root, select(root, "accepted again"))!;
    expect(deeper.headings).toEqual(["Pod lifecycle", "Pod phase", "Pending"]);
  });

  it("find the same repeat again after the text before it changed", () => {
    const root = render(DOC);
    const anchor = describeRange(root, select(root, "The Pod has been accepted", 1))!;
    const revised = render(DOC.replace("Intro text.", "A much longer introduction than there was before, which moves every offset."));
    const range = resolveAnchor(revised, anchor)!;
    expect(range.toString()).toBe("The Pod has been accepted");
    // The second repeat: what follows it is " again.", not ". The Pod".
    expect(range.startContainer.textContent!.slice(range.endOffset)).toBe(" again.");
  });

  it("tolerate changed white space and case, and give up when the words are gone", () => {
    const anchor = quoteInText("one two three four", "two three")!;
    expect(findInText("one   Two\n three four", anchor)).toEqual([6, 16]);
    expect(findInText("entirely different", anchor)).toBeNull();
  });

  it("skip rendered chrome such as copy buttons and duplicate MathML", () => {
    const root = render(`<p>Energy <span class="katex"><span class="katex-mathml">E=mc^2</span><span class="katex-html">E=mc²</span></span> holds.</p><button>Copy</button>`);
    expect(textIndex(root).text).toBe("Energy E=mc² holds.");
  });

  it("count lines of a passage in a file", () => {
    const text = "a\nbb\nccc\n";
    expect(linesOf(text, 2, 7)).toEqual([2, 3]);
  });
});
