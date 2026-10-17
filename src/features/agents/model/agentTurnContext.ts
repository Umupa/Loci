import type { Session } from "../../sessions/model/session";
import { agentLook, type Agent } from "./agent";
import {
  AGENT_PROMPT_VERSION,
  agentContext,
  loadAgentFiles,
  needsAppContextReset,
  planAgentContext,
  recordAgentContext,
  recordAppContext,
} from "./agentFiles";
import { readingContext } from "./agentReading";
import {
  loadAgentRotation,
  planRotation,
  rotationReason,
  saveAgentRotation,
} from "./agentRotation";

export type AppTurnContext = {
  /** What the app puts ahead of the user's message this turn. */
  context: string[];
  /** Whether this turn tells a fresh provider session who it is. */
  introduces: boolean;
  /** The provider session must be dropped before sending. */
  rotates: boolean;
  /** A previous attempt created a fresh provider but did not finish sending its context. */
  recovering: boolean;
  /** Call once the provider session is fresh, so the next rotation starts here. */
  commitRotation(): void;
  /** Call once the provider accepted the turn, with the session it ran in. */
  record(providerSessionId: string | undefined): void;
};

/**
 * Agent sessions carry the soul once and memory again when it changes, and
 * rotate when their context is nearly full. All sessions carrying the removed
 * global policy are replaced once using the same transcript-excerpt path.
 */
export async function prepareAppTurn(
  agent: Agent | undefined,
  session: Pick<Session, "id" | "providerSessionId" | "context" | "blocks">,
  options: { canRotate: boolean; now?: number },
): Promise<AppTurnContext> {
  const previous = loadAgentRotation(session.id);
  const pending = previous?.pending;
  const recovering = !!pending &&
    (!session.providerSessionId || session.providerSessionId !== pending.replacedProvider);
  const reset = needsAppContextReset(session.id, session.providerSessionId);
  const reason = options.canRotate && !recovering
    ? (agent ? rotationReason(session) : undefined) ?? (reset ? "policy" : undefined)
    : undefined;
  const rotation = reason
    ? planRotation(
        session.blocks,
        previous,
        reason,
        options.now ?? Date.now(),
      )
    : undefined;
  const look = agent && agentLook(agent);
  // A turn must not fail over its memory; it goes without, and tries again next time.
  const files = agent
    ? await loadAgentFiles(agent.id).catch(() => undefined)
    : undefined;
  // Identity and projects are refreshed with the soul when they change.
  const handed = files && look && {
    ...files,
    soulHash: `${files.soulHash}:${look.name}:${look.role ?? ""}:${look.projects
      .map((project) => project.path)
      .join("|")}:${AGENT_PROMPT_VERSION}`,
  };
  const plan = handed
    ? planAgentContext(
        session.id,
        rotation || recovering ? undefined : session.providerSessionId,
        handed,
      )
    : undefined;
  const context: string[] = [];
  const brief = rotation || recovering
    ? pending?.brief ?? rotation?.brief(session.id)
    : undefined;
  if (brief) context.push(brief);
  if (brief && pending && previous) {
    // Preserve the original snapshot and the task whose failed send followed
    // it, so a later user message of only "retry" still has its request.
    const after = session.blocks.findIndex((block) => block.id === previous.afterBlockId);
    const tail = session.blocks.slice(after + 1);
    if (tail.length)
      context.push(planRotation(tail, undefined, "policy", options.now ?? Date.now()).brief(session.id));
  }
  if (files && look && plan && (plan.soul || plan.memory))
    context.push(agentContext(look, files, plan));
  // What is open beside the chat changes from turn to turn, so it goes every time.
  const reading = agent ? readingContext(agent.id) : undefined;
  if (reading) context.push(reading);
  return {
    context,
    introduces: !!plan?.soul,
    rotates: !!rotation,
    recovering,
    commitRotation: () => {
      if (rotation && brief)
        saveAgentRotation(session.id, {
          ...(previous?.pending ? previous : rotation.rotation),
          pending: { brief, replacedProvider: session.providerSessionId },
        });
    },
    record: (providerSessionId) => {
      // Editing must retain its provider history. Keep the old receipt until
      // that provider can be replaced, or a model switch returns a new one.
      if (
        reset &&
        !recovering &&
        !rotation &&
        (!providerSessionId || providerSessionId === session.providerSessionId)
      )
        return;
      const saved = loadAgentRotation(session.id);
      if (providerSessionId && providerSessionId === saved?.pending?.replacedProvider)
        return;
      if (handed) recordAgentContext(session.id, providerSessionId, handed);
      else recordAppContext(session.id, providerSessionId);
      if (saved?.pending)
        saveAgentRotation(session.id, { ...saved, pending: undefined });
    },
  };
}
