import { describe, expect, it } from "vitest";
import { mergeLearningContext, sanitizeLearningContext, withLearningContext } from "./learningContext";
import type { LearningMessageContext } from "./types";

const context: LearningMessageContext = {
  sources: [{ id: "source-1", kind: "pdf", title: "Paper", quote: "This is the passage", documentId: "document", path: "/docs/paper.pdf", annotationId: "highlight", anchors: [{ page: 7, rects: [{ x: .1, y: .2, width: .5, height: .03 }] }] }],
  widgetContext: { owner: { kind: "session", id: "session" }, id: "trace", title: "Trace", revision: 2, state: { step: 3 }, selection: "the blocked operation", html: "<section>Current trace</section>" },
};
describe("learning message context", () => {
  it("roundtrips source anchors and current widget conditions through transcript validation", () => {
    expect(sanitizeLearningContext(JSON.parse(JSON.stringify(context)))).toEqual(context);
  });
  it("appends only source and widget data to the user's question", () => {
    const prompt = withLearningContext("Why does it block?", context);
    const [question, metadata] = prompt.split("\n\n<loci_learning_context>\n");
    expect(question).toBe("Why does it block?");
    expect(metadata.endsWith("\n</loci_learning_context>")).toBe(true);
    expect(JSON.parse(metadata.slice(0, -"\n</loci_learning_context>".length))).toEqual(context);
    expect(prompt).not.toContain("<loci_widgets>");
    expect(prompt).not.toContain("<loci_courses>");
  });
  it.each([{}, { sources: [] }])("preserves the original text when no learning context is supplied", (emptyContext) => {
    const question = "  Explain this passage.\n";
    expect(withLearningContext(question, emptyContext)).toBe(question);
  });
  it("preserves a widget context when no source was selected", () => {
    const widgetOnly = { widgetContext: context.widgetContext };
    const prompt = withLearningContext("Show this step", widgetOnly);
    const metadata = prompt.slice(prompt.indexOf("<loci_learning_context>\n") + "<loci_learning_context>\n".length, -"\n</loci_learning_context>".length);
    expect(JSON.parse(metadata)).toEqual(widgetOnly);
  });
  it("replaces a duplicate source and preserves the current widget during another quote", () => {
    const replacement = { ...context.sources![0], quote: "new selected passage" };
    expect(mergeLearningContext(context, { sources: [replacement] })).toEqual({ ...context, sources: [replacement] });
  });
  it("drops malformed file anchors, unsafe web addresses and non-JSON widget state", () => {
    expect(sanitizeLearningContext({ sources: [{ id: "bad", kind: "web", title: "Bad", quote: "quoted", url: "javascript:alert(1)" }], widgetContext: { ...context.widgetContext, state: { value: Infinity } } })).toEqual({});
  });
});
