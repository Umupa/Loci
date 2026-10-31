import { stopStreaming } from "../../../integrations/harness/core/apply";
import { forgetHarnessSession } from "../../../integrations/harness/core/registry";
import {
  buildDeterministicHandoff,
  completeHandoff,
  isPreparingHandoff,
  sessionChildHarnesses,
} from "./handoff";
import type { HarnessId, RuntimeMode, Session } from "./session";
import {
  deleteSession,
  setSessionArchived,
  shouldPersistSession,
  upsertSession,
  type SessionSummary,
} from "../data/sessionStore";
type Workspace = {
  sessions: Session[];
};

/** The sessions left once one is removed. */
export type SessionRemoval = { sessions: Session[] };

type ReplacementSeed = {
  harness?: HarnessId;
  cwd: string;
  model?: string;
  runtimeMode?: RuntimeMode;
  modelSettings?: Record<string, string>;
};

type WorkspaceChange =
  | { type: "stopped"; session: Session }
  | {
      type: "removed";
      mode: SessionRemovalMode;
      removal: SessionRemoval;
      session?: Session;
      savedSummary?: SessionSummary;
    };

type SessionRemovalMode = "archive" | "delete";

type SessionRemovalOptions = {
  mode: SessionRemovalMode;
  replacement: ReplacementSeed;
  workspace: {
    snapshot(): Workspace;
    apply(change: WorkspaceChange): void;
  };
  confirm(mode: SessionRemovalMode): Promise<boolean>;
  stop(sessionId: string): Promise<unknown>;
};

/**
 * Own the two-phase session-removal transaction. Callers supply state and I/O
 * adapters once; the returned interface exposes only the domain operation.
 */
export function createSessionRemover(options: SessionRemovalOptions): {
  remove(sessionId: string): Promise<boolean>;
} {
  return { remove: (sessionId) => removeSession(sessionId, options) };
}

/** Run the same lifecycle for archive and delete, reading state after each wait. */
async function removeSession(
  sessionId: string,
  options: SessionRemovalOptions,
): Promise<boolean> {
  if (!(await options.confirm(options.mode))) return false;

  await options.stop(sessionId);
  const latest = options.workspace
    .snapshot()
    .sessions.find((session) => session.id === sessionId);
  let stopped = latest;
  if (latest) {
    stopped = latest.busy ? stopStreaming(latest) : latest;
    if (isPreparingHandoff(stopped)) {
      stopped = completeHandoff(stopped, buildDeterministicHandoff(stopped));
    }
    if (stopped.queuedMessages?.length) {
      stopped = { ...stopped, queueStatus: "paused" };
    }
    // Cancellation invalidates normal turn completion. Keep a usable stopped
    // session even when the following storage operation fails.
    options.workspace.apply({ type: "stopped", session: stopped });
  }
  const harnesses: HarnessId[] = stopped
    ? sessionChildHarnesses(stopped)
    : [options.replacement.harness ?? "claude"];
  if (options.mode === "delete") {
    // Release native processes before deleting the record, so a following
    // close cannot race fire-and-forget cleanup.
    await Promise.all(
      harnesses.map((harness) => forgetHarnessSession(harness, sessionId)),
    );
  }

  let savedSummary: SessionSummary | undefined;
  if (options.mode === "delete") {
    const imagePaths = stopped?.blocks.flatMap((block) =>
      block.role === "image" && block.image ? [block.image.path] : [],
    ) ?? [];
    await deleteSession(sessionId, imagePaths);
  } else {
    if (stopped && shouldPersistSession(stopped)) {
      const saved = await upsertSession(stopped);
      if (!saved) throw new Error("The conversation could not be saved.");
      savedSummary = saved;
    }
    await setSessionArchived(sessionId, true);
  }

  const current = options.workspace.snapshot();
  const removedSession = current.sessions.find(
    (session) => session.id === sessionId,
  );
  const removal = { sessions: current.sessions.filter((session) => session.id !== sessionId) };
  // No await between the final read and commit: unrelated streaming updates
  // must survive this operation.
  if (options.mode === "archive") {
    for (const harness of harnesses) {
      void forgetHarnessSession(harness, sessionId);
    }
  }
  options.workspace.apply({
    type: "removed",
    mode: options.mode,
    removal,
    session: removedSession,
    savedSummary,
  });
  return true;
}
