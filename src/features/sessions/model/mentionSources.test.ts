import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ProjectFile } from "../../../platform/tauri/fs";
import type { Note } from "../../notes";

const files: ProjectFile[] = [
  { name: "papers", path: "/p/papers", relative: "papers", isDir: true },
  { name: "survey.pdf", path: "/p/papers/survey.pdf", relative: "papers/survey.pdf" },
  { name: "read me.md", path: "/p/docs/read me.md", relative: "docs/read me.md" },
  { name: "plan.md", path: "/p/plan.md", relative: "plan.md" },
];

function note(slug: string, title: string, updatedAt = 1): Note {
  return { id: `id-${slug}`, slug, title, body: "body", tags: [], createdAt: 1, updatedAt };
}

vi.mock("../../files/model/fileIndex", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../files/model/fileIndex")>()),
  loadProjectFiles: () => Promise.resolve(files),
}));
vi.mock("../../projects/model/recents", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../projects/model/recents")>()),
  looksLikeProject: (cwd: string) => cwd.startsWith("/"),
}));

const { applyMentionsToTurn, buildMentionSources, flatMentions, mentionFilter, mentionGroupStep, mentionKind, rankMentions } = await import("./mentionSources");
type LibraryMention = import("./mentionSources").LibraryMention;

const library: LibraryMention[] = [
  { kind: "course", label: "course/fc", title: "Firecracker", where: "2 lessons", updatedAt: 5, reference: "course" },
  { kind: "lesson", label: "lesson/fc/boot", title: "Boot", where: "Firecracker", courseId: "fc", positionKey: "course:fc:boot", updatedAt: 5, reference: "lesson" },
  { kind: "lesson", label: "lesson/fc/jailer", title: "Jailer", where: "Firecracker", courseId: "fc", positionKey: "course:fc:jailer", updatedAt: 5, reference: "lesson" },
  { kind: "lesson", label: "lesson/k8s/boot", title: "Boot", where: "Kubernetes", courseId: "k8s", positionKey: "course:k8s:boot", updatedAt: 9, reference: "lesson" },
  { kind: "source", label: "source/fc-paper", title: "Firecracker paper", where: "PDF", positionKey: "file:/lib/fc.pdf", updatedAt: 3, reference: "source" },
  { kind: "guide", label: "guide/fc-guide", title: "How to read the paper", updatedAt: 4, reference: "guide" },
  { kind: "highlight", label: "highlight/h1", title: "jailer drops privileges", where: "Firecracker paper · p. 3", updatedAt: 6, reference: "highlight" },
];

