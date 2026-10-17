import type { Root, RootContent } from "mdast";

const normalize = (text: string) => text.replace(/\s+/g, " ").trim().toLowerCase();

/** Prefer the complete title; retain the reader's partial-title fallback. */
export function sectionHeadingIndex(titles: string[], section: string): number {
  const wanted = normalize(section.replace(/^#+\s*/, ""));
  if (!wanted) return -1;
  const names = titles.map(normalize);
  const exact = names.indexOf(wanted);
  return exact >= 0 ? exact : names.findIndex((name) => name.includes(wanted));
}

function headingText(node: RootContent): string {
  if ("children" in node) return node.children.map(headingText).join("");
  if (node.type === "image" || node.type === "imageReference") return node.alt ?? "";
  if (node.type === "html") return "";
  return "value" in node ? node.value : "";
}

/** Slice parsed Markdown so fences, Setext headings and references keep their semantics. */
export function remarkDocumentSection({ section }: { section?: string }) {
  return (tree: Root) => {
    if (!section?.trim()) return;
    const headings = tree.children.filter((node) => node.type === "heading");
    const heading = headings[sectionHeadingIndex(headings.map(headingText), section)];
    if (!heading) return;
    const start = tree.children.indexOf(heading);
    const next = tree.children.findIndex((node, index) => index > start && node.type === "heading" && node.depth <= heading.depth);
    const end = next < 0 ? tree.children.length : next;
    // Definitions can live anywhere in the document. Keeping them does not
    // render unrelated prose, and preserves links, images and used footnotes.
    tree.children = tree.children.filter((node, index) =>
      (index >= start && index < end) || node.type === "definition" || node.type === "footnoteDefinition");
  };
}
