import { invoke } from "@tauri-apps/api/core";

/** Where a file sits in its git repository. */
export type RepoPlace = { repoRoot: string; pathInRepo: string };

/** A file's text, at a commit or (no `commit`) as it is on disk. */
export type CodeText = { text: string; commit?: string; head?: string } & Partial<RepoPlace>;

export type PinState = "current" | "moved" | "changed" | "missing-commit" | "missing-file" | "no-repo";

/** How a pinned file stands against the working tree. */
export type PinStatus = {
  state: PinState;
  commit?: string;
  head?: string;
  /** Commits HEAD is ahead of the pin. */
  ahead?: number;
  /** For `changed` with lines: where they are now, and whether untouched. */
  currentLines?: [number, number];
  exact?: boolean;
};

export function readCode(file: string, commit?: string): Promise<CodeText> {
  return invoke<CodeText>("code_read", { file, commit: commit ?? null });
}

export function codePinStatus(file: string, commit: string, lines?: [number, number]): Promise<PinStatus> {
  return invoke<PinStatus>("code_pin_status", { query: { file, commit, ...(lines ? { lines } : {}) } });
}

/** The full commit of `rev` (HEAD when left out) in the repository holding `file`. */
export function resolveCommit(file: string, rev?: string): Promise<{ commit: string } & RepoPlace> {
  return invoke<{ commit: string } & RepoPlace>("code_resolve", { file, rev: rev ?? null });
}

export const shortCommit = (sha: string) => sha.slice(0, 7);
