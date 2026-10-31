import { expect, it } from "vitest";
import { headingsAtOffset, plainMarkdown } from "./markdownText";

it("reads Markdown as its words, with the headings each line is under", () => {
  const plain = plainMarkdown("---\ntitle: T\n---\n# Pods\n\n- **Pending**: accepted\n\n```\n# not a heading\n```\n## Phase\n> A `phase` [link](x)\n");
  // Code is shown, so its text stays; it is just never a heading.
  expect(plain.text).toBe("Pods\n\nPending: accepted\n\n# not a heading\nPhase\nA phase link\n");
  expect(headingsAtOffset(plain, plain.text.indexOf("accepted"))).toEqual(["Pods"]);
  expect(headingsAtOffset(plain, plain.text.indexOf("link"))).toEqual(["Pods", "Phase"]);
});
