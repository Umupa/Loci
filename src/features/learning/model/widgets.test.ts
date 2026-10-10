import { describe, expect, it } from "vitest";
import { cardsOnly } from "../../sessions/model/cards";
import { parseWidget, widgetsInText } from "./widgets";

const source = (id: string, html = '<input type="range"><svg></svg><script>window.loci.setState({step:1})</script>') => `---\nid: ${id}\ntitle: A generated explanation\nsubject: Caching\nsources: ["source-a", "source-b"]\n---\n${html}`;

describe("generated explanation blocks", () => {
  it("keeps a complete HTML file and source identities without interpreting its scripts", () => {
    const result = parseWidget(source("cache"));
    expect(result.spec).toMatchObject({ id: "cache", subject: "Caching", sourceIds: ["source-a", "source-b"] });
    expect(result.spec?.html).toContain('window.loci.setState({step:1})');
  });

  it("accepts quoted metadata and comma-separated sources", () => {
    expect(parseWidget('---\nid: "cache"\ntitle: \'Cache example\'\nsources: source-a, source-a\n---\n<div>Cache</div>').spec).toMatchObject({ title: "Cache example", sourceIds: ["source-a"] });
  });

  it.each([
    "<script>alert(1)</script>",
    "---\ntitle: Missing identity\n---\n<div>x</div>",
    "---\nid: ../other\ntitle: Invalid id\n---\n<div>x</div>",
    "---\nid: example\ntitle: Missing HTML\n---\n",
    "---\nid: example\ntitle: Example\nsources: [42]\n---\n<div>x</div>",
  ])("keeps malformed blocks out of the executable widget collection", (text) => {
    expect(parseWidget(text).error).toBeTruthy();
    expect(widgetsInText(`\`\`\`loci-widget\n${text}\n\`\`\``)).toEqual([]);
  });

  it("keeps the latest same-id source and only complete fences", () => {
    const text = `\`\`\`\`loci-widget\n${source("cache", "<div>First</div>")}\n\`\`\`\`\n\`\`\`\`loci-widget\n${source("cache", "<div>Revised</div>")}\n\`\`\`\`\n\`\`\`loci-widget\n${source("half")}`;
    expect(widgetsInText(text)).toHaveLength(1);
    expect(widgetsInText(text)[0].html).toBe("<div>Revised</div>");
    expect(widgetsInText(cardsOnly(text))).toEqual(widgetsInText(text));
  });
});
