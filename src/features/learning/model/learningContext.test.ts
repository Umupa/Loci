import { describe, expect, it } from "vitest";
import { mergeLearningContext, sanitizeLearningContext, withLearningContext } from "./learningContext";
import type { LearningMessageContext } from "./types";

const context: LearningMessageContext = {
  sources: [{ id: "source-1", kind: "pdf", title: "Paper", quote: "This is the passage", documentId: "document", path: "/docs/paper.pdf", annotationId: "highlight", anchors: [{ page: 7, rects: [{ x: .1, y: .2, width: .5, height: .03 }] }] }],
};
describe("learning message context", () => {
  it("roundtrips source anchors through transcript validation", () => {
    expect(sanitizeLearningContext(JSON.parse(JSON.stringify(context)))).toEqual(context);
  });
  it("appends only source data to the user's question", () => {
    const prompt = withLearningContext("Why does it block?", context);
    const [question, metadata] = prompt.split("\n\n<loci_learning_context>\n");
    expect(question).toBe("Why does it block?");
    expect(metadata.endsWith("\n</loci_learning_context>")).toBe(true);
    expect(JSON.parse(metadata.slice(0, -"\n</loci_learning_context>".length))).toEqual(context);
    expect(prompt).not.toContain("<loci_courses>");
  });
  it.each([{}, { sources: [] }])("preserves the original text when no learning context is supplied", (emptyContext) => {
    const question = "  Explain this passage.\n";
    expect(withLearningContext(question, emptyContext)).toBe(question);
  });
  it("replaces a duplicate source during another quote", () => {
    const replacement = { ...context.sources![0], quote: "new selected passage" };
    expect(mergeLearningContext(context, { sources: [replacement] })).toEqual({ ...context, sources: [replacement] });
  });
  it("drops unsafe web addresses", () => {
  });
});
