import { projectKey, projectName } from "../../../shared/lib/paths";
import {
  hasPendingApproval,
  type Block,
  type Session,
} from "../../sessions/model/session";
import { AGENT_AVATARS, defaultAgentName } from "./agentAvatars";

/** The colors an agent's avatar can take. */
export const AGENT_COLORS = [
  "hsl(211 92% 62%)",
  "hsl(12 80% 58%)",
  "hsl(45 90% 55%)",
  "hsl(142 55% 50%)",
  "hsl(330 70% 62%)",
  "hsl(280 55% 62%)",
  "hsl(175 55% 48%)",
  "hsl(25 85% 58%)",
  "hsl(245 75% 65%)",
] as const;

/**
 * An agent is long-lived and its own: a name, a face and a color, one
 * conversation, and a working folder of its own (see `agentWorkdir`).
 */
export type Agent = {
  id: string;
  /** Its conversation; absent until it is first opened. */
  sessionId?: string;
  /** Replaces the avatar's own name. */
  name?: string;
  /** Its one main job in a few words, shown beside its name: "CI watcher". */
  role?: string;
  avatar: string;
  color: string;
  /**
   * Its working folder: cloned source in `repos/`, experiments in `lab/`.
   * Absent until first use; it keeps its path when the agent is renamed.
   */
  workdir?: string;
  /**
   * Other folders it may use, in the order they were added. Older agents
   * were given these as "projects"; the key keeps that name for their data.
   */
  projects: string[];
  /** New sessions appear in the project sidebar unless explicitly disabled. */
  showStartedSessionsInSidebar?: boolean;
  /** Files the sessions it starts into a sidebar folder named after it. */
  useSidebarFolders?: boolean;
  /**
   * Its saved chat has already had the one-time switch to Full access, so the
   * permission mode the user picks from now on is kept.
   */
  accessMigrated?: true;
};

const ROSTER_KEY = "loci:agent-roster";
const AGENTS_CHANGED = "loci:agents-changed";

function readJson(key: string): unknown {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as unknown) : undefined;
  } catch {
    return undefined;
  }
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function newAgentId(): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

function parseAgent(value: unknown): Agent | undefined {
  const entry = record(value);
  if (typeof entry.id !== "string" || !/^[A-Za-z0-9-]+$/.test(entry.id))
    return undefined;
  const text = (key: string) =>
    typeof entry[key] === "string" ? (entry[key] as string) : undefined;
  const sessionId = text("sessionId");
  const name = text("name");
  const role = text("role");
  const workdir = text("workdir");
  return {
    id: entry.id,
    ...(sessionId ? { sessionId } : {}),
    ...(name ? { name } : {}),
    ...(role ? { role } : {}),
    avatar: text("avatar") ?? AGENT_AVATARS[0].name,
    color: text("color") ?? AGENT_COLORS[0],
    ...(workdir ? { workdir } : {}),
    projects: Array.isArray(entry.projects)
      ? entry.projects.filter(
          (path): path is string => typeof path === "string" && !!path,
        )
      : [],
    ...(typeof entry.showStartedSessionsInSidebar === "boolean"
      ? { showStartedSessionsInSidebar: entry.showStartedSessionsInSidebar }
      : {}),
    ...(entry.useSidebarFolders === true ? { useSidebarFolders: true } : {}),
    ...(entry.accessMigrated === true ? { accessMigrated: true } : {}),
  };
}

/** Every agent, in the order the rail shows them. */
export function listAgents(): Agent[] {
  const parsed = readJson(ROSTER_KEY);
  if (!Array.isArray(parsed)) return [];
  return parsed.flatMap((entry) => parseAgent(entry) ?? []);
}

function saveRoster(roster: readonly Agent[]): void {
  try {
    localStorage.setItem(ROSTER_KEY, JSON.stringify(roster));
  } catch {
    return;
  }
  window.dispatchEvent(new CustomEvent(AGENTS_CHANGED));
}

export function findAgent(id: string): Agent | undefined {
  return listAgents().find((agent) => agent.id === id);
}

/**
 * An agent's library as the place a canvas lives. A canvas belongs to a
 * project folder; an agent is tied to none, so what it draws for the
 * conversation, a diagram for a lesson, say, goes into its library beside
 * its documents instead of needing a project first. This stands where a
 * project path would, and is not a path.
 */
const AGENT_CANVAS_SCOPE = "loci-agent://";

