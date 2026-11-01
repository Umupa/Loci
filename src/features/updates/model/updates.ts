import { getIdentifier, getVersion } from "@tauri-apps/api/app";
import { relaunch } from "@tauri-apps/plugin-process";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { useSyncExternalStore } from "react";

/**
 * The installed app. Only it updates itself, from GitHub Releases; Loci Dev
 * (`com.loci.desktop.dev`, every debug build) is built from source and has
 * no updater. Must match `RELEASE_IDENTIFIER` in src-tauri/src/flavor.rs.
 */
export const RELEASE_IDENTIFIER = "com.loci.desktop";

/** Long enough that launch work settles first. */
const FIRST_CHECK_DELAY_MS = 10_000;
const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;

export function updatesItself(identifier: string): boolean {
  return identifier === RELEASE_IDENTIFIER;
}

export async function updatesEnabled(): Promise<boolean> {
  try {
    return updatesItself(await getIdentifier());
  } catch {
    return false;
  }
}

/** A release the update server offers, as the prompt shows it. */
export type PendingUpdate = {
  version: string;
  currentVersion: string;
  /** The release's changelog section, as Markdown; empty when it has none. */
  notes: string;
};

/** What the prompt does after the user agrees: download, then install. */
export type InstallProgress =
  | { phase: "idle" }
  | { phase: "downloading"; percent: number | null }
  | { phase: "installing" }
  | { phase: "failed"; error: string };

export type UpdatesState = {
  /** The release on offer; null once the user chose Later or nothing is known. */
  pending: PendingUpdate | null;
  /** Whether the in-app prompt is open. */
  promptOpen: boolean;
  progress: InstallProgress;
};

const INITIAL: UpdatesState = { pending: null, promptOpen: false, progress: { phase: "idle" } };

/** The release the open prompt would install. */
let held: Update | null = null;
let state: UpdatesState = INITIAL;
let busy = false;
/** The release the user put off in this run, so quiet checks leave it alone. */
let declined: string | null = null;
const listeners = new Set<() => void>();

function publish(next: UpdatesState) {
  state = next;
  for (const listener of listeners) listener();
}

function patch(next: Partial<UpdatesState>) {
  publish({ ...state, ...next });
}

function forget(update: Update | null) {
  if (update) void update.close().catch(() => undefined);
}

export function subscribeUpdates(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function updatesSnapshot(): UpdatesState {
  return state;
}

/** The whole prompt state. Re-renders on download progress. */
export function useUpdates(): UpdatesState {
  return useSyncExternalStore(subscribeUpdates, updatesSnapshot, updatesSnapshot);
}

/** Only the release on offer, for controls that do not show progress. */
export function usePendingUpdate(): PendingUpdate | null {
  return useSyncExternalStore(subscribeUpdates, () => state.pending, () => null);
}

/** Just its version, so the rail does not re-render for every downloaded chunk. */
export function usePendingUpdateVersion(): string | null {
  return useSyncExternalStore(subscribeUpdates, () => state.pending?.version ?? null, () => null);
}

/** The release notes under the version, as the prompt's body. */
export function updateDetails(update: Pick<Update, "version" | "currentVersion" | "body">): PendingUpdate {
  return {
    version: update.version,
    currentVersion: update.currentVersion,
    notes: update.body?.trim() ?? "",
  };
}

/** The GitHub release page for a version, which the prompt links to. */
export function releaseNotesUrl(version: string): string {
  return `https://github.com/Umupa/Loci/releases/tag/v${version.replace(/^v/i, "")}`;
}

export type UpdateCheckOutcome = "disabled" | "busy" | "current" | "declined" | "available";

export type UpdateCheckResult = { outcome: UpdateCheckOutcome } | { outcome: "failed"; error: string };

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Checks GitHub Releases. An interactive check opens the prompt when a release
 * is offered; a quiet one leaves a badge on the settings button instead, and
 * skips a version the user already put off in this run.
 */
export async function checkForUpdate({ interactive }: { interactive: boolean }): Promise<UpdateCheckResult> {
  if (!(await updatesEnabled())) return { outcome: "disabled" };
  if (busy || state.promptOpen || state.progress.phase === "downloading" || state.progress.phase === "installing") {
    return { outcome: "busy" };
  }
  busy = true;
  try {
    const update = await check();
    if (!update) return { outcome: "current" };
    if (!interactive && declined === update.version) {
      forget(update);
      return { outcome: "declined" };
    }
    forget(held);
    held = update;
    publish({ pending: updateDetails(update), promptOpen: interactive, progress: { phase: "idle" } });
    return { outcome: "available" };
  } catch (error) {
    if (!interactive) console.warn("loci: update check failed", error);
    return { outcome: "failed", error: errorMessage(error) };
  } finally {
    busy = false;
  }
}

/** Whether a newer release exists, for `loci updates check`; opens nothing. */
export type UpdateProbe = { available: boolean; version: string | null; current: string };

export async function checkForUpdateNow(): Promise<UpdateProbe> {
  if (!(await updatesEnabled())) return { available: false, version: null, current: await getVersion() };
  const update = await check();
  if (!update) return { available: false, version: null, current: await getVersion() };
  const probe: UpdateProbe = { available: true, version: update.version, current: update.currentVersion };
  await update.close().catch(() => undefined);
  return probe;
}

/** Opens the prompt for a release a quiet check found. */
export function openUpdatePrompt(): void {
  if (!state.pending || state.promptOpen) return;
  patch({ promptOpen: true });
}

/**
 * Later, and the prompt's Esc and ✕. The version is remembered for this run so
 * quiet checks do not bring the prompt back; an interactive check still does.
 */
export function dismissUpdatePrompt(): void {
  if (state.progress.phase === "downloading" || state.progress.phase === "installing") return;
  if (state.pending) declined = state.pending.version;
  const update = held;
  held = null;
  forget(update);
  publish(INITIAL);
}

/** Downloads the release, installs it and relaunches. */
export async function installPendingUpdate(): Promise<void> {
  const update = held;
  if (!update) return;
  if (state.progress.phase === "downloading" || state.progress.phase === "installing") return;
  let received = 0;
  let total: number | undefined;
  patch({ promptOpen: true, progress: { phase: "downloading", percent: null } });
  try {
    await update.downloadAndInstall((event) => {
      if (event.event === "Started") {
        total = event.data.contentLength;
        patch({ progress: { phase: "downloading", percent: total ? 0 : null } });
      } else if (event.event === "Progress") {
        received += event.data.chunkLength;
        patch({ progress: { phase: "downloading", percent: total ? Math.min(100, Math.round((received / total) * 100)) : null } });
      } else {
        // The download is complete and installation follows at once.
        patch({ progress: { phase: "installing" } });
      }
    });
    patch({ progress: { phase: "installing" } });
    await relaunch();
  } catch (error) {
    patch({ progress: { phase: "failed", error: errorMessage(error) } });
  }
}

/** Clears this module's state, for tests. */
export function resetUpdatesForTests(): void {
  forget(held);
  held = null;
  busy = false;
  declined = null;
  publish(INITIAL);
}

/** Checks a little after launch, then every few hours while Loci is open. */
export function startUpdateChecks(): () => void {
  const run = () => void checkForUpdate({ interactive: false });
  const first = window.setTimeout(run, FIRST_CHECK_DELAY_MS);
  const every = window.setInterval(run, CHECK_INTERVAL_MS);
  return () => {
    window.clearTimeout(first);
    window.clearInterval(every);
  };
}
