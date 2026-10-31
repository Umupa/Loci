import { expect, it } from "vitest";
import { agentReadingPlace, budgetPlace, PLACE_LIMITS, readingContext, setAgentReading, setAgentReadingPlace } from "./agentReading";

it("tells a turn what is open beside the chat, and nothing once it closes", () => {
  setAgentReading("mentor", { kind: "course", courseId: "k8s", title: "Kubernetes", lessonId: "pods", lessonTitle: "Pods" });
  expect(readingContext("mentor")).toBe('<reading_now>\n{"kind":"course","courseId":"k8s","title":"Kubernetes","lessonId":"pods","lessonTitle":"Pods"}\n</reading_now>');
  expect(readingContext("other")).toBeUndefined();
  setAgentReading("mentor", undefined);
  expect(readingContext("mentor")).toBeUndefined();
});

it("adds where the reader is, within budget, and forgets it on another page", () => {
  setAgentReading("place", { kind: "document", id: "pods", title: "Pods" });
  setAgentReadingPlace("place", { section: ["A", "B", "C", "Pod phase"], paragraph: "word ".repeat(200), selection: { text: "x".repeat(2000) } });
  const block = readingContext("place")!;
  const shown = JSON.parse(block.split("\n")[1]);
  expect(shown.link).toBe("loci://source/pods");
  expect(shown.place.section).toEqual(["B", "C", "Pod phase"]);
  expect(shown.place.paragraph.length).toBeLessThanOrEqual(PLACE_LIMITS.paragraph);
  expect(shown.place.paragraph.endsWith("…")).toBe(true);
  expect(shown.place.selection.length).toBeLessThanOrEqual(PLACE_LIMITS.selection);
  expect(JSON.stringify(shown.place).length).toBeLessThanOrEqual(PLACE_LIMITS.block);
  setAgentReading("place", { kind: "document", id: "other", title: "Other" });
  expect(agentReadingPlace("place")).toBeUndefined();
});

it("does not repeat a selection the message already carries, and keeps a file's lines", () => {
  setAgentReading("lines", { kind: "file", path: "/src/main.rs" });
  setAgentReadingPlace("lines", { lines: [10, 40], selection: { text: "fn  main()", lines: [12, 12] } });
  expect(budgetPlace(agentReadingPlace("lines")!, ["fn main()"])).toEqual({ lines: [10, 40], selection: "attached" });
  expect(budgetPlace(agentReadingPlace("lines")!)).toEqual({ lines: [10, 40], selection: { lines: [12, 12], text: "fn main()" } });
  setAgentReadingPlace("lines", { selection: undefined });
  expect(agentReadingPlace("lines")).toEqual({ lines: [10, 40] });
});