export function agentCanvasScope(agentId: string): string {
  return `${AGENT_CANVAS_SCOPE}${agentId}`;
}

/** The agent whose library a canvas is in, if it is in one. */
export function canvasScopeAgentId(cwd: string | undefined): string | undefined {
  return cwd?.startsWith(AGENT_CANVAS_SCOPE) ? cwd.slice(AGENT_CANVAS_SCOPE.length) : undefined;
}

/** The agent whose conversation this is. */
export function agentForSession(sessionId: string): Agent | undefined {
  return listAgents().find((agent) => agent.sessionId === sessionId);
}

export function isAgentSession(sessionId: string): boolean {
  return !!agentForSession(sessionId);
}

/**
 * The avatar and color the next agent gets: ones the others are not using
 * yet, where any are left.
 */
export function nextAgentLook(
  roster: readonly Pick<Agent, "avatar" | "color">[] = listAgents(),
): { avatar: string; color: string } {
  const avatars = new Set(roster.map((agent) => agent.avatar));
  const colors = new Set(roster.map((agent) => agent.color));
  return {
    avatar: (
      AGENT_AVATARS.find((avatar) => !avatars.has(avatar.name)) ??
      AGENT_AVATARS[roster.length % AGENT_AVATARS.length]
    ).name,
    color:
      AGENT_COLORS.find((color) => !colors.has(color)) ??
      AGENT_COLORS[roster.length % AGENT_COLORS.length],
  };
}

/**
 * A new agent starting with the projects given, if any. It takes the look
 * and name chosen for it, or the next look the others are not using.
 */
export function createAgent(
  projects: readonly string[] = [],
  chosen: Partial<Pick<Agent, "name" | "role" | "avatar" | "color">> = {},
): Agent {
  const roster = listAgents();
  const name = chosen.name?.trim();
  const agent: Agent = {
    id: newAgentId(),
    ...nextAgentLook(roster),
    ...(chosen.avatar ? { avatar: chosen.avatar } : {}),
    ...(chosen.color ? { color: chosen.color } : {}),
    ...(name ? { name } : {}),
    ...(chosen.role?.trim() ? { role: chosen.role.trim() } : {}),
    projects: uniqueProjects(projects),
  };
  saveRoster([...roster, agent]);
  return agent;
}

