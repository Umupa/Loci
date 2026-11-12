// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Agent } from "../../agents/model/agent";
import type { CourseSummary } from "../../learning/model/course";
import type { MentorPage } from "../model/mentorPage";
import { LibraryCourses, NEW_COURSE_PROMPT } from "./LibraryCourses";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

let root: Root;
let host: HTMLDivElement;
let selected: string | undefined;
let page: MentorPage | undefined;
let drafts: string[];
const agent: Agent = { id: "a", name: "Ada", avatar: "loci", color: "#123456" };
const summary = (id: string, title: string, read: number, total = 2, createdAt = 1): CourseSummary =>
  ({ id, agentId: agent.id, title, engine: "reading", itemCount: total, masteredCount: read, updatedAt: 10 - createdAt, createdAt });
const data = JSON.stringify({ engine: "reading", chapters: [{ title: "Basics", lessons: [
  { id: "intro", title: "Intro", document: "doc" }, { id: "loop", title: "vcpu_run_loop_with_a_very_long_identifier", file: "/repo/vcpu.rs" },
] }] });

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  selected = undefined; page = undefined; drafts = [];
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    const input = args as { id?: string; courseId?: string; agentId?: string };
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
    onDraft: (text) => drafts.push(text),
    isNew: (id) => id === "net",
  }));
  await act(async () => draw());
}
const sections = () => [...host.querySelectorAll<HTMLElement>("[data-library-course]")].map((course) => course.dataset.libraryCourse);
const press = (key: string) => act(async () => { document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true })); });

it("lists every course in one outline, in the order they were written, each under its title", async () => {
  await render([summary("net", "2. Networking", 0, 2, 5), summary("kvm", "一、KVM", 1, 2, 1)]);
  await vi.waitFor(() => expect(host.querySelectorAll("[data-library-lesson]")).toHaveLength(4));
  expect(sections()).toEqual(["kvm", "net"]);
  expect([...host.querySelectorAll(".library-course-title")].map((title) => title.textContent)).toEqual(["kvm", "netNew"]);
  expect(host.querySelector(".library-readline")?.getAttribute("title")).toBe("1 of 2 read");
  // No path, no switcher, no second list, and no asks once there is a course.
  expect(host.querySelector("[data-library-path], [data-library-step], .library-others")).toBeNull();
  expect(host.querySelector(".library-ask")).toBeNull();
});

it("opens a lesson from any course and moves through them with the arrow keys", async () => {
  await render([summary("kvm", "KVM", 1, 2, 1), summary("net", "Networking", 0, 2, 2)]);
  await vi.waitFor(() => expect(host.querySelector('[data-library-course="net"] [data-library-lesson="loop"]')).not.toBeNull());
  await act(async () => host.querySelector<HTMLButtonElement>('[data-library-course="net"] [data-library-lesson="intro"]')!.click());
  expect(page).toEqual({ kind: "course", course: { courseId: "net", agentId: "a", title: "net", itemId: "intro" } });
  host.querySelector<HTMLButtonElement>('[data-library-course="kvm"] [data-library-lesson="loop"]')!.focus();
  await press("ArrowDown");
  expect(document.activeElement?.closest("[data-library-course]")?.getAttribute("data-library-course")).toBe("net");
});

it("asks for a course when there is none", async () => {
  await render([]);
  const ask = host.querySelector<HTMLButtonElement>(".library-ask")!;
  expect(ask.textContent).toBe("Ask Ada for a course");
  await act(async () => ask.click());
  expect(drafts).toEqual([NEW_COURSE_PROMPT]);
});
