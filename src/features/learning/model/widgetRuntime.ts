import { useEffect, useSyncExternalStore } from "react";
import { IS_WIN } from "../../../platform/tauri/platform";
import { getLearningWidget, setLearningWidgetSaved, setLearningWidgetState, subscribeLearningChanges } from "./learningStore";
import { widgetKey } from "./widgets";
import type { JsonValue, StoredWidget, WidgetRef, WidgetSpec } from "./types";

export const WIDGET_PROXY_URL = IS_WIN ? "http://loci-widget.localhost/proxy.html" : "loci-widget://localhost/proxy.html";
type Entry = { widget: StoredWidget; localState: boolean; listeners: Set<() => void>; stateWrite?: Promise<void>; error?: string };
const entries = new Map<string, Entry>();

export function seedWidget(ref: WidgetRef, spec: WidgetSpec, sourceSessionId: string): StoredWidget {
  const key = widgetKey(ref);
  let entry = entries.get(key);
  if (!entry) {
    entry = { widget: { ...spec, owner: ref.owner, sourceSessionId, sourceBlockId: "", revision: 0, saved: false, state: {}, createdAt: 0, updatedAt: 0 }, localState: false, listeners: new Set() };
    entries.set(key, entry);
  }
  return entry.widget;
}

function emit(entry: Entry) { entry.listeners.forEach((listener) => listener()); }
export function adoptStoredWidget(stored: StoredWidget) {
  const key = widgetKey(stored);
  const entry = entries.get(key);
  if (!entry) {
    entries.set(key, { widget: stored, localState: false, listeners: new Set() });
    return;
  }
  // An earlier read can finish after a new source was registered.
  if (stored.revision < entry.widget.revision) return;
  entry.widget = { ...stored, state: entry.localState ? entry.widget.state : stored.state };
  entry.error = undefined;
  emit(entry);
}

export async function refreshWidget(ref: WidgetRef) {
  const found = await getLearningWidget(ref);
  if (found) adoptStoredWidget(found);
  return found;
}

export function currentWidget(ref: WidgetRef): StoredWidget | undefined { return entries.get(widgetKey(ref))?.widget; }

/** Both panes share this write order; a late native write must not overwrite a newer interaction. */
function persistWidgetState(entry: Entry, ref: WidgetRef, state: JsonValue): Promise<void> {
  const write = (entry.stateWrite ?? Promise.resolve()).then(() => setLearningWidgetState(ref, state));
  // Report this failure to its caller, while allowing the next interaction to persist.
  entry.stateWrite = write.catch(() => undefined);
  return write;
}

export async function changeWidgetState(ref: WidgetRef, state: JsonValue) {
  const entry = entries.get(widgetKey(ref));
  if (!entry) return;
  entry.localState = true;
  entry.widget = { ...entry.widget, state };
  emit(entry);
  if (entry.widget.saved) await persistWidgetState(entry, ref, state);
}

export async function retainWidget(ref: WidgetRef, saved: boolean) {
  const stored = await setLearningWidgetSaved(ref, saved);
  // The native save is already committed. Later controls must persist even while this flush waits.
  adoptStoredWidget(stored);
  const entry = entries.get(widgetKey(ref));
  if (saved && entry?.localState) await persistWidgetState(entry, ref, entry.widget.state);
}

export function useWidget(ref: WidgetRef, spec: WidgetSpec, sourceSessionId: string) {
  seedWidget(ref, spec, sourceSessionId);
  const key = widgetKey(ref);
  const widget = useSyncExternalStore(
    (listener) => {
      const entry = entries.get(key)!;
      entry.listeners.add(listener);
      return () => { entry.listeners.delete(listener); };
    },
    () => entries.get(key)!.widget,
  );
  useEffect(() => {
    let current = true;
    let request = 0;
    const load = () => {
      const sequence = ++request;
      // Native writes trigger another read; a pre-write snapshot must not undo the acknowledged save.
      void getLearningWidget(ref).then((found) => {
        if (current && sequence === request && found) adoptStoredWidget(found);
      }).catch(() => undefined);
    };
    load();
    const stop = subscribeLearningChanges(load);
    return () => { current = false; stop(); };
  }, [key]);
  return widget;
}

export type WidgetRuntimeMessage =
  | { type: "ready" }
  | { type: "resize"; height: number }
  | { type: "state"; state: JsonValue }
  | { type: "ask"; text: string; selection?: string }
  | { type: "source"; id: string }
  | { type: "error"; message: string };

export function isJsonValue(value: unknown, depth = 0): value is JsonValue {
  if (depth > 30) return false;
  if (value === null || typeof value === "boolean" || typeof value === "string") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) return value.every((item) => isJsonValue(item, depth + 1));
  return !!value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype && Object.values(value).every((item) => isJsonValue(item, depth + 1));
}

/** The untrusted iframe cannot choose a conversation, native command or arbitrary source. */
export function parseRuntimeMessage(value: unknown, sourceIds: readonly string[]): WidgetRuntimeMessage | undefined {
  if (!value || typeof value !== "object") return;
  const data = value as Record<string, unknown>;
  if (data.type === "ready") return { type: "ready" };
  if (data.type === "resize" && typeof data.height === "number" && Number.isFinite(data.height)) return { type: "resize", height: Math.max(160, Math.min(1000, Math.round(data.height))) };
  if (data.type === "state" && isJsonValue(data.state) && new TextEncoder().encode(JSON.stringify(data.state)).byteLength <= 64 * 1024) return { type: "state", state: data.state };
  if (data.type === "ask" && typeof data.text === "string" && data.text.trim() && data.text.length <= 20_000) return { type: "ask", text: data.text.trim(), ...(typeof data.selection === "string" ? { selection: data.selection.slice(0, 2000) } : {}) };
  if (data.type === "source" && typeof data.id === "string" && sourceIds.includes(data.id)) return { type: "source", id: data.id };
  if (data.type === "error" && typeof data.message === "string") return { type: "error", message: data.message.slice(0, 2000) };
}
