import { useSyncExternalStore } from "react";
import { readFlag, writeFlag } from "./storageFlags";

export const CANVAS_MCP_ENABLED_KEY = "loci.builtinExcalidrawMcpEnabled";
const CHANGE_EVENT = "loci:builtinexcalidrawmcpchange";
let unsaved: boolean | null = null;

/** App-wide preference, shared by Claude Code and Codex. */
export function loadCanvasMcpEnabled(): boolean {
  return unsaved ?? readFlag(CANVAS_MCP_ENABLED_KEY) ?? true;
}

export function saveCanvasMcpEnabled(enabled: boolean): void {
  writeFlag(CANVAS_MCP_ENABLED_KEY, enabled);
  // A storage failure must still let the user turn it off in this window.
  unsaved = readFlag(CANVAS_MCP_ENABLED_KEY) === enabled ? null : enabled;
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(CHANGE_EVENT));
  }
}

export function subscribeCanvasMcpEnabled(onChange: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  const onStorage = (event: StorageEvent) => {
    if (event.key !== CANVAS_MCP_ENABLED_KEY && event.key !== null) return;
    unsaved = null;
    onChange();
  };
  window.addEventListener(CHANGE_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(CHANGE_EVENT, onChange);
    window.removeEventListener("storage", onStorage);
  };
}

export function useCanvasMcpEnabled(): boolean {
  return useSyncExternalStore(subscribeCanvasMcpEnabled, loadCanvasMcpEnabled, () => true);
}
