import { invoke } from "@tauri-apps/api/core";
import { documentPlaceRequested } from "../../agents/model/documentPlace";
import { filePlaceRequested } from "../../files/model/filePlace";
import type { MentorLesson, MentorPage } from "./mentorPage";

/**
 * Where in a page the reader was, to come back to it. Each kind of reader
 * fills what it can; `ratio` is there for all of them and is used when the
 * finer place can no longer be found (the text changed, say).
 */
export type ReadingPosition = {
  /** A PDF: the page at the top of the view, and how far down it the view starts (0–1). */
  page?: number;
  within?: number;
  /** Code: the first line on screen (the file's numbering). */
  line?: number;
  /** Markdown: the block at the top of the view, by its opening words and which of the blocks opening so it is, and how far into it the view starts. */
  anchor?: { text: string; index: number; within: number };
  /** The share of the scrollable height above the view. */
  ratio: number;
};

type Stored = ReadingPosition & { at: number };

/** Pages remembered per mentor; the least recently read go first. */
export const POSITIONS_MAX = 50;
/** The mentor_state key the positions are kept under. */
export const POSITIONS_KEY = "places";
/** Scrolling changes the position many times a second; SQLite hears of it at most this often. */
export const POSITIONS_WRITE_MS = 1500;

const positions = new Map<string, Map<string, Stored>>();
const dirty = new Set<string>();
let timer: ReturnType<typeof setTimeout> | undefined;
let loading: Promise<void> | undefined;
let flushOnHide = false;

function inTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/** The page's name among a mentor's positions; nothing for pages that have no reading position. */
export function positionKey(page: MentorPage | undefined, lesson?: MentorLesson): string | undefined {
  if (!page) return undefined;
  if (page.kind === "course") {
    // A course is read lesson by lesson, each from its own place.
    const lessonId = lesson?.id ?? page.course.itemId;
    return lessonId ? `course:${page.course.courseId}:${lessonId}` : undefined;
  }
  if (page.kind === "document") return `document:${page.document.id}`;
  if (page.kind === "note") return `note:${page.id}`;
  if (page.kind === "file") return `file:${page.path}${page.commit ? `@${page.commit}` : ""}`;
  return undefined;
}

/**
 * Whether a link or a command asked for a place in this page (a line, a PDF
 * page, a section) since `since`, or still has one waiting: that place is
 * where the reader goes, not the remembered one.
 */
export function placeRequested(agentId: string, page: MentorPage, since: number): boolean {
  if (page.kind === "file") return filePlaceRequested(page.path, since);
  if (page.kind === "document") return documentPlaceRequested(agentId, page.document.id, since);
  return false;
}

const fraction = (value: unknown): value is number => typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1;
const count = (value: unknown): value is number => typeof value === "number" && Number.isInteger(value) && value > 0;

/** A stored position read back, or nothing when it is not one. */
export function parsePosition(value: unknown): Stored | undefined {
  if (!value || typeof value !== "object") return undefined;
  const raw = value as Record<string, unknown>;
  if (!fraction(raw.ratio)) return undefined;
  const out: Stored = { ratio: raw.ratio, at: typeof raw.at === "number" && Number.isFinite(raw.at) ? raw.at : 0 };
  if (count(raw.page)) { out.page = raw.page; out.within = fraction(raw.within) ? raw.within : 0; }
  if (count(raw.line)) out.line = raw.line;
  const anchor = raw.anchor as Record<string, unknown> | undefined;
  if (anchor && typeof anchor.text === "string" && anchor.text && typeof anchor.index === "number" && Number.isInteger(anchor.index) && anchor.index >= 0 && fraction(anchor.within))
    out.anchor = { text: anchor.text, index: anchor.index, within: anchor.within };
  return out;
}

/** Keeps the most recently read `POSITIONS_MAX`. */
function trim(pages: Map<string, Stored>): void {
  if (pages.size <= POSITIONS_MAX) return;
  const oldest = [...pages.entries()].sort((a, b) => a[1].at - b[1].at).slice(0, pages.size - POSITIONS_MAX);
  for (const [key] of oldest) pages.delete(key);
}

const samePosition = (a: ReadingPosition, b: ReadingPosition) =>
  a.ratio === b.ratio && a.page === b.page && a.within === b.within && a.line === b.line
  && a.anchor?.text === b.anchor?.text && a.anchor?.index === b.anchor?.index && a.anchor?.within === b.anchor?.within;

/** The reader is at `position` in the page `key`. Kept in memory at once, written to SQLite a moment later. */
export function rememberPosition(agentId: string, key: string, position: ReadingPosition, now = Date.now()): void {
  let pages = positions.get(agentId);
  if (!pages) { pages = new Map(); positions.set(agentId, pages); }
  const before = pages.get(key);
  pages.delete(key); // re-inserted last, so insertion order also reads newest last
  pages.set(key, { ...position, at: now });
  trim(pages);
  if (before && samePosition(before, position)) return;
  dirty.add(agentId);
  schedule();
}

/** Where the reader was in the page `key`, if it has been there. */
export function recalledPosition(agentId: string, key: string): ReadingPosition | undefined {
  const stored = positions.get(agentId)?.get(key);
  if (!stored) return undefined;
  const { at: _at, ...position } = stored;
  return position;
}

/**
 * Reads what earlier runs kept, once. What this window has already recorded
 * is newer and stays. Resolves (to nothing) outside the app or on failure.
 */
export function loadPositions(): Promise<void> {
  if (!loading) loading = (async () => {
    if (!inTauri()) return;
    try {
      const saved = await invoke<Record<string, unknown>>("mentor_state_all", { key: POSITIONS_KEY });
      for (const [agentId, value] of Object.entries(saved ?? {})) {
        if (!value || typeof value !== "object" || Array.isArray(value)) continue;
        let pages = positions.get(agentId);
        const fresh = new Map<string, Stored>();
        for (const [key, raw] of Object.entries(value)) {
          const parsed = parsePosition(raw);
          if (parsed && !pages?.has(key)) fresh.set(key, parsed);
        }
        if (!fresh.size) continue;
        if (!pages) { pages = new Map(); positions.set(agentId, pages); }
        for (const [key, parsed] of fresh) pages.set(key, parsed);
        trim(pages);
      }
    } catch { /* The positions start empty; reading still works. */ }
  })();
  return loading;
}

function schedule(): void {
  if (timer || !inTauri()) return;
  if (!flushOnHide) {
    flushOnHide = true;
    // Quitting inside the write delay would lose the last place read.
    window.addEventListener("pagehide", () => void flushPositions());
  }
  timer = setTimeout(() => { timer = undefined; void flushPositions(); }, POSITIONS_WRITE_MS);
}

/** Writes the mentors whose positions changed. Waits for the load, so a write never drops what earlier runs kept. */
export async function flushPositions(): Promise<void> {
  if (timer) { clearTimeout(timer); timer = undefined; }
  if (!dirty.size || !inTauri()) return;
  await loadPositions();
  const writes = [...dirty].map((agent) => ({ agent, key: POSITIONS_KEY, value: Object.fromEntries(positions.get(agent) ?? []) }));
  dirty.clear();
  await invoke("mentor_state_set", { writes }).catch(() => undefined);
}

/** For tests: forget module state. */
export function resetPositionsForTests(): void {
  positions.clear();
  dirty.clear();
  if (timer) clearTimeout(timer);
  timer = undefined;
  loading = undefined;
}
