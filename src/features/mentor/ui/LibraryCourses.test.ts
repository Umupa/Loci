// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Agent } from "../../agents/model/agent";
import type { CourseSummary } from "../../learning/model/course";
import type { LearningPath } from "../../learning/model/coursePath";
import type { MentorPage } from "../model/mentorPage";
import { LibraryCourses, NEW_COURSE_PROMPT, NEW_PATH_PROMPT } from "./LibraryCourses";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

let root: Root;
let host: HTMLDivElement;
let path: LearningPath | null;
let selected: string | undefined;
let page: MentorPage | undefined;
let drafts: string[];
const agent: Agent = { id: "a", name: "Ada", avatar: "loci", color: "#123456", projects: [] };
const summary = (id: string, title: string, read: number, total = 2, updatedAt = 1): CourseSummary =>
  ({ id, agentId: agent.id, title, engine: "reading", itemCount: total, masteredCount: read, updatedAt });
const data = JSON.stringify({ engine: "reading", chapters: [{ title: "Basics", lessons: [
  { id: "intro", title: "Intro", document: "doc" }, { id: "loop", title: "vcpu_run_loop_with_a_very_long_identifier", file: "/repo/vcpu.rs" },
] }] });

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  path = null; selected = undefined; page = undefined; drafts = [];
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { id?: string; courseId?: string; agentId?: string };
    if (command === "course_path_read") return { path };
    if (command === "course_get") return { id: input.id, agentId: input.agentId, title: input.id, updatedAt: 1, engine: "reading", dataJson: data };
    if (command === "course_progress_get") return input.courseId === "kvm" ? [{ itemId: "intro", status: "mastered" }] : [];
    throw new Error(`Unexpected command: ${command}`);
  });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.unstubAllGlobals(); vi.clearAllMocks(); });

async function render(courses: CourseSummary[]) {
  const draw = () => root.render(createElement(LibraryCourses, {
    agent, courses, selected, page,
    onOpen: (next) => { page = next; draw(); },
    onSelect: (id) => { selected = id; draw(); },
    onDraft: (text) => drafts.push(text),
    isNew: (id) => id === "net",
  }));
  await act(async () => draw());
}
const row = (id: string) => host.querySelector<HTMLButtonElement>(`[data-library-step="${id}"] > button`)!;
const open = () => [...host.querySelectorAll<HTMLElement>("[data-library-course]")].map((course) => course.dataset.libraryCourse);
const press = (key: string) => act(async () => { document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true })); });

const onPath = [summary("kvm", "一、KVM 第一性原理", 1), summary("net", "2. Networking", 0), summary("loose", "Loose ends", 0, 3)];

it("shows the path as numbered courses without their own ordinals, and opens the next course in place", async () => {
  path = { title: "Sandboxes", courses: [{ id: "kvm" }, { id: "net", after: ["kvm"] }, { id: "snap", title: "三、Snapshots", after: ["kvm", "net"] }] };
  await render(onPath);
  await vi.waitFor(() => expect(host.querySelector("[data-library-path]")).not.toBeNull());
  expect(host.querySelector(".library-path-kicker")).toBeNull();
  expect(host.querySelector(".library-path-title")?.textContent).toBe("Sandboxes");
  expect(host.querySelector(".library-head .library-readline")?.getAttribute("aria-label")).toBe("1 of 4 read");
  expect([...host.querySelectorAll(".library-step-title")].map((title) => title.textContent)).toEqual(["KVM 第一性原理", "NetworkingNew", "Snapshots", "Loose ends"]);
  expect([...host.querySelectorAll(".library-dot")].map((dot) => dot.className.split("--").pop())).toEqual(["learning", "untouched", "planned", "untouched"]);
  // Prerequisites not read yet are one small tag, by number, with their names on hover.
  const tags = [...host.querySelectorAll<HTMLElement>(".library-tag")];
  expect(tags.map((tag) => [tag.closest("[data-library-step]")!.getAttribute("data-library-step"), tag.textContent, tag.title]))
    .toEqual([["net", "After 1", "Best after KVM 第一性原理"], ["snap", "After 1, 2", "Best after KVM 第一性原理, Networking"]]);
  expect(host.querySelector(".library-others")?.textContent).toBe("Other courses");

  // The first course not read to the end is the current one, open under its row.
  await vi.waitFor(() => expect(open()).toEqual(["kvm"]));
  expect(row("kvm").getAttribute("aria-current")).toBe("true");
  expect(row("kvm").getAttribute("aria-expanded")).toBe("true");
  expect(row("snap").hasAttribute("aria-expanded")).toBe(false);
  await vi.waitFor(() => expect(host.querySelector('[data-library-course="kvm"] [data-library-lesson="intro"]')).not.toBeNull());

  // A planned course asks for it to be written, and nothing opens.
  await act(async () => row("snap").click());
  expect(drafts).toEqual(['Please write the course "三、Snapshots" (id snap) on my learning path.']);
  expect(open()).toEqual(["kvm"]);
});

