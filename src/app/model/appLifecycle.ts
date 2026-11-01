import { invoke } from "@tauri-apps/api/core";
import { hasFileDrafts } from "../../features/files/model/fileDrafts";
import { ask } from "@tauri-apps/plugin-dialog";
import {
  bindHarnessSession,
  forgetHarnessSession,
  isLiveHarness,
} from "../../integrations/harness/core/registry";
import { killAllChildren } from "../../integrations/harness/core/child";
import {
  hasInFlightSessions,
  inFlightRefs,
  isInFlightSession,
  markTurnInterrupted,
  quitWhileBusyMessage,
  wasTurnInterrupted,
  workspaceFromResumed,
  type ResumedWorkspace,
} from "../../features/sessions/model/inFlight";
import { sessionWorkCwd, type Session } from "../../features/sessions/model/session";
import { sessionChildHarnesses } from "../../features/sessions/model/handoff";
import {
  getSession,
  listInFlightSessions,
  replaceInFlightSessions,
  shouldPersistSession,
  upsertSession,
} from "../../features/sessions/data/sessionStore";

export type { ResumedWorkspace };
export { hasInFlightSessions };

export type BootWorkspace = {
  /** Sessions whose turns a quit interrupted, to resume. */
  resumed: ResumedWorkspace | null;
};

export type WorkspaceSaveMode = "quit" | "transition" | "unload";

let resumedPromise: Promise<ResumedWorkspace | null> | null = null;
let bootPromise: Promise<BootWorkspace> | null = null;
let quitting = false;
let quitDialogOpen = false;
let bootingResumed: ResumedWorkspace | null = null;
let liveWorkspace: {
  sessions: () => Session[];
  flush: () => void;
} | null = null;

export function isAppQuitting(): boolean {
  return quitting;
}

export function setQuitWorkspace(
  sessions: () => Session[],
  flush: () => void,
): () => void {
  liveWorkspace = { sessions, flush };
  bootingResumed = null;
  return () => {
    if (liveWorkspace?.sessions === sessions) liveWorkspace = null;
  };
}

/**
 * Persist this window for a quit the coordinator has already confirmed.
 * Exiting is `confirm_quit`'s job, once every window has reported ready.
 */
export async function handleQuitRequested(): Promise<boolean> {
  if (liveWorkspace) {
    liveWorkspace.flush();
    quitting = true;
    try {
      await persistQuitState(liveWorkspace.sessions(), "quit");
      return true;
    } catch {
      quitting = false;
      return false;
    }
  }
  const { resumed } = await loadBootWorkspace();
  const pending = resumed ?? bootingResumed;
  quitting = true;
  if (!pending) return true;
  try {
    await persistBootingResume(pending);
    return true;
  } catch {
    quitting = false;
    return false;
  }
}

/** Each window counts its own live turns; Rust sums them into one decision. */
export async function reportQuitPoll(id: number): Promise<void> {
  let inFlight = 0;
  if (liveWorkspace) {
    liveWorkspace.flush();
    // Count every active turn before asking to quit.
    inFlight = liveWorkspace.sessions().filter(isInFlightSession).length;
  }
  await invoke("quit_poll_reply", { id, inFlight }).catch(() => undefined);
}

/** The one quit dialog, shown by whichever window the coordinator picked. */
export async function askQuitConfirmation(
  id: number,
  inFlight: number,
): Promise<void> {
  let confirmed = false;
  if (!quitDialogOpen) {
    quitDialogOpen = true;
    try {
      confirmed = await ask(quitWhileBusyMessage(inFlight), {
        title: "Loci",
        kind: "warning",
        okLabel: "Quit",
      });
    } catch {
      confirmed = false;
    } finally {
      quitDialogOpen = false;
    }
  }
  await invoke("quit_decision", { id, confirmed }).catch(() => undefined);
}

export async function commitQuit(id: number): Promise<void> {
  const persisted = await handleQuitRequested();
  await invoke("quit_ready", { id, persisted }).catch(() => undefined);
}

/**
 * A quit that stopped part-way because another window could not save. This
 * window is staying open, so it must go back to persisting on unload.
 */
export function abortQuit(): void {
  quitting = false;
}

/** Confirm and stop this window's work without terminating other windows. */
export async function closeBusyWindow(): Promise<void> {
  if (!liveWorkspace) return;
  liveWorkspace.flush();
  await confirmAndCloseWindow(liveWorkspace.sessions());
}

export function loadResumedWorkspace(): Promise<ResumedWorkspace | null> {
  if (!resumedPromise) resumedPromise = loadResumedWorkspaceOnce();
  return resumedPromise;
}

/** Restore runs once; callers share the same promise. */
export function loadBootWorkspace(): Promise<BootWorkspace> {
  if (!bootPromise) bootPromise = loadResumedWorkspace().then((resumed) => ({ resumed }));
  return bootPromise;
}

/**
 * The sessions whose turns were running at quit. Earlier versions also saved
 * a tab layout in `workspace_snapshot`; it is no longer read or written, and
 * the table is left as it is.
 */
