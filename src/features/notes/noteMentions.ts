export type RankedFile = ProjectFile & FuzzyHit;
import { type FuzzyHit } from "../../shared/lib/fuzzy";
import type { ProjectFile } from "../../platform/tauri/fs";
import { isMarkdownBlockquotePosition } from "../sessions/model/quoteDraft";

export type MentionToken = {
  start: number;
  end: number;
  query: string;
};

/** `@label` → the note it points at, plus the label to write. */
export type MentionIndex = {
  /** Every writable label (basename when unique, always the relative path). */
  labels: Map<string, ProjectFile>;
  /** Preferred label per file path — the shortest unambiguous one. */
  labelOf: Map<string, string>;
};

export type MentionHit = {
  start: number;
  end: number;
  label: string;
  file: ProjectFile;
};

export type MentionTextPart = {
  text: string;
  file?: ProjectFile;
};

const MENTION_TOKEN_RE = /(^|\s)@(\S+)/g;
const TRAILING_PUNCTUATION = new Set([
  ",",
  ";",
  ":",
  "!",
  "?",
  ")",
  "]",
  "}",
  '"',
  "'",
  "/",
]);
const MAX_QUERY = 120;

/** Mention token that contains `cursor`, if the user is typing `@note`. */
export function mentionTokenAt(
  text: string,
  cursor: number,
): MentionToken | null {
  const i = clamp(cursor, 0, text.length);
  let start = i;
  while (start > 0 && !isSpace(text[start - 1]!)) start -= 1;
  if (text[start] !== "@") return null;
  if (isMarkdownBlockquotePosition(text, start)) return null;

  let end = start + 1;
  while (end < text.length && !isSpace(text[end]!)) end += 1;

  const typed = text.slice(start + 1, i);
  if (typed.includes("@") || typed.length > MAX_QUERY) return null;

  return { start, end, query: typed };
}

export function replaceMentionToken(
  text: string,
  token: MentionToken,
  label: string,
): string {
  const rest = text.slice(token.end);
  const spacer = rest.startsWith(" ") ? "" : " ";
  return `${text.slice(0, token.start)}@${label}${spacer}${rest}`;
}

export function buildMentionIndex(files: ProjectFile[]): MentionIndex {
  const entries = files.filter((file) =>
    isMentionableRelative(file.relative),
  );
  const counts = new Map<string, number>();
  for (const file of entries) {
    counts.set(file.name, (counts.get(file.name) ?? 0) + 1);
  }

  const labels = new Map<string, ProjectFile>();
  const labelOf = new Map<string, string>();
  const used = new Set<string>();

  const claim = (label: string, file: ProjectFile, preferred = false) => {
    if (!isTokenSafe(label) || used.has(label)) return false;
    used.add(label);
    labels.set(label, file);
    if (preferred || !labelOf.has(file.path)) labelOf.set(file.path, label);
    return true;
  };

  for (const file of entries) {
    const unique =
      !file.isDir && counts.get(file.name) === 1 && isTokenSafe(file.name);
    if (unique) claim(file.name, file, true);
    if (isTokenSafe(file.relative)) claim(file.relative, file);
  }

  for (const file of entries) {
    if (labelOf.has(file.path)) continue;
    const encoded = encodeMentionToken(file.relative);
    if (!encoded) continue;
    let label = encoded;
    for (let n = 2; used.has(label) && n < 1000; n++) {
      label = `${encoded}~${n}`;
    }
    claim(label, file, true);
  }

  return { labels, labelOf };
}

export function mentionLabel(file: ProjectFile, index: MentionIndex): string {
  return index.labelOf.get(file.path) ?? file.relative;
}

/** Split composer text so known `@file` tokens can be highlighted. */
export function fileMentionParts(
  text: string,
  labels: ReadonlyMap<string, ProjectFile>,
): MentionTextPart[] {
  if (!text) return [];
  const hits = scanMentions(text, labels);
  if (hits.length === 0) return [{ text }];

  const parts: MentionTextPart[] = [];
  let cursor = 0;
  for (const hit of hits) {
    if (hit.start > cursor) parts.push({ text: text.slice(cursor, hit.start) });
    parts.push({ text: text.slice(hit.start, hit.end), file: hit.file });
    cursor = hit.end;
  }
  if (cursor < text.length) parts.push({ text: text.slice(cursor) });
  return parts;
}

function scanMentions(
  text: string,
  labels: ReadonlyMap<string, ProjectFile>,
): MentionHit[] {
  if (labels.size === 0) return [];
  const hits: MentionHit[] = [];
  MENTION_TOKEN_RE.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = MENTION_TOKEN_RE.exec(text))) {
    const raw = match[2];
    if (!raw) continue;
    const start = match.index + (match[1] ?? "").length;
    if (isMarkdownBlockquotePosition(text, start)) continue;
    const resolved = resolveLabel(raw, labels);
    if (!resolved) continue;
    const mentionEnd = start + 1 + resolved.label.length;
        hits.push({
      start,
      end: mentionEnd,
      label: resolved.label,
      file: resolved.file,
    });
  }
  return hits;
}

/** `@note/topic,` still points at `note/topic` — peel trailing punctuation. */
function resolveLabel(
  raw: string,
  labels: ReadonlyMap<string, ProjectFile>,
): { label: string; file: ProjectFile } | null {
  let value = raw;
  while (value) {
    const file = labels.get(value);
    if (file) return { label: value, file };
    if (!TRAILING_PUNCTUATION.has(value[value.length - 1]!)) return null;
    value = value.slice(0, -1);
  }
  return null;
}

/** Workspace-relative only: no absolute paths, `..`, or control / format characters. */
function isSafeProjectRelative(relative: string): boolean {
  if (!relative || relative.length > MAX_QUERY * 4) return false;
  if (hasUnsafeChars(relative)) return false;
  if (relative.startsWith("/") || relative.startsWith("\\")) return false;
  if (relative.includes("://")) return false;
  for (const part of relative.split("/")) {
    if (!part || part === "." || part === "..") return false;
  }
  return true;
}

/**
 * `@` tokens are one whitespace-delimited word. Collapse whitespace so a
 * spaced path still inserts as a normal `@label`; the real relative path is
 * recovered from the mention index on send.
 */
function encodeMentionToken(relative: string): string | null {
  const encoded = relative.replace(/\s+/g, "-");
  return isTokenSafe(encoded) ? encoded : null;
}

function isTokenSafe(value: string): boolean {
  return (
    value.length > 0 &&
    value.length <= MAX_QUERY &&
    !/[\s@\\]/.test(value) &&
    !hasUnsafeChars(value)
  );
}

/** ASCII/C1 controls, bidi/format marks, and Unicode line/paragraph separators. */
function hasUnsafeChars(value: string): boolean {
  return /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(value);
}

function isMentionableRelative(relative: string): boolean {
  if (!isSafeProjectRelative(relative)) return false;
  return isTokenSafe(relative) || encodeMentionToken(relative) != null;
}

function isSpace(ch: string): boolean {
  return ch === " " || ch === "\n" || ch === "\t" || ch === "\r";
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}