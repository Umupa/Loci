// @vitest-environment happy-dom
import { webcrypto } from "node:crypto";
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { copyText } from "../../../platform/tauri/clipboard";
import { findAgent } from "../../agents/model/agent";
import { setConceptStatus } from "../../canvas/concepts";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { NAVIGATE_CONCEPT_EVENT, OPEN_COURSE_EVENT, openCourse, type LearningStatus, type ParsedCourse } from "../model/course";
import { readAgentDocument } from "../../agents/model/agentDocuments";
import { requestOpenFile } from "../../files/model/filePlace";
import { CourseHostContext } from "../model/courseContext";
import { CourseCard } from "./CourseCard";
import { CoursePane } from "./CoursePane";
import { computeLineDiff, DiffCard } from "./DiffCard";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../../platform/tauri/clipboard", () => ({ copyText: vi.fn() }));
vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../canvas/concepts", () => ({ setConceptStatus: vi.fn() }));
vi.mock("../../sessions/model/quoteDraft", () => ({ requestAddToChat: vi.fn() }));
vi.mock("../../sessions/ui/AgentMarkdown", () => ({ AgentMarkdown: ({ text }: { text: string }) => createElement("div", { "data-markdown": true }, text) }));
const highlighter = vi.hoisted(() => ({ highlight: vi.fn(() => null), getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));
vi.mock("../../agents/model/agentDocuments", () => ({ readAgentDocument: vi.fn(), subscribeAgentDocuments: () => () => undefined }));
vi.mock("../../files/model/filePlace", () => ({ requestOpenFile: vi.fn() }));
vi.mock("../../agents/ui/DocumentBody", () => ({
  shownDocument: (stored: object) => stored,
  DocumentBody: ({ document, section }: { document: { body: string; sourceUrl?: string }; section?: string }) => createElement("div", { "data-reading": section ?? "", "data-source": document.sourceUrl ?? "" }, document.body),
}));

const makeStep = (id: string) => ({ id, title: `Step ${id}`, summary: `Build ${id}`, file: "main.py", before: "", after: "run()\n\n", explanation: `Explanation ${id}`, runCommand: "python main.py" });
const build: ParsedCourse = { id: "build", title: "Build an Agent", engine: "build-your-own", data: { engine: "build-your-own", steps: [makeStep("s01"), makeStep("s02"), makeStep("s03")] } };
const domain: ParsedCourse = { id: "domain", title: "Kubernetes", engine: "reading", canvasId: "canvas-a", data: { engine: "reading", canvasId: "canvas-a", chapters: [
  { title: "Workloads", lessons: [{ id: "container", title: "Container", document: "doc-container" }, { id: "pod", title: "Pod", document: "doc-pod", section: "Pod phase" }] },
  { title: "Papers", lessons: [{ id: "borg", title: "Borg", file: "/books/borg.pdf", pages: [3, 9] }] },
] } };
const source = (course: ParsedCourse) => `---\nid: ${course.id}\ntitle: ${course.title}\nengine: ${course.engine}\n${course.canvasId ? `canvas-id: ${course.canvasId}\n` : ""}---\n${JSON.stringify(course.data)}\n`;
const key = (owner: string, id: string) => JSON.stringify([owner, id]);
const courses = new Map<string, unknown>();
const progress = new Map<string, Map<string, LearningStatus>>();
let container: HTMLDivElement, root: Root;
const deferred = <T,>() => {
  let resolve!: (value: T) => void, reject!: (cause: unknown) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const stored = (course: ParsedCourse, agentId = "owner") => ({ id: course.id, agentId, title: course.title, updatedAt: 42, engine: course.engine, dataJson: JSON.stringify(course.data) });
const command = async (name: string, args: any): Promise<any> => {
  if (name === "course_get") return courses.get(key(args.agentId, args.id)) ?? null;
  if (name === "course_progress_get") return [...(progress.get(key(args.agentId, args.courseId)) ?? new Map()).entries()].map(([itemId, status]) => ({ itemId, status }));
  if (name === "course_upsert") { courses.set(key(args.course.agentId, args.course.id), args.course); return args.course; }
  if (name === "course_progress_set") {
    const scope = key(args.agentId, args.courseId), next = progress.get(scope) ?? new Map();
    next.set(args.itemId, args.status); progress.set(scope, next); return;
  }
  throw new Error(`Unexpected invoke: ${name}`);
};
const pane = (courseId = "build", agentId = "owner") => createElement(CoursePane, { courseId, agentId, sourceSessionId: "original-chat", focused: true, onFocus: vi.fn(), onClose: vi.fn() });
const button = (label: string) => [...container.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent === label || (label === "Open Course" && item.getAttribute("aria-label")?.startsWith("Open course ")))!;
const nav = (title: string) => [...container.querySelectorAll<HTMLButtonElement>("nav button")].find((item) => item.textContent?.endsWith(title))!;
const navigate = (detail: object) => act(() => window.dispatchEvent(new CustomEvent(NAVIGATE_CONCEPT_EVENT, { detail })));

beforeEach(() => {
  vi.clearAllMocks(); courses.clear(); progress.clear();
  courses.set(key("owner", "build"), stored(build)); courses.set(key("owner", "domain"), stored(domain));
  vi.mocked(invoke).mockImplementation(command);
  vi.mocked(copyText).mockResolvedValue(undefined);
  vi.mocked(setConceptStatus).mockResolvedValue(undefined);
  vi.mocked(findAgent).mockReturnValue(undefined);
  vi.mocked(readAgentDocument).mockImplementation(async (_agent, id) => id === "doc-missing" ? undefined : { id, title: id, body: `${id} text`, sourceUrl: `https://kubernetes.io/${id}`, createdAt: 1, updatedAt: 1 });
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true); vi.stubGlobal("crypto", webcrypto);
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("streams into a complete card without changing hook order and persists full scoped course before opening", async () => {
  const opened = vi.fn(); window.addEventListener(OPEN_COURSE_EVENT, opened);
  const card = (incomplete: boolean) => createElement(CourseHostContext.Provider, { value: { agentId: "owner", sourceSessionId: "original-chat" } }, createElement(CourseCard, { source: source(domain), incomplete }));
  try {
    await act(async () => root.render(card(true))); expect(container.textContent).toContain("3 items so far"); expect(invoke).not.toHaveBeenCalled();
    await act(async () => root.render(card(false))); expect(button("Open Course").title).toBe("2 chapters · 3 lessons");
    await act(async () => button("Open Course").click());
    const payload = vi.mocked(invoke).mock.calls[0][1] as { course: { agentId: string; dataJson: string } };
    expect(payload.course.agentId).toBe("owner"); expect(JSON.parse(payload.course.dataJson)).toEqual(domain.data);
    expect(opened.mock.calls[0][0].detail).toEqual({ courseId: "domain", agentId: "owner", title: "Kubernetes", sourceSessionId: "original-chat" });
  } finally { window.removeEventListener(OPEN_COURSE_EVENT, opened); }
});

it("shows an upsert error and keeps a failed course closed", async () => {
  vi.mocked(invoke).mockRejectedValueOnce(new Error("disk full"));
  const opened = vi.fn(); window.addEventListener(OPEN_COURSE_EVENT, opened);
  try {
    await act(async () => root.render(createElement(CourseHostContext.Provider, { value: { agentId: "owner", sourceSessionId: "original-chat" } }, createElement(CourseCard, { source: source(build), incomplete: false }))));
    await act(async () => button("Open Course").click()); expect(container.querySelector('[role="alert"]')?.textContent).toContain("disk full"); expect(opened).not.toHaveBeenCalled(); expect(button("Open Course").disabled).toBe(false);
  } finally { window.removeEventListener(OPEN_COURSE_EVENT, opened); }
});

it("previews a course in an ordinary conversation without saving it", async () => {
  await act(async () => root.render(createElement(CourseHostContext.Provider, { value: { sourceSessionId: "chat" } }, createElement(CourseCard, { source: source(build), incomplete: false }))));
  expect(button("Open Course").disabled).toBe(true);
  expect(container.textContent).toContain("Courses belong to an agent");
  expect(invoke).not.toHaveBeenCalledWith("course_upsert", expect.anything());
});

it("opens a course the agent saved from a fence without a body", async () => {
  courses.set(key("owner", "build"), { id: "build", agentId: "owner", engine: "build-your-own", title: build.title, dataJson: JSON.stringify(build.data), createdAt: 1, updatedAt: 1 });
  const opened = vi.fn(); window.addEventListener(OPEN_COURSE_EVENT, opened);
  try {
    await act(async () => root.render(createElement(CourseHostContext.Provider, { value: { agentId: "owner", sourceSessionId: "agent-chat" } }, createElement(CourseCard, { source: "---\nid: build\ntitle: Linked\n---\n", incomplete: false }))));
    expect(container.textContent).toContain(`${build.title}`);
    expect(button("Open Course").title).toBe("3 steps");
    await act(async () => button("Open Course").click());
    expect(invoke).not.toHaveBeenCalledWith("course_upsert", expect.anything());
    expect(opened.mock.calls[0][0].detail).toMatchObject({ courseId: "build", agentId: "owner", sourceSessionId: "agent-chat" });
  } finally { window.removeEventListener(OPEN_COURSE_EVENT, opened); }
});

it("does not open a previous card's course after its source changes during persistence", async () => {
  const write = deferred<unknown>(); vi.mocked(invoke).mockReturnValueOnce(write.promise);
  const opened = vi.fn(); window.addEventListener(OPEN_COURSE_EVENT, opened);
  const card = (course: ParsedCourse) => createElement(CourseHostContext.Provider, { value: { agentId: "owner", sourceSessionId: "original-chat" } }, createElement(CourseCard, { source: source(course), incomplete: false }));
  try {
    await act(async () => root.render(card(build))); act(() => button("Open Course").click()); await act(async () => root.render(card(domain)));
    await act(async () => write.resolve({})); expect(opened).not.toHaveBeenCalled(); expect(container.textContent).toContain("Kubernetes");
  } finally { window.removeEventListener(OPEN_COURSE_EVENT, opened); }
});

it("opens the first unmastered step, saves progress, and recovers it after remounting", async () => {
  progress.set(key("owner", "build"), new Map([["s01", "mastered"]]));
  await act(async () => root.render(pane())); expect(nav("Step s02").getAttribute("aria-current")).toBe("step"); expect(container.textContent).toContain("Explanation s02");
  await act(async () => button("Mark as mastered").click());
  expect(invoke).toHaveBeenCalledWith("course_progress_set", { courseId: "build", agentId: "owner", itemId: "s02", status: "mastered" });
  expect(nav("Step s02").getAttribute("aria-label")).toContain("mastered");
  act(() => root.unmount()); root = createRoot(container); await act(async () => root.render(pane())); expect(nav("Step s03").getAttribute("aria-current")).toBe("step");
});

it("keeps stored progress on map failure, exposes recovery, and retries only the map", async () => {
  vi.mocked(setConceptStatus).mockRejectedValueOnce(new Error("drawing conflict"));
  await act(async () => root.render(pane("domain"))); await act(async () => button("Mark as read").click());
  expect(nav("Container").getAttribute("aria-label")).toBe("Container, Read"); expect(container.textContent).toContain("Progress saved for Container");
  expect(setConceptStatus).toHaveBeenCalledWith("canvas-a", "domain", "container", "mastered", "owner");
  const writes = vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set").length;
  await act(async () => button("Retry map update").click()); expect(container.textContent).not.toContain("drawing conflict");
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set")).toHaveLength(writes);
});

it("does not claim mastery when native progress saving fails", async () => {
  vi.mocked(invoke).mockImplementation(async (name, args) => { if (name === "course_progress_set") throw new Error("database locked"); return command(name, args); });
  await act(async () => root.render(pane("domain"))); await act(async () => button("Mark as read").click());
  expect(nav("Container").getAttribute("aria-label")).toBe("Container, Not started"); expect(container.querySelector('[role="alert"]')?.textContent).toContain("database locked"); expect(setConceptStatus).not.toHaveBeenCalled();
});

it("scopes concept navigation and retains a valid target arriving before initial load finishes", async () => {
  const read = deferred<unknown>(); vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_get" ? read.promise : command(name, args));
  await act(async () => root.render(pane("domain"))); navigate({ courseId: "domain", conceptId: "borg", canvasId: "canvas-a", agentId: "owner" });
  await act(async () => read.resolve(stored(domain))); expect(nav("Borg").getAttribute("aria-current")).toBe("step");
  for (const wrong of [{ courseId: "build", conceptId: "pod" }, { courseId: "domain", conceptId: "pod", canvasId: "other" }, { courseId: "domain", conceptId: "pod", agentId: "other" }, { courseId: "domain", conceptId: "missing" }]) navigate(wrong);
  expect(nav("Borg").getAttribute("aria-current")).toBe("step");
  await act(async () => navigate({ courseId: "domain", conceptId: "pod", canvasId: "canvas-a" })); expect(container.textContent).toContain("doc-pod text"); expect(nav("Container")).toBeTruthy();
});

it("refreshes same-id updated courses without losing a still-valid selection", async () => {
  await act(async () => root.render(pane("domain"))); await act(async () => nav("Borg").click());
  const updated = structuredClone(domain);
  if (updated.data.engine === "reading") updated.data.chapters[1].title = "Revised chapter";
  courses.set(key("owner", "domain"), stored(updated));
  await act(async () => openCourse({ courseId: "domain", agentId: "owner", title: "Kubernetes" }));
  expect(nav("Borg").getAttribute("aria-current")).toBe("step"); expect(container.textContent).toContain("Revised chapter");
});

it("groups lessons under their chapters and numbers them through the course in the order written", async () => {
  await act(async () => root.render(pane("domain")));
  const chapters = [...container.querySelectorAll("nav section")];
  expect(chapters.map((chapter) => chapter.querySelector("h3")?.textContent)).toEqual(["Workloads", "Papers"]);
  expect(chapters.map((chapter) => [...chapter.querySelectorAll("button")].map((item) => item.textContent))).toEqual([["01Container", "02Pod"], ["03Borg"]]);
  expect(container.textContent).toContain("0 / 3 read");
});

it("shows a lesson's source itself, from its section, and starts reading when a lesson is opened", async () => {
  await act(async () => root.render(pane("domain")));
  expect(container.querySelector("[data-reading]")?.textContent).toBe("doc-container text");
  expect(container.querySelector("[data-reading]")?.getAttribute("data-source")).toBe("https://kubernetes.io/doc-container");
  // The lesson shown on opening the course was not chosen by the reader.
  expect(invoke).not.toHaveBeenCalledWith("course_progress_set", expect.anything());
  await act(async () => nav("Pod").click());
  expect(readAgentDocument).toHaveBeenLastCalledWith("owner", "doc-pod");
  expect(container.querySelector("[data-reading]")?.getAttribute("data-reading")).toBe("Pod phase");
  expect(invoke).toHaveBeenCalledWith("course_progress_set", { courseId: "domain", agentId: "owner", itemId: "pod", status: "learning" });
  expect(nav("Pod").getAttribute("aria-label")).toBe("Pod, Reading");
  await act(async () => nav("Pod").click());
  expect(vi.mocked(invoke).mock.calls.filter(([name]) => name === "course_progress_set")).toHaveLength(1);
});

it("opens a file lesson at its first page, and says when a lesson's document is not in the library", async () => {
  await act(async () => root.render(pane("domain"))); await act(async () => nav("Borg").click());
  expect(container.textContent).toContain("borg.pdf · pages 3–9");
  act(() => button("Open to read").click());
  expect(requestOpenFile).toHaveBeenCalledWith("/books/borg.pdf", { page: 3 });
  const missing = structuredClone(domain);
  if (missing.data.engine === "reading") missing.data.chapters[0].lessons[0].document = "doc-missing";
  courses.set(key("owner", "domain"), stored(missing));
  await act(async () => openCourse({ courseId: "domain", agentId: "owner", title: "Kubernetes" })); await act(async () => nav("Container").click());
  expect(container.querySelector('[role="alert"]')?.textContent).toContain("doc-missing");
});

it("drops a late course load after the owner and course switch", async () => {
  const old = deferred<unknown>(); vi.mocked(invoke).mockImplementation(async (name, args: any) => name === "course_get" && args.id === "build" ? old.promise : command(name, args));
  await act(async () => root.render(pane())); await act(async () => root.render(pane("domain")));
  await act(async () => old.resolve(stored(build))); expect(container.textContent).toContain("doc-container text"); expect(container.textContent).not.toContain("Step s01");
});

it("does not attach a late save error to another course or a reloaded generation", async () => {
  const write = deferred<unknown>(); vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_progress_set" ? write.promise : command(name, args));
  await act(async () => root.render(pane())); act(() => button("Mark as mastered").click());
  await act(async () => openCourse({ courseId: "build", agentId: "owner", title: build.title }));
  await act(async () => write.reject(new Error("old save failure"))); expect(container.textContent).not.toContain("old save failure"); expect(button("Mark as mastered").disabled).toBe(false);
});

it("merges progress saved by another pane while its early progress snapshot is still loading", async () => {
  const read = deferred<unknown>(); vi.mocked(invoke).mockImplementation(async (name, args) => name === "course_get" ? read.promise : command(name, args));
  await act(async () => root.render(pane()));
  act(() => window.dispatchEvent(new CustomEvent("loci:course-progress", { detail: { courseId: "build", agentId: "owner", itemId: "s01", status: "mastered" } })));
  await act(async () => read.resolve(stored(build))); expect(nav("Step s01").getAttribute("aria-label")).toContain("mastered"); expect(nav("Step s02").getAttribute("aria-current")).toBe("step");
});

it("prepares scoped course progress in the original conversation without sending it", async () => {
  await act(async () => root.render(pane("domain"))); act(() => button("Test understanding").click());
  expect(requestAddToChat).toHaveBeenCalledWith(expect.stringContaining('Current lesson: "Container" (container)'), "plain", { targetSessionId: "original-chat" });
  expect(vi.mocked(requestAddToChat).mock.calls[0][0]).toContain("courseId: domain");
});

it("shows load failures with a retry action", async () => {
  vi.mocked(invoke).mockRejectedValueOnce(new Error("read failed")); await act(async () => root.render(pane())); expect(container.textContent).toContain("read failed");
  await act(async () => button("Retry").click()); expect(container.textContent).toContain("Explanation s01");
});

it("keeps same-id courses from different owners separate during a pane switch", async () => {
  const other = { ...build, title: "Other owner's course", data: { engine: "build-your-own" as const, steps: [{ ...makeStep("s01"), title: "Other lesson", explanation: "Other explanation" }] } };
  courses.set(key("other-owner", "build"), stored(other, "other-owner"));
  progress.set(key("owner", "build"), new Map([["s01", "mastered"]]));
  await act(async () => root.render(pane())); await act(async () => root.render(pane("build", "other-owner")));
  expect(container.textContent).toContain("Other explanation"); expect(container.textContent).not.toContain("Explanation s02");
  expect(nav("Other lesson").getAttribute("aria-label")).toContain("untouched");
  await act(async () => button("Mark as mastered").click());
  expect(progress.get(key("other-owner", "build"))?.get("s01")).toBe("mastered"); expect(progress.get(key("owner", "build"))?.get("s02")).toBeUndefined();
});

it("preserves blank lines and indentation in a real diff card, and reports clipboard failures", async () => {
  expect(computeLineDiff("", "  first\n\n  last\n")?.map((line) => line.text)).toEqual(["  first", "", "  last"]);
  await act(async () => root.render(createElement(DiffCard, { id: "diff", title: "Diff", file: "unknown.ext", before: "", after: "  first\n\n  last\n", runCommand: "run --arg" })));
  expect(container.querySelectorAll(".diff-card__line--add")).toHaveLength(3); expect(container.querySelector(".diff-card__text")?.textContent).toBe("  first");
  vi.mocked(copyText).mockRejectedValueOnce(new Error("clipboard denied")); await act(async () => button("Copy command").click()); expect(container.querySelector('[role="alert"]')?.textContent).toContain("clipboard denied");
  await act(async () => button("Copy command").click()); expect(copyText).toHaveBeenCalledWith("run --arg"); expect(button("Copied")).toBeTruthy();
});

it("accepts a source lesson's line range and rejects it on a document or beside pages", async () => {
  const { parseCourseData } = await import("../model/course");
  const course = (lesson: Record<string, unknown>) => ({ chapters: [{ title: "Tour", lessons: [{ id: "a", title: "A", ...lesson }] }] });
  const parsed = parseCourseData("reading", course({ file: "/repo/src/main.rs", lines: [10, 40] }));
  expect(parsed.engine === "reading" && parsed.chapters[0].lessons[0].lines).toEqual([10, 40]);
  expect(() => parseCourseData("reading", course({ document: "doc", lines: [1, 2] }))).toThrow("belong to a file");
  expect(() => parseCourseData("reading", course({ file: "/repo/a.rs", lines: [1, 2], pages: [1, 1] }))).toThrow("not both");
  expect(() => parseCourseData("reading", course({ file: "/repo/a.rs", lines: [5, 2] }))).toThrow("lines must be");
});
