// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { NotePane } from "./NotePane";
import { NOTES_CHANGED_EVENT, type Note, type NoteUpsert } from "../notes";

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke }));
vi.mock("@tauri-apps/api/webview", () => ({ getCurrentWebview: () => ({ onDragDropEvent: async () => () => {} }) }));
vi.mock("@tauri-apps/api/window", () => ({ getCurrentWindow: () => ({ isMaximized: async () => false, onResized: async () => () => {} }) }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", null, text), MarkdownSourceHighlight: ({ text }: { text: string }) => createElement("span", null, text) }));
let host: HTMLDivElement, root: Root, stored: Note;
const back = vi.fn(), close = vi.fn();
let failSave: boolean;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true); localStorage.clear(); vi.clearAllMocks();
  stored = { id: "note-a", agentId: "agent-a", title: "Thoughts", slug: "thoughts", body: "Old idea", tags: [], slugPending: false, createdAt: 1, updatedAt: 1 };
  failSave = false;
  invoke.mockImplementation(async (command: string, args?: { id?: string; note?: NoteUpsert }) => {
    if (command === "notes_get") return stored;
    if (command === "notes_upsert") {
      if (failSave) throw new Error("Disk unavailable");
      stored = { ...stored, ...args!.note!, updatedAt: 2 }; return stored;
    }
    throw new Error(command);
  });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { failSave = false; await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });
async function mount(agentId = "agent-a") {
  await act(async () => root.render(createElement(NotePane, { noteId: "note-a", agentId, recents: [], focused: true, onFocus: vi.fn(), onClose: close, onBack: back })));
}
async function editTitle() {
  await act(async () => {
    const title = host.querySelector<HTMLInputElement>('[aria-label="Note title"]')!;
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(title, "Revised thoughts");
    title.dispatchEvent(new Event("input", { bubbles: true }));
  });
}

it("saves pending edits before closing and preserves agent ownership", async () => {
  await mount(); await editTitle();
  const changed = vi.fn();
  window.addEventListener(NOTES_CHANGED_EVENT, changed);
  await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="Close"]')!.click());
  window.removeEventListener(NOTES_CHANGED_EVENT, changed);
  expect(changed).toHaveBeenCalledOnce();
  expect(stored.title).toBe("Revised thoughts");
  expect(stored.agentId).toBe("agent-a");
  expect(close).toHaveBeenCalledOnce();
});

it("keeps the editor and draft visible when saving fails before Back", async () => {
  await mount(); await editTitle(); failSave = true;
  await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="Back to notes"]')!.click());
  expect(back).not.toHaveBeenCalled();
  expect(host.querySelector('[role="alert"]')?.textContent).toContain("Disk unavailable");
  expect(host.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Revised thoughts");
  failSave = false;
  await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="Back to notes"]')!.click());
  expect(back).toHaveBeenCalledOnce();
});

it("does not open another agent's note by ID", async () => {
  await mount("agent-b");
  expect(host.querySelector('[aria-label="Note title"]')).toBeNull();
  expect(host.textContent).toContain("This note is no longer available.");
});


it("keeps an unsaved draft mounted when a background refresh cannot read the note", async () => {
  await mount(); await editTitle();
  const original = invoke.getMockImplementation()!;
  invoke.mockImplementation(async (command: string, args: unknown) => {
    if (command === "notes_get") throw new Error("Cannot read note");
    return original(command, args);
  });
  await act(async () => window.dispatchEvent(new Event(NOTES_CHANGED_EVENT)));
  expect(host.querySelector('[role="alert"]')?.textContent).toContain("Cannot read note");
  expect(host.querySelector<HTMLInputElement>('[aria-label="Note title"]')?.value).toBe("Revised thoughts");
});
