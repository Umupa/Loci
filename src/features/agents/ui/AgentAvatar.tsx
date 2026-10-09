import { AVATAR_GRID, agentAvatar } from "../model/agentAvatars";

type Props = {
  /** Avatar name; see `agentAvatars`. */
  name: string;
  /** The agent's color, which paints its head. */
  color: string;
  className?: string;
};

/** An agent's pixel face: its head in its color, looking back with white eyes. */
export function AgentAvatar({
  name,
  color,
  className = "size-4 shrink-0",
}: Props) {
  const avatar = agentAvatar(name);
  return (
    <svg
      aria-hidden
      viewBox={`0 0 ${AVATAR_GRID} ${AVATAR_GRID}`}
      shapeRendering="crispEdges"
      className={className}
    >
      <path d={avatar.headPath} fill={color} />
      <path d={avatar.eyesPath} fill="#fff" />
    </svg>
  );
}
