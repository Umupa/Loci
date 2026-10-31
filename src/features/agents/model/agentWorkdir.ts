import { invoke } from "@tauri-apps/api/core";
import { findAgent, updateAgent, type Agent } from "./agent";
import { defaultAgentName } from "./agentAvatars";
import { pathKey } from "../../../shared/lib/paths";

/**
 * Each mentor works in a folder of its own that the user can see: cloned
 * source under `repos/`, experiments under `lab/`. By default it is
 * `~/Loci/<slug>` (`~/Loci-Dev/<slug>` for Loci Dev), created the first time
 * it is needed; the user can point it at any folder instead. The app only
 * creates folders there, never moves or deletes anything (see
 * `src-tauri/src/agent.rs`).
 */

const SLUG_MAX = 40;

/**
 * The default folder name for a mentor: its name in lowercase ASCII words
 * joined by dashes, "Repo Lens" → "repo-lens". A name with nothing of that
 * left, such as one written in Chinese, falls back to `mentor-<id>`.
 */
export function workdirSlug(agent: Pick<Agent, "id" | "name" | "avatar">): string {
  const name = agent.name?.trim() || defaultAgentName(agent.avatar);
  const slug = name
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .slice(0, SLUG_MAX)
    .replace(/^-+|-+$/g, "");
  if (slug && slug !== "repos") return slug;
  return `mentor-${agent.id.replace(/[^A-Za-z0-9]/g, "").slice(0, 8).toLowerCase()}`;
}

const ensuring = new Map<string, Promise<string>>();

/**
 * The mentor's workdir, created on first use. A folder it already has is
 * left as it is: nothing is created inside it.
 */
export function ensureAgentWorkdir(agentId: string): Promise<string> {
  const pending = ensuring.get(agentId);
  if (pending) return pending;
  const work = resolveWorkdir(agentId).finally(() => ensuring.delete(agentId));
  ensuring.set(agentId, work);
  return work;
}

async function resolveWorkdir(agentId: string): Promise<string> {
  const agent = findAgent(agentId);
  if (!agent) throw new Error("No such agent");
  if (agent.workdir) return invoke<string>("agent_workdir_ensure", { path: agent.workdir });
  const created = await invoke<string>("agent_workdir_create", { slug: workdirSlug(agent) });
  // Another window may have given it one meanwhile; the first one stays, and
  // the empty folder made here is left alone rather than deleted.
  const now = findAgent(agentId);
  if (now?.workdir) return now.workdir;
  updateAgent(agentId, (current) => ({ ...current, workdir: created }));
  return created;
}

/**
 * Points the mentor at another folder, such as one the user already keeps
 * study material in. Nothing in the folder is changed. A running chat keeps
 * the folder it started in until it is reset.
 */
export async function setAgentWorkdir(agentId: string, path: string): Promise<string> {
  const chosen = await invoke<string>("agent_workdir_ensure", { path });
  updateAgent(agentId, (agent) => ({ ...agent, workdir: chosen }));
  return chosen;
}

/** Whether `path` is `folder` or inside it; `~` stands for the home folder. */
export function folderHolds(folder: string, path: string): boolean {
  if (folder === "~") return true;
  const parent = pathKey(folder).replace(/\/+$/, "");
  const child = pathKey(path).replace(/\/+$/, "");
  return child === parent || child.startsWith(`${parent}/`);
}
