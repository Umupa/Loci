import { useSyncExternalStore } from "react";

/*
 * Reading width: lessons and documents keep to a ~68ch measure by default; the
 * reader can let the body run the full width of its column instead. One choice
 * for every reading surface, remembered across launches, and shown on <html>
 * as `data-reading-wide` so the stylesheet alone lifts the measure.
 */
const KEY = "loci.readingWide";
const listeners = new Set<() => void>();

function read(): boolean {
  try { return localStorage.getItem(KEY) === "1"; } catch { return false; }
}

let wide = read();
apply();

function apply() {
  if (typeof document === "undefined") return;
  if (wide) document.documentElement.dataset.readingWide = "";
  else delete document.documentElement.dataset.readingWide;
}

export function isReadingWide() { return wide; }

export function setReadingWide(value: boolean) {
  if (value === wide) return;
  wide = value;
  try { if (value) localStorage.setItem(KEY, "1"); else localStorage.removeItem(KEY); } catch { /* keep it for this session */ }
  apply();
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

export function useReadingWide(): [boolean, (value: boolean) => void] {
  return [useSyncExternalStore(subscribe, isReadingWide, isReadingWide), setReadingWide];
}
