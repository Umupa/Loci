// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const highlighter = vi.hoisted(() => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "light" }));

const file = "/m/repos/e2b/envd/main.go";
const pin = "a".repeat(40);
const then = ["package main", "func A() {}", "func B() {}", "func C() {}"].join("\n");
const now = ["package main", "// new", "func A() {}", "func B() {}", "func C() {}"].join("\n");
let status: Record<string, unknown>;
let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} });
  status = { state: "changed", commit: pin, head: "b".repeat(40), ahead: 3, currentLines: [3, 4], exact: true };
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "course_get") return { id: "tour", agentId: "owner", title: "Tour", updatedAt: 1, engine: "reading",
      dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Tour", lessons: [{ id: "a", title: "A and B", file, lines: [2, 3], commit: pin }] }] }) };
    if (command === "course_progress_get") return [];
    if (command === "course_progress_set") return;
    if (command === "code_pin_status") return status;
    if (command === "code_read") return { text: then, commit: (args as { commit: string }).commit };
    if (command === "read_text_file") return now;
    if (command === "learning_annotations_for") return [];
    throw new Error(`Unexpected command: ${command}`);
  });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

const render = async () => {
  await act(async () => root.render(createElement(CoursePane, { courseId: "tour", agentId: "owner", focused: true, onFocus: () => {}, onClose: () => {}, reader: true })));
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
};
const code = () => host.querySelector("pre")?.textContent;
const summary = () => host.querySelector(".course-pane__summary")?.textContent?.replace("Open whole file", "");

it("reads a pinned lesson at its commit, says the file changed, and opens the current lines", async () => {
  await render();
  expect(code()).toBe("func A() {}\nfunc B() {}");
  expect(summary()).toBe("main.go · lines 2–3 · @aaaaaaa");
  expect(host.querySelector(".course-pane__summary button")?.textContent).toBe("Open whole file");
  const notice = host.querySelector(".course-pane__pin")!;
  expect(notice.textContent).toContain("changed since. Showing it as it was at aaaaaaa.");
  await act(async () => notice.querySelector("button")!.click());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(code()).toBe("func A() {}\nfunc B() {}");
  expect(summary()).toBe("main.go · lines 3–4");
  expect(host.querySelector(".course-pane__pin")?.textContent).toContain("as it is now (HEAD bbbbbbb), lines 3–4");
  await act(async () => host.querySelector<HTMLButtonElement>(".course-pane__pin button")!.click());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(summary()).toBe("main.go · lines 2–3 · @aaaaaaa");
});

it("opens a definition from the excerpt in place of the lesson, at its commit", async () => {
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "code_definition") return { name: "B", definitions: [{ file: "/m/repos/e2b/envd/b.go", pathInRepo: "envd/b.go", line: 7, column: 6, kind: "function", preview: "func B() {}" }] };
    if (command === "course_get") return { id: "tour", agentId: "owner", title: "Tour", updatedAt: 1, engine: "reading",
      dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Tour", lessons: [{ id: "a", title: "A and B", file, lines: [2, 3], commit: pin }] }] }) };
    if (command === "course_progress_get" || command === "learning_annotations_for") return [];
    if (command === "code_pin_status") return status;
    if (command === "code_read") return { text: then, commit: (args as { commit: string }).commit };
    return undefined;
  });
  const opened = vi.fn();
  window.addEventListener("loci:open-file", opened);
  await render();
  const pre = host.querySelector("pre")!;
  // ⌘-click "B" in "func B() {}", the excerpt's second line (file line 3).
  const textNode = (() => { const walker = document.createTreeWalker(pre, NodeFilter.SHOW_TEXT); let node; let seen = ""; while ((node = walker.nextNode())) { if (seen.length + node.textContent!.length > "func A() {}\nfunc B".length - 1) return { node, offset: "func A() {}\nfunc B".length - 1 - seen.length }; seen += node.textContent; } throw new Error("no text"); })();
  vi.stubGlobal("document", Object.assign(document, { caretRangeFromPoint: () => { const range = document.createRange(); range.setStart(textNode.node, textNode.offset); return range; } }));
  await act(async () => { pre.dispatchEvent(new MouseEvent("click", { bubbles: true, metaKey: true, ctrlKey: true, clientX: 5, clientY: 5 })); });
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(vi.mocked(invoke)).toHaveBeenCalledWith("code_definition", { query: { file, line: 3, column: 6, commit: pin } });
  expect(opened).toHaveBeenCalledTimes(1);
  expect((opened.mock.calls[0][0] as CustomEvent).detail).toEqual({ path: "/m/repos/e2b/envd/b.go", commit: pin, fromLine: 3 });
  window.removeEventListener("loci:open-file", opened);
});

it("shows the working tree when the clone lacks the commit", async () => {
  status = { state: "missing-commit", head: "b".repeat(40) };
  await render();
  expect(host.querySelector(".course-pane__pin")?.textContent).toContain("is not in this clone");
  expect(code()).toBe("// new\nfunc A() {}");
  expect(vi.mocked(invoke).mock.calls.some(([command]) => command === "code_read")).toBe(false);
});

it("says nothing more than a quiet line when only HEAD moved", async () => {
  status = { state: "moved", commit: pin, head: "b".repeat(40), ahead: 1 };
  await render();
  expect(host.querySelector(".course-pane__pin")?.textContent).toBe("HEAD (bbbbbbb) is 1 commit past this lesson's commit; main.go is unchanged.");
  expect(host.querySelector(".course-pane__pin button")).toBeNull();
});
