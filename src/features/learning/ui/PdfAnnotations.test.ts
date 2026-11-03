// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AnnotationList, AnnotationToolbar } from "./PdfAnnotations";
import { createPdfAnnotation } from "../model/pdfAnnotations";
import { OPEN_LEARNING_DISCUSSION_EVENT } from "../model/navigation";
import { registerLearningSource } from "../model/learningStore";
import { copyText } from "../../../platform/tauri/clipboard";
import { createNote, getNote, upsertNote } from "../../notes/notes";
import { NOTE_SAVED_EVENT, rememberedNoteTarget } from "../../notes/noteTarget";

vi.mock("../model/learningStore", () => ({ registerLearningSource: vi.fn(async () => undefined) }));
vi.mock("../../../platform/tauri/clipboard", () => ({ copyText: vi.fn(async () => undefined) }));
vi.mock("../../notes/notes", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../notes/notes")>(),
  getNote: vi.fn(), upsertNote: vi.fn(), createNote: vi.fn(), listAgentNotes: vi.fn(), loadNotes: vi.fn(),
}));

describe("reading notes and discussions", () => {
  let host: HTMLDivElement; let root: Root;
  const annotation = { ...createPdfAnnotation({ id: "doc", title: "Book", path: "/book.pdf", fingerprint: "book", createdAt: 1, updatedAt: 1 }, "A useful passage", [{ page: 3, rects: [{ x: 0.1, y: 0.2, width: 0.3, height: 0.1 }] }]), note: "Read again", discussions: [{ sessionId: "session", blockId: "block" }] };
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    vi.mocked(getNote).mockImplementation(async (id) => id === stored.id ? stored : null);
    vi.mocked(upsertNote).mockImplementation(async (note) => ({ ...stored, ...note }));
    vi.mocked(createNote).mockImplementation(async (input) => ({ ...stored, id: "new-note", title: input.title ?? "", body: input.body ?? "" }));
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });

  it("lists the saved passage and its note, and selects its page anchor", async () => {
    const select = vi.fn();
    await act(async () => root.render(createElement(AnnotationList, { annotations: [annotation], onSelect: select, onClose: vi.fn() })));
    expect(host.textContent).toContain("Page 3"); expect(host.textContent).toContain("Read again"); expect(host.textContent).toContain("1 discussion");
    const entry = [...host.querySelectorAll("button")].find((button) => button.textContent?.includes("A useful passage"))!;
    await act(async () => entry.click());
    expect(select).toHaveBeenCalledWith(annotation);
  });

  it("says how to start in one line, with no count, when nothing is marked", async () => {
    await act(async () => root.render(createElement(AnnotationList, { annotations: [], onSelect: vi.fn(), onClose: vi.fn() })));
    expect(host.querySelector(".pdf-annotations__empty")?.textContent).toBe("Select text to highlight it");
    expect(host.querySelector(".pdf-annotations__count")).toBeNull();
    expect(host.querySelector(".pdf-annotations__empty")?.children).toHaveLength(0);
  });

  it("orders passages by page and position without rearranging the stored list", async () => {
    const pageOne = { ...annotation, id: "page-one", anchors: [{ page: 1, rects: [{ x: 0.1, y: 0.5, width: 0.3, height: 0.1 }] }] };
    const pageThreeTop = { ...annotation, id: "page-three-top", anchors: [{ page: 3, rects: [{ x: 0.1, y: 0.1, width: 0.3, height: 0.1 }] }] };
    const annotations = [annotation, pageThreeTop, pageOne];
    await act(async () => root.render(createElement(AnnotationList, { annotations, selectedId: pageThreeTop.id, onSelect: vi.fn(), onClose: vi.fn() })));
    const entries = [...host.querySelectorAll<HTMLButtonElement>("button[aria-pressed]")];
    expect(entries.map((entry) => entry.querySelector(".pdf-annotations__page")?.textContent)).toEqual(["Page 1", "Page 3", "Page 3"]);
    expect(entries.map((entry) => entry.getAttribute("aria-pressed"))).toEqual(["false", "true", "false"]);
    expect(annotations.map((entry) => entry.id)).toEqual([annotation.id, pageThreeTop.id, pageOne.id]);
  });

  const bar = (props: Partial<Parameters<typeof AnnotationToolbar>[0]> = {}) => createElement(AnnotationToolbar, {
    annotation, anchor: new DOMRect(100, 100, 10, 10), askLabel: "Ask Kern", notes: shelf,
    onAsk: vi.fn(), onSave: vi.fn(async () => {}), onDelete: vi.fn(async () => {}), onDismiss: vi.fn(), ...props,
  });
  const shelf = { scope: "agent-a", agentId: "agent-a", list: vi.fn(async () => [stored]) };
  const stored = { id: "reading", slug: "reading", title: "Reading log", body: "Earlier", tags: [], slugPending: false, createdAt: 1, updatedAt: 1 };
  const button = (label: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((entry) => (entry.textContent || entry.getAttribute("aria-label")) === label)!;
  const field = () => document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Note"]');
  const type = async (text: string) => act(async () => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(field()!, text);
    field()!.dispatchEvent(new Event("input", { bubbles: true }));
  });

  it("is a bar of actions with its note as a line under it, and the note field closed", async () => {
    await act(async () => root.render(bar()));
    const toolbar = document.querySelector('[role="toolbar"][aria-label="Highlight actions"]')!;
    expect([...toolbar.querySelectorAll(".reading-toolbar__actions button")].map((entry) => entry.textContent || entry.getAttribute("aria-label")))
      .toEqual(["Note", "Ask Kern", "Save to note", "Copy quote", "Open discussion", "Delete highlight"]);
    expect(toolbar.querySelector("h2, blockquote")).toBeNull();
    expect(field()).toBeNull();
    expect(button("Read again").className).toContain("reading-toolbar__note");
  });

  it("opens the note field from Note, saves it, and asks with the note as it stands", async () => {
    const onSave = vi.fn(async () => {}); const onAsk = vi.fn();
    await act(async () => root.render(bar({ onSave, onAsk })));
    await act(async () => button("Note").click());
    expect(document.activeElement).toBe(field());
    expect(button("Save").disabled).toBe(true);
    await type("How does this compare with the experiment?");
    await act(async () => button("Save").click());
    expect(onSave).toHaveBeenCalledWith(annotation, "How does this compare with the experiment?");
    expect(field()).toBeNull();
    await act(async () => button("Ask Kern").click());
    expect(onAsk).toHaveBeenCalledWith({ ...annotation, note: "How does this compare with the experiment?" });
  });

  it("keeps a typed note when the bar is dismissed or the passage is asked about", async () => {
    const onSave = vi.fn(async () => {}); const onAsk = vi.fn(); const onDismiss = vi.fn();
    await act(async () => root.render(bar({ onSave, onAsk, onDismiss })));
    await act(async () => button("Note").click());
    await type("A half-formed thought");
    await act(async () => window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(onSave).toHaveBeenCalledWith(annotation, "A half-formed thought");
    expect(onDismiss).toHaveBeenCalledOnce();
    onSave.mockClear(); onDismiss.mockClear();
    await type("Why does this hold?");
    await act(async () => button("Ask Kern").click());
    expect(onSave).toHaveBeenCalledWith(annotation, "Why does this hold?");
    expect(onAsk).toHaveBeenCalledWith({ ...annotation, note: "Why does this hold?" });
  });

  it("asks which note the first time, then saves the quote, its link and the note to the one chosen last", async () => {
    const onDismiss = vi.fn();
    const saved = vi.fn(); window.addEventListener(NOTE_SAVED_EVENT, saved);
    await act(async () => root.render(bar({ onDismiss })));
    await act(async () => button("Save to note").click());
    expect(document.querySelector('[role="menu"][aria-label="Add to which note"]')).not.toBeNull();
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
    await act(async () => button("Reading log").click());
    expect(registerLearningSource).toHaveBeenCalledWith(annotation.source);
    expect(vi.mocked(upsertNote).mock.calls[0][0].body).toBe(`Earlier\n\n> A useful passage\n>\n> — [Book · p. 3](loci://source/${annotation.source.id}#p3&quote=A%20useful%20passage)\n\nRead again\n`);
    expect(onDismiss).toHaveBeenCalledOnce();
    expect((saved.mock.calls[0][0] as CustomEvent).detail).toMatchObject({ id: "reading", title: "Reading log" });
    expect(rememberedNoteTarget("agent-a")).toEqual({ kind: "note", id: "reading", title: "Reading log" });
    // The next passage goes straight there, with no question.
    await act(async () => root.render(bar({ key: "again", onDismiss })));
    await act(async () => button("Save to note").click());
    expect(document.querySelector('[role="menu"]')).toBeNull();
    expect(upsertNote).toHaveBeenCalledTimes(2);
    window.removeEventListener(NOTE_SAVED_EVENT, saved);
  });

  it("starts a new note from the picker, and goes on adding to that note", async () => {
    await act(async () => root.render(bar({ annotation: { ...annotation, note: "" } })));
    await act(async () => button("Save to note").click());
    await act(async () => button("New note").click());
    expect(createNote).toHaveBeenCalledWith({ title: "A useful passage", body: expect.stringMatching(/^> A useful passage\n>\n> — \[Book · p\. 3\]\(loci:\/\/source\/.+\)$/), agentId: "agent-a" });
    expect(rememberedNoteTarget("agent-a")).toEqual({ kind: "note", id: "new-note", title: "A useful passage" });
  });

  it("copies the passage as a linked Markdown quote", async () => {
    await act(async () => root.render(bar()));
    await act(async () => button("Copy quote").click());
    expect(copyText).toHaveBeenCalledWith(expect.stringMatching(/^> A useful passage\n>\n> — \[Book · p\. 3\]\(loci:.+\)\n\nRead again$/));
  });

  it("reopens the linked discussion and removes a mark through its visible controls", async () => {
    const onDelete = vi.fn(async () => {}); const onDismiss = vi.fn();
    const confirm = vi.fn(() => true); vi.stubGlobal("confirm", confirm);
    const receive = vi.fn(); window.addEventListener(OPEN_LEARNING_DISCUSSION_EVENT, receive);
    await act(async () => root.render(bar({ onDelete, onDismiss })));
    await act(async () => button("Open discussion").click());
    expect((receive.mock.calls[0][0] as CustomEvent).detail).toEqual({ sessionId: "session", blockId: "block" });
    await act(async () => button("Delete highlight").click());
    expect(confirm).toHaveBeenCalledWith("Delete this highlight and its note?");
    expect(onDelete).toHaveBeenCalledWith(annotation); expect(onDismiss).toHaveBeenCalledOnce();
    window.removeEventListener(OPEN_LEARNING_DISCUSSION_EVENT, receive);
  });

  it("keeps a highlight when deleting it and its note is declined, and asks nothing for a bare highlight", async () => {
    const onDelete = vi.fn(async () => {}); const onDismiss = vi.fn();
    const confirm = vi.fn(() => false); vi.stubGlobal("confirm", confirm);
    await act(async () => root.render(bar({ onDelete, onDismiss })));
    await act(async () => button("Delete highlight").click());
    expect(onDelete).not.toHaveBeenCalled();
    expect(onDismiss).not.toHaveBeenCalled();
    await act(async () => root.render(bar({ key: "bare", annotation: { ...annotation, note: "" }, onDelete, onDismiss })));
    confirm.mockClear();
    await act(async () => button("Delete highlight").click());
    expect(confirm).not.toHaveBeenCalled();
    expect(onDelete).toHaveBeenCalledOnce();
  });
});
