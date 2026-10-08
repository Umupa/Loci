import { useSyncExternalStore } from "react";
import type { FilePlace } from "../../../shared/lib/appResourceLinks";

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
