import { beforeEach, describe, expect, it, vi } from "vitest";
import { MissingNoteError } from "../../notes/noteTarget";

const notes = vi.hoisted(() => ({
  getNote: vi.fn(), createNote: vi.fn(), appendToNote: vi.fn(), saveNoteImagesFromFiles: vi.fn(),
}));
vi.mock("../../notes/notes", () => ({ getNote: notes.getNote, createNote: notes.createNote, noteTitle: (text: string) => text }));
vi.mock("../../notes/noteImages", async (original) => ({ ...await original<object>(), saveNoteImagesFromFiles: notes.saveNoteImagesFromFiles }));
vi.mock("../../notes/noteTarget", async (original) => ({ ...await original<object>(), appendToNote: notes.appendToNote }));

const { quoteMarkdown, savePictureQuoteToNote } = await import("./quoteNote");

const source = { id: "s-area", kind: "pdf" as const, title: "Firecracker.pdf", quote: "", documentId: "doc", path: "/fc.pdf",
  anchors: [{ page: 4, rects: [{ x: 0.1, y: 0.2, width: 0.5, height: 0.3 }] }] };
const picture = new File([new Uint8Array([137, 80, 78, 71])], "Firecracker p4.png", { type: "image/png" });

describe("an area of a PDF page saved to a note", () => {
  beforeEach(() => {
    for (const fn of Object.values(notes)) fn.mockReset();
    notes.saveNoteImagesFromFiles.mockResolvedValue([{ name: "Firecracker p4.png", markdownPath: "assets/n1/firecracker-p4.png" }]);
    notes.appendToNote.mockImplementation(async (id: string, body: string) => ({ id, title: "t", body }));
  });

  it("is its picture, kept with the note, then its words quoted with a link to the page", async () => {
    notes.getNote.mockResolvedValue({ id: "n1" });
    const markdown = quoteMarkdown("Table 2: phases\nPending accepted", { ...source, quote: "Table 2: phases\nPending accepted" });
    const saved = await savePictureQuoteToNote(picture, markdown, "Table 2", { kind: "note", id: "n1", title: "Reading" });
    expect(notes.saveNoteImagesFromFiles).toHaveBeenCalledWith("n1", [picture]);
    expect(saved.body).toBe([
      "![Firecracker p4.png](assets/n1/firecracker-p4.png)",
      "",
      "> Table 2: phases",
      "> Pending accepted",
      ">",
      "> — [Firecracker.pdf · p. 4](loci://source/s-area#p4&quote=Table%202%3A%20phases%20Pending%20accepted)",
    ].join("\n"));
  });

  it("with no words is its picture and a link, in a new note for the mentor", async () => {
    notes.createNote.mockResolvedValue({ id: "n2" });
    const saved = await savePictureQuoteToNote(picture, quoteMarkdown("", source), "Firecracker.pdf · p. 4", { kind: "new" }, "kern");
    expect(notes.createNote).toHaveBeenCalledWith({ title: "Firecracker.pdf · p. 4", body: "", agentId: "kern" });
    expect(notes.appendToNote.mock.calls[0][0]).toBe("n2");
    expect(saved.body).toBe("![Firecracker p4.png](assets/n1/firecracker-p4.png)\n\n> — [Firecracker.pdf · p. 4](loci://source/s-area#p4)");
  });

  it("copies no picture into a note that is gone", async () => {
    notes.getNote.mockResolvedValue(null);
    await expect(savePictureQuoteToNote(picture, "> x", "x", { kind: "note", id: "gone", title: "Old" })).rejects.toBeInstanceOf(MissingNoteError);
    expect(notes.saveNoteImagesFromFiles).not.toHaveBeenCalled();
  });
});
