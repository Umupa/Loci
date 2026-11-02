// @vitest-environment happy-dom
import { act, createElement, useMemo, useRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { registerLearningSource, upsertAnnotation } from "../model/learningStore";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { findAgent } from "../../agents/model/agent";
import { documentMarkSpec } from "../../agents/model/documentMarks";
import type { AgentDocument } from "../../sessions/model/cards";
import type { FileSelection } from "../../files/hooks/useFileSelection";
import { ReadingSelectionMenu } from "./ReadingSelectionMenu";
import { useReadingMarks } from "./useReadingMarks";
import { createNote, getNote, upsertNote } from "../../notes/notes";
import { NOTE_SAVED_EVENT, rememberedNoteTarget, rememberNoteTarget } from "../../notes/noteTarget";
import { copyText } from "../../../platform/tauri/clipboard";

const platform = vi.hoisted(() => ({ isMac: true }));
vi.mock("../../../platform/tauri/platform", () => ({ get IS_MAC() { return platform.isMac; } }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../model/learningStore", () => ({
  registerLearningSource: vi.fn(), listAnnotations: vi.fn(async () => []), subscribeLearningChanges: () => () => {},
  upsertAnnotation: vi.fn(async (annotation: unknown) => annotation), deleteAnnotation: vi.fn(),
}));
vi.mock("../../notes/notes", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../notes/notes")>(),
  getNote: vi.fn(), upsertNote: vi.fn(), createNote: vi.fn(), listAgentNotes: vi.fn(async () => []), loadNotes: vi.fn(async () => []),
}));
vi.mock("../../../platform/tauri/clipboard", () => ({ copyText: vi.fn(async () => undefined) }));
vi.mock("../../sessions/model/quoteDraft", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../sessions/model/quoteDraft")>(),
  requestAddToChat: vi.fn(),
}));

let container: HTMLDivElement;
let root: Root;
type HarnessProps = { document: AgentDocument; agentId?: string; selection: FileSelection | null; onDismiss: () => void };
let props: HarnessProps;
/** A document reader's menu as DocumentBody wires it. */
function Harness({ document, agentId, selection, onDismiss }: HarnessProps) {
  const ref = useRef<HTMLDivElement>(null);
  const spec = useMemo(() => documentMarkSpec(document, agentId), [document, agentId]);
  const marks = useReadingMarks(ref, spec, { agentId });
  return createElement("div", { ref }, createElement("p", null, document.body), createElement(ReadingSelectionMenu, { selection, onDismiss, askLabel: marks.askLabel, toChat: marks.toChat, onMark: marks.onMark, quote: marks.quote, notes: marks.notes,
    resetKey: JSON.stringify([document.id, document.body, document.title, document.sourceUrl, agentId]) }), marks.popover);
}
const fallback = (quote: string) => ({ exact: quote, prefix: "", suffix: "", start: 0, end: 0 });
const passage = (doc: AgentDocument, quote = "First line\nSecond line") => ({ id: "source-1", kind: "document", agentId: "agent-a", documentId: doc.id, title: doc.title, quote,
  ...(doc.sourceUrl ? { url: doc.sourceUrl } : {}), anchor: fallback(quote) });
const ownDocument = { id: "strategy", title: "Network strategy", body: "First line\nSecond line" };
const sourceDocument = { ...ownDocument, sourceUrl: "https://example.org/network" };

