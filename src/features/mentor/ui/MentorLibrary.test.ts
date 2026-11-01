// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { Agent } from "../../agents/model/agent";
import type { StoredDocument } from "../../agents/model/agentDocuments";
import { MentorLibrary } from "./MentorLibrary";

let container: HTMLDivElement;
let root: Root;
const onOpen = vi.fn();
const onChange = vi.fn();
const agent: Agent = { id: "a1", avatar: "nova", color: "blue", projects: [] };

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
  onOpen.mockClear();
  onChange.mockClear();
});

const render = (documents: StoredDocument[]) => act(() => root.render(createElement(MentorLibrary, {
  agent, segment: "sources", data: { documents }, errors: {}, onRetry: () => {}, onOpen,
  onNewNote: () => {}, creatingNote: false, onOpenFile: () => {}, onChange, onDraft: () => {},
})));

it("lists a PDF source with a PDF icon and its page count, and opens the PDF reader", async () => {
  await render([{
    id: "firecracker", title: "Firecracker: Lightweight Virtualization", subject: "Virtualization",
    kind: "source", sourceUrl: "https://www.usenix.org/system/files/nsdi20-paper-agache.pdf",
    pdf: { path: "/home/u/Loci/paper-reader/sources/firecracker.pdf", pages: 15 },
    createdAt: 1, updatedAt: 1,
  }]);
  const row = container.querySelector<HTMLElement>("[data-resource-id='firecracker']")!;
  expect(row.textContent).toContain("PDF · 15 pages");
  expect(row.textContent).toContain("usenix.org");
  expect(row.querySelector(".mentor-library-icon")?.innerHTML).not.toBe("");
  act(() => row.click());
  expect(onOpen).toHaveBeenCalledWith({ kind: "file", path: "/home/u/Loci/paper-reader/sources/firecracker.pdf" });
  // Opening a PDF keeps the Sources segment instead of falling back to Files.
  expect(onChange).toHaveBeenCalledWith({ segment: "sources" });
});

it("still opens a Markdown source in the document reader", async () => {
  await render([{ id: "kvm", title: "KVM API", kind: "source", sourceUrl: "https://k.org/api", createdAt: 1, updatedAt: 1 }]);
  act(() => container.querySelector<HTMLElement>("[data-resource-id='kvm']")!.click());
  expect(onOpen).toHaveBeenCalledWith({ kind: "document", document: { id: "kvm", title: "KVM API", body: "" } });
});
