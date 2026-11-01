// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { readAgentDocument } from "../../agents/model/agentDocuments";
import { compareView } from "../model/compareView";
import { measurePlace } from "../../mentor/ui/useReadingPlace";
import { CoursePane } from "./CoursePane";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../agents/model/agentDocuments", () => ({ readAgentDocument: vi.fn(), subscribeAgentDocuments: () => () => {} }));
const highlighter = vi.hoisted(() => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "light" }));

const pin = "a".repeat(40);
const e2b = "/m/repos/e2b-dev/runtime/orchestrator/restore.go";
const cube = "/m/repos/cube/src/restore.rs";
const then = ["package sandbox", "func Restore() {", "  load()", "}"].join("\n");
const now = ["package sandbox", "// moved", "func Restore() {", "  load()", "}"].join("\n");
const rust = ["use x;", "fn restore() {", "    resume();", "}"].join("\n");
const doc = { id: "virtio", title: "Virtio spec", body: "# Virtio\n\nIntro\n\n## Virtqueues\n\nQueues carry buffers.\n\n## Devices\n\nOther text.\n", createdAt: 1, updatedAt: 1 };
const lesson = { id: "restore", title: "Restoring a sandbox", compare: [
  { label: "E2B", file: e2b, lines: [2, 3], commit: pin, note: "Reads the snapshot before it starts the VM." },
  { label: "Cube", file: cube, lines: [2, 3] },
  { label: "Spec", document: "virtio", section: "Virtqueues" },
] };
let host: HTMLDivElement;
let root: Root;
let lessonSeen: unknown;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} });
  vi.spyOn(HTMLElement.prototype, "scrollIntoView").mockImplementation(() => {});
  vi.mocked(readAgentDocument).mockResolvedValue(doc);
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "course_get") return { id: "sandboxes", agentId: "owner", title: "Sandboxes", updatedAt: 1, engine: "reading",
      dataJson: JSON.stringify({ engine: "reading", chapters: [{ title: "Lifecycle", lessons: [lesson] }] }) };
    if (command === "course_progress_get") return [];
    if (command === "course_progress_set") return;
    if (command === "code_pin_status") return { state: "changed", commit: pin, head: "b".repeat(40), ahead: 2, currentLines: [3, 4], exact: true };
    if (command === "code_read") return { text: then, commit: (args as { commit: string }).commit, repoRoot: "/m/repos/e2b-dev/runtime", pathInRepo: "orchestrator/restore.go" };
    if (command === "read_text_file") return (args as { path: string }).path === cube ? rust : now;
    if (command === "learning_annotations_for") return [];
    throw new Error(`Unexpected command: ${command}`);
  });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  vi.clearAllMocks();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

const render = async () => {
  await act(async () => root.render(createElement(CoursePane, { courseId: "sandboxes", agentId: "owner", focused: true, onFocus: () => {}, onClose: () => {}, reader: true,
    onLessonChange: (seen) => { lessonSeen = seen; } })));
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 30)); });
};
const parts = () => [...host.querySelectorAll<HTMLElement>("[data-compare-part]")];
const where = (part: HTMLElement) => part.querySelector(".course-compare__where")?.textContent;

