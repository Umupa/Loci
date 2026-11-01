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
let progressWrites: Array<{ itemId: string; status: string }>;
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
  progressWrites = [];
  vi.mocked(readAgentDocument).mockResolvedValue(doc);
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "course_get") return { id: "architecture", agentId: "owner", title: "Architecture", updatedAt: 1, engine: "reading", dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Architecture", lessons }] }) };
    if (command === "course_progress_get") return [];
    if (command === "course_progress_set") { progressWrites.push(args as { itemId: string; status: string }); return; }
    throw new Error(`Unexpected command: ${command}`);
  });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.restoreAllMocks(); vi.clearAllMocks(); vi.unstubAllGlobals(); });
const mount = async () => {
  await act(async () => root.render(createElement(CoursePane, { courseId: "architecture", agentId: "owner", focused: true, onFocus: () => {}, onClose: () => {} })));
  flushFrames();
};

it("switches lessons sharing a document and shows only each lesson's section, without document chrome", async () => {
  await mount();
  expect(headings()).toEqual(["1. API server", "Requests"]);
  expect(host.querySelector(".document-section-bar")).toBeNull();
  expect(host.querySelector("[data-document-source]")).toBeNull();
  await click('[aria-label^="etcd lesson,"]');
  expect(headings()).toEqual(["2. etcd MVCC", "Revisions"]);
  expect(host.querySelector('.agent-markdown a[href="https://example.com/spec"]')).not.toBeNull();
  expect(host.querySelector("[data-footnotes]")?.textContent).toContain("Supporting evidence.");
  expect(host.querySelector(".agent-markdown")?.textContent).toContain("## This is code");
  expect(host.querySelector(".agent-markdown")?.textContent).not.toContain("Scheduling details");
  expect(readAgentDocument).toHaveBeenCalledTimes(1);
  await click('[aria-label^="API lesson,"]');
  expect(headings()).toEqual(["1. API server", "Requests"]);
});

it("opens an empty or unmatched section at the document top", async () => {
  await mount();
  await click('[aria-label^="Whole document,"]');
  expect(headings()[0]).toBe("Kubernetes architecture");
  expect(host.querySelector(".document-section-bar")).toBeNull();
  expect(scroll).toHaveBeenLastCalledWith({ block: "start", behavior: "instant" });
  await click('[aria-label^="Missing section,"]');
  expect(headings()[0]).toBe("Kubernetes architecture");
  expect(host.querySelector(".document-section-toggle")).toBeNull();
});

it("opens a chosen lesson at its start, not at the last lesson's offset, and ignores its settling scroll", async () => {
  await mount();
  const main = host.querySelector<HTMLElement>(".course-pane__main")!;
  main.scrollTop = 900;
  await click('[aria-label^="etcd lesson,"]');
  expect(main.scrollTop).toBe(0);
  await act(async () => { main.dispatchEvent(new Event("scroll")); });
  expect(progressWrites).toEqual([expect.objectContaining({ itemId: "etcd", status: "learning" })]);
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

it("shows a source lesson's line range as highlighted code, and a Markdown file as itself", async () => {
  const { sourceExcerpt } = await import("./CoursePane");
  const text = ["a", "b", "c", "d"].join("\n");
  expect(sourceExcerpt(text, "main.rs", [2, 3])).toBe("```rs\nb\nc\n```");
  expect(sourceExcerpt("# Title\n\nBody", "README.md")).toBe("# Title\n\nBody");
  expect(sourceExcerpt("x = '```'", "a.py", [1, 1])).toBe("````py\nx = '```'\n````");
});