const stored = { id: "reading", slug: "reading", title: "Reading log", body: "Earlier", tags: [], slugPending: false, createdAt: 1, updatedAt: 1 };

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
  vi.mocked(getNote).mockImplementation(async (id) => id === stored.id ? stored : null);
  vi.mocked(upsertNote).mockImplementation(async (note) => ({ ...stored, ...note }));
  vi.mocked(createNote).mockImplementation(async (input) => ({ ...stored, id: "new-note", title: input.title ?? "", body: input.body ?? "" }));
  platform.isMac = true;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  vi.stubGlobal("crypto", { randomUUID: () => "source-1" });
  vi.mocked(findAgent).mockReturnValue({ sessionId: "agent-chat", name: "Kern" } as never);
  vi.mocked(registerLearningSource).mockResolvedValue(undefined as never);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  props = {
    document: ownDocument,
    agentId: "agent-a",
    selection: { text: "First line\nSecond line", rect: new DOMRect(20, 80, 160, 20), range: document.createRange() },
    onDismiss: vi.fn(),
  };
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  document.querySelectorAll("[data-shortcut-recorder-active], [data-test-editable]").forEach((element) => element.remove());
  vi.unstubAllGlobals();
});

const render = async () => { await act(async () => root.render(createElement(Harness, props))); };
const toolbar = () => document.querySelector('[role="toolbar"]');
const dialog = () => document.querySelector('[role="dialog"][aria-label="Comment on selected text"]');
const labelOf = (entry: Element) => entry.textContent || entry.getAttribute("aria-label");
const button = (label: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((entry) => labelOf(entry)?.startsWith(label))!;
const actions = () => [...toolbar()!.querySelectorAll("button")].map(labelOf);
const comment = () => document.querySelector<HTMLTextAreaElement>('textarea[aria-label="Comment"]')!;
const typeComment = async (value: string) => {
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(comment(), value);
    comment().dispatchEvent(new Event("input", { bubbles: true }));
  });
};
const key = async (options: KeyboardEventInit, target: EventTarget = window) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...options });
  await act(async () => target.dispatchEvent(event));
  return event;
};

