import { describe, expect, it } from "vitest";
import { draftConflicts, editDraft, getFileDraft, moveFileDrafts, setFileDraft } from "./fileDrafts";

describe("file drafts", () => {
  it("keeps the first disk text as the base while editing, and drops the draft when edits are undone", () => {
    const first = editDraft(null, "# Title\n", "# Title!\n");
    expect(first).toEqual({ text: "# Title!\n", base: "# Title\n" });
    expect(editDraft(first, "# Title\n", "# Title!!\n")).toEqual({ text: "# Title!!\n", base: "# Title\n" });
    expect(editDraft(first, "# Title\n", "# Title\n")).toBeNull();
  });

  it("flags a conflict only when the disk text moved away from the draft's base", () => {
    const draft = { text: "mine", base: "old" };
    expect(draftConflicts(draft, "old")).toBe(false);
    expect(draftConflicts(draft, "agent rewrote it")).toBe(true);
    expect(draftConflicts(null, "anything")).toBe(false);
  });

  it("moves drafts with their files", () => {
    setFileDraft("/p/a.md", { text: "x", base: "" });
    setFileDraft("/other/b.md", { text: "y", base: "" });
    moveFileDrafts((path) => path.replace("/p/", "/q/"));
    expect(getFileDraft("/p/a.md")).toBeNull();
    expect(getFileDraft("/q/a.md")).toEqual({ text: "x", base: "" });
    expect(getFileDraft("/other/b.md")).toEqual({ text: "y", base: "" });
    setFileDraft("/q/a.md", null);
    setFileDraft("/other/b.md", null);
  });
});
