import type { ProjectFile } from "../../../platform/tauri/fs";
import { findFiles, loadProjectFiles } from "../../files/model/fileIndex";
import { isNoteMentionPath, notesAsProjectFiles, rankNoteFiles, type Note } from "../../notes";
import {
  buildMentionIndex,
  fileMentionParts,
  type MentionIndex,
  type RankedFile,
} from "../../notes/noteMentions";
import { looksLikeProject } from "../../projects/model/recents";

const MAX_PICKER = 30;

/** Where a mention points: decides its icon, its label and how it is sent. */
export type MentionKind = "note" | "file";

export function mentionKind(path: string): MentionKind {
  return isNoteMentionPath(path) ? "note" : "file";
}

export type MentionSources = {
  notes: readonly Note[];
  files: readonly ProjectFile[];
};

/**
 * Everything `@` can point at, for highlighting what the user typed. File
 * labels (short names when unambiguous) come from the project's own index, so
 * a note title can never take a file's label.
 */
export function buildMentionSources({ notes, files }: MentionSources): MentionIndex {
  const fileIndex = buildMentionIndex([...files]);
  const labels = new Map(fileIndex.labels);
  for (const file of notesAsProjectFiles([...notes])) {
    labels.set(file.relative, file);
  }
  return { labels, labelOf: fileIndex.labelOf };
}

const EMPTY_FILES = 8;
const EMPTY_OTHERS = 4;

/**
 * The `@` picker's list. Typing `note/` narrows to notes; an empty query
 * offers what is likely wanted: the project's top level, then the latest notes.
 */
export function rankMentions(sources: MentionSources, query: string): RankedFile[] {
  const needle = query.replace(/\/+$/, "").trim();
  const { notes, files } = sources;
  const onlyNotes = needle.startsWith("note/");
  const rest = onlyNotes ? needle.slice("note/".length) : needle;
  const ranked = (file: ProjectFile, score: number, positions: number[] = []): RankedFile => ({ ...file, score, positions });

  const noteHits = rankNoteFiles([...notes], rest, needle ? MAX_PICKER : EMPTY_OTHERS);
  if (onlyNotes) return noteHits.slice(0, MAX_PICKER);

  if (!needle) {
    const top = files
      .filter((file) => !file.relative.includes("/"))
      .sort((a, b) => Number(!!b.isDir) - Number(!!a.isDir) || a.name.localeCompare(b.name))
      .slice(0, EMPTY_FILES)
      .map((file) => ranked(file, 0));
    return [...top, ...noteHits];
  }

  const fileHits = findFiles(files, needle, MAX_PICKER).map((hit) => ranked(hit.file, hit.score, hit.positions));
  return [...fileHits, ...noteHits]
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_PICKER);
}

function whitespaceFree(relative: string): string {
  return /\s/.test(relative) ? `\`${relative}\`` : `@${relative}`;
}

/**
 * Turn `@` mentions into what the agent can use: a file's short label becomes
 * its project-relative path. Notes are handled separately; anything that does
 * not resolve is left as typed.
 */
export async function applyMentionsToTurn(text: string, cwd: string): Promise<string> {
  if (!text.includes("@") || !looksLikeProject(cwd)) return text;
  const files = await loadProjectFiles(cwd).catch(() => [] as ProjectFile[]);
  const parts = fileMentionParts(text, buildMentionIndex(files).labels);
  if (!parts.some((part) => part.file)) return text;
  return parts.map((part) => part.file ? whitespaceFree(part.file.relative) : part.text).join("");
}
