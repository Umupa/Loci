import type { RuntimeMode } from "../../sessions/model/session";
import { findAgent, updateAgent } from "./agent";

const DEFAULT_ACCESS_KEY = "loci:agent-default-access";
const ACCESS_CHANGED = "loci:agent-default-access-changed";

/** Mentors run without prompts until the user picks another default. */
export const NEW_AGENT_ACCESS: RuntimeMode = "full-access";

/**
 * What an existing mentor's saved chat switches to once. It is fixed rather
 * than read from the default, because raising the default later must not
 * reopen a migration that already happened.
 */
export const AGENT_ACCESS_MIGRATION: RuntimeMode = "full-access";

function isRuntimeMode(value: unknown): value is RuntimeMode {
  return (
    value === "supervised" ||
    value === "auto-accept-edits" ||
    value === "auto" ||
    value === "full-access"
  );
}

/** The permission mode a new mentor's conversation starts with. */
export function loadNewAgentAccess(): RuntimeMode {
  try {
    const stored = localStorage.getItem(DEFAULT_ACCESS_KEY);
    if (isRuntimeMode(stored)) return stored;
  } catch {
    /* Keep this window usable. */
  }
  return NEW_AGENT_ACCESS;
}

export function saveNewAgentAccess(mode: RuntimeMode): void {
  if (!isRuntimeMode(mode)) return;
  try {
    localStorage.setItem(DEFAULT_ACCESS_KEY, mode);
  } catch {
    /* Keep this window usable. */
  }
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(ACCESS_CHANGED));
  }
}

const listeners = new Set<() => void>();

function notify() {
  for (const listener of listeners) listener();
}

function onStorage(event: StorageEvent) {
  if (event.key !== DEFAULT_ACCESS_KEY && event.key !== null) return;
  notify();
}

export function subscribeNewAgentAccess(onChange: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  if (listeners.size === 0) {
    window.addEventListener(ACCESS_CHANGED, notify);
    window.addEventListener("storage", onStorage);
  }
  listeners.add(onChange);
  return () => {
    listeners.delete(onChange);
    if (listeners.size === 0) {
      window.removeEventListener(ACCESS_CHANGED, notify);
      window.removeEventListener("storage", onStorage);
    }
  };
}

/**
 * Records that this mentor's saved chat has had its one-time access change,
 * so the mode the user picks in its settings from now on is kept.
 */
export function markAgentAccessMigrated(agentId: string): void {
  if (findAgent(agentId)?.accessMigrated) return;
  updateAgent(agentId, (agent) =>
    agent.accessMigrated ? agent : { ...agent, accessMigrated: true },
  );
}
