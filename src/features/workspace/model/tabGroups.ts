import { projectKey, projectName } from "../../../shared/lib/paths";
import { knownProjectPaths, notifyProjectPathsChanged } from "../../projects/model/recents";
import { TAB_GROUP_COLORS } from "./tabGroupColors";
export { TAB_GROUP_COLORS } from "./tabGroupColors";

export function tabGroupColor(project: string): string {
  let hash = 0;
  for (let i = 0; i < project.length; i++) {
    hash = (hash * 31 + project.charCodeAt(i)) >>> 0;
  }
  return TAB_GROUP_COLORS[(hash % (TAB_GROUP_COLORS.length - 1)) + 1];
}

const COLOR_KEY = "loci:tab-group:colors";
const CUSTOM_COLOR_KEY = "loci:tab-group:custom-colors";
const LABEL_KEY = "loci:tab-group:labels";
const LABELS_CHANGED = "loci:tab-group-labels-changed";
const LOGO_KEY = "loci:tab-group:logos";
const MASCOT_KEY = "loci:tab-group:mascots";

const HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;

export const TAB_GROUP_LOGOS_CHANGED = "loci:tab-group-logos-changed";

let logoDisplayRevision = 0;

export function tabGroupLogoDisplayRevision(): number {
  return logoDisplayRevision;
}

function readRecord(key: string): Record<string, string> {
  migrateProjectAppearanceKeys();
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object") return {};
    return Object.fromEntries(
      Object.entries(parsed).filter(
        (entry): entry is [string, string] =>
          typeof entry[0] === "string" && typeof entry[1] === "string",
      ),
    );
  } catch {
    return {};
  }
}

function writeRecord(key: string, value: Record<string, string>): boolean {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

const APPEARANCE_KEYS = [
  COLOR_KEY,
  CUSTOM_COLOR_KEY,
  LABEL_KEY,
  LOGO_KEY,
  MASCOT_KEY,
] as const;

const KEY_VERSION_KEY = "loci:tab-group:key-version";
const KEY_VERSION = "2";
/** Guards the reads the migration itself makes. */
let migrating = false;
/** One attempt per storage instance, so an unfinished pass is not re-run hot. */
let attemptedFor: unknown = null;

/** Folder names carry no separator; every path key does, drive roots aside. */
function looksLikeFolderNameKey(key: string): boolean {
  return !key.includes("/") && key !== "~" && !/^[A-Za-z]:$/.test(key);
}

/**
 * Appearance used to be filed under the project's folder name, so checkouts that
 * share a name — `cortex/agentbase` and `cortex-finance/agentbase` — overwrote
 * each other's label, color, logo and mascot. Keys are full paths now; each old
 * entry moves to every remembered project that carries its name, which keeps
 * both rails looking the same until one of them is changed.
 *
 * A project we do not remember yet — evicted from recents, never pinned — cannot
 * be matched, so its entry stays under the old name and the pass is left unfinished.
 * Later launches retry until every name is claimed, which is what stops a
 * reopened project from losing its label for good.
 */
export function migrateProjectAppearanceKeys(): void {
  if (migrating) return;
  let store: Storage;
  try {
    store = localStorage;
    if (store.getItem(KEY_VERSION_KEY) === KEY_VERSION) return;
  } catch {
    return;
  }
  if (attemptedFor === store) return;
  attemptedFor = store;
  migrating = true;
  try {
    if (migrateNow()) store.setItem(KEY_VERSION_KEY, KEY_VERSION);
  } catch {
    /* quota or storage loss: the pass stays unfinished and retries next launch */
  } finally {
    migrating = false;
  }
}

/** `true` once nothing folder-name-shaped is left to claim. */
function migrateNow(): boolean {
  const byName = new Map<string, string[]>();
  for (const path of knownProjectPaths()) {
    const name = projectName(path);
    const keys = byName.get(name);
    if (keys) keys.push(projectKey(path));
    else byName.set(name, [projectKey(path)]);
  }

  let done = true;
  for (const store of APPEARANCE_KEYS) {
    const record = readRecord(store);
    const next: Record<string, string> = {};
    let changed = false;
    for (const [name, value] of Object.entries(record)) {
      const keys = byName.get(name);
      if (keys) {
        for (const key of keys) next[key] = value;
        changed = true;
        continue;
      }
      // A name nothing claims stays put, and keeps the pass unfinished.
      next[name] = value;
      done &&= !looksLikeFolderNameKey(name);
    }
    if (changed && !writeRecord(store, next)) done = false;
  }
  return done;
}

export function loadTabGroupColors(): Record<string, number> {
  const raw = readRecord(COLOR_KEY);
  const out: Record<string, number> = {};
  for (const [project, value] of Object.entries(raw)) {
    const index = Number.parseInt(value, 10);
    if (index >= 0 && index < TAB_GROUP_COLORS.length) out[project] = index;
  }
  return out;
}

export function loadTabGroupCustomColors(): Record<string, string> {
  const raw = readRecord(CUSTOM_COLOR_KEY);
  const out: Record<string, string> = {};
  for (const [project, value] of Object.entries(raw)) {
    if (HEX_COLOR_RE.test(value)) out[project] = value.toLowerCase();
  }
  return out;
}

function writeTabGroupColorIndices(next: Record<string, number>): void {
  writeRecord(
    COLOR_KEY,
    Object.fromEntries(Object.entries(next).map(([k, v]) => [k, String(v)])),
  );
}

function writeTabGroupCustomColors(next: Record<string, string>): void {
  writeRecord(CUSTOM_COLOR_KEY, next);
}

function clearTabGroupColorIndex(project: string): void {
  const next = loadTabGroupColors();
  if (!(project in next)) return;
  delete next[project];
  writeTabGroupColorIndices(next);
}

function clearTabGroupCustomColor(project: string): void {
  const next = loadTabGroupCustomColors();
  if (!(project in next)) return;
  delete next[project];
  writeTabGroupCustomColors(next);
}

export function saveTabGroupColor(project: string, index: number | null): void {
  clearTabGroupCustomColor(project);
  const next = loadTabGroupColors();
  if (index == null) delete next[project];
  else next[project] = index;
  writeTabGroupColorIndices(next);
  notifyProjectPathsChanged();
}

export function saveTabGroupCustomColor(
  project: string,
  color: string | null,
): void {
  clearTabGroupColorIndex(project);
  const next = loadTabGroupCustomColors();
  if (color == null || !HEX_COLOR_RE.test(color)) delete next[project];
  else next[project] = color.toLowerCase();
  writeTabGroupCustomColors(next);
  notifyProjectPathsChanged();
}

export function loadTabGroupLabels(): Record<string, string> {
  return readRecord(LABEL_KEY);
}

export function subscribeTabGroupLabels(onChange: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  window.addEventListener(LABELS_CHANGED, onChange);
  return () => window.removeEventListener(LABELS_CHANGED, onChange);
}

function notifyTabGroupLabelsChanged(): void {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new Event(LABELS_CHANGED));
}

