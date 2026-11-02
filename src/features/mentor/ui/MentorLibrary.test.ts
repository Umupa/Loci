// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Agent } from "../../agents/model/agent";
import type { StoredDocument } from "../../agents/model/agentDocuments";
import { MentorLibrary } from "./MentorLibrary";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

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

it("lists the courses in the Courses segment, choosing one through the library and badging only the open one", async () => {
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { id?: string; agentId?: string };
    if (command === "course_path_read") return { path: null };
    if (command === "course_get") return { id: input.id, agentId: input.agentId, title: input.id, updatedAt: 1, engine: "reading",
      dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "One", lessons: [{ id: "l1", title: "L1", document: "d" }] }] }) };
    if (command === "course_progress_get") return [];
    throw new Error(`Unexpected command: ${command}`);
  });
  const courses = [
    { id: "kvm", agentId: agent.id, title: "1. KVM", engine: "reading" as const, itemCount: 1, masteredCount: 0, updatedAt: 2 },
    { id: "net", agentId: agent.id, title: "2. Networking", engine: "reading" as const, itemCount: 1, masteredCount: 0, updatedAt: 1 },
  ];
  await act(() => root.render(createElement(MentorLibrary, {
    agent, segment: "courses", data: { courses }, errors: {}, onRetry: () => {}, onOpen,
    onNewNote: () => {}, creatingNote: false, onOpenFile: () => {}, onChange, onDraft: () => {},
    courseBadge: (courseId, lessonId) => createElement("i", { "data-badge": `${courseId}:${lessonId ?? ""}` }),
  })));
  await vi.waitFor(() => expect(container.querySelector('[data-library-course="kvm"] [data-library-lesson="l1"]')).not.toBeNull());
  expect([...container.querySelectorAll(".library-step-title")].map((title) => title.textContent)).toEqual(["KVM", "Networking"]);
  expect([...container.querySelectorAll<HTMLElement>("[data-badge]")].map((badge) => badge.dataset.badge)).toEqual(["kvm:", "kvm:l1"]);
  await act(async () => container.querySelector<HTMLButtonElement>('[data-library-step="net"] > button')!.click());
  expect(onChange).toHaveBeenCalledWith({ course: "net" });
  await vi.waitFor(() => expect(onOpen).toHaveBeenCalledWith({ kind: "course", course: { courseId: "net", agentId: agent.id, title: "2. Networking", itemId: "l1" } }));
});
