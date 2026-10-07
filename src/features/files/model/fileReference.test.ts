import { describe, expect, it } from "vitest";
import { fileReference, selectionLines, selectionReference } from "./fileReference";

describe("file references", () => {
  it("quotes a passage and cites its file and page outside the quote", () => {
    expect(selectionReference("dense retrieval\n\nbeats BM25", "papers/survey.pdf", { page: 12 })).toBe(
      "> dense retrieval\n>\n> beats BM25\n\n— `papers/survey.pdf`, p. 12",
    );
  });

  it("cites lines, one or a range, and cites a bare file when the place is unknown", () => {
    expect(selectionReference("x", "a.txt", { lines: [4, 4] })).toBe("> x\n\n— `a.txt`, line 4");
    expect(selectionReference("x", "a.txt", { lines: [4, 6] })).toBe("> x\n\n— `a.txt`, lines 4–6");
    expect(selectionReference("x", "notes/a.md", null)).toBe("> x\n\n— `notes/a.md`");
    expect(fileReference("notes/a.md")).toBe("`notes/a.md`");
  });

  it("numbers the lines a selection covers", () => {
    const text = "one\ntwo\nthree\nfour";
    expect(selectionLines(text, 0, 3)).toEqual([1, 1]);
    expect(selectionLines(text, 4, 13)).toEqual([2, 3]);
    // Dragging backwards, and ending just after a newline, still cover the same lines.
    expect(selectionLines(text, 8, 4)).toEqual([2, 2]);
    expect(selectionLines(text, 4, 8)).toEqual([2, 2]);
  });
});
