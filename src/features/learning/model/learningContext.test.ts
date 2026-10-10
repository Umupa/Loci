import { describe, expect, it } from "vitest";
import { mergeLearningContext, sanitizeLearningContext, withLearningContext } from "./learningContext";
import type { LearningMessageContext } from "./types";

const context: LearningMessageContext = {
  sources: [{ id: "source-1", kind: "pdf", title: "Paper", quote: "This is the passage", documentId: "document", path: "/docs/paper.pdf", annotationId: "highlight", anchors: [{ page: 7, rects: [{ x: .1, y: .2, width: .5, height: .03 }] }] }],
  widgetContext: { owner: { kind: "session", id: "session" }, id: "trace", title: "Trace", revision: 2, state: { step: 3 }, selection: "the blocked operation" },
};
describe("learning message context", () => {
  it("roundtrips source anchors and current widget conditions through transcript validation", () => {
    expect(sanitizeLearningContext(JSON.parse(JSON.stringify(context)))).toEqual(context);
  });
  it("keeps supplied excerpts and conditions separate from the user's question", () => {
    const prompt = withLearningContext("Why does it block?", context);
    expect(prompt).toMatch(/^Why does it block\?/);
    expect(prompt).toContain('"page": 7');
    expect(prompt).toContain('"step": 3');
    expect(prompt).toContain("Distinguish source claims, your inference, and observed experiment results");
    expect(prompt).toContain("loci-widget\n---\nid:");
    expect(prompt).toContain("does not send automatically");
  });
  it("replaces a duplicate source and preserves the current widget during another quote", () => {
    const replacement = { ...context.sources![0], quote: "new selected passage" };
    expect(mergeLearningContext(context, { sources: [replacement] })).toEqual({ ...context, sources: [replacement] });
  });
  it("drops malformed file anchors, unsafe web addresses and non-JSON widget state", () => {
    expect(sanitizeLearningContext({ sources: [{ id: "bad", kind: "web", title: "Bad", quote: "quoted", url: "javascript:alert(1)" }], widgetContext: { ...context.widgetContext, state: { value: Infinity } } })).toEqual({});
  });
});
