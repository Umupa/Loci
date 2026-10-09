import { AVATAR_TILE, agentAvatar } from "../model/agentAvatars";

type Props = {
  /** Avatar name; see `agentAvatars`. */
  name: string;
  /** The agent's color, which fills the tile behind the figure. */
  color: string;
  className?: string;
};

/** An agent's framed pixel avatar: its color as the ground, the figure inked over it. */
export function AgentAvatar({
  name,
  color,
  className = "size-4 shrink-0",
}: Props) {
  const avatar = agentAvatar(name);
  return (
    <svg
      aria-hidden
      viewBox={`0 0 ${AVATAR_TILE} ${AVATAR_TILE}`}
      shapeRendering="crispEdges"
      className={className}
    >
      <rect width={AVATAR_TILE} height={AVATAR_TILE} fill="#111" />
      <rect
        x={1}
        y={1}
        width={AVATAR_TILE - 2}
        height={AVATAR_TILE - 2}
        fill={color}
      />
      <path d={avatar.fillPath} fill="#fff" />
      <path d={avatar.shadePath} fill="#fff" fillOpacity={0.55} />
      <path d={avatar.inkPath} fill="#111" />
    </svg>
  );
}
