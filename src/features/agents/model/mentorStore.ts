import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { workdirSlug } from "./mentorSlug";

/**
 * Mentors live in folders (v0.4): `<mentors root>/<slug>/mentor.json` says who
 * a mentor is, and Rust's registry keeps the rest of the roster. The window
 * keeps a copy in localStorage (`loci:agent-roster`) so `listAgents()` stays
 * synchronous, and so an older Loci still finds the roster after a downgrade.
 *
 * - At boot, `hydrateMentors` hands the 0.3 roster and view state to the
 *   migration (a no-op once done), then replaces the copy with the registry's.
 * - Every roster change is sent to Rust (`queueRosterSync`), which writes
 *   `mentor.json` and gives a new mentor its folder.
 * - Another window's change, or a folder copied into the root, arrives as
 *   `loci:mentors-changed` and is loaded into the copy.
 */

const ROSTER_KEY = "loci:agent-roster";
const VIEW_KEY = "loci:agent-overviews.v1";
const AGENTS_CHANGED = "loci:agents-changed";
export const MENTORS_CHANGED = "loci:mentors-changed";
export const MENTOR_CONTENT_CHANGED = "loci:mentor-content-changed";

export type MigrationReport = {
  dryRun: boolean;
  done: boolean;
  backup?: string;
  mentors: { id: string; name: string; folder: string; workdir?: string; files: Record<string, unknown>; progress: number; conflicts: string[]; error?: string }[];
  orphanAgentFiles: string[];
  otherFolders: string[];
  deadTables: string[];
  caughtUp: number;
};

type RosterEntry = Record<string, unknown> & { id: string };

let registryReady = false;
let chain: Promise<void> = Promise.resolve();
let latest: RosterEntry[] | undefined;
const unsynced = new Set<string>();
const removing = new Set<string>();
let listening = false;

function inTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

function readArray(key: string): RosterEntry[] {
  try {
    const value = JSON.parse(localStorage.getItem(key) ?? "[]") as unknown;
    return Array.isArray(value)
      ? value.filter((entry): entry is RosterEntry => !!entry && typeof entry === "object" && typeof (entry as RosterEntry).id === "string")
      : [];
  } catch {
    return [];
  }
}

function readObject(key: string): Record<string, unknown> | undefined {
  try {
    const value = JSON.parse(localStorage.getItem(key) ?? "null") as unknown;
    return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
  } catch {
    return undefined;
  }
}

/** Whether the registry, not the window's copy, is the roster's truth. */
export function mentorRegistryReady(): boolean {
  return registryReady;
}

/** Resolves once every roster change made so far has reached Rust. */
export function rosterSettled(): Promise<void> {
  return chain;
}

/** The registry's roster merged with entries this window has not sent yet. */
export function mergeRoster(registry: readonly RosterEntry[], local: readonly RosterEntry[], pending: ReadonlySet<string>, gone: ReadonlySet<string>): RosterEntry[] {
  const merged = registry.filter((entry) => !gone.has(entry.id));
  const known = new Set(merged.map((entry) => entry.id));
  for (const entry of local) {
    if (!known.has(entry.id) && pending.has(entry.id)) merged.push(entry);
  }
  return merged;
}

function writeCopy(roster: readonly RosterEntry[]): void {
  try {
    const next = JSON.stringify(roster);
    if (localStorage.getItem(ROSTER_KEY) === next) return;
    localStorage.setItem(ROSTER_KEY, next);
  } catch {
    return;
  }
  window.dispatchEvent(new CustomEvent(AGENTS_CHANGED));
}

/**
 * Loads the registry's roster into this window's copy, after every roster
 * change this window has sent: a reload that overtook a sync still in flight
 * would put back an older roster (and lose, say, a new conversation id).
 */
function reload(): Promise<void> {
  const run = chain.then(reloadNow);
  chain = run.catch(() => undefined);
  return run;
}