describe("rankMentions", () => {
  const sources = { notes: [note("plan-q3", "Quarterly plan")], files };
  const ids = (groups: ReturnType<typeof rankMentions>) => groups.map((group) => group.id);
  const rows = (groups: ReturnType<typeof rankMentions>) => flatMentions(groups).map((hit) => hit.relative);

  it("offers the project's top level, then notes, for a bare @ outside a mentor", () => {
    const groups = rankMentions(sources, "");
    expect(ids(groups)).toEqual(["note", "file"]);
    expect(flatMentions(groups).map((hit) => [mentionKind(hit.path), hit.relative])).toEqual([
      ["note", "note/plan-q3"],
      ["file", "papers"],
      ["file", "plan.md"],
    ]);
  });

  it("puts what was read lately, then the open course's lessons, ahead of a few of each group", () => {
    const groups = rankMentions({ ...sources, library, recent: ["file:/lib/fc.pdf", "note:id-plan-q3", "course:fc:jailer", "gone:x"], currentCourse: "fc" }, "");
    expect(ids(groups)).toEqual(["recent", "lesson", "course", "guide", "highlight", "file"]);
    expect(groups[0]!.items.map((hit) => hit.relative)).toEqual(["source/fc-paper", "note/plan-q3", "lesson/fc/jailer"]);
    // Recent rows are not repeated in their own groups; the open course's lessons lead.
    expect(groups[1]!.items.map((hit) => hit.relative)).toEqual(["lesson/fc/boot", "lesson/k8s/boot"]);
    expect(groups[1]!.items.map((hit) => hit.where)).toEqual(["Firecracker", "Kubernetes"]);
  });

  it("without an open course, lists lessons among the other groups", () => {
    expect(ids(rankMentions({ ...sources, library }, ""))).toEqual(["course", "lesson", "source", "guide", "note", "highlight", "file"]);
  });

  it("matches within each group and puts the group with the best match first", () => {
    const groups = rankMentions({ ...sources, library }, "jailer");
    expect(ids(groups)[0]).toBe("lesson");
    expect(rows(groups)).toEqual(["lesson/fc/jailer", "highlight/h1"]);
    expect(ids(rankMentions({ ...sources, library }, "plan"))).toEqual(expect.arrayContaining(["note", "file"]));
    // Two lessons of one name, told apart by their course.
    expect(flatMentions(rankMentions({ ...sources, library }, "boot")).map((hit) => hit.where)).toEqual(["Firecracker", "Kubernetes"]);
  });

  it("narrows to one group after a prefix, in English or Chinese", () => {
    expect(mentionFilter("资料/fire")).toEqual({ only: "source", rest: "fire" });
    expect(mentionFilter("课/")).toEqual({ only: "lesson", rest: "" });
    expect(mentionFilter("课程/")).toEqual({ only: "course", rest: "" });
    expect(mentionFilter("Lesson/b")).toEqual({ only: "lesson", rest: "b" });
    expect(mentionFilter("fire")).toEqual({ rest: "fire" });
    expect(rows(rankMentions({ ...sources, library }, "资料/"))).toEqual(["source/fc-paper"]);
    expect(rows(rankMentions({ ...sources, library }, "lesson/boot"))).toEqual(["lesson/fc/boot", "lesson/k8s/boot"]);
    expect(rows(rankMentions({ ...sources, library }, "高亮/"))).toEqual(["highlight/h1"]);
    expect(rows(rankMentions(sources, "note/qu"))).toEqual(["note/plan-q3"]);
    expect(rows(rankMentions(sources, "笔记/"))).toEqual(["note/plan-q3"]);
    expect(rows(rankMentions(sources, "file/survey"))).toEqual(["papers/survey.pdf"]);
  });

  it("finds a library item by the id a typed label carries", () => {
    expect(rows(rankMentions({ ...sources, library }, "lesson/fc/jailer"))).toEqual(["lesson/fc/jailer"]);
  });

  it("highlights a file match across its whole path", () => {
    const [hit] = flatMentions(rankMentions(sources, "survey"));
    expect(hit!.relative).toBe("papers/survey.pdf");
    expect(hit!.positions).toEqual([7, 8, 9, 10, 11, 12]);
  });

  it("steps Tab from group to group, wrapping around", () => {
    const groups = rankMentions({ ...sources, library }, "");
    const starts = groups.reduce<number[]>((all, group, index) => [...all, index ? all[index - 1]! + groups[index - 1]!.items.length : 0], []);
    expect(mentionGroupStep(groups, 0, 1)).toBe(starts[1]);
    expect(mentionGroupStep(groups, starts[1]! + 1, 1)).toBe(starts[2]);
    expect(mentionGroupStep(groups, 0, -1)).toBe(starts[starts.length - 1]);
    expect(mentionGroupStep(groups, starts[starts.length - 1]!, 1)).toBe(0);
  });
});

describe("buildMentionSources", () => {
  it("recognises notes and files in typed text", () => {
    const index = buildMentionSources({ notes: [note("plan-q3", "Quarterly plan")], files });
    expect([...index.labels.keys()].sort()).toEqual(expect.arrayContaining(["note/plan-q3", "survey.pdf", "papers/survey.pdf"]));
  });

  it("recognises library mentions, with their kind", () => {
    const index = buildMentionSources({ notes: [], files, library });
    expect(mentionKind(index.labels.get("lesson/fc/jailer")!.path)).toBe("lesson");
    expect(mentionKind(index.labels.get("highlight/h1")!.path)).toBe("highlight");
    expect(index.labels.get("source/fc-paper")!.name).toBe("Firecracker paper");
  });
});

describe("applyMentionsToTurn", () => {
  beforeEach(() => vi.clearAllMocks());

  it("writes a file's short label as its project-relative path", async () => {
    expect(await applyMentionsToTurn("summarise @survey.pdf, then @plan.md", "/p")).toBe("summarise @papers/survey.pdf, then @plan.md");
  });

  it("keeps a path with spaces readable by quoting it", async () => {
    expect(await applyMentionsToTurn("see @docs/read-me.md", "/p")).toBe("see `docs/read me.md`");
  });

  it("leaves text alone when nothing resolves, outside a project, or inside a quote", async () => {
    expect(await applyMentionsToTurn("mail me@example.com or @nothing", "/p")).toBe("mail me@example.com or @nothing");
    expect(await applyMentionsToTurn("extend @canvas/system-sketch", "/p")).toBe("extend @canvas/system-sketch");
    expect(await applyMentionsToTurn("@plan.md", "~")).toBe("@plan.md");
    expect(await applyMentionsToTurn("> quoted @survey.pdf", "/p")).toBe("> quoted @survey.pdf");
  });
});
