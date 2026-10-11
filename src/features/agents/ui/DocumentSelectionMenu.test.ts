// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { registerLearningSource } from "../../learning/model/learningStore";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { findAgent } from "../model/agent";
import { DocumentSelectionMenu } from "./DocumentSelectionMenu";

const platform = vi.hoisted(() => ({ isMac: true }));
vi.mock("../../../platform/tauri/platform", () => ({ get IS_MAC() { return platform.isMac; } }));
vi.mock("../model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../learning/model/learningStore", () => ({ registerLearningSource: vi.fn() }));
vi.mock("../../sessions/model/quoteDraft", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../sessions/model/quoteDraft")>(),
  requestAddToChat: vi.fn(),
}));

let container: HTMLDivElement;
let root: Root;
let props: ComponentProps<typeof DocumentSelectionMenu>;
const ownDocument = { id: "strategy", title: "Network strategy", body: "First line\nSecond line" };
const sourceDocument = { ...ownDocument, sourceUrl: "https://example.org/network" };

beforeEach(() => {
  vi.clearAllMocks();
  platform.isMac = true;
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  vi.stubGlobal("crypto", { randomUUID: () => "source-1" });
  vi.mocked(findAgent).mockReturnValue({ sessionId: "agent-chat" } as never);
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

const render = async () => { await act(async () => root.render(createElement(DocumentSelectionMenu, props))); };
const toolbar = () => document.querySelector('[role="toolbar"]');
const dialog = () => document.querySelector('[role="dialog"][aria-label="Comment on selected text"]');
const button = (label: string) => [...document.querySelectorAll<HTMLButtonElement>("button")].find((entry) => entry.textContent?.startsWith(label))!;
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

it("offers Ask, Comment and Quote with the requested macOS shortcuts", async () => {
  await render();
  expect([...toolbar()!.querySelectorAll("button")].map((entry) => entry.textContent?.match(/^(Ask|Comment|Quote)/)?.[0])).toEqual(["Ask", "Comment", "Quote"]);
  expect(button("Comment").textContent).toMatch(/⌥.*⌘.*M/);
  expect(button("Quote").textContent).toMatch(/⌘.*L/);
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("prepares an explanation question with the selected document passage", async () => {
  await render();
  await act(async () => button("Ask").click());
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\n请解释这段内容。", "plain", { targetSessionId: "agent-chat" });
  expect(registerLearningSource).not.toHaveBeenCalled();
  expect(props.onDismiss).toHaveBeenCalledOnce();
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
  const source = { id: "source-1", kind: "web", url: sourceDocument.sourceUrl, title: sourceDocument.title, quote: "First line\nSecond line" };
  expect(registerLearningSource).toHaveBeenLastCalledWith(source);
  expect(requestAddToChat).toHaveBeenCalledWith("请解释这段内容。", "plain", { sources: [source], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("quotes an agent document to the agent's chat without sending", async () => {
  await render();
  await act(async () => button("Quote").click());
  expect(requestAddToChat).toHaveBeenCalledWith("First line\nSecond line", "quote", { targetSessionId: "agent-chat" });
  expect(registerLearningSource).not.toHaveBeenCalled();
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("waits for a web source to save, keeps a failed selection, and allows retry", async () => {
  let rejectSave!: (reason: Error) => void;
  vi.mocked(registerLearningSource).mockImplementationOnce(() => new Promise((_resolve, reject) => { rejectSave = reject; }));
  props.document = sourceDocument;
  await render();
  await act(async () => button("Quote").click());
  expect(button("Quote").disabled).toBe(true);
  expect(requestAddToChat).not.toHaveBeenCalled();
  expect(props.onDismiss).not.toHaveBeenCalled();
  await act(async () => rejectSave(new Error("Disk full")));
  expect(document.querySelector('[role="alert"]')?.textContent).toContain("Disk full");
  expect(button("Quote").disabled).toBe(false);
  await act(async () => button("Quote").click());
  const source = { id: "source-1", kind: "web", url: sourceDocument.sourceUrl, title: sourceDocument.title, quote: "First line\nSecond line" };
  expect(registerLearningSource).toHaveBeenLastCalledWith(source);
  expect(requestAddToChat).toHaveBeenCalledWith("", "plain", { sources: [source], targetSessionId: "agent-chat" });
  expect(props.onDismiss).toHaveBeenCalledOnce();
});

it("keeps the selected passage while writing a comment after the native selection clears", async () => {
  await render();
  await act(async () => button("Comment").click());
  expect(dialog()?.textContent).toContain("First line");
  expect(document.activeElement).toBe(comment());
  expect(button("Add to chat").disabled).toBe(true);
  props = { ...props, selection: null };
  await render();
  expect(dialog()).not.toBeNull();
  await typeComment("  Please compare both lines.  ");
  await act(async () => button("Add to chat").click());
  expect(requestAddToChat).toHaveBeenCalledWith("> First line\n> Second line\n\nPlease compare both lines.", "plain", { targetSessionId: "agent-chat" });
  expect(dialog()).toBeNull();
});

it("preserves the web quotation and comment when saving its source fails", async () => {
  props.document = sourceDocument;
  vi.mocked(registerLearningSource).mockRejectedValueOnce(new Error("Offline"));
  await render();
  await act(async () => button("Comment").click());
  await typeComment("Why does this work?");
  await act(async () => button("Add to chat").click());
  expect(dialog()).not.toBeNull();
  expect(comment().value).toBe("Why does this work?");
  expect(document.querySelector('[role="alert"]')?.textContent).toContain("Offline");
  expect(requestAddToChat).not.toHaveBeenCalled();
  await act(async () => button("Add to chat").click());
  expect(requestAddToChat).toHaveBeenCalledWith("Why does this work?", "plain", {
    sources: [{ id: "source-1", kind: "web", url: sourceDocument.sourceUrl, title: sourceDocument.title, quote: "First line\nSecond line" }],
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
  await act(async () => button("Comment").click());
  await typeComment("Draft comment");
  props = { ...props, document, selection: null };
  await render();
  expect(dialog()).toBeNull();
  expect(requestAddToChat).not.toHaveBeenCalled();
});

it("dismisses a captured comment when its owning agent changes", async () => {
  await render();
  await act(async () => button("Comment").click());
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
  expect(requestAddToChat).toHaveBeenCalledWith("First line\nSecond line", "quote", { targetSessionId: "agent-chat" });
});

it("uses Ctrl shortcuts on other platforms", async () => {
  platform.isMac = false;
  await render();
  expect(button("Comment").textContent).toContain("Ctrl");
  const commentKey = await key({ code: "KeyM", key: "m", ctrlKey: true, altKey: true });
  expect(commentKey.defaultPrevented).toBe(true);
  expect(dialog()).not.toBeNull();
  await key({ code: "Escape", key: "Escape" });
  const quoteKey = await key({ code: "KeyL", key: "l", ctrlKey: true });
  expect(quoteKey.defaultPrevented).toBe(true);
  expect(requestAddToChat).toHaveBeenCalledWith("First line\nSecond line", "quote", { targetSessionId: "agent-chat" });
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
  await act(async () => button("Quote").click());
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
  await act(async () => button("Quote").click());
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
  await act(async () => button("Quote").click());
  if (reason === "scroll") await act(async () => window.dispatchEvent(new Event("scroll")));
  props = { ...props, selection: null };
  await render();
  await act(async () => resolveSave());
  expect(requestAddToChat).not.toHaveBeenCalled();
  expect(document.querySelector('[role="alert"]')).toBeNull();
});
