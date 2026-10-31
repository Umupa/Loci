import type { Annotation } from "./types";

/** Where a mark is, as a reader would say it: a page, a section, some lines. */
export function annotationPlace(annotation: Annotation, orphan = false): string {
  if (orphan) return "This passage changed";
  if (annotation.anchors.length) return `Page ${annotation.anchors.map((anchor) => anchor.page).join(", ")}`;
  const lines = annotation.anchor?.lines;
  if (lines) return lines[0] === lines[1] ? `Line ${lines[0]}` : `Lines ${lines[0]}–${lines[1]}`;
  const headings = annotation.anchor?.headings;
  return headings?.length ? headings[headings.length - 1] : "Passage";
}
