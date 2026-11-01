import { NOTIONISTS_AVATARS } from "./notionists.generated";

export type AgentAvatarStyle = "notionists";

export type AgentAvatar = {
  readonly name: string;
  readonly style: AgentAvatarStyle;
  /** Head and shoulders, for avatars large enough to show them. */
  readonly viewBox: string;
  /** The face alone, for avatars the size of an icon. */
  readonly faceViewBox: string;
  /** Trusted, pre-generated SVG body; resource IDs are instance-scoped by the renderer. */
  readonly markup: string;
  readonly canBlink: boolean;
};

/** Saved names remain stable when replacing the artwork. */
export const AGENT_AVATARS: readonly AgentAvatar[] = NOTIONISTS_AVATARS;

/**
 * An unknown stored avatar keeps rendering as the first face. The earlier
 * robot set also had a `neutral-` twin of each face; those wear the same face.
 */
export function agentAvatar(name?: string | null): AgentAvatar {
  const base = name?.replace(/^neutral-/, "");
  return AGENT_AVATARS.find((avatar) => avatar.name === base) ?? AGENT_AVATARS[0];
}

export function defaultAgentName(name: string): string {
  const avatar = agentAvatar(name);
  return avatar.name.charAt(0).toUpperCase() + avatar.name.slice(1);
}
