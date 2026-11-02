import { describe, expect, it } from "vitest";
import { parseAppResourceUrl } from "../../../shared/lib/appResourceLinks";
import { quoteLink, quoteMarkdown } from "./quoteNote";
import type { LearningSource } from "./types";

const anchor = (exact: string) => ({ exact, prefix: "", suffix: "", start: 0, end: exact.length });
const pdf: LearningSource = { id: "s-pdf", kind: "pdf", title: "Firecracker", quote: "A microVM\nboots fast", documentId: "doc", path: "/fc.pdf", anchors: [{ page: 7, rects: [] }] };
const code: LearningSource = { id: "s-code", kind: "file", title: "main.rs", quote: "fn run()", path: "/src/main.rs", lines: [12, 14] };
const markdownFile: LearningSource = { id: "s-md", kind: "file", title: "guide.md", quote: "Read slowly", path: "/guide.md", anchor: anchor("Read slowly") };
const lesson: LearningSource = { id: "s-doc", kind: "document", title: "Pods", quote: "The phase of a Pod", agentId: "kern", documentId: "pods", section: "Pod phase" };

describe("a passage saved to a note", () => {
  it("links back to the page, lines or section it came from, with its words to flash there", () => {
    expect(quoteLink(pdf)).toBe("loci://source/s-pdf#p7&quote=A%20microVM%20boots%20fast");
    expect(quoteLink(code)).toBe("loci://source/s-code#L12-14&quote=fn%20run()");
    expect(quoteLink(markdownFile)).toBe("loci://source/s-md#quote=Read%20slowly");
    expect(quoteLink(lesson)).toBe("loci://source/s-doc#section=Pod%20phase&quote=The%20phase%20of%20a%20Pod");
    expect(quoteLink({ id: "w", kind: "web", title: "Blog", quote: "x", url: "https://example.org/post" })).toBe("https://example.org/post");
    for (const source of [pdf, code, markdownFile, lesson]) expect(parseAppResourceUrl(quoteLink(source))).toBeDefined();
  });

  it("names a long passage by its opening words, so the link stays valid in any script", () => {
    const long = { ...lesson, quote: "沙箱".repeat(400) };
    const link = quoteLink(long);
    expect(parseAppResourceUrl(link)).toMatchObject({ place: { section: "Pod phase", quote: "沙箱".repeat(60) } });
  });

  it("falls back to the bare link when its place cannot be carried", () => {
    expect(quoteLink({ ...lesson, section: "H".repeat(400) })).toBe("loci://source/s-doc");
  });

  it("is a Markdown quote, a linked citation, then the reader's note", () => {
    expect(quoteMarkdown("A microVM\n\nboots fast  ", pdf, "  Compare with gVisor. ")).toBe(
      "> A microVM\n>\n> boots fast\n>\n> — [Firecracker · p. 7](loci://source/s-pdf#p7&quote=A%20microVM%20boots%20fast)\n\nCompare with gVisor.");
    expect(quoteMarkdown("fn run()", { ...code, title: "[draft] main.rs" })).toBe("> fn run()\n>\n> — [\\[draft\\] main.rs · L12–14](loci://source/s-code#L12-14&quote=fn%20run())");
    expect(quoteMarkdown("Just words")).toBe("> Just words");
  });

  it("keeps a whole block as its Markdown, linked by the words a reader sees at its start", () => {
    const table = "| Phase | Meaning |\n| --- | --- |\n| Pending | accepted |";
    const block: LearningSource = { ...lesson, quote: table,
      anchor: { exact: table, prefix: "", suffix: "", start: 40, end: 40, headings: ["Pod phase"], block: { kind: "table", index: 0, lead: "PhaseMeaning" } } };
    expect(quoteLink(block)).toBe("loci://source/s-doc#section=Pod%20phase&quote=PhaseMeaning");
    expect(quoteMarkdown(table, block)).toBe(
      "> | Phase | Meaning |\n> | --- | --- |\n> | Pending | accepted |\n>\n> — [Pods · Pod phase](loci://source/s-doc#section=Pod%20phase&quote=PhaseMeaning)");
    // A diagram or a picture shows no words: the link names only its section.
    const diagram: LearningSource = { ...block, quote: "```mermaid\ngraph TD; A-->B\n```",
      anchor: { ...block.anchor!, exact: "```mermaid\ngraph TD; A-->B\n```", block: { kind: "mermaid", index: 0 } } } as LearningSource;
    expect(quoteLink(diagram)).toBe("loci://source/s-doc#section=Pod%20phase");
    expect(quoteMarkdown(diagram.quote, diagram).split("\n").slice(0, 3)).toEqual(["> ```mermaid", "> graph TD; A-->B", "> ```"]);
  });
});
