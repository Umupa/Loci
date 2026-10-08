import { sameProjectPath } from "../projects/model/recents";
import type { SessionSummary } from "../sessions/data/sessionStore";
import { newSession, newSessionLike, type HarnessId, type Session } from "../sessions/model/session";
import { LEARN_HARNESSES, learnEnabledInThread, supportsLearnHarness } from "./learnCommand";

/**
 * The session a node's new session is made like: the project's last learning
 * conversation if it is still loaded, else its newest stored conversation on a
 * provider that can learn, else the first provider that can.
 */
export function learnSessionFor(
  cwd: string,
  loaded: readonly Session[],
  stored: readonly SessionSummary[],
  available: (harness: HarnessId) => boolean,
): Session {
  const here = loaded.filter((session) => sameProjectPath(session.cwd, cwd) && supportsLearnHarness(session.harness));
  const seed = [...here].reverse().find((session) => learnEnabledInThread(session.blocks)) ?? here[here.length - 1];
  if (seed) return newSessionLike(seed, cwd);
  const past = stored.find((summary) => !summary.archived && !summary.draft && supportsLearnHarness(summary.harness) && available(summary.harness));
  if (past) return newSession(past.harness, cwd, past.model, past.runtimeMode);
  return newSession(LEARN_HARNESSES.find(available) ?? LEARN_HARNESSES[0], cwd);
}
