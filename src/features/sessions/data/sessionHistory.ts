import { fuzzyMatch } from "../../../shared/lib/fuzzy";
import { sameProjectPath } from "../../projects/model/recents";
import {
  sessionDisplayTitle,
  sessionDraftBlock,
  sessionNeedsInput,
  type Session,
} from "../model/session";
import { shouldPersistSession, type SessionSummary } from "./sessionStore";

export function compareSessionSummaries(
  a: SessionSummary,
  b: SessionSummary,
): number {
  const pin = Number(!!b.pinned) - Number(!!a.pinned);
  if (pin !== 0) return pin;
  return b.updatedAt - a.updatedAt || a.id.localeCompare(b.id);
}

export function mergeHistorySummary(
  current: SessionSummary[],
  summary: SessionSummary,
): SessionSummary[] {
  const previous = current.find((entry) => entry.id === summary.id);
  const next = {
    ...summary,
    archived: summary.archived ?? previous?.archived,
    pinned: summary.pinned ?? previous?.pinned,
  };
  return [next, ...current.filter((entry) => entry.id !== summary.id)].sort(
    compareSessionSummaries,
  );
}

/**
 * Swap in one project's freshly fetched rows while leaving every other
 * project's cached rows alone. `history` is keyed only by the `cwd` on each
 * row, so holding several projects at once costs nothing and lets a revisit
 * paint from cache instead of from an empty list.
 */
export function replaceProjectHistory(
  current: SessionSummary[],
  cwd: string,
  rows: SessionSummary[],
): SessionSummary[] {
  const others = current.filter((entry) => !sameProjectPath(entry.cwd, cwd));
  return [...others, ...rows];
}

/**
 * `mergeHistorySummary`, but scoped so persisting a session cannot drop the
 * other projects the cache is holding. A session that changed project is
 * removed from its old one so the id cannot appear twice.
 */
export function mergeProjectHistorySummary(
  current: SessionSummary[],
  summary: SessionSummary,
): SessionSummary[] {
  const mine: SessionSummary[] = [];
  const others: SessionSummary[] = [];
  for (const entry of current) {
    if (sameProjectPath(entry.cwd, summary.cwd)) mine.push(entry);
    else if (entry.id !== summary.id) others.push(entry);
  }
  return [...others, ...mergeHistorySummary(mine, summary)];
}

export function filterSessionsByArchive(
  rows: SessionSummary[],
  showArchived: boolean,
): SessionSummary[] {
  return rows.filter((row) => !!row.archived === showArchived);
}

export function filterSessionsByQuery(
  rows: SessionSummary[],
  query: string,
): SessionSummary[] {
  const needle = query.trim();
  if (!needle) return rows;
  return rows.filter((row) => sessionSearchHit(row, needle));
}

function sessionSearchHit(row: SessionSummary, query: string): boolean {
  const title = sessionDisplayTitle(row.title, row.harness);
  const fields = [title, row.title, row.model, row.harness];
  return fields.some((field) => field && fuzzyMatch(query, field) != null);
}

export function summaryFromSession(
  session: Session,
): SessionSummary {
  return {
    id: session.id,
    cwd: session.cwd,
    harness: session.harness,
    model: session.model,
    runtimeMode: session.runtimeMode,
    title: session.title,
    draft: !!sessionDraftBlock(session),
    providerSessionId: session.providerSessionId,
    createdAt: 0,
    updatedAt: Date.now(),
  };
}

export function historyWithLiveSessions(
  history: SessionSummary[],
  sessions: Session[],
  cwd: string,
): SessionSummary[] {
  let rows = history.filter((entry) => sameProjectPath(entry.cwd, cwd));
  for (const session of sessions) {
    if (!sameProjectPath(session.cwd, cwd)) continue;
    const live = session.busy || sessionNeedsInput(session);
    if (!shouldPersistSession(session) && !live) continue;
    const storedIndex = rows.findIndex((row) => row.id === session.id);
    if (storedIndex >= 0) {
      const stored = rows[storedIndex];
      const draft = !!sessionDraftBlock(session);
      if (
        !!stored.draft !== draft ||
        stored.title !== session.title
      ) {
        rows[storedIndex] = {
          ...stored,
          title: session.title,
          draft: draft || undefined,
        };
      }
      continue;
    }
    rows = mergeHistorySummary(rows, summaryFromSession(session));
  }
  return rows.sort(compareSessionSummaries);
}
