// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { RETURN_AFTER_MS, returningTo, returnSummary, touchMentor } from "./mentorReturn";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

const course = { id: "virtio", agentId: "kern", title: "Virtio", updatedAt: 1, engine: "reading", bodies: ["map", "queue"],
  dataJson: JSON.stringify({ chapters: [{ title: "Rings", lessons: [{ id: "map", title: "The map" }, { id: "later", title: "Planned" }, { id: "queue", title: "Two rings" }] }] }) };
let progress: { itemId: string; status: string }[];
beforeEach(() => {
  localStorage.clear();
  progress = [];
  vi.mocked(invoke).mockReset().mockImplementation(async (name: string) => {
    if (name === "lesson_questions_list") return [{ courseId: "virtio", lessonId: "map", sessionId: "chat", messageId: "m1", text: "Why two rings?", askedAt: 5 }];
    if (name === "course_get") return course;
    if (name === "course_progress_get") return progress;
    return null;
  });
});

it("counts coming back only after six hours away from that mentor", () => {
  const now = 1_000 * RETURN_AFTER_MS;
  expect(returningTo("kern", now)).toBe(false);
  touchMentor("kern", now - RETURN_AFTER_MS + 1000);
  expect(returningTo("kern", now)).toBe(false);
  touchMentor("kern", now - RETURN_AFTER_MS);
  expect(returningTo("kern", now)).toBe(true);
  expect(returningTo("other", now)).toBe(false);
});

it("names the lesson left on, the last question, and goes on to it while unread, else to the next written lesson", async () => {
  expect(await returnSummary("kern", { courseId: "virtio", lessonId: "map" })).toMatchObject({
    last: { lessonId: "map", title: "The map", read: false }, question: { text: "Why two rings?" }, next: { lessonId: "queue" }, go: { lessonId: "map" },
  });
  progress = [{ itemId: "map", status: "mastered" }];
  // Without a page left open, the lesson last asked about stands in.
  expect(await returnSummary("kern")).toMatchObject({ last: { lessonId: "map", read: true }, go: { lessonId: "queue", title: "Two rings" } });
});
