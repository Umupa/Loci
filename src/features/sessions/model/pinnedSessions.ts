import { normalizeProjectPath } from "../../projects/model/recents";

const PINNED_COLLAPSED_KEY = "loci.pinnedSessionsCollapsed";

function storageKey(cwd: string): string | null {
  if (!cwd || cwd === "~") return null;
  return normalizeProjectPath(cwd);
}

export function loadPinnedSessionsCollapsed(cwd: string): boolean {
  const key = storageKey(cwd);
  if (!key) return false;
  try {
    const raw = localStorage.getItem(PINNED_COLLAPSED_KEY);
    if (!raw) return false;
    const parsed: unknown = JSON.parse(raw);
    return Boolean(
      parsed &&
        typeof parsed === "object" &&
        !Array.isArray(parsed) &&
        (parsed as Record<string, unknown>)[key] === true,
    );
  } catch {
    return false;
  }
}

export function savePinnedSessionsCollapsed(
  cwd: string,
  collapsed: boolean,
): void {
  const key = storageKey(cwd);
  if (!key) return;
  try {
    const raw = localStorage.getItem(PINNED_COLLAPSED_KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : {};
    const store =
      parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? { ...(parsed as Record<string, unknown>) }
        : {};
    if (collapsed) store[key] = true;
    else delete store[key];
    localStorage.setItem(PINNED_COLLAPSED_KEY, JSON.stringify(store));
  } catch {
    // private mode / quota
  }
}

/** Move the collapsed state when a project path changes. */
export function rebasePinnedSessionsCollapsed(from: string, to: string): void {
  const oldKey = storageKey(from);
  const newKey = storageKey(to);
  if (!oldKey || !newKey || oldKey === newKey) return;
  try {
    const raw = localStorage.getItem(PINNED_COLLAPSED_KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : {};
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return;
    const state = { ...(parsed as Record<string, unknown>) };
    if (!(oldKey in state)) return;
    if (!(newKey in state)) state[newKey] = state[oldKey];
    delete state[oldKey];
    localStorage.setItem(PINNED_COLLAPSED_KEY, JSON.stringify(state));
  } catch {
    // private mode / quota
  }
}
