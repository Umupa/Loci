import type { Session } from "../../sessions/model/session";
import { agentLook, type Agent } from "./agent";
import {
  AGENT_PROMPT_VERSION,
  agentContext,
  loadAgentFiles,
  planAgentContext,
  recordAgentContext,
} from "./agentFiles";
import {
  loadAgentRotation,
  planRotation,
  rotationReason,
  saveAgentRotation,
} from "./agentRotation";

export type AgentTurnContext = {
  /** What the app puts ahead of the user's message this turn. */
  context: string[];
  /** Whether this turn tells a fresh provider session who it is. */
  introduces: boolean;
  /** The provider session must be dropped before sending: its context is full. */
  rotates: boolean;
  /** Call once the provider session is fresh, so the next rotation starts here. */
  commitRotation(): void;
  /** Call once the provider accepted the turn, with the session it ran in. */
  record(providerSessionId: string | undefined): void;
};

/**
 * What an agent's turn carries beyond the user's words. A provider session is
 * handed the soul once and memory again only when it changes; one whose
 * context is nearly full is replaced, and the fresh one is briefed on where
 * the conversation was.
 */
export async function prepareAgentTurn(
  agent: Agent,
  session: Pick<Session, "id" | "providerSessionId" | "context" | "blocks">,
  options: { canRotate: boolean; now?: number },
): Promise<AgentTurnContext> {
  const reason = options.canRotate ? rotationReason(session) : undefined;
  const rotation = reason
    ? planRotation(
        session.blocks,
        loadAgentRotation(session.id),
        reason,
        options.now ?? Date.now(),
      )
    : undefined;
  const look = agentLook(agent);
  // A turn must not fail over its memory; it goes without, and tries again next time.
  const files = await loadAgentFiles(agent.id).catch(() => undefined);
  // Who it is counts as part of its soul: a rename or a change to its
  // projects is handed over too, and so is a change to the fixed rules.
  const handed = files && {
    ...files,
    soulHash: `${files.soulHash}:${look.name}:${look.role ?? ""}:${look.projects
      .map((project) => project.path)
      .join("|")}:${AGENT_PROMPT_VERSION}`,
  };
  const plan = handed
    ? planAgentContext(
        session.id,
        rotation ? undefined : session.providerSessionId,
        handed,
      )
    : undefined;
  const context: string[] = [];
  if (rotation) context.push(rotation.brief(session.id));
  if (files && plan && (plan.soul || plan.memory))
    context.push(agentContext(look, files, plan));
  return {
    context,
    introduces: !!plan?.soul,
    rotates: !!rotation,
    commitRotation: () => {
      if (rotation) saveAgentRotation(session.id, rotation.rotation);
    },
    record: (providerSessionId) => {
      if (handed) recordAgentContext(session.id, providerSessionId, handed);
    },
  };
}