async function loadResumedWorkspaceOnce(): Promise<ResumedWorkspace | null> {
  const refs = await listInFlightSessions().catch(() => []);
  const sessions: Session[] = [];
  await Promise.all(refs.map(async (ref) => {
    const record = await getSession(ref.sessionId).catch(() => null);
    if (record) sessions.push(markTurnInterrupted(record));
  }));
  const workspace = workspaceFromResumed(refs.flatMap((ref) => sessions.filter((session) => session.id === ref.sessionId)));
  bootingResumed = workspace;
  if (workspace) {
    await Promise.all(
      workspace.sessions
        .filter(shouldPersistSession)
        .map((session) => upsertSession(session).catch(() => null)),
    );
  }
  return workspace;
}

export function bindResumedSessions(sessions: Session[]): void {
  for (const session of sessions) {
    if (!session.providerSessionId || !isLiveHarness(session.harness))
      continue;
    bindHarnessSession(
      session.harness,
      session.id,
      session.providerSessionId,
      sessionWorkCwd(session),
      session.providerAccountId,
      session.blocks,
    );
  }
}

export async function hideCurrentWindow(): Promise<void> {
  await invoke("hide_window");
}

export async function closeCurrentWindow(): Promise<void> {
  await invoke("destroy_window");
}

/** Persist the idle window before performing its native close action. */
export async function persistAndCloseWindow(persist: () => Promise<void>, toTray: boolean): Promise<void> {
  await persist();
  await (toTray ? hideCurrentWindow() : closeCurrentWindow());
}

/**
 * A window close that would discard unsaved file edits asks once, as leaving
 * a reader does. Hiding to the tray keeps the edits, so it does not ask.
 */
export async function confirmDiscardFileDrafts(toTray: boolean): Promise<boolean> {
  if (toTray || !hasFileDrafts()) return true;
  return ask("Close Loci and discard unsaved changes to your files?", {
    title: "Loci",
    kind: "warning",
    okLabel: "Discard changes",
    cancelLabel: "Keep editing",
  });
}

export async function persistLiveTranscripts(
  sessions: Session[],
): Promise<void> {
  await Promise.all(
    sessions
      .filter(shouldPersistSession)
      .map((session) => upsertSession(session).catch(() => null)),
  );
}

export async function persistQuitState(
  sessions: Session[],
  mode: WorkspaceSaveMode = "quit",
): Promise<void> {
  const refs = inFlightRefs(sessions);
  const interrupted = new Set(refs.map((ref) => ref.sessionId));
  // Explicit quit/close/reload can still be aborted on failure. Only the
  // unavoidable beforeunload path is best-effort. An idle window transition
  // must not clear the in-flight records owned by other windows.
  const write = <T,>(pending: Promise<T>): Promise<T | null> =>
    mode === "unload" ? pending.catch(() => null) : pending;

  await Promise.all(
    sessions.map(async (session) => {
      if (!shouldPersistSession(session)) return;
      const payload = interrupted.has(session.id)
        ? markTurnInterrupted(session)
        : session;
      await write(upsertSession(payload));
    }),
  );
  // Vite/webview reload must not wipe a restored snapshot: those chats are idle
  // in this process until Continue runs.
  if (mode === "quit" || refs.length > 0) {
    await write(replaceInFlightSessions(refs));
  }
}

async function persistBootingResume(workspace: ResumedWorkspace): Promise<void> {
  await Promise.all(
    workspace.sessions
      .filter(shouldPersistSession)
      .map((session) => upsertSession(session).catch(() => null)),
  );
  await replaceInFlightSessions(
    workspace.sessions
      .filter(wasTurnInterrupted)
      .map((session) => ({
        sessionId: session.id,
        cwd: session.cwd,
      })),
  ).catch(() => undefined);
}

async function confirmAndCloseWindow(sessions: Session[]): Promise<void> {
  if (quitDialogOpen) return;
  quitDialogOpen = true;
  try {
    const refs = inFlightRefs(sessions);
    if (refs.length > 0) {
      const ok = await ask(
        "Close this window and stop its running chats? Other windows will stay open.",
        { title: "Loci", kind: "warning", okLabel: "Close window" },
      );
      if (!ok) return;
    }
    quitting = true;
    try {
      await persistQuitState(sessions, "quit");
      await reapWindowRuntime(sessions, false);
      await closeCurrentWindow();
    } catch {
      quitting = false;
    }
  } finally {
    quitDialogOpen = false;
  }
}

export async function reapWindowRuntime(
  sessions: Session[],
  includeAllChildren = true,
): Promise<void> {
  await Promise.all(
    sessions.map((session) =>
      Promise.all(
        sessionChildHarnesses(session).map((harness) =>
          forgetHarnessSession(harness, session.id),
        ),
      ),
    ),
  );
  // Catalog probes, title generators, and usage scrapers are not session
  // children. Stop them so no auxiliary process outlives the window.
  if (includeAllChildren) await killAllChildren().catch(() => undefined);
}
