import { AVATAR_BOX, agentAvatar } from "../model/agentAvatars";

type Props = {
  /** Avatar name; see `agentAvatars`. */
  name: string;
  /** The agent's color, which fills the whole shape. */
  color: string;
  className?: string;
};

/** An agent's face: its shape in its color, with a pair of eyes looking up and to the side. */
export function AgentAvatar({
  name,
  color,
  className = "size-4 shrink-0",
}: Props) {
  const avatar = agentAvatar(name);
  const [x, y] = avatar.eyes;
  return (
    <svg
      aria-hidden
      viewBox={`0 0 ${AVATAR_BOX} ${AVATAR_BOX}`}
      className={className}
    >
      <path
        d={avatar.body}
        fill={color}
        stroke={color}
        strokeWidth={3}
        strokeLinejoin="round"
      />
      <g stroke="#fff" strokeWidth={1.7} strokeLinecap="round">
        <path d={`M${x} ${y}l.6 2.3`} />
        <path d={`M${x + 3.2} ${y + 0.5}l.6 2.3`} />
      </g>
    </svg>
  );
}
