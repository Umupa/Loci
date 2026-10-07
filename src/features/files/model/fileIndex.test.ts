import { describe, expect, it } from "vitest";
import type { ProjectFile } from "../../../platform/tauri/fs";
import { findFiles } from "./fileIndex";

function file(relative: string, isDir = false): ProjectFile {
  const name = relative.split("/").pop()!;
  return { name, relative, path: `/project/${relative}`, isDir };
}

const files = [
  file("papers", true),
  file("papers/2024/survey.pdf"),
  file("notes/paper-outline.md"),
  file("drafts/summary.md"),
];

describe("findFiles", () => {
  it("ranks a name match above one that only the folder path produced", () => {
    expect(findFiles(files, "paper").map((hit) => hit.file.relative)).toEqual([
      "papers",
      "notes/paper-outline.md",
      "papers/2024/survey.pdf",
    ]);
  });

  it("finds a file by its path and highlights only the part inside its name", () => {
    const [hit] = findFiles(files, "2024/sur");
    expect(hit.file.relative).toBe("papers/2024/survey.pdf");
    expect(hit.namePositions).toEqual([0, 1, 2]);
  });

  it("returns nothing for a blank query or one that matches no file", () => {
    expect(findFiles(files, "  ")).toEqual([]);
    expect(findFiles(files, "zzz")).toEqual([]);
  });
});
