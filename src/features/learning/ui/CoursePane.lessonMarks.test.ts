// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Annotation } from "../model/types";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
const highlighter = vi.hoisted(() => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "light" }));

const file = "/src/main.rs";
const text = ["fn main() {", "    let a = 1;", "    let b = 2;", "    let c = 3;", "}", "", "// far below", "fn other() {}"].join("\n");
const lesson = { id: "tour", title: "The entry point", file, lines: [2, 4] as [number, number] };
const at = (id: string, lines: [number, number], quote: string): Annotation => ({
  id, documentId: "", target: { kind: "file", path: file },
  anchor: { exact: quote, prefix: "", suffix: "", start: 0, end: quote.length, lines },
  source: { id: `source-${id}`, kind: "file", path: file, title: "main.rs", quote, lines, anchor: { exact: quote, prefix: "", suffix: "", start: 0, end: quote.length, lines } },
  anchors: [], note: "", discussions: [], createdAt: 1, updatedAt: 1,
});
const marks = [at("inside", [2, 3], "let a = 1;"), at("outside", [7, 8], "fn other() {}")];
let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} });
  vi.mocked(invoke).mockImplementation(async (command) => {
    if (command === "course_get") return { id: "tour-course", agentId: "owner", title: "A code tour", updatedAt: 1, engine: "reading",
      dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Tour", lessons: [lesson] }] }) };
    if (command === "course_progress_get") return [];
    if (command === "course_progress_set") return;
    if (command === "read_text_file") return text;
    if (command === "learning_annotations_for") return marks;
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

it("counts and lists only the highlights inside the lesson's lines", async () => {
  await act(async () => root.render(createElement(CoursePane, { courseId: "tour-course", agentId: "owner", focused: true, onFocus: () => {}, onClose: () => {}, reader: true })));
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
  const actions = host.querySelector<HTMLButtonElement>('button[aria-label="Lesson actions"]')!;
  await act(async () => actions.click());
  const item = () => [...document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')].find((entry) => entry.textContent?.startsWith("Highlights & notes"))!;
  expect(item().querySelector(".lesson-menu__label")?.textContent).toBe("Highlights & notes");
  expect(item().querySelector(".lesson-menu__meta")?.textContent).toBe("1");
  await act(async () => item().click());
  const listed = [...document.querySelectorAll<HTMLButtonElement>(".pdf-annotations__entry")];
  expect(listed).toHaveLength(1);
  expect(listed[0].textContent).toContain("let a = 1;");
  expect(listed[0].textContent).not.toContain("fn other() {}");
});
