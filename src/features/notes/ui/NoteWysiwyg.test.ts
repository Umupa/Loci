// @vitest-environment happy-dom
import { act, createElement, createRef } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { NoteWysiwyg, type NoteWysiwygHandle } from "./NoteWysiwyg";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => "/tmp/x.png"), convertFileSrc: (path: string) => path }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
vi.mock("../../../platform/tauri/fs", () => ({ readBinaryFile: vi.fn(async () => new Uint8Array()) }));

let host: HTMLDivElement, root: Root;
const onChange = vi.fn();
const handle = createRef<NoteWysiwygHandle>();

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true); onChange.mockClear();
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });

async function render(value: string) {
  await act(async () => root.render(createElement(NoteWysiwyg, { value, onChange, handle })));
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
}

it("shows markdown as formatted text", async () => {
  await render("# Title\n\n* one\n* **two**");
  expect(host.querySelector("h1")?.textContent).toBe("Title");
  expect(host.querySelectorAll("li")).toHaveLength(2);
  expect(host.querySelector("strong")?.textContent).toBe("two");
});

it("never rewrites a note it only opened or reloaded", async () => {
  await render("* one\n* two");
  await render("* three\n* four");
  expect(host.textContent).toContain("three");
  expect(onChange).not.toHaveBeenCalled();
});

it("reports an edit as markdown at once", async () => {
  await render("Hello");
  await act(async () => handle.current!.insertMarkdown("**bold**"));
  expect(onChange).toHaveBeenCalledTimes(1);
  expect(onChange.mock.calls[0]![0]).toContain("**bold**");
});

it("follows a Loci link in a note, such as a saved passage, inside the app", async () => {
  const { followNoteLink } = await import("./NoteWysiwyg");
  const { APP_RESOURCE_OPEN_EVENT } = await import("../../../shared/lib/appResourceLinks");
  const opened = vi.fn();
  window.addEventListener(APP_RESOURCE_OPEN_EVENT, opened);
  expect(followNoteLink("loci://source/s-pdf#p7&quote=A%20microVM")).toBe(true);
  expect((opened.mock.calls[0][0] as CustomEvent).detail).toEqual({ kind: "source", id: "s-pdf", place: { page: 7, quote: "A microVM" } });
  expect(followNoteLink("loci://elsewhere/x")).toBe(false);
  window.removeEventListener(APP_RESOURCE_OPEN_EVENT, opened);
  await render("> A microVM\n>\n> — [Firecracker · p. 7](loci://source/s-pdf#p7&quote=A%20microVM)");
  expect(host.querySelector("a")?.textContent).toBe("Firecracker · p. 7");
  // The editor keeps the link's address for ⌘-click and writes it back as it was.
  await act(async () => handle.current!.insertMarkdown("Next"));
  expect(onChange.mock.calls[0]![0]).toContain("[Firecracker · p. 7](loci://source/s-pdf#p7\\&quote=A%20microVM)");
});