it("offers Highlight, Ask (named for the mentor), Save to note and Copy as one small bar", async () => {
  await render();
  expect(actions()).toEqual(["Highlight", "Ask Kern", "Save to note", "Copy quote"]);
  expect(toolbar()!.querySelector("h2, blockquote, textarea")).toBeNull();
  expect(button("Ask").title).toMatch(/⌘L.*⌥⌘M/);
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("quotes the passage in the mentor's draft for the reader's own question, with its anchored source", async () => {
  await render();
  await act(async () => button("Ask").click());
  expect(registerLearningSource).toHaveBeenCalledWith(passage(ownDocument));
  // A prompt keeps the blank line after the quote: the cursor lands there, ready to type.
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n", "prompt", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("quotes a document outside any library as plain text, and offers no highlight there", async () => {
  props.agentId = undefined;
  await render();
  expect(actions()).toEqual(["Ask", "Save to note", "Copy quote"]);
  await act(async () => button("Ask").click());
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n", "prompt", {});
  expect(registerLearningSource).not.toHaveBeenCalled();
});

it("keeps a highlight on the library document and opens its own bar, the note field closed", async () => {
  await render();
  const range = document.createRange();
  range.selectNodeContents(container.querySelector("p")!);
  props = { ...props, selection: { ...props.selection!, range } };
  await render();
  await act(async () => button("Highlight").click());
  expect(upsertAnnotation).toHaveBeenCalledWith(expect.objectContaining({
    target: { kind: "document", agentId: "agent-a", documentId: "strategy" },
    anchor: expect.objectContaining({ exact: "First line\nSecond line" }),
    source: expect.objectContaining({ kind: "document", annotationId: "source-1" }),
  }));
  expect(document.querySelector('[role="toolbar"][aria-label="Highlight actions"]')).not.toBeNull();
  expect(document.querySelector('textarea[aria-label="Note"]')).toBeNull();
  await act(async () => button("Note").click());
  expect(document.querySelector('textarea[aria-label="Note"]')).toBe(document.activeElement);
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("keeps the web passage available when Ask cannot save its source, and permits retry", async () => {
  let rejectSave!: (reason: Error) => void;
  vi.mocked(registerLearningSource).mockImplementationOnce(() => new Promise((_resolve, reject) => { rejectSave = reject; }));
  props.document = sourceDocument;
  await render();
  await act(async () => button("Ask").click());
  expect(button("Ask").disabled).toBe(true);
  expect(requestAddToChat).not.toHaveBeenCalled();
  expect(props.onDismiss).not.toHaveBeenCalled();
  await act(async () => rejectSave(new Error("Source unavailable")));
  expect(document.querySelector('[role="alert"]')?.textContent).toContain("Source unavailable");
  expect(button("Ask").disabled).toBe(false);
  expect(requestAddToChat).not.toHaveBeenCalled();
  await act(async () => button("Ask").click());
  const source = passage(sourceDocument);
  expect(registerLearningSource).toHaveBeenLastCalledWith(source);
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n", "prompt", { sources: [source], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("quotes an agent document to the agent's chat without sending", async () => {
  await render();
  await key({ code: "KeyL", key: "l", metaKey: true });
  expect(requestAddToChat).toHaveBeenCalledWith("", "plain", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("waits for a web source to save, keeps a failed selection, and allows retry", async () => {
  let rejectSave!: (reason: Error) => void;
  vi.mocked(registerLearningSource).mockImplementationOnce(() => new Promise((_resolve, reject) => { rejectSave = reject; }));
  props.document = sourceDocument;
  await render();
  await key({ code: "KeyL", key: "l", metaKey: true });
  expect(button("Ask").disabled).toBe(true);
  expect(requestAddToChat).not.toHaveBeenCalled();
  expect(props.onDismiss).not.toHaveBeenCalled();
  await act(async () => rejectSave(new Error("Disk full")));
  expect(document.querySelector('[role="alert"]')?.textContent).toContain("Disk full");
  expect(button("Ask").disabled).toBe(false);
  await key({ code: "KeyL", key: "l", metaKey: true });
  const source = passage(sourceDocument);
  expect(registerLearningSource).toHaveBeenLastCalledWith(source);
  expect(requestAddToChat).toHaveBeenCalledWith("", "plain", { sources: [source], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("keeps the selected passage while writing a comment after the native selection clears", async () => {
  await render();
  await key({ code: "KeyM", key: "µ", metaKey: true, altKey: true });
  expect(dialog()?.textContent).toContain("First line");
  expect(document.activeElement).toBe(comment());
  expect(button("Add to chat").disabled).toBe(true);
  props = { ...props, selection: null };
  await render();
  expect(dialog()).not.toBeNull();
  await typeComment("  Please compare both lines.  ");
  await act(async () => button("Add to chat").click());
  expect(requestAddToChat).toHaveBeenCalledWith("Please compare both lines.", "plain", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
  expect(dialog()).toBeNull();
});

it("preserves the web quotation and comment when saving its source fails", async () => {
  props.document = sourceDocument;
  vi.mocked(registerLearningSource).mockRejectedValueOnce(new Error("Offline"));
  await render();
  await key({ code: "KeyM", key: "µ", metaKey: true, altKey: true });
  await typeComment("Why does this work?");
  await act(async () => button("Add to chat").click());
  expect(dialog()).not.toBeNull();
  expect(comment().value).toBe("Why does this work?");
  expect(document.querySelector('[role="alert"]')?.textContent).toContain("Offline");
  expect(requestAddToChat).not.toHaveBeenCalled();
  await act(async () => button("Add to chat").click());
  expect(requestAddToChat).toHaveBeenCalledWith("Why does this work?", "plain", {
    sources: [passage(sourceDocument)],
    targetSessionId: "agent-chat",
  });
  expect(dialog()).toBeNull();
});

it.each([
  ["document", { ...ownDocument, id: "other" }],
  ["revision", { ...ownDocument, body: "A revision" }],
  ["source", sourceDocument],
])("dismisses a captured comment when its %s changes", async (_reason, document) => {
  await render();
  await key({ code: "KeyM", key: "µ", metaKey: true, altKey: true });
  await typeComment("Draft comment");
  props = { ...props, document, selection: null };
  await render();
  expect(dialog()).toBeNull();
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("dismisses a captured comment when its owning agent changes", async () => {
  await render();
  await key({ code: "KeyM", key: "µ", metaKey: true, altKey: true });
  props = { ...props, agentId: "agent-b", selection: null };
  await render();
  expect(dialog()).toBeNull();
});

it("uses physical keys for macOS Comment and Quote shortcuts", async () => {
  await render();
  const commentKey = await key({ code: "KeyM", key: "µ", metaKey: true, altKey: true });
  expect(commentKey.defaultPrevented).toBe(true);
  expect(dialog()).not.toBeNull();
  expect(requestAddToChat).not.toHaveBeenCalled();
  await key({ code: "Escape", key: "Escape" });
  await render();
  const quoteKey = await key({ code: "KeyL", key: "l", metaKey: true });
  expect(quoteKey.defaultPrevented).toBe(true);
  expect(requestAddToChat).toHaveBeenCalledWith("", "plain", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
});

it("uses Ctrl shortcuts on other platforms", async () => {
  platform.isMac = false;
  await render();
  const commentKey = await key({ code: "KeyM", key: "m", ctrlKey: true, altKey: true });
  expect(commentKey.defaultPrevented).toBe(true);
  expect(dialog()).not.toBeNull();
  await key({ code: "Escape", key: "Escape" });
  const quoteKey = await key({ code: "KeyL", key: "l", ctrlKey: true });
  expect(quoteKey.defaultPrevented).toBe(true);
  expect(requestAddToChat).toHaveBeenCalledWith("", "plain", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
});

it.each([
  { isComposing: true },
  { repeat: true },
  { shiftKey: true },
  { altKey: true },
])("leaves the Quote chord alone at this boundary: %j", async (boundary) => {
  await render();
  const event = await key({ code: "KeyL", key: "l", metaKey: true, ...boundary });
  expect(event.defaultPrevented).toBe(false);
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("does not steal shortcuts from editable controls or shortcut recording", async () => {
  await render();
  const input = document.createElement("input");
  input.dataset.testEditable = "true";
  document.body.append(input);
  const editableEvent = await key({ code: "KeyL", key: "l", metaKey: true }, input);
  expect(editableEvent.defaultPrevented).toBe(false);
  const recorder = document.createElement("div");
  recorder.dataset.shortcutRecorderActive = "true";
  document.body.append(recorder);
  const recorderEvent = await key({ code: "KeyL", key: "l", metaKey: true });
  expect(recorderEvent.defaultPrevented).toBe(false);
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("does not handle a shortcut without a document selection", async () => {
  props.selection = null;
  await render();
  const event = await key({ code: "KeyL", key: "l", metaKey: true });
  expect(event.defaultPrevented).toBe(false);
  expect(toolbar()).toBeNull();
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("does not add a passage after its document changes while the source saves", async () => {
  let resolveSave!: () => void;
  vi.mocked(registerLearningSource).mockImplementationOnce(() => new Promise((resolve) => { resolveSave = () => resolve(undefined as never); }));
  props.document = sourceDocument;
  await render();
  await key({ code: "KeyL", key: "l", metaKey: true });
  props = { ...props, document: { ...sourceDocument, body: "Revised passage" }, selection: null };
  await render();
  await act(async () => resolveSave());
  expect(requestAddToChat).not.toHaveBeenCalled();
  expect(document.querySelector('[role="alert"]')).toBeNull();
});

it("does not show an old source-save failure after the menu was dismissed", async () => {
  let rejectSave!: (reason: Error) => void;
  vi.mocked(registerLearningSource).mockImplementationOnce(() => new Promise((_resolve, reject) => { rejectSave = reject; }));
  props.document = sourceDocument;
  await render();
  await key({ code: "KeyL", key: "l", metaKey: true });
  await key({ code: "Escape", key: "Escape" });
  const selection = props.selection;
  props = { ...props, selection: null };
  await render();
  await act(async () => rejectSave(new Error("Old failure")));
  props = { ...props, selection };
  await render();
  expect(toolbar()).not.toBeNull();
  expect(document.querySelector('[role="alert"]')).toBeNull();
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it.each(["scroll", "selection"])("cancels a pending quotation when %s dismisses its menu", async (reason) => {
  let resolveSave!: () => void;
  vi.mocked(registerLearningSource).mockImplementationOnce(() => new Promise((resolve) => { resolveSave = () => resolve(undefined as never); }));
  props.document = sourceDocument;
  await render();
  await key({ code: "KeyL", key: "l", metaKey: true });
  if (reason === "scroll") await act(async () => window.dispatchEvent(new Event("scroll")));
  props = { ...props, selection: null };
  await render();
  await act(async () => resolveSave());
  expect(requestAddToChat).not.toHaveBeenCalled();
  expect(document.querySelector('[role="alert"]')).toBeNull();
});

it("saves a selection to the note it went to last, as a quote linked back to its place", async () => {
  rememberNoteTarget("agent-a", { kind: "note", id: "reading", title: "Reading log" });
  const saved = vi.fn(); window.addEventListener(NOTE_SAVED_EVENT, saved);
  await render();
  expect(button("Save to note").title).toBe("Save to “Reading log”");
  await act(async () => button("Save to note").click());
  expect(document.querySelector('[role="menu"]')).toBeNull();
  expect(registerLearningSource).toHaveBeenCalledWith(passage(ownDocument));
  expect(vi.mocked(upsertNote).mock.calls[0][0]).toMatchObject({ id: "reading",
    body: "Earlier\n\n> First line\n> Second line\n>\n> — [Network strategy](loci://source/source-1#quote=First%20line%20Second%20line)\n" });
  expect((saved.mock.calls[0][0] as CustomEvent).detail).toMatchObject({ id: "reading" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
  expect(requestAddToChat).not.toHaveBeenCalled();
  window.removeEventListener(NOTE_SAVED_EVENT, saved);
});

it("asks which note while holding the passage, and remembers a new note for the next one", async () => {
  await render();
  await act(async () => button("Save to note").click());
  expect(document.querySelector('[role="menu"][aria-label="Add to which note"]')).not.toBeNull();
  // Focus moving into the picker clears the native selection; the passage stays.
  props = { ...props, selection: null };
  await render();
  await act(async () => button("New note").click());
  expect(createNote).toHaveBeenCalledWith({ title: "First line", body: expect.stringContaining("> First line\n> Second line\n>\n> — [Network strategy]("), agentId: "agent-a" });
  expect(rememberedNoteTarget("agent-a")).toEqual({ kind: "note", id: "new-note", title: "First line" });
  expect(toolbar()).toBeNull();
});

it("asks again when the remembered note is gone", async () => {
  rememberNoteTarget("agent-a", { kind: "note", id: "deleted", title: "Old" });
  await render();
  await act(async () => button("Save to note").click());
  expect(document.querySelector('[role="menu"]')?.textContent).toContain("That note is no longer there.");
  expect(rememberedNoteTarget("agent-a")).toBeNull();
});

it("copies the passage as a Markdown quote linked to where it was read", async () => {
  await render();
  await act(async () => button("Copy quote").click());
  expect(copyText).toHaveBeenCalledWith("> First line\n> Second line\n>\n> — [Network strategy](loci://source/source-1#quote=First%20line%20Second%20line)");
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("opens the note picker from the chevron beside a remembered note", async () => {
  rememberNoteTarget("agent-a", { kind: "note", id: "reading", title: "Reading log" });
  await render();
  await act(async () => button("Choose another note").click());
  expect(document.querySelector('[role="menu"][aria-label="Add to which note"]')).not.toBeNull();
  props = { ...props, selection: null };
  await render();
  await act(async () => button("Back").click());
  expect(document.querySelector('[role="menu"]')).toBeNull();
  expect(toolbar()).toBeNull();
  expect(upsertNote).not.toHaveBeenCalled();
});
