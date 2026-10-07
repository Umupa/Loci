import type { ProjectFile } from "../../../platform/tauri/fs";
import { fuzzyMatch } from "../../../shared/lib/fuzzy";
import { canvasElementsToText, loadCanvases, type Canvas } from "../../canvas/canvas";
import { findFiles, loadProjectFiles } from "../../files/model/fileIndex";
import { isNoteMentionPath, notesAsProjectFiles, rankNoteFiles, type Note } from "../../notes";
import {
  buildMentionIndex,
  fileMentionParts,
  type MentionIndex,
  type RankedFile,
} from "../../notes/noteMentions";
import { looksLikeProject, sameProjectPath } from "../../projects/model/recents";

export const CANVAS_MENTION_PREFIX = "canvas/";
export const CANVAS_PATH_PREFIX = "canvas:";

const MAX_LABEL = 40;
const MAX_PICKER = 30;
/** Past this, a drawing's elements stay out of the prompt; the agent reads them itself. */
const MAX_CANVAS_PROMPT_CHARS = 60_000;

export function isCanvasMentionPath(path: string): boolean {
  return path.startsWith(CANVAS_PATH_PREFIX);
}

/** Where a mention points: decides its icon, its label and how it is sent. */
export type MentionKind = "note" | "canvas" | "file";

export function mentionKind(path: string): MentionKind {
  return isNoteMentionPath(path) ? "note" : isCanvasMentionPath(path) ? "canvas" : "file";
}

function slugify(title: string): string {
  const slug = title
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, MAX_LABEL)
    .replace(/-+$/g, "");
  return slug || "drawing";
}

/**
 * `canvas/<title>` labels for a project's drawings. A title two drawings share
 * gets the start of the id too, assigned oldest first so a label does not move
 * when a newer drawing appears.
 */
export function canvasMentionLabels(canvases: readonly Canvas[]): Map<string, Canvas> {
  const labels = new Map<string, Canvas>();
  const ordered = [...canvases].sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id));
  for (const canvas of ordered) {
    const base = `${CANVAS_MENTION_PREFIX}${slugify(canvas.title)}`;
    let label = base;
    for (let size = 4; labels.has(label) && size <= canvas.id.length; size += 4) {
      label = `${base}-${canvas.id.slice(0, size)}`;
    }
    labels.set(label, canvas);
  }
  return labels;
}

function canvasAsProjectFile(label: string, canvas: Canvas): ProjectFile {
  return { name: canvas.title, path: `${CANVAS_PATH_PREFIX}${canvas.id}`, relative: label };
}

export function canvasesAsProjectFiles(canvases: readonly Canvas[]): ProjectFile[] {
  return [...canvasMentionLabels(canvases)].map(([label, canvas]) => canvasAsProjectFile(label, canvas));
}

/** Drawings that belong to a project, the only ones an `@canvas/` mention can reach. */
export function projectCanvases(canvases: readonly Canvas[], cwd: string): Canvas[] {
  return canvases.filter((canvas) => !!canvas.cwd && sameProjectPath(canvas.cwd, cwd));
}

export type MentionSources = {
  notes: readonly Note[];
  canvases: readonly Canvas[];
  files: readonly ProjectFile[];
};

/**
 * Everything `@` can point at, for highlighting what the user typed. File
 * labels (short names when unambiguous) come from the project's own index, so
 * a note or drawing title can never take a file's label.
 */
export function buildMentionSources({ notes, canvases, files }: MentionSources): MentionIndex {
  const fileIndex = buildMentionIndex([...files]);
  const labels = new Map(fileIndex.labels);
  for (const file of [...notesAsProjectFiles([...notes]), ...canvasesAsProjectFiles(canvases)]) {
    labels.set(file.relative, file);
  }
  return { labels, labelOf: fileIndex.labelOf };
}

const EMPTY_FILES = 8;
const EMPTY_OTHERS = 4;

/**
 * The `@` picker's list. Typing `note/` or `canvas/` narrows to that kind; an
 * empty query offers what is likely wanted: the project's top level, then the
 * latest notes and drawings.
 */