async function reloadNow(): Promise<void> {
  const status = await invoke<{ ready: boolean }>("storage_status");
  registryReady = status.ready;
  if (!registryReady) return;
  const agents = await invoke<RosterEntry[]>("mentors_load");
  if (latest) return; // a newer local change is on its way; its answer reloads
  writeCopy(mergeRoster(agents, readArray(ROSTER_KEY), unsynced, removing));
}

/**
 * Before the first render: migrate 0.3 data (once), then load the roster
 * from the registry. Failures leave the saved roster in charge.
 */
export async function hydrateMentors(): Promise<MigrationReport | undefined> {
  if (!inTauri()) return undefined;
  try {
    const report = await invoke<MigrationReport>("storage_migrate", {
      input: { roster: readArray(ROSTER_KEY), overviews: readObject(VIEW_KEY) ?? null },
    });
    for (const mentor of report.mentors) {
      if (mentor.error) console.warn(`Mentor ${mentor.name || mentor.id} stays in the old tables for now: ${mentor.error}`);
    }
    await reload();
    await hydrateViewState();
    if (!listening) {
      listening = true;
      void listen(MENTORS_CHANGED, () => {
        void reload().catch(() => undefined);
      });
      void listen<ContentChange>(MENTOR_CONTENT_CHANGED, (event) => {
        for (const change of contentChangeEvents(event.payload ?? {})) window.dispatchEvent(change);
      });
    }
    return report;
  } catch (error) {
    console.warn("Mentor folders are unavailable; using the saved roster.", error);
    return undefined;
  }
}

/** Sends the roster to Rust, coalescing bursts of changes into one call. */
export function queueRosterSync(roster: readonly RosterEntry[]): void {
  if (!inTauri()) return;
  for (const entry of roster) if (!entry.workdir) unsynced.add(entry.id);
  latest = [...roster];
  chain = chain
    .then(async () => {
      const sending = latest;
      latest = undefined;
      if (!sending) return;
      // The folder name a new mentor gets: its name, else its face's name, as 0.3 named workdirs.
      const roster = sending.map((entry) => typeof entry.avatar === "string" ? { ...entry, slug: workdirSlug(entry as { id: string; name?: string; avatar: string }) } : entry);
      const agents = await invoke<RosterEntry[]>("mentors_sync", { roster });
      for (const entry of sending) unsynced.delete(entry.id);
      if (registryReady && !latest) writeCopy(mergeRoster(agents, readArray(ROSTER_KEY), unsynced, removing));
    })
    .catch((error: unknown) => {
      console.warn("Could not save the roster to mentors' folders.", error);
    });
}

/** Forgets a mentor in the registry; its folder stays on disk. */
export function queueMentorRemoval(id: string): void {
  if (!inTauri()) return;
  removing.add(id);
  unsynced.delete(id);
  chain = chain
    .then(() => invoke<void>("mentors_remove", { id }))
    .catch((error: unknown) => console.warn("Could not forget the mentor's folder.", error))
    .finally(() => removing.delete(id));
}

export type ContentChange = { agentId?: string | null; kind?: string; id?: string | null };

/**
 * A file changed in a mentor's folder (the watcher, or a reindex): the
 * events the window already refreshes on, as if the app had saved it.
 */
export function contentChangeEvents(change: ContentChange): Event[] {
  const agentId = change.agentId ?? undefined;
  switch (change.kind) {
    case "documents":
      return [new CustomEvent("loci:agent-documents-changed")];
    case "courses":
      return agentId ? [new CustomEvent("loci:courses-changed", { detail: { agentId, ...(change.id ? { courseId: change.id } : {}) } })] : [];
    case "notes":
      return [new Event("loci:notes-changed")];
    case "canvases":
      return [new Event("loci-canvases-changed")];
    case "files":
      return [new CustomEvent("loci:agent-files-changed")];
    default:
      // A reindex of everything.
      return [
        new CustomEvent("loci:agent-documents-changed"),
        ...(agentId ? [new CustomEvent("loci:courses-changed", { detail: { agentId } })] : []),
        new Event("loci:notes-changed"),
        new Event("loci-canvases-changed"),
        new CustomEvent("loci:agent-files-changed"),
      ];
  }
}

