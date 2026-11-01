// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TranscriptSelectionMenu } from "./TranscriptSelectionMenu";

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  localStorage.clear();
  localStorage.setItem("loci.noteTarget.global", JSON.stringify({ kind: "new" }));
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

describe("TranscriptSelectionMenu", () => {
  it("keeps selected text available when saving a note fails", async () => {
    let rejectSave!: (reason: Error) => void;
    const onDismiss = vi.fn();
    const onAddToNotes = vi.fn(
      () =>
        new Promise<void>((_resolve, reject) => {
          rejectSave = reject;
        }),
    );
    act(() =>
      root.render(
        createElement(TranscriptSelectionMenu, {
          selection: { text: "Keep this", rect: new DOMRect(10, 20, 100, 20) },
          onAddToNotes,
          onDismiss,
        }),
      ),
    );
    const button = document.querySelector<HTMLButtonElement>(
      '[role="toolbar"] button',
    )!;
    await act(async () => button.click());
    expect(onDismiss).not.toHaveBeenCalled();
    expect(button.disabled).toBe(true);
    await act(async () => rejectSave(new Error("Disk full")));
    expect(document.querySelector('[role="alert"]')?.textContent).toContain(
      "Disk full",
    );
    expect(button.disabled).toBe(false);
    onAddToNotes.mockResolvedValue();
    await act(async () => button.click());
    expect(onDismiss).toHaveBeenCalledOnce();
  });

  it("names the action that failed", async () => {
    const onAddToChat = vi.fn(() => Promise.reject(new Error("No session")));
    act(() =>
      root.render(
        createElement(TranscriptSelectionMenu, {
          selection: { text: "A useful link", rect: new DOMRect(10, 20, 100, 20) },
          onAddToChat,
          onDismiss: vi.fn(),
        }),
      ),
    );
    const button = document.querySelector<HTMLButtonElement>('[role="toolbar"] button')!;
    await act(async () => button.click());
    const alert = document.querySelector('[role="alert"]')?.textContent;
    expect(alert).toContain("Could not add to chat");
    expect(alert).not.toContain("note");
    expect(alert).toContain("No session");
  });

  it("offers the selected text to both chat and notes", async () => {
    const onAddToChat = vi.fn();
    const onAddToNotes = vi.fn();
    const onDismiss = vi.fn();
    act(() =>
      root.render(
        createElement(TranscriptSelectionMenu, {
          selection: {
            text: "A useful link",
            rect: new DOMRect(10, 20, 100, 20),
          },
          onAddToChat,
          onAddToNotes,
          onDismiss,
        }),
      ),
    );

    const toolbar = document.querySelector(
      '[role="toolbar"][aria-label="Selected text actions"]',
    );
    expect(toolbar?.textContent).toContain("Add to chat");
    expect(toolbar?.textContent).toContain("Add to a new note");

    const notes = Array.from(toolbar?.querySelectorAll("button") ?? []).find(
      (button) => button.textContent?.includes("Add to a new note"),
    );
    await act(async () => notes?.click());

    expect(onAddToNotes).toHaveBeenCalledWith("A useful link", { kind: "new" });
    expect(onAddToChat).not.toHaveBeenCalled();
    expect(onDismiss).toHaveBeenCalledOnce();
  });

  const notes = [
    { id: "n-old", slug: "old", title: "Old reading", body: "", tags: [], slugPending: false, createdAt: 1, updatedAt: 1 },
    { id: "n-new", slug: "new", title: "Kernel notes", body: "", tags: [], slugPending: false, createdAt: 2, updatedAt: 5 },
  ];
  const buttonNamed = (text: string) => Array.from(document.querySelectorAll<HTMLButtonElement>('[role="toolbar"] button')).find((button) => button.textContent?.includes(text));
  async function show(onAddToNotes: ReturnType<typeof vi.fn>, onDismiss = vi.fn()) {
    await act(async () => root.render(createElement(TranscriptSelectionMenu, {
      selection: { text: "mmap is lazy", rect: new DOMRect(10, 20, 100, 20) },
      onAddToNotes, listNotes: async () => notes, onDismiss,
    })));
  }

  it("asks the first time whether to start a note or add to one", async () => {
    localStorage.clear();
    const onAddToNotes = vi.fn(async () => notes[1]);
    const onDismiss = vi.fn();
    await show(onAddToNotes, onDismiss);
    await act(async () => buttonNamed("Add to notes…")!.click());
    expect(onAddToNotes).not.toHaveBeenCalled();
    const items = [...document.querySelectorAll('[role="menuitem"]')].map((item) => item.textContent);
    expect(items).toEqual(["New note", "Kernel notes", "Old reading"]);
    await act(async () => buttonNamed("Kernel notes")!.click());
    expect(onAddToNotes).toHaveBeenCalledWith("mmap is lazy", { kind: "note", id: "n-new", title: "Kernel notes" });
    expect(onDismiss).toHaveBeenCalledOnce();
    expect(JSON.parse(localStorage.getItem("loci.noteTarget.global")!)).toEqual({ kind: "note", id: "n-new", title: "Kernel notes" });
  });

  it("goes to the last note chosen, and can be pointed at another", async () => {
    localStorage.setItem("loci.noteTarget.global", JSON.stringify({ kind: "note", id: "n-new", title: "Kernel notes" }));
    const onAddToNotes = vi.fn(async () => undefined);
    await show(onAddToNotes);
    await act(async () => buttonNamed("Add to “Kernel notes”")!.click());
    expect(onAddToNotes).toHaveBeenLastCalledWith("mmap is lazy", { kind: "note", id: "n-new", title: "Kernel notes" });

    await show(onAddToNotes);
    await act(async () => document.querySelector<HTMLButtonElement>('[aria-label="Choose another note"]')!.click());
    await act(async () => buttonNamed("New note")!.click());
    expect(onAddToNotes).toHaveBeenLastCalledWith("mmap is lazy", { kind: "new" });
    expect(JSON.parse(localStorage.getItem("loci.noteTarget.global")!)).toEqual({ kind: "new" });
  });
});
