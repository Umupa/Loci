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

it("reads a pinned lesson at its commit, says the file changed, and opens the current lines", async () => {
  await render();
  expect(code()).toBe("func A() {}\nfunc B() {}");
  expect(host.querySelector(".course-pane__summary")?.textContent).toBe("main.go · lines 2–3 · @aaaaaaa");
  const notice = host.querySelector(".course-pane__pin")!;
  expect(notice.textContent).toContain("changed since. Showing it as it was at aaaaaaa.");
  await act(async () => notice.querySelector("button")!.click());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(code()).toBe("func A() {}\nfunc B() {}");
  expect(host.querySelector(".course-pane__summary")?.textContent).toBe("main.go · lines 3–4");
  expect(host.querySelector(".course-pane__pin")?.textContent).toContain("as it is now (HEAD bbbbbbb), lines 3–4");
  await act(async () => host.querySelector<HTMLButtonElement>(".course-pane__pin button")!.click());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(host.querySelector(".course-pane__summary")?.textContent).toBe("main.go · lines 2–3 · @aaaaaaa");
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
