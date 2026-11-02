import { expect, it } from "vitest";
import { agentReadingPlace, agentReadingVersion, budgetPlace, PLACE_LIMITS, readingContext, readingSkipped, readingTag, setAgentReading, setAgentReadingPlace, skipReadingOnce, takeReadingContext } from "./agentReading";

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

it("names a comparison's parts and the part in view", async () => {
  const { readingOf } = await import("../../mentor/model/mentorPage");
  const compare = [
    { label: "E2B", file: "/m/repos/e2b/restore.go", lines: [40, 88] as [number, number], commit: "a".repeat(40), note: "Reads the snapshot." },
    { label: "Spec", document: "virtio", section: "Virtqueues" },
  ];
  const reading = readingOf({ kind: "course", course: { courseId: "sbx", agentId: "m", title: "Sandboxes" } }, { id: "restore", title: "Restoring", compare });
  setAgentReading("compare", reading);
  setAgentReadingPlace("compare", { part: "E2B", lines: [50, 70] });
  const shown = JSON.parse(readingContext("compare")!.split("\n")[1]);
  expect(shown).toEqual({ kind: "course", courseId: "sbx", title: "Sandboxes", lessonId: "restore", lessonTitle: "Restoring",
    compare: [{ label: "E2B", file: "/m/repos/e2b/restore.go", lines: [40, 88], commit: "a".repeat(40) }, { label: "Spec", document: "virtio", section: "Virtqueues" }],
    place: { part: "E2B", lines: [50, 70] } });
  setAgentReading("compare", undefined);
});

it("names what the composer's tag shows as the reader moves and selects", () => {
  setAgentReading("tag", { kind: "document", id: "fc", title: "Firecracker" });
  const tag = () => readingTag({ kind: "document", id: "fc", title: "Firecracker" }, agentReadingPlace("tag"));
  expect(tag()).toEqual({ kind: "document", title: "Firecracker" });
  setAgentReadingPlace("tag", { page: 3 });
  expect(tag()).toEqual({ kind: "document", title: "Firecracker", page: 3 });
  setAgentReadingPlace("tag", { selection: { text: "first line\nsecond line", page: 4 } });
  expect(tag()).toEqual({ kind: "document", title: "Firecracker", page: 4, selected: 2 });
  setAgentReadingPlace("tag", { selection: undefined });
  expect(tag()).toEqual({ kind: "document", title: "Firecracker", page: 3 });
  expect(readingTag({ kind: "course", courseId: "k8s", title: "Kubernetes", lessonId: "pods", lessonTitle: "Pods" }, undefined))
    .toEqual({ kind: "course", parent: "Kubernetes", title: "Pods" });
  expect(readingTag({ kind: "file", path: "/src/vmm/main.rs" }, { lines: [12, 40] })).toEqual({ kind: "file", title: "main.rs", lines: [12, 40] });
  expect(readingTag({ kind: "file", path: "/src/vmm/main.rs" }, { lines: [1, 80], selection: { text: "a", lines: [12, 14] } }))
    .toEqual({ kind: "file", title: "main.rs", lines: [12, 14], selected: 3 });
  expect(readingTag({ kind: "note", id: "n1" }, undefined, "Plan").title).toBe("Plan");
});

it("tells subscribers only when the page or place really changes", () => {
  setAgentReading("ver", { kind: "note", id: "n" });
  const before = agentReadingVersion();
  setAgentReading("ver", { kind: "note", id: "n" });
  setAgentReadingPlace("ver", {});
  expect(agentReadingVersion()).toBe(before);
  setAgentReadingPlace("ver", { page: 2 });
  setAgentReadingPlace("ver", { page: 2 });
  expect(agentReadingVersion()).toBe(before + 1);
});

it("drops the page from one turn after a dismissal, then sends it again", () => {
  setAgentReading("skip", { kind: "document", id: "fc", title: "Firecracker" });
  skipReadingOnce("skip");
  expect(readingSkipped("skip")).toBe(true);
  expect(takeReadingContext("skip")).toBeUndefined();
  expect(readingSkipped("skip")).toBe(false);
  expect(takeReadingContext("skip")).toContain("<reading_now>");
  // Opening another page shows it again: the dismissal was about the old one.
  skipReadingOnce("skip");
  setAgentReading("skip", { kind: "document", id: "other", title: "Other" });
  expect(takeReadingContext("skip")).toContain("Other");
});
