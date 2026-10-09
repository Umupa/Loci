import { projectKey, projectName } from "../../../shared/lib/paths";
import {
  loadTabGroupLabels,
  resolveTabGroupLabel,
  TAB_GROUP_COLORS,
} from "../../workspace/model/tabGroups";
import {
  hasPendingApproval,
  type Block,
  type Session,
} from "../../sessions/model/session";
import { AGENT_AVATARS, defaultAgentName } from "./agentAvatars";

/** The project palette's colors, plus indigo for an agent's ninth preset. */
export const AGENT_COLORS = [
  ...TAB_GROUP_COLORS.slice(1),
  "hsl(245 75% 65%)",
] as const;

/**
 * An agent is long-lived and its own: a name, a face and a color, one
 * conversation, and the projects it works on. It is not tied to any one of
 * them; it lives on the rail beside the projects and can be given more.
 */
export type Agent = {
  id: string;
  /** Its conversation; absent until it is first opened. */
  sessionId?: string;
  /** Replaces the avatar's own name. */
  name?: string;
  avatar: string;
  color: string;
  /** Project folders it works on, in the order they were added. */
  projects: string[];
  /** New sessions appear in the project sidebar unless explicitly disabled. */
  showStartedSessionsInSidebar?: boolean;
  /** Files the sessions it starts into a sidebar folder named after it. */
  useSidebarFolders?: boolean;
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
  return {
    id: entry.id,
    ...(sessionId ? { sessionId } : {}),
    ...(name ? { name } : {}),
    avatar: text("avatar") ?? AGENT_AVATARS[0].name,
    color: text("color") ?? AGENT_COLORS[0],
    projects: Array.isArray(entry.projects)
      ? entry.projects.filter(
          (path): path is string => typeof path === "string" && !!path,
        )
      : [],
    ...(typeof entry.showStartedSessionsInSidebar === "boolean"
      ? { showStartedSessionsInSidebar: entry.showStartedSessionsInSidebar }
      : {}),
    ...(entry.useSidebarFolders === true ? { useSidebarFolders: true } : {}),
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

/** A new agent with the next look, starting with the projects given, if any. */
export function createAgent(projects: readonly string[] = []): Agent {
  const roster = listAgents();
  const agent: Agent = {
    id: newAgentId(),
    ...nextAgentLook(roster),
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

/** Whether the agent has been given this project. */
export function agentWorksOn(agent: Pick<Agent, "projects">, path: string) {
  const key = projectKey(path);
  return agent.projects.some((project) => projectKey(project) === key);
}

export function subscribeAgents(onChange: () => void): () => void {
  window.addEventListener(AGENTS_CHANGED, onChange);
  return () => window.removeEventListener(AGENTS_CHANGED, onChange);
}

/**
 * Snapshot for `useSyncExternalStore`; stable while storage is unchanged.
 * Project labels are part of it, since an agent's look names its projects.
 */
export function agentsSnapshot(): string {
  try {
    return `${localStorage.getItem(ROSTER_KEY) ?? ""}|${JSON.stringify(
      loadTabGroupLabels(),
    )}`;
  } catch {
    return "";
  }
}

/** One project an agent works on, as the rail labels it. */
export type AgentProject = { path: string; name: string };

export type AgentLook = {
  /** The user's name for it, or its avatar's: "Ember", "Wisp". */
  name: string;
  avatar: string;
  color: string;
  projects: AgentProject[];
};

/** How an agent looks, and the projects it works on by their rail labels. */
export function agentLook(agent: Agent): AgentLook {
  const labels = loadTabGroupLabels();
  return {
    name: agent.name?.trim() || defaultAgentName(agent.avatar),
    avatar: agent.avatar,
    color: agent.color,
    projects: agent.projects.map((path) => ({
      path,
      name: resolveTabGroupLabel(projectKey(path), labels, projectName(path)),
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