export function saveTabGroupLabel(project: string, label: string): void {
  const trimmed = label.trim();
  const next = loadTabGroupLabels();
  if (!trimmed) delete next[project];
  else next[project] = trimmed;
  if (!writeRecord(LABEL_KEY, next)) return;
  notifyTabGroupLabelsChanged();
  notifyProjectPathsChanged();
}

export function loadTabGroupLogos(): Record<string, string> {
  return readRecord(LOGO_KEY);
}

export function saveTabGroupLogo(project: string, path: string | null): void {
  const next = loadTabGroupLogos();
  if (!path) delete next[project];
  else next[project] = path;
  writeRecord(LOGO_KEY, next);
}

export function loadTabGroupMascots(): Record<string, string> {
  return readRecord(MASCOT_KEY);
}

/** `null` restores the mascot picked from the project's name. */
export function saveTabGroupMascot(project: string, name: string | null): void {
  const next = loadTabGroupMascots();
  if (!name) delete next[project];
  else next[project] = name;
  writeRecord(MASCOT_KEY, next);
  notifyProjectPathsChanged();
}

/** Drops every saved appearance override for a project. */
export function clearTabGroupSettings(project: string): void {
  for (const key of APPEARANCE_KEYS) {
    const next = readRecord(key);
    if (!(project in next)) continue;
    delete next[project];
    if (writeRecord(key, next) && key === LABEL_KEY) {
      notifyTabGroupLabelsChanged();
    }
  }
}

/** Move project appearance overrides to the key derived from its new path. */
export function rebaseProjectTabGroupSettings(from: string, to: string): void {
  const oldKey = projectKey(from);
  const newKey = projectKey(to);
  if (oldKey === newKey) return;
  let labelsChanged = false;
  let logosChanged = false;
  for (const key of APPEARANCE_KEYS) {
    const next = readRecord(key);
    if (!(oldKey in next)) continue;
    if (!(newKey in next)) next[newKey] = next[oldKey];
    delete next[oldKey];
    if (!writeRecord(key, next)) continue;
    labelsChanged ||= key === LABEL_KEY;
    logosChanged ||= key === LOGO_KEY;
  }
  if (labelsChanged) notifyTabGroupLabelsChanged();
  if (logosChanged) notifyTabGroupLogosChanged();
}

export function resolveTabGroupMascot(
  project: string,
  overrides?: Record<string, string>,
): string | null {
  return overrides?.[project] ?? null;
}

export function resolveTabGroupLogo(
  project: string,
  overrides?: Record<string, string>,
): string | null {
  return overrides?.[project] ?? null;
}

export function notifyTabGroupLogosChanged(): void {
  logoDisplayRevision += 1;
  window.dispatchEvent(new CustomEvent(TAB_GROUP_LOGOS_CHANGED));
}

export function resolveTabGroupColor(
  project: string,
  overrides?: Record<string, number>,
  customOverrides?: Record<string, string>,
  fallbackKey?: string,
): string {
  const custom = customOverrides?.[project];
  if (custom && HEX_COLOR_RE.test(custom)) return custom;

  const index = overrides?.[project];
  if (index != null && index >= 0 && index < TAB_GROUP_COLORS.length) {
    return TAB_GROUP_COLORS[index];
  }
  return tabGroupColor(fallbackKey || project);
}

export function resolveTabGroupCustomColor(
  project: string,
  overrides?: Record<string, string>,
): string | null {
  const custom = overrides?.[project];
  return custom && HEX_COLOR_RE.test(custom) ? custom : null;
}

export function resolveTabGroupLabel(
  project: string,
  overrides?: Record<string, string>,
  fallback = "Group",
): string {
  return overrides?.[project]?.trim() || fallback;
}

export function resolveTabGroupColorIndex(
  project: string,
  overrides?: Record<string, number>,
  customOverrides?: Record<string, string>,
): number | null {
  if (resolveTabGroupCustomColor(project, customOverrides)) return null;

  const index = overrides?.[project];
  if (index != null && index >= 0 && index < TAB_GROUP_COLORS.length) {
    return index;
  }
  return null;
}
