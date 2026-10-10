import { describe, expect, it, vi } from "vitest";
import { consumeLearningDraft, getLearningDraftContext, peekLearningDraft, queueLearningDraft, setLearningDraftContext } from "./learningDraft";
import type { LearningMessageContext } from "./types";

const context: LearningMessageContext = { sources: [{ id: "source-1", kind: "web", title: "Reference", quote: "The relevant paragraph", url: "https://example.org/docs" }] };
describe("targeted learning drafts", () => {
  it("waits for the original conversation and retains multiple requests in order", () => {
    queueLearningDraft("original", { text: "Explain this", mode: "plain", targetSessionId: "original", ...context });
    queueLearningDraft("original", { text: "Show the next step", mode: "plain", targetSessionId: "original" });
    expect(peekLearningDraft("other-visible-session")).toBeUndefined();
    const first = peekLearningDraft("original")!;
    expect(first).toMatchObject({ text: "Explain this", ...context });
    consumeLearningDraft("original", first.id + 1);
    expect(peekLearningDraft("original")).toBe(first);
    consumeLearningDraft("original", first.id);
    const second = peekLearningDraft("original")!;
    expect(second.text).toBe("Show the next step");
    consumeLearningDraft("original", second.id);
    expect(peekLearningDraft("original")).toBeUndefined();
  });
  it("keeps composer context scoped to a conversation and clears it after acceptance", () => {
    setLearningDraftContext("draft", context);
    expect(getLearningDraftContext("draft")).toEqual(context);
    expect(getLearningDraftContext("another")).toEqual({});
    setLearningDraftContext("draft", {});
    expect(getLearningDraftContext("draft")).toEqual({});
  });
  it("matches typed composer text across pane remounts and a full module reload", async () => {
    const drafts = await import("../../sessions/model/draftCache");
    const learning = await import("./learningDraft");
    drafts.setComposerDraft("lifecycle", "Why does this call block?");
    learning.setLearningDraftContext("lifecycle", context);
    // A remounted pane reads both from their module caches.
    expect(drafts.getComposerDraft("lifecycle")).toBe("Why does this call block?");
    expect(learning.getLearningDraftContext("lifecycle")).toEqual(context);
    vi.resetModules();
    const reloadedDrafts = await import("../../sessions/model/draftCache");
    const reloadedLearning = await import("./learningDraft");
    // Neither unsent composer cache promises restart persistence; /draft uses the session store.
    expect(reloadedDrafts.getComposerDraft("lifecycle")).toBeUndefined();
    expect(reloadedLearning.getLearningDraftContext("lifecycle")).toEqual({});
    drafts.clearComposerDraft("lifecycle");
    learning.setLearningDraftContext("lifecycle", {});
  });
});