export type ExportSummary = { path: string; files: number; bytes: number; repos: { path: string; remote?: string; head?: string }[] };
export type ImportSummary = { id: string; folder: string; renamedId: boolean; files: number; progress: number; annotations: number };

/** Zips the mentor's folder (without repos/ and lab/ unless asked) to `path`. */
export function exportMentor(agentId: string, path: string, withRepos = false): Promise<ExportSummary> {
  return invoke<ExportSummary>("mentors_export", { agent: agentId, path, withRepos });
}

/** Imports a mentor from an exported .zip, or brings back a mentor folder where it is. */
export async function importMentor(from: { path: string } | { folder: string }): Promise<ImportSummary> {
  const summary = await invoke<ImportSummary>("mentors_import", "path" in from ? { path: from.path } : { folder: from.folder });
  await reload();
  return summary;
}

export type StorageStatus = { ready: boolean; root: string; mentors: { id: string; name?: string; folder: string; folderPresent: boolean; migrated: boolean; files: Record<string, number>; problems: number }[] };
export type LibraryProblem = { path: string; kind: string; id: string; error: string };
export type LibraryHit = { agentId: string; kind: string; id: string; title: string; snippet: string };

/** Where mentors' folders are, and what each holds. */
export function storageStatus(): Promise<StorageStatus> {
  return invoke<StorageStatus>("storage_status");
}

/** Runs (or with `dryRun` only describes) the 0.3 → 0.4 migration of this window's roster. */
export async function migrateStorage(options: { dryRun?: boolean; redo?: string } = {}): Promise<MigrationReport> {
  const report = await invoke<MigrationReport>("storage_migrate", {
    input: { roster: readArray(ROSTER_KEY), overviews: readObject(VIEW_KEY) ?? null, dryRun: !!options.dryRun, ...(options.redo ? { redo: options.redo } : {}) },
  });
  if (!options.dryRun) await reload();
  return report;
}

/** Re-reads mentors' folders (one, or all) into the index. */
export function reindexMentors(agentId?: string): Promise<{ id: string; changed: number }[]> {
  return invoke("storage_reindex", { agent: agentId ?? null });
}

/** Files in a mentor's folder that Loci could not read, or read with a warning. */
export function checkLibrary(agentId: string): Promise<LibraryProblem[]> {
  return invoke<LibraryProblem[]>("library_check", { agent: agentId });
}

/** Full-text search over mentors' titles, sources, guides and notes. */
export function searchLibrary(query: string, agentId?: string, limit?: number): Promise<LibraryHit[]> {
  return invoke<LibraryHit[]>("library_search", { query, agent: agentId ?? null, limit: limit ?? null });
}

let viewTimer: ReturnType<typeof setTimeout> | undefined;

/** Mirrors each mentor's view state into SQLite, a moment after it settles. */
export function mirrorViewState(states: Record<string, unknown>): void {
  if (!inTauri()) return;
  if (viewTimer) clearTimeout(viewTimer);
  viewTimer = setTimeout(() => {
    viewTimer = undefined;
    const writes = Object.entries(states).map(([agent, value]) => ({ agent, key: "view", value }));
    if (writes.length) void invoke("mentor_state_set", { writes }).catch(() => undefined);
  }, 500);
}

/** Fills view state this window does not have (a wiped WebView, an import). */
async function hydrateViewState(): Promise<void> {
  const saved = await invoke<Record<string, unknown>>("mentor_state_all", { key: "view" });
  const local = readObject(VIEW_KEY) ?? {};
  let changed = false;
  for (const [agent, value] of Object.entries(saved)) {
    if (!(agent in local) && value && typeof value === "object") {
      local[agent] = value;
      changed = true;
    }
  }
  if (changed) {
    try {
      localStorage.setItem(VIEW_KEY, JSON.stringify(local));
    } catch {
      return;
    }
  }
}

/** For tests: forget module state. */
export function resetMentorStoreForTests(): void {
  registryReady = false;
  chain = Promise.resolve();
  latest = undefined;
  unsynced.clear();
  removing.clear();
}
