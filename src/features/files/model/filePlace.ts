import { useSyncExternalStore } from "react";
import type { FilePlace } from "../../../shared/lib/appResourceLinks";

/**
 * How a file opens beyond its place: at a commit (code read as it was then),
 * and the line navigation left, for Back.
 */
export type OpenFileOptions = { commit?: string; fromLine?: number };

/** A file link carries its location to the owner that decides where to open it. */
export type OpenFileFn = (path: string, place?: FilePlace, options?: OpenFileOptions) => void;

/** A place a link asked a file pane to show; `token` tells two requests for the same place apart. */
export type FilePlaceRequest = { place: FilePlace; token: number };

const requests = new Map<string, FilePlaceRequest>();
const listeners = new Set<() => void>();
let counter = 0;

function notify() {
  for (const listener of listeners) listener();
}

/** Ask the pane showing `path`, now or once it opens, to scroll to a page or a line. */
export function requestFilePlace(path: string, place: FilePlace): void {
  requests.set(path, { place, token: ++counter });
  notify();
}

/** Fired on `window`: open this file in a pane, wherever the user is working. */
export const OPEN_FILE_EVENT = "loci:open-file";

/** Open a file from somewhere that owns no panes, such as a lesson, optionally at a place in it. */
export function requestOpenFile(path: string, place?: FilePlace, options: OpenFileOptions = {}): void {
  if (place) requestFilePlace(path, place);
  window.dispatchEvent(new CustomEvent<{ path: string } & OpenFileOptions>(OPEN_FILE_EVENT, { detail: { path, ...options } }));
}

/** The pane has shown the place. A request is for the click that made it, so it does not outlive it. */
export function consumeFilePlace(path: string, token: number): void {
  if (requests.get(path)?.token !== token) return;
  requests.delete(path);
  notify();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

export function useFilePlace(path: string): FilePlaceRequest | undefined {
  return useSyncExternalStore(subscribe, () => requests.get(path), () => undefined);
}

/** Character offset at which a 1-based line starts; past the last line, the start of the last one. */
export function lineOffset(text: string, line: number): number {
  let offset = 0;
  for (let current = 1; current < line; current++) {
    const next = text.indexOf("\n", offset);
    if (next === -1) return offset;
    offset = next + 1;
  }
  return offset;
}

/** The characters of lines `first` to `last` (1-based, inclusive), without the final line break. */
export function lineRange(text: string, first: number, last: number): [number, number] {
  const start = lineOffset(text, first);
  const newline = text.indexOf("\n", lineOffset(text, Math.max(first, last)));
  return [start, newline === -1 ? text.length : newline];
}

/** A Markdown heading as a reader meets it: its text, and which of the headings with that text it is. */
export type HeadingPlace = { text: string; index: number };

// Headings are matched by letters and digits only: the preview drops the marks the source carries.
const headingKey = (text: string) => text.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");

/**
 * The heading a line of a Markdown source falls under, or null above the first
 * one. Lines in the front matter and in fenced code are not headings.
 */
export function headingAbove(text: string, line: number): HeadingPlace | null {
  const lines = text.split(/\r?\n/);
  let start = 0;
  if (/^\uFEFF?---[ \t]*$/.test(lines[0] ?? "")) {
    const close = lines.findIndex((entry, index) => index > 0 && /^(?:---|\.\.\.)[ \t]*$/.test(entry));
    if (close > 0) start = close + 1;
  }
  const seen = new Map<string, number>();
  let found: HeadingPlace | null = null;
  let fence: string | null = null;
  for (let index = start; index < Math.min(line, lines.length); index++) {
    const marker = /^\s{0,3}(`{3,}|~{3,})/.exec(lines[index])?.[1];
    if (marker && (!fence || (marker[0] === fence[0] && marker.length >= fence.length))) { fence = fence ? null : marker; continue; }
    const heading = fence ? null : /^\s{0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$/.exec(lines[index]);
    if (!heading) continue;
    // A link shows its text, not its address.
    const key = headingKey(heading[1].replace(/\]\([^)]*\)/g, "]"));
    if (!key) continue;
    found = { text: key, index: seen.get(key) ?? 0 };
    seen.set(key, found.index + 1);
  }
  return found;
}

/** A heading named by its text, such as a section a reader is asked to show; the first one with that text. */
export function headingPlace(title: string): HeadingPlace | null {
  const text = headingKey(title);
  return text ? { text, index: 0 } : null;
}

/** The element a rendered Markdown document shows for a heading found by `headingAbove`. */
export function findHeading(root: ParentNode, place: HeadingPlace): HTMLElement | null {
  const matches = [...root.querySelectorAll<HTMLElement>("h1,h2,h3,h4,h5,h6")].filter((element) => headingKey(element.textContent ?? "") === place.text);
  return matches[place.index] ?? null;
}

const MIRRORED = ["boxSizing", "width", "fontFamily", "fontSize", "fontWeight", "fontStyle", "lineHeight", "letterSpacing", "tabSize",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth"] as const;

/**
 * How far down a textarea its text at `offset` sits, wrapped lines included.
 * A hidden copy with the same box and font lays out the text before `offset`.
 */
export function textareaOffsetTop(area: HTMLTextAreaElement, offset: number): number {
  const style = getComputedStyle(area);
  const mirror = document.createElement("div");
  for (const name of MIRRORED) mirror.style[name] = style[name];
  Object.assign(mirror.style, { position: "absolute", visibility: "hidden", top: "0", left: "-9999px", height: "auto", whiteSpace: "pre-wrap", overflowWrap: "break-word" });
  mirror.textContent = area.value.slice(0, offset);
  const marker = document.createElement("span");
  marker.textContent = "​";
  mirror.append(marker);
  document.body.append(mirror);
  const top = marker.offsetTop;
  mirror.remove();
  return top;
}
