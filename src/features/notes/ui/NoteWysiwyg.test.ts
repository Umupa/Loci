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
