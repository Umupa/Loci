import type { ProjectFile } from "../../../platform/tauri/fs";
import { findFiles, loadProjectFiles } from "../../files/model/fileIndex";
import { isNoteMentionPath, notesAsProjectFiles, rankNoteFiles, type Note } from "../../notes";
import {
  buildMentionIndex,
  fileMentionParts,
  type MentionIndex,
  type RankedFile,
} from "../../notes/noteMentions";
import { fuzzyMatch } from "../../../shared/lib/fuzzy";
import { looksLikeProject } from "../../projects/model/recents";

const MAX_PICKER = 30;

/** Where a mention points: decides its icon, its group, its label and how it is sent. */
export type MentionKind = "course" | "lesson" | "source" | "guide" | "note" | "highlight" | "file";
/** The picker's groups, in the order they are listed. */
export const MENTION_KINDS: readonly MentionKind[] = ["course", "lesson", "source", "guide", "note", "highlight", "file"];
export type MentionGroupId = MentionKind | "recent";
export type LibraryKind = Exclude<MentionKind, "note" | "file">;

/** Library mentions are kept beside files and notes under this path prefix. */
const LIBRARY_PATH = "library:";

export function mentionKind(path: string): MentionKind {
  if (path.startsWith(LIBRARY_PATH)) return path.slice(LIBRARY_PATH.length).split("/")[0] as LibraryKind;
  return isNoteMentionPath(path) ? "note" : "file";
}

/** Something in the mentor's library that `@` can point at. */
export type LibraryMention = {
  kind: LibraryKind;
  /** What is written after `@`, such as `lesson/<course>/<lesson>`: one token, readable by the agent too. */
  label: string;
  title: string;
  /** Where it lives, so same-named items can be told apart: a lesson's course, a highlight's source. */
  where?: string;
  /** Its reading-position key, to find it among what was read recently. */
  positionKey?: string;
  /** A lesson's course, so the open course's lessons come first. */
  courseId?: string;
  updatedAt: number;
  /** One line telling the agent what it is and how to read it. */
  reference: string;
};

/** A row of the picker. `relative` is the label written after `@`. */
export type MentionCandidate = RankedFile & { kind: MentionKind; where?: string };
export type MentionGroup = { id: MentionGroupId; items: MentionCandidate[] };

export type MentionSources = {
  notes: readonly Note[];
  files: readonly ProjectFile[];
  /** The mentor's courses, lessons, sources, guides and highlights. */
  library?: readonly LibraryMention[];
  /** Reading-position keys of what the reader showed lately, newest first. */
  recent?: readonly string[];
  /** The course open beside the chat: its lessons are offered first. */
  currentCourse?: string;
};

export function libraryFile(entry: LibraryMention): ProjectFile {
  return { name: entry.title, path: `${LIBRARY_PATH}${entry.label}`, relative: entry.label };
}

/**
 * Everything `@` can point at, for highlighting what the user typed. File
 * labels (short names when unambiguous) come from the project's own index, so
 * a note title can never take a file's label.
 */
export function buildMentionSources({ notes, files, library = [] }: MentionSources): MentionIndex {
  const fileIndex = buildMentionIndex([...files]);
  const labels = new Map(fileIndex.labels);
  for (const file of notesAsProjectFiles([...notes])) labels.set(file.relative, file);
  for (const entry of library) labels.set(entry.label, libraryFile(entry));
  return { labels, labelOf: fileIndex.labelOf };
}

/** `@资料/` and `@source/` alike narrow the picker to one group. */
const PREFIXES: Record<MentionKind, readonly string[]> = {
  course: ["course", "课程"],
  lesson: ["lesson", "课"],
  source: ["source", "资料"],
  guide: ["guide", "导读"],
  note: ["note", "笔记"],
  highlight: ["highlight", "高亮"],
  file: ["file", "文件"],
};

/** The group a typed prefix names, and what is typed after it. */
export function mentionFilter(query: string): { only?: MentionKind; rest: string } {
  const typed = query.trimStart();
  for (const kind of MENTION_KINDS) {
    for (const prefix of PREFIXES[kind]) {
      if (typed.toLowerCase().startsWith(`${prefix}/`)) return { only: kind, rest: typed.slice(prefix.length + 1) };
    }
  }
  return { rest: typed };
}

const RECENT = 5;
const EMPTY_LESSONS = 6;
const EMPTY_FILES = 4;
const EMPTY_OTHERS = 3;
const PER_GROUP = 6;
const TITLE_BONUS = 400;

function candidate(file: ProjectFile, kind: MentionKind, score = 0, positions: number[] = [], where?: string): MentionCandidate {
  return { ...file, kind, score, positions, ...(where ? { where } : {}) };
}

function libraryCandidate(entry: LibraryMention, score = 0, positions: number[] = []): MentionCandidate {
  return candidate(libraryFile(entry), entry.kind, score, positions, entry.where);
}