it("opens one course at a time: another course opens at its next lesson, the open one folds and unfolds", async () => {
  path = { courses: [{ id: "kvm" }, { id: "net" }] };
  await render(onPath);
  await vi.waitFor(() => expect(open()).toEqual(["kvm"]));

  await act(async () => row("net").click());
  await vi.waitFor(() => expect(page).toEqual({ kind: "course", course: { courseId: "net", agentId: "a", title: "2. Networking", itemId: "intro" } }));
  expect(selected).toBe("net");
  await vi.waitFor(() => expect(open()).toEqual(["net"]));
  expect(row("kvm").getAttribute("aria-expanded")).toBe("false");
  await vi.waitFor(() => expect(host.querySelector('[data-library-lesson="intro"]')?.getAttribute("aria-current")).toBe("step"));

  // Clicking the open course folds it, keeping it marked as current; again unfolds it.
  const opened = page;
  await act(async () => row("net").click());
  expect(open()).toEqual([]);
  expect(row("net").getAttribute("aria-current")).toBe("true");
  expect(row("net").getAttribute("aria-expanded")).toBe("false");
  await act(async () => row("net").click());
  expect(open()).toEqual(["net"]);
  expect(page).toBe(opened);

  // A course off the path opens in place the same way.
  await act(async () => row("loose").click());
  await vi.waitFor(() => expect(open()).toEqual(["loose"]));
});

it("moves through courses and lessons with the arrow keys, folding a course with ←", async () => {
  path = { courses: [{ id: "kvm" }, { id: "net" }] };
  await render(onPath);
  await vi.waitFor(() => expect(host.querySelector('[data-library-lesson="loop"]')).not.toBeNull());
  row("kvm").focus();
  await press("ArrowDown");
  expect(document.activeElement?.className).toContain("library-chapter-title");
  await press("ArrowDown");
  expect((document.activeElement as HTMLElement).dataset.libraryLesson).toBe("intro");
  await press("End");
  expect(document.activeElement).toBe(row("loose"));
  row("kvm").focus();
  await press("ArrowLeft");
  expect(open()).toEqual([]);
  await press("ArrowRight");
  expect(open()).toEqual(["kvm"]);
  expect(document.activeElement).toBe(row("kvm"));
});

it("lists courses as rows when there is no path, with asks for a course and a path", async () => {
  await render([summary("kvm", "KVM", 1, 2, 1), summary("net", "Networking", 0, 2, 5)]);
  // Without a path or a choice, the course updated last is the current one.
  await vi.waitFor(() => expect(open()).toEqual(["net"]));
  expect(host.querySelector("[data-library-path]")).toBeNull();
  expect(host.querySelector('[aria-label="Courses"]')).not.toBeNull();
  expect(host.querySelectorAll(".library-dot--loose")).toHaveLength(2);
  expect(host.querySelector(".library-switcher")).toBeNull();
  const asks = [...host.querySelectorAll<HTMLButtonElement>(".library-ask")];
  expect(asks.map((ask) => ask.textContent)).toEqual(["Ask Ada for a course", "Ask Ada to plan a path"]);
  await act(async () => asks.forEach((ask) => ask.click()));
  expect(drafts).toEqual([NEW_COURSE_PROMPT, NEW_PATH_PROMPT]);
});

it("shows a single course as its head and outline, without a list", async () => {
  await render([summary("kvm", "一、KVM", 1)]);
  await vi.waitFor(() => expect(host.querySelector('[data-library-course="kvm"] [data-library-lesson="intro"]')).not.toBeNull());
  expect(host.querySelector("[data-library-step]")).toBeNull();
  expect(host.querySelector(".library-course-title")?.textContent).toBe("kvm");
  expect(host.querySelector(".library-readline")?.getAttribute("title")).toBe("1 of 2 read");
  expect([...host.querySelectorAll(".library-ask")].map((ask) => ask.textContent)).toEqual(["Ask Ada for a course"]);
});
