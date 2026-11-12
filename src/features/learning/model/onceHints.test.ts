// @vitest-environment happy-dom
import { beforeEach, expect, it } from "vitest";
import { hintSeen, lessonHint, markHintSeen } from "./onceHints";

beforeEach(() => localStorage.clear());

it("shows asking first, then the original, each once on this device", () => {
  const lesson = { text: true, source: true, original: false };
  expect(lessonHint({ text: false, source: true, original: false })).toBeNull();
  expect(lessonHint(lesson)).toBe("select-to-ask");
  markHintSeen("select-to-ask");
  expect(lessonHint(lesson)).toBe("original");
  expect(lessonHint({ ...lesson, source: false })).toBeNull();
  markHintSeen("original");
  expect(lessonHint(lesson)).toBeNull();
  expect(hintSeen("original")).toBe(true);
});

it("treats a broken record as nothing seen", () => {
  localStorage.setItem("loci.hintsSeen", "{oops");
  expect(lessonHint({ text: true, source: false, original: false })).toBe("select-to-ask");
});
