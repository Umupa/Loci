import { BOTTTS_AVATARS } from "./bottts.generated";

export type AgentAvatarStyle = "bottts" | "bottts-neutral";

export type AgentAvatar = {
  readonly name: string;
  readonly style: AgentAvatarStyle;
  readonly viewBox: string;
  /** Trusted, pre-generated Bottts SVG body; resource IDs are instance-scoped by the renderer. */
  readonly markup: string;
  readonly canBlink: boolean;
};

/** Saved names remain stable when replacing the artwork. */
export const AGENT_AVATARS: readonly AgentAvatar[] = BOTTTS_AVATARS;

/** An unknown stored avatar keeps rendering as the first face. */
export function agentAvatar(name?: string | null): AgentAvatar {
  return AGENT_AVATARS.find((avatar) => avatar.name === name) ?? AGENT_AVATARS[0];
}

export function defaultAgentName(name: string): string {
  const avatar = agentAvatar(name);
  const baseName = avatar.name.replace(/^neutral-/, "");
  return baseName.charAt(0).toUpperCase() + baseName.slice(1);
}
