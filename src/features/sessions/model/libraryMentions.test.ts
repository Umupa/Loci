import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Annotation } from "../../learning/model/types";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => invoke(...args) }));

const { applyLibraryMentionsToTurn, courseMentions, documentMention, highlightMention, libraryLabelsIn, withLibraryMentions } = await import("./libraryMentions");

const course = { id: "fc", title: "Firecracker", updatedAt: 1,
  data: { engine: "reading" as const, chapters: [{ title: "One", lessons: [{ id: "jailer", title: "The jailer", file: "/repo/jailer.rs", lines: [1, 40] as [number, number] }] }] } };

function mark(change: Partial<Annotation> = {}): Annotation {
  return {
    id: "h-1", documentId: "", target: { kind: "document", agentId: "m", documentId: "fc-paper" },
    anchor: { exact: "The jailer drops privileges", prefix: "", suffix: "", start: 0, end: 10, headings: ["Security"] },
    source: { id: "s", kind: "document", agentId: "m", documentId: "fc-paper", title: "Firecracker paper", quote: "The jailer drops privileges" },
    anchors: [], note: "", discussions: [], createdAt: 1, updatedAt: 2, ...change,
  };
}

describe("library mentions", () => {
  it("labels a course and its lessons so each tells the mentor how to read it", () => {
    const [whole, lesson] = courseMentions(course);
    expect(whole).toMatchObject({ kind: "course", label: "course/fc", where: "1 lesson", reference: 'course "Firecracker": courses.read fc' });
    expect(lesson).toMatchObject({ kind: "lesson", label: "lesson/fc/jailer", where: "Firecracker", courseId: "fc", positionKey: "course:fc:jailer" });
    expect(lesson!.reference).toBe('lesson "The jailer" (id jailer) of course "Firecracker": courses.read fc');
  });

  it("tells a source, a PDF source and a guide apart, each with its loci:// link", () => {
    const source = documentMention({ id: "pods", title: "Pods", kind: "source", sourceUrl: "https://k8s.io", createdAt: 1, updatedAt: 2 });
    expect(source).toMatchObject({ kind: "source", label: "source/pods", positionKey: "document:pods" });
    expect(source.reference).toBe('source "Pods": loci://source/pods (documents.read pods)');
    const pdf = documentMention({ id: "fc-paper", title: "Firecracker", kind: "source", sourceUrl: "https://x", pdf: { path: "/lib/fc.pdf" }, createdAt: 1, updatedAt: 2 });
    expect(pdf).toMatchObject({ kind: "source", where: "PDF", positionKey: "file:/lib/fc.pdf" });
    expect(pdf.reference).toContain("PDF source");
    const guide = documentMention({ id: "brief", title: "Reading brief", kind: "guide", createdAt: 1, updatedAt: 2 });
    expect(guide).toMatchObject({ kind: "guide", label: "guide/brief" });
    expect(guide.reference).toBe('your guide "Reading brief": loci://source/brief (documents.read brief)');
  });

  it("points a highlight at its passage, with the learner's note", () => {
    const entry = highlightMention(mark({ note: "Why not seccomp alone?" }), { id: "fc-paper", title: "Firecracker paper" });
    expect(entry).toMatchObject({ kind: "highlight", label: "highlight/h-1", title: "The jailer drops privileges", where: "Firecracker paper · Security" });
    expect(entry.reference).toContain('"The jailer drops privileges", their note: "Why not seccomp alone?"');
    expect(entry.reference).toContain("loci://source/fc-paper#section=Security&quote=The%20jailer%20drops%20privileges");
    expect(entry.reference).toContain("annotations.list --source fc-paper");
    const page = highlightMention(mark({ anchors: [{ page: 3, rects: [] }] }), { id: "fc-paper", title: "Firecracker paper" });
    expect(page.where).toBe("Firecracker paper · p. 3");
    expect(page.reference).toContain("loci://source/fc-paper#p3&quote=");
    const file = highlightMention(mark({ target: { kind: "file", path: "/repo/jailer.rs" }, anchor: { exact: "fn main", prefix: "", suffix: "", start: 0, end: 7, lines: [12, 14] } }));
    expect(file.where).toBe("jailer.rs · L12–14");
    expect(file.reference).toContain("(/repo/jailer.rs lines 12-14)");
    expect(file.reference).toContain("annotations.list --file /repo/jailer.rs");
  });

  it("finds the library labels a message mentions, not those in a quote", () => {
    expect(libraryLabelsIn("compare @lesson/fc/jailer with @source/pods, and @source/pods\n> @guide/quoted\nmail a@source/x")).toEqual(["lesson/fc/jailer", "source/pods"]);
  });

  it("lists what the mentions are under the message, leaving unknown ones as typed", () => {
    const library = [...courseMentions(course), documentMention({ id: "pods", title: "Pods", kind: "source", sourceUrl: "https://k8s.io", createdAt: 1, updatedAt: 2 })];
    expect(withLibraryMentions("why @lesson/fc/jailer and @source/gone?", library)).toBe([
      "why @lesson/fc/jailer and @source/gone?",
      "",
      "---",
      "Mentioned from your library:",
      '- @lesson/fc/jailer: lesson "The jailer" (id jailer) of course "Firecracker": courses.read fc',
    ].join("\n"));
    expect(withLibraryMentions("nothing @source/gone", library)).toBe("nothing @source/gone");
  });

  beforeEach(() => { invoke.mockReset(); });

  it("loads the library only when a message mentions something in it", async () => {
    expect(await applyLibraryMentionsToTurn("see @plan.md", "m")).toBe("see @plan.md");
    expect(invoke).not.toHaveBeenCalled();
    invoke.mockImplementation(async (command: string) => {
      if (command === "course_list_all") return [];
      if (command === "agent_documents_list") return [{ id: "pods", title: "Pods", kind: "source", sourceUrl: "https://k8s.io", createdAt: 1, updatedAt: 2 }];
      if (command === "learning_annotations_query") return [];
      throw new Error(command);
    });
    expect(await applyLibraryMentionsToTurn("read @source/pods", "m")).toContain("- @source/pods: source \"Pods\": loci://source/pods");
  });
});
