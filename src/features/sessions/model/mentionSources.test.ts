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

const { applyMentionsToTurn, buildMentionSources, mentionKind, rankMentions } = await import("./mentionSources");

describe("rankMentions", () => {
  const sources = { notes: [note("plan-q3", "Quarterly plan")], files };

  it("offers the project's top level, then notes, for a bare @", () => {
    const kinds = rankMentions(sources, "").map((hit) => [mentionKind(hit.path), hit.relative]);
    expect(kinds).toEqual([
      ["file", "papers"],
      ["file", "plan.md"],
      ["note", "note/plan-q3"],
    ]);
  });

  it("mixes files and notes by match quality", () => {
    const hits = rankMentions(sources, "plan").map((hit) => hit.relative);
    expect(hits).toContain("plan.md");
    expect(hits).toContain("note/plan-q3");
  });

  it("narrows to notes after a note/ prefix", () => {
    expect(rankMentions(sources, "note/qu").map((hit) => hit.relative)).toEqual(["note/plan-q3"]);
    expect(rankMentions(sources, "note/").every((hit) => mentionKind(hit.path) === "note")).toBe(true);
  });

  it("highlights a file match across its whole path", () => {
    const [hit] = rankMentions(sources, "survey");
    expect(hit.relative).toBe("papers/survey.pdf");
    expect(hit.positions).toEqual([7, 8, 9, 10, 11, 12]);
  });
});

describe("buildMentionSources", () => {
  it("recognises notes and files in typed text", () => {
    const index = buildMentionSources({ notes: [note("plan-q3", "Quarterly plan")], files });
    expect([...index.labels.keys()].sort()).toEqual(expect.arrayContaining(["note/plan-q3", "survey.pdf", "papers/survey.pdf"]));
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