function uniqueProjects(paths: readonly string[]): string[] {
  const seen = new Set<string>();
  return paths.filter((path) => {
    const key = projectKey(path);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function updateAgent(
  id: string,
  change: (agent: Agent) => Agent,
): Agent | undefined {
  const roster = listAgents();
  const index = roster.findIndex((agent) => agent.id === id);
  if (index < 0) return undefined;
  const next = change(roster[index]);
  if (!next.name?.trim()) delete next.name;
  if (!next.role?.trim()) delete next.role;
  if (!next.workdir?.trim()) delete next.workdir;
  next.projects = uniqueProjects(next.projects);
  roster[index] = next;
  saveRoster(roster);
  return next;
}

/** Forgets the agent. Its folder of files stays on disk. */
export function removeAgent(id: string): void {
  saveRoster(listAgents().filter((agent) => agent.id !== id));
}

export function reorderAgents(ids: readonly string[]): void {
  const roster = listAgents();
  const order = new Map(ids.map((id, index) => [id, index]));
  saveRoster(
    [...roster].sort(
      (a, b) =>
        (order.get(a.id) ?? Number.MAX_SAFE_INTEGER) -
        (order.get(b.id) ?? Number.MAX_SAFE_INTEGER),
    ),
  );
}

export function saveAgentSessionId(agentId: string, sessionId: string): void {
  updateAgent(agentId, (agent) => ({ ...agent, sessionId }));
}

export function addAgentProject(agentId: string, path: string): void {
  updateAgent(agentId, (agent) => ({
    ...agent,
    projects: [...agent.projects, path],
  }));
}

export function removeAgentProject(agentId: string, path: string): void {
  const key = projectKey(path);
  updateAgent(agentId, (agent) => ({
    ...agent,
    projects: agent.projects.filter((project) => projectKey(project) !== key),
  }));
}

/**
 * Every folder the agent works in: its own workdir first, then the other
 * folders it was given. Its reach through the app CLI follows this list.
 */
export function agentFolders(agent: Pick<Agent, "workdir" | "projects">): string[] {
  return uniqueProjects(agent.workdir ? [agent.workdir, ...agent.projects] : agent.projects);
}

/** Whether the agent has been given this project. */
export function agentWorksOn(agent: Pick<Agent, "projects">, path: string) {
  const key = projectKey(path);
  return agent.projects.some((project) => projectKey(project) === key);
}

/**
 * Calls back when the roster changes: in this window through its own event,
 * and in another window (or anything else writing storage) through `storage`.
 */
export function subscribeAgents(onChange: () => void): () => void {
  const onStorage = (event: StorageEvent) => { if (event.key === ROSTER_KEY || event.key === null) onChange(); };
  window.addEventListener(AGENTS_CHANGED, onChange);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(AGENTS_CHANGED, onChange);
    window.removeEventListener("storage", onStorage);
  };
}

/** Snapshot for `useSyncExternalStore`; stable while storage is unchanged. */
export function agentsSnapshot(): string {
  try {
    return localStorage.getItem(ROSTER_KEY) ?? "";
  } catch {
    return "";
  }
}

/** One other folder an agent was given, as the rail labels it. */
export type AgentProject = { path: string; name: string };

export type AgentLook = {
  /** The user's name for it, or its avatar's: "Ember", "Wisp". */
  name: string;
  /** Its one main job, when it has been given one. */
  role?: string;
  avatar: string;
  color: string;
  /** Its working folder, once it has one. */
  workdir?: string;
  /** Other folders it was given, by their rail labels. */
  projects: AgentProject[];
};

/** How an agent looks, its workdir, and the other folders it was given. */
export function agentLook(agent: Agent): AgentLook {
  return {
    name: agent.name?.trim() || defaultAgentName(agent.avatar),
    ...(agent.role?.trim() ? { role: agent.role.trim() } : {}),
    avatar: agent.avatar,
    color: agent.color,
    ...(agent.workdir ? { workdir: agent.workdir } : {}),
    projects: agent.projects.map((path) => ({
      path,
      name: projectName(path),
    })),
  };
}

/** Its projects as a phrase: "app", "app and site", "app, site and api". */
export function agentProjectsPhrase(projects: readonly AgentProject[]): string {
  const names = projects.map((project) => project.name);
  if (names.length <= 1) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/** Plain one-line take on a step's title, for the agent's status. */
function plainLine(text: string): string {
  return text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/^\s*(?:#{1,6}|>)\s*/gm, "")
    .replace(/[`*_]/g, "")
    .replace(/^\s*[-\d.]+\s+/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** What the agent is doing right now, as the rail shows it. */
export type AgentStatus = "working" | "needs-you" | "idle";

export type AgentState = {
  status: AgentStatus;
  /** Short present-tense note while working or waiting. */
  activity?: string;
};

export const AGENT_STATUS_LABEL: Record<AgentStatus, string> = {
  working: "Working",
  "needs-you": "Needs you",
  idle: "Idle",
};

/** The agent's state, with the step it is on or the call it is waiting for. */
export function agentState(
  session: Pick<Session, "blocks" | "busy" | "pendingQuestion" | "usageLimit">,
): AgentState {
  const { blocks, pendingQuestion: question } = session;
  if (question) {
    return {
      status: "needs-you",
      activity: question.title?.trim() || question.questions[0]?.prompt.trim(),
    };
  }
  if (hasPendingApproval(blocks)) {
    const approval = latest(
      blocks,
      (block) => !!block.approval && !block.approval.decided,
    );
    return {
      status: "needs-you",
      activity: approval?.tool?.title
        ? `Approve ${plainLine(approval.tool.title)}`
        : "Waiting for approval",
    };
  }
  if (session.usageLimit) {
    return { status: "needs-you", activity: "Usage limit reached" };
  }
  if (!session.busy) return { status: "idle" };
  const last = blocks[blocks.length - 1];
  if (last?.role === "assistant" && !last.tool && last.streaming) {
    return { status: "working", activity: "Writing a reply" };
  }
  // Only a step from the current turn says what it is doing now.
  for (let i = blocks.length - 1; i >= 0; i--) {
    const block = blocks[i];
    if (block.role === "user") break;
    if (block.tool?.title) {
      return { status: "working", activity: plainLine(block.tool.title) };
    }
  }
  return { status: "working", activity: "Thinking" };
}

function latest(
  blocks: readonly Block[],
  match: (block: Block) => boolean,
): Block | undefined {
  for (let i = blocks.length - 1; i >= 0; i--) {
    if (match(blocks[i])) return blocks[i];
  }
  return undefined;
}
