// @vitest-environment happy-dom
import { describe, expect, it } from "vitest";
import { BLOCK_SOURCE_MAX, blockAnchor, blockAt, fencedSource, imageSource, readingBlocks, resolveBlock } from "./blockAnchor";

const TABLE = "| Phase | Meaning |\n| --- | --- |\n| Pending | accepted |";
const DIAGRAM = "```mermaid\ngraph TD; A --> B\n```";

function block(kind: string, source: string, inner: string): string {
  const element = document.createElement(kind === "table" ? "table" : "div");
  element.dataset.blockKind = kind;
  element.dataset.blockSource = source;
  element.innerHTML = inner;
  return element.outerHTML;
}

function render(html: string): HTMLElement {
  const root = document.createElement("div");
  root.innerHTML = html;
  document.body.replaceChildren(root);
  return root;
}

const DOC = () => [
  "<h1>Pods</h1><p>Intro.</p><h2>Pod phase</h2>",
  block("table", TABLE, "<thead><tr><th>Phase</th><th>Meaning</th></tr></thead><tbody><tr><td>Pending</td><td>accepted</td></tr></tbody>"),
  block("mermaid", DIAGRAM, "<svg><text>A</text></svg>"),
  "<p>Between.</p>",
  block("code", "```ts\nconst a = 1;\n```", "<pre><code>const a = 1;</code></pre>"),
].join("");

describe("block anchors", () => {
  it("list a reader's blocks in order, numbered within their kind", () => {
    const root = render(DOC() + block("table", "| x |\n| - |", "<tr><td>x</td></tr>"));
    expect(readingBlocks(root).map((entry) => [entry.kind, entry.index])).toEqual([["table", 0], ["mermaid", 0], ["code", 0], ["table", 1]]);
    expect(blockAt(root, root.querySelector("td"))?.source).toBe(TABLE);
    expect(blockAt(root, root.querySelector("p"))).toBeNull();
  });

  it("remember a block by its source, its place among its kind, the headings above it and its opening words", () => {
    const root = render(DOC());
    const [table, diagram] = readingBlocks(root);
    const anchor = blockAnchor(root, table);
    expect(anchor).toMatchObject({ exact: TABLE, headings: ["Pods", "Pod phase"], block: { kind: "table", index: 0, lead: "PhaseMeaningPendingaccepted" } });
    expect(anchor.start).toBe("PodsIntro.Pod phase".length);
    // A diagram has no words a reader sees; it sorts where the text after it starts.
    const drawn = blockAnchor(root, diagram);
    expect(drawn.block).toEqual({ kind: "mermaid", index: 0 });
    expect(drawn.start).toBe("PodsIntro.Pod phasePhaseMeaningPendingaccepted".length);
  });

  it("find the block again after other blocks and text moved, nearest its old place among repeats", () => {
    const root = render(DOC());
    const anchor = blockAnchor(root, readingBlocks(root)[1]);
    const moved = render(block("mermaid", "```mermaid\ngraph LR; X\n```", "<svg></svg>") + "<p>New intro.</p>" + DOC());
    const found = resolveBlock(readingBlocks(moved), anchor);
    expect(found?.source).toBe(DIAGRAM);
    expect(found?.index).toBe(1);

    const twice = render(DOC() + block("mermaid", DIAGRAM, "<svg></svg>") + block("mermaid", DIAGRAM, "<svg></svg>"));
    expect(resolveBlock(readingBlocks(twice), { ...anchor, block: { kind: "mermaid", index: 2 } })?.index).toBe(2);
  });

  it("ignore changed white space, and become an orphan when the block itself was rewritten", () => {
    const root = render(DOC());
    const anchor = blockAnchor(root, readingBlocks(root)[0]);
    const spaced = render(block("table", TABLE.replace(/ \| /g, "  |  "), "<tr><td>Phase</td></tr>"));
    expect(resolveBlock(readingBlocks(spaced), anchor)).not.toBeNull();
    const rewritten = render(block("table", TABLE.replace("accepted", "scheduled"), "<tr><td>Phase</td></tr>"));
    expect(resolveBlock(readingBlocks(rewritten), anchor)).toBeNull();
    // Only a block of the same kind will do.
    const code = render(block("code", TABLE, "<pre>x</pre>"));
    expect(resolveBlock(readingBlocks(code), anchor)).toBeNull();
  });

  it("keep the start of a very long block and find it by that", () => {
    const long = `\`\`\`text\n${"line\n".repeat(BLOCK_SOURCE_MAX / 4)}\`\`\``;
    const root = render(block("code", long, "<pre>line</pre>"));
    const anchor = blockAnchor(root, readingBlocks(root)[0]);
    expect(anchor.exact.length).toBe(BLOCK_SOURCE_MAX);
    expect(resolveBlock(readingBlocks(root), anchor)?.source).toBe(long);
  });
});

describe("block sources", () => {
  it("fence code with its language and meta, longer than any fence inside it", () => {
    expect(fencedSource("ts", "title=a.ts", "const a = 1;\n")).toBe("```ts title=a.ts\nconst a = 1;\n```");
    expect(fencedSource("", "", "plain")).toBe("```\nplain\n```");
    expect(fencedSource("md", "", "```js\nx\n```")).toBe("````md\n```js\nx\n```\n````");
  });

  it("write a picture with its alt text and an address that stays one link", () => {
    expect(imageSource("Pod phases", "https://example.com/p.svg")).toBe("![Pod phases](https://example.com/p.svg)");
    expect(imageSource("a [b]\nc", "figures/my plot (1).png")).toBe("![a \\[b\\] c](<figures/my plot (1).png>)");
  });
});
