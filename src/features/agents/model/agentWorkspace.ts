import { newSession, type Session } from "../../sessions/model/session";
import { agentForSession, findAgent, saveAgentSessionId } from "./agent";
import { forgetAgentContext } from "./agentFiles";
import { forgetAgentRotation } from "./agentRotation";

const openingAgents = new Map<string, Promise<Session | undefined>>();

/**
 * Load the agent's conversation without opening or replacing a workspace tab.
 * A new one starts with Auto permissions in the agent's workdir, or in the
 * home folder when that cannot be made. A saved one keeps the folder it
 * started in: the provider's conversation is tied to it.
 */
export function ensureAgentSession(
  agentId: string,
  host: {
    home(): Promise<string>;
    /** The agent's workdir, created on first use. */
    workdir(agentId: string): Promise<string>;
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
  const cwd = await host.workdir(agentId).catch(() => host.home());
  // Removed while its folder was looked up.
  if (!findAgent(agentId)) return undefined;
  const session: Session = { ...host.create(cwd), runtimeMode: "auto" };
  saveAgentSessionId(agentId, session.id);
  host.add(session);
  return session;
}

/**
 * Reset only the agent's chat, keeping its identity and memory. The fresh
 * chat starts in the agent's workdir: this is where a chat that began in the
 * home folder moves into it, since its provider conversation ends here anyway.
 */
export async function resetAgentSession(
  current: Session,
  host: {
    /** The agent's workdir; the old folder is kept when it cannot be made. */
    workdir?(agentId: string): Promise<string>;
    stop(id: string): Promise<void>;
    remove(session: Session): Promise<void>;
    replace(previousId: string, session: Session): void;
  },
): Promise<Session> {
  const agentId = agentForSession(current.id)?.id;
  const cwd = agentId && host.workdir
    ? await host.workdir(agentId).catch(() => current.cwd)
    : current.cwd;
  await host.stop(current.id);
  const fresh = newSession(
    current.harness,
    cwd,
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
