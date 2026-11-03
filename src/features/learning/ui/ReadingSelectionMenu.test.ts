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

const platform = vi.hoisted(() => ({ isMac: true }));
vi.mock("../../../platform/tauri/platform", () => ({ get IS_MAC() { return platform.isMac; } }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../model/learningStore", () => ({
  registerLearningSource: vi.fn(), listAnnotations: vi.fn(async () => []), subscribeLearningChanges: () => () => {},
  upsertAnnotation: vi.fn(async (annotation: unknown) => annotation), deleteAnnotation: vi.fn(),
}));
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
  return createElement("div", { ref }, createElement("p", null, document.body), createElement(ReadingSelectionMenu, { selection, onDismiss, askLabel: marks.askLabel, toChat: marks.toChat, onMark: marks.onMark,
    resetKey: JSON.stringify([document.id, document.body, document.title, document.sourceUrl, agentId]) }), marks.popover);
}
const fallback = (quote: string) => ({ exact: quote, prefix: "", suffix: "", start: 0, end: 0 });
const passage = (doc: AgentDocument, quote = "First line\nSecond line") => ({ id: "source-1", kind: "document", agentId: "agent-a", documentId: doc.id, title: doc.title, quote,
  ...(doc.sourceUrl ? { url: doc.sourceUrl } : {}), anchor: fallback(quote) });
const ownDocument = { id: "strategy", title: "Network strategy", body: "First line\nSecond line" };
const sourceDocument = { ...ownDocument, sourceUrl: "https://example.org/network" };

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
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
const labelOf = (entry: Element) => entry.textContent || entry.getAttribute("aria-label");
const button = (label: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((entry) => labelOf(entry)?.startsWith(label))!;
const actions = () => [...toolbar()!.querySelectorAll("button")].map(labelOf);
const key = async (options: KeyboardEventInit, target: EventTarget = window) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...options });
  await act(async () => target.dispatchEvent(event));
  return event;
};

it("offers Highlight and Ask (named for the mentor) as one small bar", async () => {
  await render();
  expect(actions()).toEqual(["Highlight", "Ask Kern"]);
  expect(toolbar()!.querySelector("h2, blockquote, textarea")).toBeNull();
  expect(button("Highlight").title).toContain("(H)");
  expect(button("Ask").title).toContain("⌘L");
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

it("asks about a document outside any library as plain text, and offers no highlight there", async () => {
  props.agentId = undefined;
  await render();
  expect(actions()).toEqual(["Ask"]);
  await act(async () => button("Ask").click());
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n", "prompt", {});
  expect(registerLearningSource).not.toHaveBeenCalled();
});

it("keeps a highlight on the library document and goes away, with no bar left on it", async () => {
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
  expect(props.onDismiss).toHaveBeenCalledOnce();
  expect(document.querySelector('[role="toolbar"][aria-label="Highlight actions"]')).toBeNull();
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("highlights with H, but not while typing", async () => {
  const range = document.createRange();
  await render();
  range.selectNodeContents(container.querySelector("p")!);
  props = { ...props, selection: { ...props.selection!, range } };
  await render();
  const input = document.createElement("input");
  input.dataset.testEditable = "true";
  document.body.append(input);
  expect((await key({ code: "KeyH", key: "h" }, input)).defaultPrevented).toBe(false);
  expect(upsertAnnotation).not.toHaveBeenCalled();
  expect((await key({ code: "KeyH", key: "h", metaKey: true })).defaultPrevented).toBe(false);
  const event = await key({ code: "KeyH", key: "h" });
  expect(event.defaultPrevented).toBe(true);
  expect(upsertAnnotation).toHaveBeenCalledOnce();
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

it("asks with ⌘L, as Ask does", async () => {
  await render();
  const event = await key({ code: "KeyL", key: "l", metaKey: true });
  expect(event.defaultPrevented).toBe(true);
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n", "prompt", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("asks with Ctrl+L on other platforms", async () => {
  platform.isMac = false;
  await render();
  const event = await key({ code: "KeyL", key: "l", ctrlKey: true });
  expect(event.defaultPrevented).toBe(true);
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n", "prompt", { sources: [passage(ownDocument)], targetSessionId: "agent-chat" });
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