export function rankMentions(sources: MentionSources, query: string): RankedFile[] {
  const needle = query.replace(/\/+$/, "").trim();
  const { notes, canvases, files } = sources;
  const only = needle.startsWith("note/") ? "note" : needle.startsWith("canvas/") ? "canvas" : null;
  const rest = only ? needle.slice(only.length + 1) : needle;
  const ranked = (file: ProjectFile, score: number, positions: number[] = []): RankedFile => ({ ...file, score, positions });

  const noteHits = only === "canvas" ? [] : rankNoteFiles([...notes], rest, needle ? MAX_PICKER : EMPTY_OTHERS);
  const canvasFiles = canvasesAsProjectFiles(canvases);
  const canvasHits: RankedFile[] = [];
  if (only !== "note") {
    if (!rest) {
      const recent = [...canvases].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, needle ? MAX_PICKER : EMPTY_OTHERS);
      for (const canvas of recent) {
        const file = canvasFiles.find((entry) => entry.path === `${CANVAS_PATH_PREFIX}${canvas.id}`);
        if (file) canvasHits.push(ranked(file, 0));
      }
    } else {
      for (const file of canvasFiles) {
        const hit = fuzzyMatch(rest, file.name);
        if (hit) canvasHits.push(ranked(file, hit.score + 400, hit.positions));
      }
    }
  }

  if (only) return [...noteHits, ...canvasHits.sort((a, b) => b.score - a.score)].slice(0, MAX_PICKER);

  if (!needle) {
    const top = files
      .filter((file) => !file.relative.includes("/"))
      .sort((a, b) => Number(!!b.isDir) - Number(!!a.isDir) || a.name.localeCompare(b.name))
      .slice(0, EMPTY_FILES)
      .map((file) => ranked(file, 0));
    return [...top, ...noteHits, ...canvasHits];
  }

  const fileHits = findFiles(files, needle, MAX_PICKER).map((hit) => ranked(hit.file, hit.score, hit.positions));
  return [...fileHits, ...noteHits, ...canvasHits]
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_PICKER);
}

function whitespaceFree(relative: string): string {
  return /\s/.test(relative) ? `\`${relative}\`` : `@${relative}`;
}

/** The elements of a drawing as the prompt carries them. */
function canvasPromptJson(canvas: Canvas): string {
  let elements: unknown[] = [];
  try {
    const parsed = JSON.parse(canvas.dataJson) as { elements?: unknown[] };
    elements = (parsed.elements ?? []).filter((element) => !(element as { isDeleted?: boolean }).isDeleted);
  } catch {
    /* an unreadable drawing is sent as empty */
  }
  const json = JSON.stringify(elements, null, 2);
  return json.length > MAX_CANVAS_PROMPT_CHARS
    ? `[${elements.length} elements, too large to include. Read them with loci_excalidraw get_elements.]`
    : json;
}

export function injectCanvasPrompt(text: string, canvases: readonly Canvas[]): string {
  if (canvases.length === 0) return text;
  const blocks = canvases.map((canvas) => [
    `Referenced drawing "${canvas.title.trim() || "Untitled"}":`,
    "",
    canvasElementsToText(canvas.title, canvasPromptJson(canvas), canvas.id),
  ].join("\n"));
  return [text.trimEnd(), "", "---", ...blocks].join("\n");
}

/**
 * Turn `@` mentions into what the agent can use: a file's short label becomes
 * its project-relative path, and a referenced drawing is attached as text with
 * its checkpoint id so the agent can also edit it. Notes are handled
 * separately; anything that does not resolve is left as typed.
 */
export async function applyMentionsToTurn(text: string, cwd: string): Promise<string> {
  if (!text.includes("@") || !looksLikeProject(cwd)) return text;
  const [files, canvases] = await Promise.all([
    loadProjectFiles(cwd).catch(() => [] as ProjectFile[]),
    loadCanvases().then((all) => projectCanvases(all, cwd)).catch(() => [] as Canvas[]),
  ]);
  const fileIndex = buildMentionIndex(files);
  const canvasLabels = canvasesAsProjectFiles(canvases);
  const labels = new Map(fileIndex.labels);
  for (const file of canvasLabels) labels.set(file.relative, file);

  const parts = fileMentionParts(text, labels);
  if (!parts.some((part) => part.file)) return text;
  const attached = new Map<string, Canvas>();
  const rewritten = parts.map((part) => {
    if (!part.file) return part.text;
    if (isCanvasMentionPath(part.file.path)) {
      const canvas = canvases.find((entry) => part.file!.path === `${CANVAS_PATH_PREFIX}${entry.id}`);
      if (canvas) attached.set(canvas.id, canvas);
      return part.text;
    }
    return whitespaceFree(part.file.relative);
  }).join("");
  return injectCanvasPrompt(rewritten, [...attached.values()]);
}