it("stacks three parts on one page: one pinned at an old commit, one current, one a source section", async () => {
  await render();
  expect(host.querySelector("h2")?.textContent).toBe("Restoring a sandbox");
  expect([...host.querySelectorAll(".course-compare__jump-item")].map((item) => item.textContent)).toEqual(["E2B", "Cube", "Spec"]);
  const [first, second, third] = parts();
  expect(parts().map((part) => part.dataset.comparePart)).toEqual(["E2B", "Cube", "Spec"]);

  // The pinned part reads at its commit, says the file changed, and numbers its lines.
  expect(where(first)).toBe("e2b-dev/runtime@aaaaaaaorchestrator/restore.go:2–3");
  expect(first.querySelector("pre")?.textContent).toBe("func Restore() {\n  load()");
  expect(first.querySelector("[data-reading-lines-from]")?.getAttribute("data-reading-lines-from")).toBe("2");
  expect(first.querySelector(".course-pane__pin")?.textContent).toContain("Showing it as it was at aaaaaaa");
  expect(first.querySelector("[data-compare-note]")?.textContent).toBe("Mentor's noteReads the snapshot before it starts the VM.");
  expect(first.querySelector(".course-compare__actions button")?.textContent).toBe("Open whole file");

  // The current part reads the working tree.
  expect(where(second)).toBe("cube/src/restore.rs:2–3");
  expect(second.querySelector("pre")?.textContent).toBe("fn restore() {\n    resume();");
  expect(second.querySelector(".course-pane__pin")).toBeNull();

  // The source part shows only its section.
  expect(where(third)).toBe("Virtio spec§ Virtqueues");
  expect(third.textContent).toContain("Queues carry buffers.");
  expect(third.textContent).not.toContain("Other text.");

  // reader show reads which parts are shown, and at which commit.
  expect(compareView("owner")).toEqual({ courseId: "sandboxes", lessonId: "restore", parts: [
    { label: "E2B", collapsed: false, file: e2b, commit: pin, lines: [2, 3], pin: "changed" },
    { label: "Cube", collapsed: false, file: cube, lines: [2, 3] },
    { label: "Spec", collapsed: false, document: "virtio", section: "Virtqueues" },
  ] });
  // The conversation is told the parts (without the notes).
  expect(lessonSeen).toEqual({ id: "restore", title: "Restoring a sandbox", compare: [
    { label: "E2B", file: e2b, lines: [2, 3], commit: pin }, { label: "Cube", file: cube, lines: [2, 3] }, { label: "Spec", document: "virtio", section: "Virtqueues" },
  ] });
});

it("folds a part, opens current in one part only, and jumps to a folded part", async () => {
  await render();
  const toggle = () => parts()[1].querySelector<HTMLButtonElement>(".course-compare__toggle")!;
  await act(async () => toggle().click());
  expect(toggle().getAttribute("aria-expanded")).toBe("false");
  expect(parts()[1].querySelector<HTMLElement>(`#${CSS.escape(toggle().getAttribute("aria-controls")!)}`)?.hidden).toBe(true);
  expect(compareView("owner")?.parts[1].collapsed).toBe(true);

  await act(async () => parts()[0].querySelector<HTMLButtonElement>(".course-pane__pin button")!.click());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(parts()[0].querySelector("pre")?.textContent).toBe("func Restore() {\n  load()");
  expect(where(parts()[0])).toBe("e2b-dev/runtimeorchestrator/restore.go:3–4");
  expect(compareView("owner")?.parts[0]).toMatchObject({ lines: [3, 4] });
  expect(compareView("owner")?.parts[0].commit).toBeUndefined();

  await act(async () => host.querySelectorAll<HTMLButtonElement>(".course-compare__jump-item")[1].click());
  expect(toggle().getAttribute("aria-expanded")).toBe("true");
  expect(HTMLElement.prototype.scrollIntoView).toHaveBeenCalled();
});

it("names the part in view as the reading place", async () => {
  await render();
  const [first, second] = parts();
  const box = (top: number, bottom: number) => ({ top, bottom, left: 0, right: 600, width: 600, height: bottom - top, x: 0, y: top, toJSON: () => ({}) }) as DOMRect;
  const main = host.querySelector<HTMLElement>(".course-pane__main")!;
  vi.spyOn(main, "getBoundingClientRect").mockReturnValue(box(0, 500));
  vi.spyOn(first, "getBoundingClientRect").mockReturnValue(box(-400, 10));
  vi.spyOn(second, "getBoundingClientRect").mockReturnValue(box(10, 300));
  expect(measurePlace(main).part).toBe("Cube");
});

it("closes the comparison's report when the lesson leaves", async () => {
  await render();
  expect(compareView("owner")).toBeDefined();
  await act(async () => root.render(createElement("div")));
  expect(compareView("owner")).toBeUndefined();
});
