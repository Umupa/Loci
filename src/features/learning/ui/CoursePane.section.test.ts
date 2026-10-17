// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { readAgentDocument } from "../../agents/model/agentDocuments";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agentDocuments", () => ({ readAgentDocument: vi.fn(), subscribeAgentDocuments: () => () => {} }));
const highlighter = vi.hoisted(() => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "light" }));

const body = [
  "# Kubernetes architecture", "", "Introduction", "", "## 1. API server", "", "API details", "",
  "### Requests", "", "Request details", "", "## 2. etcd **MVCC**", "", "Storage details [reference][spec]. Note[^a]", "",
  "### Revisions", "", "Revision details", "", "```text", "## This is code", "```", "",
  "## 3. Scheduling", "", "Scheduling details", "", "# Appendix", "", "Appendix details", "",
  "[spec]: https://example.com/spec", "[^a]: Supporting evidence.",
].join("\n");
const doc = { id: "k8s-arch", title: "Kubernetes architecture", body, createdAt: 1, updatedAt: 1 };
const lessons = [
  { id: "api", title: "API lesson", document: doc.id, section: "1. API server" },
  { id: "etcd", title: "etcd lesson", document: doc.id, section: "2. etcd MVCC" },
  { id: "all", title: "Whole document", document: doc.id, section: "" },
  { id: "missing", title: "Missing section", document: doc.id, section: "Unknown chapter" },
];
let host: HTMLDivElement, root: Root;
let frames: Map<number, FrameRequestCallback>, frameId: number;
let scroll: ReturnType<typeof vi.spyOn>;
const flushFrames = () => act(() => { const pending = [...frames.values()]; frames.clear(); pending.forEach((callback) => callback(0)); });
const headings = () => [...host.querySelectorAll(".course-pane__reading .agent-markdown :is(h1,h2,h3)")].filter((el) => !el.closest("[data-footnotes]")).map((el) => el.textContent);
const click = async (selector: string) => { await act(async () => host.querySelector<HTMLButtonElement>(selector)!.click()); flushFrames(); };

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} });
  frameId = 0; frames = new Map();
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { frames.set(++frameId, callback); return frameId; });
  vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
  scroll = vi.spyOn(HTMLElement.prototype, "scrollIntoView").mockImplementation(() => {});
  vi.mocked(readAgentDocument).mockResolvedValue(doc);
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "course_get") return { id: "architecture", agentId: "owner", title: "Architecture", updatedAt: 1, engine: "reading", dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Architecture", lessons }] }) };
    if (command === "course_progress_get") return [];
    if (command === "course_progress_set") return;
    throw new Error(`Unexpected command: ${command}`);
  });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.restoreAllMocks(); vi.clearAllMocks(); vi.unstubAllGlobals(); });
const mount = async () => {
  await act(async () => root.render(createElement(CoursePane, { courseId: "architecture", agentId: "owner", focused: true, onFocus: () => {}, onClose: () => {} })));
  flushFrames();
};

it("switches lessons sharing a document, focuses descendants, and toggles full text at the selected heading", async () => {
  await mount();
  expect(headings()).toEqual(["1. API server", "Requests"]);
  expect(host.querySelector(".document-section-path")?.textContent).toBe("Kubernetes architecture/1. API server");
  await click('[aria-label^="etcd lesson,"]');
  expect(headings()).toEqual(["2. etcd MVCC", "Revisions"]);
  expect(host.querySelector('.agent-markdown a[href="https://example.com/spec"]')).not.toBeNull();
  expect(host.querySelector("[data-footnotes]")?.textContent).toContain("Supporting evidence.");
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("## This is code");
  expect(host.querySelector(".agent-markdown")?.textContent).not.toContain("Scheduling details");
  expect(readAgentDocument).toHaveBeenCalledTimes(1);
  await click(".document-section-toggle");
  expect(headings()).toContain("Kubernetes architecture");
  expect(headings()).toContain("3. Scheduling");
  expect(scroll).toHaveBeenLastCalledWith({ block: "center", behavior: "smooth" });
  expect(scroll.mock.contexts.at(-1)?.textContent).toBe("2. etcd MVCC");
  expect(host.querySelector("[data-section-target]")?.textContent).toBe("2. etcd MVCC");
  await click(".document-section-toggle");
  expect(headings()).toEqual(["2. etcd MVCC", "Revisions"]);
  expect(scroll).toHaveBeenLastCalledWith({ block: "start", behavior: "instant" });
  await click(".document-section-toggle");
  await click('[aria-label^="API lesson,"]');
  expect(headings()).toEqual(["1. API server", "Requests"]);
});

it("opens an empty section at the document top and explains unmatched sections", async () => {
  await mount();
  await click('[aria-label^="Whole document,"]');
  expect(headings()[0]).toBe("Kubernetes architecture");
  expect(host.querySelector(".document-section-bar")).toBeNull();
  expect(scroll).toHaveBeenLastCalledWith({ block: "start", behavior: "instant" });
  await click('[aria-label^="Missing section,"]');
  expect(headings()[0]).toBe("Kubernetes architecture");
  expect(host.querySelector('[role="status"]')?.textContent).toContain("was not found. Showing the full document.");
  expect(host.querySelector(".document-section-toggle")).toBeNull();
});

it("uses parsed headings, preferring exact formatted/Setext titles and ending at higher-level headings", () => {
  const text = "# Start\n\n## 术语扩展\n\nWrong partial\n\n术语\n---\n\nRight section\n\n### `子标题`\n\nNested\n\n# End\n\nOutside";
  host.innerHTML = renderToStaticMarkup(createElement(AgentMarkdown, { text, wholeDocument: true, section: "## 术语" }));
  expect([...host.querySelectorAll("h1,h2,h3")].map((el) => el.textContent)).toEqual(["术语", "子标题"]);
  expect(host.textContent).toContain("Right section");
  expect(host.textContent).not.toContain("Wrong partial");
  expect(host.textContent).not.toContain("Outside");
  host.innerHTML = renderToStaticMarkup(createElement(AgentMarkdown, { text, wholeDocument: true, section: "子标题" }));
  expect(host.textContent).toContain("Nested");
  expect(host.textContent).not.toContain("Right section");
  host.innerHTML = renderToStaticMarkup(createElement(AgentMarkdown, { text, wholeDocument: true, section: "End" }));
  expect(host.textContent).toContain("Outside");
  expect(host.textContent).not.toContain("Nested");
});
