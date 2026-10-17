// @vitest-environment happy-dom
import { beforeEach, expect, it } from "vitest";
import { isBriefing, loadSeenBriefings, saveSeenBriefings } from "./briefings";

beforeEach(() => localStorage.clear());

it("files notes tagged briefing and remembers which were read", () => {
  expect(isBriefing({ tags: ["briefing", "market"] })).toBe(true);
  expect(isBriefing({ tags: ["v2ex"] })).toBe(false);
  expect(loadSeenBriefings().size).toBe(0);
  saveSeenBriefings(new Set(["a", "b"]));
  expect([...loadSeenBriefings()]).toEqual(["a", "b"]);
  localStorage.setItem("loci.feeds.briefingsSeen", "not json");
  expect(loadSeenBriefings().size).toBe(0);
});
