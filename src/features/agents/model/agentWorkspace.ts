import { newSession, type Session } from "../../sessions/model/session";
import { agentForSession, findAgent, saveAgentSessionId } from "./agent";
import { forgetAgentContext } from "./agentFiles";
import { forgetAgentRotation } from "./agentRotation";

const openingAgents = new Map<string, Promise<Session | undefined>>();

/**
 * Load the agent's conversation without opening or replacing a workspace tab.
 * A new one starts with Auto permissions in the home folder: no single
 * project is its own.
 */
export function ensureAgentSession(
  agentId: string,
  host: {
    home(): Promise<string>;
    load(id: string): Promise<Session | null | undefined>;
    create(cwd: string): Session;
    add(session: Session): void;
  },
): Promise<Session | undefined> {
  const pending = openingAgents.get(agentId);
  if (pending) return pending;
  const opening = loadAgentSession(agentId, host).finally(() => {
    if (openingAgents.get(agentId) === opening) openingAgents.delete(agentId);
  });
  openingAgents.set(agentId, opening);
  return opening;
}

async function loadAgentSession(
  agentId: string,
  host: Parameters<typeof ensureAgentSession>[1],
): Promise<Session | undefined> {
  const agent = findAgent(agentId);
  if (!agent) return undefined;
  if (agent.sessionId) {
    const existing = await host.load(agent.sessionId);
    if (existing) {
      host.add(existing);
      return existing;
    }
  }
  const home = await host.home();
  // Removed while the home folder was looked up.
  if (!findAgent(agentId)) return undefined;
  const session: Session = { ...host.create(home), runtimeMode: "auto" };
  saveAgentSessionId(agentId, session.id);
  host.add(session);
  return session;
}

/** Reset only the agent's chat, keeping its identity and memory. */
export async function resetAgentSession(
  current: Session,
  host: {
    stop(id: string): Promise<void>;
    remove(session: Session): Promise<void>;
    replace(previousId: string, session: Session): void;
  },
): Promise<Session> {
  const agentId = agentForSession(current.id)?.id;
  await host.stop(current.id);
  const fresh = newSession(
    current.harness,
    current.cwd,
    current.model,
    current.runtimeMode,
    current.modelSettings,
  );
  // A failed deletion must leave the original conversation selected.
  await host.remove(current);
  forgetAgentContext(current.id);
  forgetAgentRotation(current.id);
  if (agentId) saveAgentSessionId(agentId, fresh.id);
  host.replace(current.id, fresh);
  return fresh;
}
