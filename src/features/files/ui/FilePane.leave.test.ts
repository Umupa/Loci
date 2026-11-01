// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { readTextFile } from "../../../platform/tauri/fs";
import { getFileDraft } from "../model/fileDrafts";
import { FilePane } from "./FilePane";

vi.mock("../../../platform/tauri/fs", () => ({
  basename: (path: string) => path.split("/").pop(), readTextFile: vi.fn(), writeTextFile: vi.fn(),
  readBinaryFile: vi.fn(), readDocumentFile: vi.fn(), openPathWithDefaultApp: vi.fn(), revealPath: vi.fn(),
}));
vi.mock("../model/fileWatch", () => ({ watchFile: () => () => {}, syncWatchedMtime: vi.fn() }));
vi.mock("../../learning/model/learningStore", () => ({
  getReadingDocumentByPath: vi.fn(), registerReadingDocument: vi.fn(), relocateReadingDocument: vi.fn(),
  listPdfAnnotations: vi.fn(async () => []), registerLearningSource: vi.fn(), upsertPdfAnnotation: vi.fn(),
  deletePdfAnnotation: vi.fn(), listAnnotations: vi.fn(async () => []), upsertAnnotation: vi.fn(),
  deleteAnnotation: vi.fn(), subscribeLearningChanges: () => () => {},
}));
vi.mock("../../sessions/ui/MarkdownDocumentPreview", () => ({ MarkdownDocumentPreview: ({ text }: { text: string }) => createElement("div", null, text) }));

const path = "/notes/plan.md";
let host: HTMLDivElement;
let root: Root;
let registered: (() => Promise<boolean>) | null;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.mocked(readTextFile).mockResolvedValue("# Plan\n\nThe original text.");
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

async function show() {
  registered = null;
  await act(async () => root.render(createElement(FilePane, {
    path, cwd: "/", preview: false, focused: true, onFocus: vi.fn(), onPin: vi.fn(), onClose: vi.fn(), onOpenFile: vi.fn(),
    onBeforeLeave: (guard: (() => Promise<boolean>) | null) => { registered = guard; },
  })));
}

/** Types into the source editor, which keeps the edit as a draft. */
async function edit() {
  await act(async () => [...host.querySelectorAll<HTMLButtonElement>('[role="tab"]')].find((tab) => tab.textContent === "Source")!.click());
  const editor = host.querySelector<HTMLTextAreaElement>(`[aria-label="Edit plan.md"]`)!;
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")!.set!.call(editor, "# Plan\n\nMy rewrite.");
    editor.dispatchEvent(new Event("input", { bubbles: true }));
  });
}

it("registers a leave guard that asks before discarding unsaved edits", async () => {
  const confirm = vi.fn(() => false);
  vi.stubGlobal("confirm", confirm);
  await show();
  await edit();
  expect(getFileDraft(path)).not.toBeNull();
  expect(registered).not.toBeNull();
  const leave = async () => {
    let allowed = false;
    await act(async () => { allowed = await registered!(); });
    return allowed;
  };
  expect(await leave()).toBe(false);
  expect(confirm).toHaveBeenCalledWith("Leave “plan.md” and discard its unsaved changes?");
  expect(getFileDraft(path)).not.toBeNull();
  confirm.mockReturnValueOnce(true);
  expect(await leave()).toBe(true);
  expect(getFileDraft(path)).toBeNull();
});

it("leaves without asking when nothing was edited, and unregisters on unmount", async () => {
  const confirm = vi.fn(() => true);
  vi.stubGlobal("confirm", confirm);
  await show();
  let allowed = false;
  await act(async () => { allowed = await registered!(); });
  expect(allowed).toBe(true);
  expect(confirm).not.toHaveBeenCalled();
  await act(async () => root.unmount());
  expect(registered).toBeNull();
  root = createRoot(host);
});
