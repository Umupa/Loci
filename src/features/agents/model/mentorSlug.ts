import { defaultAgentName } from "./agentAvatars";

const SLUG_MAX = 40;

/**
 * The default folder name for a mentor: its name in lowercase ASCII words
 * joined by dashes, "Repo Lens" → "repo-lens". A name with nothing of that
 * left, such as one written in Chinese, falls back to `mentor-<id>`.
 */
export function workdirSlug(agent: { id: string; name?: string; avatar: string }): string {
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
