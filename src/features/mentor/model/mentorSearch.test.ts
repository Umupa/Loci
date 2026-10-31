import { expect, it } from "vitest";
import { agentCanvasScope, type Agent } from "../../agents/model/agent";
import type { CourseWithProgress } from "../../learning/model/course";
import type { Note } from "../../notes";
import { mentorSearchItems, searchMentorItems, type MentorSearchSources } from "./mentorSearch";

const agents: Agent[] = [
  { id: "sandbox", sessionId: "chat-s", name: "Sandbox", avatar: "loci", color: "#123456", projects: [] },
  { id: "kernel", sessionId: "chat-k", name: "Kernel", avatar: "loci", color: "#654321", projects: [] },
];
const course: CourseWithProgress = {
  id: "jailer", agentId: "sandbox", title: "Firecracker isolation", updatedAt: 1, progress: new Map(),
  data: { engine: "reading", chapters: [{ title: "M6", lessons: [{ id: "6-02", title: "Jailer and cgroups", document: "doc" }] }] },
} as CourseWithProgress;
const sources: MentorSearchSources = {
  agents,
  courses: [course, { ...course, id: "orphan-course", agentId: "removed" } as CourseWithProgress],
  documents: new Map([["sandbox", [{ id: "jailer-md", title: "jailer.md", subject: "Firecracker", createdAt: 1, updatedAt: 1 }]]]),
  notes: [
    { id: "n1", title: "Namespaces recap", agentId: "kernel", body: "", tags: [] } as unknown as Note,
    { id: "n2", title: "Loose thoughts", body: "", tags: [] } as unknown as Note,
  ],
  canvases: [
    { id: "c1", title: "Jail map", cwd: agentCanvasScope("sandbox"), dataJson: "{}", tags: [], createdAt: 1, updatedAt: 1 },
    { id: "c2", title: "Project drawing", cwd: "/repo", dataJson: "{}", tags: [], createdAt: 1, updatedAt: 1 },
  ],
};

it("indexes mentors and what they keep, with the page each opens", () => {
  const items = mentorSearchItems(sources);
  expect(items.map((item) => item.id)).toEqual([
    "mentor:sandbox", "mentor:kernel",
    "course:sandbox:jailer", "lesson:sandbox:jailer:6-02",
    "source:sandbox:jailer-md",
    "note:n1", "note:n2",
    "canvas:c1",
  ]);
  expect(items.find((item) => item.kind === "lesson")).toMatchObject({ context: "Sandbox › Firecracker isolation", agentId: "sandbox",
    page: { kind: "course", course: { courseId: "jailer", agentId: "sandbox", itemId: "6-02" } } });
  // A note no mentor owns is still found, and opens wherever the user is.
  expect(items.find((item) => item.id === "note:n2")).toMatchObject({ context: "Notes", page: { kind: "note", id: "n2" } });
  expect(items.find((item) => item.id === "note:n2")?.agentId).toBeUndefined();
});

it("ranks whole and prefix matches before matches inside words, and mentors first on ties", () => {
  const items = mentorSearchItems(sources);
  // Equal matches keep the order mentor, course, lesson, source, note, canvas.
  expect(searchMentorItems(items, "jail").map((item) => item.id)).toEqual(["lesson:sandbox:jailer:6-02", "source:sandbox:jailer-md", "canvas:c1"]);
  // A match at the start of a later word beats one inside a word.
  expect(searchMentorItems(items, "cgroup").map((item) => item.id)).toEqual(["lesson:sandbox:jailer:6-02"]);
  // A title match comes before one in the course a lesson belongs to.
  expect(searchMentorItems(items, "racker").map((item) => item.id)).toEqual(["course:sandbox:jailer", "lesson:sandbox:jailer:6-02"]);
  expect(searchMentorItems(items, "kernel").map((item) => item.id)[0]).toBe("mentor:kernel");
  // Words can match where an item lives as well as its title.
  expect(searchMentorItems(items, "kernel recap").map((item) => item.id)).toEqual(["note:n1"]);
  expect(searchMentorItems(items, "nothing like this")).toEqual([]);
  expect(searchMentorItems(items, "  ").map((item) => item.kind)).toEqual(["mentor", "mentor"]);
});
