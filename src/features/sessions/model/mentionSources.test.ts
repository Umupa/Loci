import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ProjectFile } from "../../../platform/tauri/fs";
import type { Canvas } from "../../canvas/canvas";
import type { Note } from "../../notes";

const files: ProjectFile[] = [
  { name: "papers", path: "/p/papers", relative: "papers", isDir: true },
  { name: "survey.pdf", path: "/p/papers/survey.pdf", relative: "papers/survey.pdf" },
  { name: "read me.md", path: "/p/docs/read me.md", relative: "docs/read me.md" },
  { name: "plan.md", path: "/p/plan.md", relative: "plan.md" },
];

function canvas(id: string, title: string, extra: Partial<Canvas> = {}): Canvas {
  return {
    id,
    title,
    dataJson: JSON.stringify({ elements: [{ id: "a", type: "rectangle", isDeleted: false }, { id: "b", isDeleted: true }] }),
    tags: [],
    cwd: "/p",
    createdAt: 1,
    updatedAt: 1,
    ...extra,
  };
}

function note(slug: string, title: string, updatedAt = 1): Note {
  return { id: `id-${slug}`, slug, title, body: "body", tags: [], createdAt: 1, updatedAt };
}

const canvases = [canvas("aaaa1111", "System sketch"), canvas("bbbb2222", "System sketch", { createdAt: 2 }), canvas("cccc3333", "Elsewhere", { cwd: "/other" })];

vi.mock("../../files/model/fileIndex", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../files/model/fileIndex")>()),
  loadProjectFiles: () => Promise.resolve(files),
}));
vi.mock("../../canvas/canvas", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../canvas/canvas")>()),
  loadCanvases: () => Promise.resolve(canvases),
}));
vi.mock("../../projects/model/recents", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../projects/model/recents")>()),
  looksLikeProject: (cwd: string) => cwd.startsWith("/"),
}));

const { applyMentionsToTurn, buildMentionSources, canvasMentionLabels, mentionKind, projectCanvases, rankMentions } = await import("./mentionSources");

describe("canvas labels", () => {
  it("slugifies titles and tells apart drawings that share one, oldest keeping the plain label", () => {
    const labels = canvasMentionLabels(canvases.slice(0, 2));
    expect([...labels].map(([label, c]) => [label, c.id])).toEqual([
      ["canvas/system-sketch", "aaaa1111"],
      ["canvas/system-sketch-bbbb", "bbbb2222"],
    ]);
    expect([...canvasMentionLabels([canvas("x", "架构 图")]).keys()]).toEqual(["canvas/架构-图"]);
    expect([...canvasMentionLabels([canvas("y", "???")]).keys()]).toEqual(["canvas/drawing"]);
  });

  it("only offers a project's own drawings", () => {
    expect(projectCanvases(canvases, "/p").map((c) => c.id)).toEqual(["aaaa1111", "bbbb2222"]);
  });
});

describe("rankMentions", () => {
  const sources = { notes: [note("plan-q3", "Quarterly plan")], canvases: projectCanvases(canvases, "/p"), files };

  it("offers the project's top level, then notes and drawings, for a bare @", () => {
    const kinds = rankMentions(sources, "").map((hit) => [mentionKind(hit.path), hit.relative]);
    expect(kinds).toEqual([
      ["file", "papers"],
      ["file", "plan.md"],
      ["note", "note/plan-q3"],
      ["canvas", "canvas/system-sketch"],
      ["canvas", "canvas/system-sketch-bbbb"],
    ]);
  });

  it("mixes files, notes and drawings by match quality", () => {
    const hits = rankMentions(sources, "plan").map((hit) => hit.relative);
    expect(hits).toContain("plan.md");
    expect(hits).toContain("note/plan-q3");
    expect(rankMentions(sources, "sketch").map((hit) => mentionKind(hit.path))).toEqual(["canvas", "canvas"]);
  });

  it("narrows to one kind after a note/ or canvas/ prefix", () => {
    expect(rankMentions(sources, "canvas/").every((hit) => mentionKind(hit.path) === "canvas")).toBe(true);
    expect(rankMentions(sources, "note/qu").map((hit) => hit.relative)).toEqual(["note/plan-q3"]);
    expect(rankMentions(sources, "canvas/sys")).toHaveLength(2);
  });

  it("highlights a file match across its whole path", () => {
    const [hit] = rankMentions(sources, "survey");
    expect(hit.relative).toBe("papers/survey.pdf");
    expect(hit.positions).toEqual([7, 8, 9, 10, 11, 12]);
  });
});

describe("buildMentionSources", () => {
  it("recognises all three kinds in typed text", () => {
    const index = buildMentionSources({ notes: [note("plan-q3", "Quarterly plan")], canvases: projectCanvases(canvases, "/p"), files });
    expect([...index.labels.keys()].sort()).toEqual(expect.arrayContaining(["note/plan-q3", "canvas/system-sketch", "survey.pdf", "papers/survey.pdf"]));
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

  it("attaches a mentioned drawing's live elements and checkpoint id", async () => {
    const out = await applyMentionsToTurn("extend @canvas/system-sketch please", "/p");
    expect(out).toContain("extend @canvas/system-sketch please");
    expect(out).toContain('Referenced drawing "System sketch":');
    expect(out).toContain('Excalidraw checkpoint id: "aaaa1111"');
    expect(out).toContain('"id": "a"');
    expect(out).not.toContain('"id": "b"');
  });

  it("leaves text alone when nothing resolves, outside a project, or inside a quote", async () => {
    expect(await applyMentionsToTurn("mail me@example.com or @nothing", "/p")).toBe("mail me@example.com or @nothing");
    expect(await applyMentionsToTurn("@plan.md", "~")).toBe("@plan.md");
    expect(await applyMentionsToTurn("> quoted @survey.pdf", "/p")).toBe("> quoted @survey.pdf");
  });
});
