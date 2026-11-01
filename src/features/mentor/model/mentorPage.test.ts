import { expect, it } from "vitest";
import { parseStoredPage, readingOf, samePage, storedPage } from "./mentorPage";

it("remembers identifiers, never contents, and the lesson a course was on", () => {
  expect(storedPage({ kind: "document", document: { id: "d", title: "Doc", body: "secret body", subject: "S" } }))
    .toEqual({ kind: "document", document: { id: "d", title: "Doc", body: "", subject: "S" } });
  expect(storedPage({ kind: "course", course: { courseId: "c", agentId: "a", title: "C", sourceSessionId: "s", openRequest: 3 } }, { id: "l2", title: "Two" }))
    .toEqual({ kind: "course", course: { courseId: "c", agentId: "a", title: "C", itemId: "l2" } });
  expect(storedPage(undefined)).toBeUndefined();
});

it("reads back only well-formed pages", () => {
  for (const page of [
    { kind: "course", course: { courseId: "c", agentId: "a", title: "C", itemId: "l" } },
    { kind: "document", document: { id: "d", title: "Doc", body: "" } },
    { kind: "note", id: "n" }, { kind: "canvas", id: "x" }, { kind: "file", path: "/a/b.pdf" }, { kind: "file", path: "/r/a.go", commit: "abcdef0" },
  ]) expect(parseStoredPage(page)).toEqual(page);
  expect(parseStoredPage({ kind: "file", path: "/r/a.go", commit: "HEAD; rm" })).toEqual({ kind: "file", path: "/r/a.go" });
  for (const bad of [null, "note", { kind: "note" }, { kind: "habit", id: "h" }, { kind: "course", course: { courseId: "c" } }, { kind: "file", path: "" }])
    expect(parseStoredPage(bad)).toBeUndefined();
});

it("tells the conversation what is read and compares pages by what they show", () => {
  const course = { kind: "course" as const, course: { courseId: "c", agentId: "a", title: "C", itemId: "l1" } };
  expect(readingOf(course, { id: "l2", title: "Two" })).toEqual({ kind: "course", courseId: "c", title: "C", lessonId: "l2", lessonTitle: "Two" });
  expect(readingOf(undefined, undefined)).toBeUndefined();
  expect(samePage(course, { kind: "course", course: { ...course.course, itemId: "other" } })).toBe(true);
  expect(samePage({ kind: "note", id: "n" }, { kind: "canvas", id: "n" })).toBe(false);
  expect(samePage({ kind: "file", path: "/a.go", commit: "abcdef0" }, { kind: "file", path: "/a.go" })).toBe(false);
  expect(readingOf({ kind: "file", path: "/a.go", commit: "abcdef0" }, undefined)).toEqual({ kind: "file", path: "/a.go", commit: "abcdef0" });
});
