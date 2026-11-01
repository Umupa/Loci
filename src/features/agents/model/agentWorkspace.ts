import { modelEffortSetting, resolveModel } from "../../sessions/model/models";
import { newSession, type Session } from "../../sessions/model/session";
import {
  agentForSession,
  findAgent,
  saveAgentDefaults,
  saveAgentSessionId,
  type Agent,
  type MentorDefaults,
} from "./agent";
import {
  AGENT_ACCESS_MIGRATION,
  loadNewAgentAccess,
  markAgentAccessMigrated,
} from "./agentAccess";
import { forgetAgentContext } from "./agentFiles";
import { forgetAgentRotation } from "./agentRotation";

const openingAgents = new Map<string, Promise<Session | undefined>>();

/**
 * The provider, model, effort and permission mode a chat runs with, as the
 * mentor's `mentor.json` `defaults` keep them.
 */
export function defaultsFromSession(
  session: Pick<Session, "harness" | "model" | "modelSettings" | "runtimeMode">,
): MentorDefaults {
  const setting = modelEffortSetting(resolveModel(session.harness, session.model));
  const effort = setting ? session.modelSettings[setting.id] : undefined;
  return {
    provider: session.harness,
    model: session.model,
    mode: session.runtimeMode,
    ...(effort ? { effort } : {}),
    ...(Object.keys(session.modelSettings).length
      ? { modelSettings: { ...session.modelSettings } }
      : {}),
  };
}

/**
 * A fresh conversation that starts as the mentor's stored defaults say. The
 * stored model and effort win over what the last one chosen anywhere or the
 * catalogs (which may not have loaded yet) would pick.
 */
export function sessionFromDefaults(cwd: string, defaults: MentorDefaults): Session {
  const storedModel = defaults.model.trim();
  const created = newSession(defaults.provider, cwd, storedModel, defaults.mode);
  // A catalog that has not loaded yet does not know a stored custom model;
  // `newSession` would resolve it to the provider's default. Keep the id the
  // provider accepted before.
  const session: Session = storedModel && created.model !== storedModel
    ? { ...created, model: storedModel }
    : created;
  if (defaults.modelSettings && Object.keys(defaults.modelSettings).length) {
    return { ...session, modelSettings: { ...session.modelSettings, ...defaults.modelSettings } };
  }
  const setting = defaults.effort
    ? modelEffortSetting(resolveModel(session.harness, session.model))
    : undefined;
  if (!setting || !setting.options.some((option) => option.value === defaults.effort))
    return session;
  return {
    ...session,
    modelSettings: { ...session.modelSettings, [setting.id]: defaults.effort! },
  };
}

/** Keeps a mentor's stored defaults with its chat; other chats are left alone. */
export function saveSessionDefaults(
  session: Pick<Session, "id" | "harness" | "model" | "modelSettings" | "runtimeMode">,
): void {
  const agent = agentForSession(session.id);
  if (agent) saveAgentDefaults(agent.id, defaultsFromSession(session));
}

/**
 * Load the agent's conversation without opening or replacing a workspace tab.
 * A new one starts with the default permissions for new mentors in the agent's
 * workdir, or in the home folder when that cannot be made. A saved one keeps
 * the folder it started in: the provider's conversation is tied to it. A saved
 * chat from before mentors defaulted to Full access switches once; a choice
 * made in its settings after that is kept.
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
      const session = migrateAgentAccess(agent, existing);
      host.add(session);
      return session;
    }
  }
  const cwd = await host.workdir(agentId).catch(() => host.home());
  // Removed while its folder was looked up.
  const updated = findAgent(agentId);
  if (!updated) return undefined;
  const session: Session = updated.defaults
    ? sessionFromDefaults(cwd, updated.defaults)
    : { ...host.create(cwd), runtimeMode: loadNewAgentAccess() };
  saveAgentSessionId(agentId, session.id);
  // A mentor created now took the current default; reopening it is not a migration.
  markAgentAccessMigrated(agentId);
  // Held in `mentor.json`, so an empty chat that is released comes back the same.
  saveAgentDefaults(agentId, defaultsFromSession(session));
  host.add(session);
  return session;
}

/**
 * The one-time switch for a mentor whose chat predates Full access. The flag is
 * recorded here so a later manual choice in its settings is not overridden.
 */
function migrateAgentAccess(agent: Agent, session: Session): Session {
  if (agent.accessMigrated) return session;
  markAgentAccessMigrated(agent.id);
  const migrated = session.runtimeMode === AGENT_ACCESS_MIGRATION
    ? session
    : { ...session, runtimeMode: AGENT_ACCESS_MIGRATION };
  saveAgentDefaults(agent.id, defaultsFromSession(migrated));
  return migrated;
}

/**
 * Reset only the agent's chat, keeping its identity, memory and permissions.
 * The fresh chat starts in the agent's workdir: this is where a chat that began
 * in the home folder moves into it, since its provider conversation ends here
 * anyway.
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
  const agent = agentId ? findAgent(agentId) : undefined;
  const cwd = agentId && host.workdir
    ? await host.workdir(agentId).catch(() => current.cwd)
    : current.cwd;
  await host.stop(current.id);
  const fresh = agent?.defaults
    ? sessionFromDefaults(cwd, agent.defaults)
    : newSession(
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