/** A title match counts most, then where it lives, then its id (a typed `@lesson/fc/jailer`). */
function scoreLibrary(entry: LibraryMention, needle: string): MentionCandidate | undefined {
  const title = fuzzyMatch(needle, entry.title);
  if (title) return libraryCandidate(entry, title.score + TITLE_BONUS, title.positions);
  const where = entry.where ? fuzzyMatch(needle, entry.where) : null;
  const id = where ? null : fuzzyMatch(needle, entry.label.slice(entry.label.indexOf("/") + 1));
  const hit = where ?? id;
  return hit ? libraryCandidate(entry, hit.score) : undefined;
}

/** One group's rows: the best matches, or with nothing typed what is likely wanted. */
function groupItems(sources: MentionSources, kind: MentionKind, rest: string, limit: number): MentionCandidate[] {
  if (kind === "note") return rankNoteFiles([...sources.notes], rest, limit).map((hit) => ({ ...hit, kind: "note" }));
  if (kind === "file") {
    if (!rest) return sources.files
      .filter((file) => !file.relative.includes("/"))
      .sort((a, b) => Number(!!b.isDir) - Number(!!a.isDir) || a.name.localeCompare(b.name))
      .slice(0, limit)
      .map((file) => candidate(file, "file"));
    return findFiles(sources.files, rest, limit).map((hit) => candidate(hit.file, "file", hit.score, hit.positions));
  }
  const entries = (sources.library ?? []).filter((entry) => entry.kind === kind);
  if (rest) return entries
    .map((entry) => scoreLibrary(entry, rest))
    .filter((hit): hit is MentionCandidate => !!hit)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
  // Lessons keep the course's order, the open course's first; the rest newest first.
  const ordered = kind === "lesson"
    ? [...entries.filter((entry) => entry.courseId === sources.currentCourse), ...entries.filter((entry) => entry.courseId !== sources.currentCourse)]
    : [...entries].sort((a, b) => b.updatedAt - a.updatedAt);
  return ordered.slice(0, limit).map((entry) => libraryCandidate(entry));
}

/** What the reader showed lately, as rows: lessons, sources and guides, notes, files. */
function recentItems(sources: MentionSources): MentionCandidate[] {
  const byKey = new Map<string, MentionCandidate>();
  for (const entry of sources.library ?? []) if (entry.positionKey) byKey.set(entry.positionKey, libraryCandidate(entry));
  // A note's position key is its mention path; a file's is `file:` and its absolute path.
  for (const file of notesAsProjectFiles([...sources.notes])) byKey.set(file.path, candidate(file, "note"));
  const files = new Map(sources.files.map((file) => [`file:${file.path}`, file]));
  const items: MentionCandidate[] = [];
  for (const key of sources.recent ?? []) {
    const found = byKey.get(key) ?? (files.has(key) ? candidate(files.get(key)!, "file") : undefined);
    if (found && !items.some((item) => item.path === found.path)) items.push(found);
    if (items.length === RECENT) break;
  }
  return items;
}

/**
 * The `@` picker's rows, in groups. A prefix such as `资料/` or `note/` keeps
 * one group. With nothing typed: what was read lately and the open course's
 * lessons, then a few of each group. Otherwise each group's best matches, the
 * group with the best match first.
 */
export function rankMentions(sources: MentionSources, query: string): MentionGroup[] {
  const { only, rest: typed } = mentionFilter(query);
  const rest = typed.replace(/\/+$/, "").trim();
  if (only) {
    const items = groupItems(sources, only, rest, MAX_PICKER);
    return items.length ? [{ id: only, items }] : [];
  }
  if (!rest) {
    const recent = recentItems(sources);
    const shown = new Set(recent.map((item) => item.path));
    const limit = (kind: MentionKind) => kind === "file" ? EMPTY_FILES : kind === "lesson" && sources.currentCourse ? EMPTY_LESSONS : EMPTY_OTHERS;
    const order: MentionKind[] = sources.currentCourse ? ["lesson", ...MENTION_KINDS.filter((kind) => kind !== "lesson")] : [...MENTION_KINDS];
    const groups: MentionGroup[] = [{ id: "recent", items: recent }];
    for (const kind of order) {
      // Room for the rows already offered as recent, so each group still shows a few.
      const items = groupItems(sources, kind, "", limit(kind) + RECENT).filter((item) => !shown.has(item.path)).slice(0, limit(kind));
      groups.push({ id: kind, items });
    }
    return groups.filter((group) => group.items.length);
  }
  return MENTION_KINDS
    .map((kind) => ({ id: kind, items: groupItems(sources, kind, rest, PER_GROUP) }))
    .filter((group) => group.items.length)
    .sort((a, b) => b.items[0]!.score - a.items[0]!.score);
}

/** The rows as the keyboard walks them. */
export function flatMentions(groups: readonly MentionGroup[]): MentionCandidate[] {
  return groups.flatMap((group) => group.items);
}

/** Tab's target: the first row of the next (or, with -1, the previous) group, wrapping around. */
export function mentionGroupStep(groups: readonly MentionGroup[], active: number, step: 1 | -1): number {
  const starts: number[] = [];
  let at = 0;
  for (const group of groups) { starts.push(at); at += group.items.length; }
  if (!starts.length) return 0;
  let current = starts.length - 1;
  while (current > 0 && starts[current]! > active) current -= 1;
  return starts[(current + step + starts.length) % starts.length]!;
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
