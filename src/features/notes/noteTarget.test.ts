// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";
import { getNote, upsertNote, type Note } from "./notes";
import { keepInHighlightsNote } from "./noteTarget";

vi.mock("./notes", () => ({ getNote: vi.fn(), upsertNote: vi.fn() }));

const note = (id: string, body: string): Note => ({ id, slug: id, title: "Highlights", body, tags: [], slugPending: false, createdAt: 1, updatedAt: 1 });

beforeEach(() => {
  localStorage.clear();
  vi.clearAllMocks();
  vi.mocked(upsertNote).mockImplementation(async (input) => note(input.id!, input.body));
});

it("makes the highlights note the first time, then adds to it without asking", async () => {
  const create = vi.fn(async () => note("kept", "> First"));
  expect((await keepInHighlightsNote("kern", "> First", create)).id).toBe("kept");
  expect(create).toHaveBeenCalledOnce();

  vi.mocked(getNote).mockResolvedValue(note("kept", "> First"));
  const second = await keepInHighlightsNote("kern", "> Second", create);
  expect(create).toHaveBeenCalledOnce();
  expect(second.body).toBe("> First\n\n> Second\n");
});

it("keeps one note per mentor and makes it again after it was deleted", async () => {
  const create = vi.fn(async () => note("fresh", "> Again"));
  localStorage.setItem("loci.highlightsNote.kern", "gone");
  vi.mocked(getNote).mockResolvedValue(null);
  expect((await keepInHighlightsNote("kern", "> Again", create)).id).toBe("fresh");
  expect(localStorage.getItem("loci.highlightsNote.kern")).toBe("fresh");
  expect(localStorage.getItem("loci.highlightsNote.ada")).toBeNull();
});
