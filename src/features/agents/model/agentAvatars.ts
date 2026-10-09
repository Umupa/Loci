/**
 * An agent's face: a soft blob in its own color with a pair of eyes, like a
 * contact in a messenger. A project's mascot is a flat pixel sprite on a
 * square grid, so a round, smooth shape with a look in its eyes is what tells
 * an agent from a project at a glance.
 *
 * Shapes are drawn on a 24×24 box. Angular ones are stroked in their own
 * color with round joins, which is what softens their corners.
 */
export type AgentAvatar = {
  name: string;
  /** SVG path data for the body. */
  body: string;
  /** Where the eyes sit, as the top of the left one; a shape's mass decides. */
  eyes: readonly [x: number, y: number];
};

export const AVATAR_BOX = 24;

export const AGENT_AVATARS: readonly AgentAvatar[] = [
  // A plain circle.
  { name: "ember", body: "M12 3a9 9 0 1 0 0 18a9 9 0 0 0 0-18z", eyes: [12.6, 7.4] },
  // A tall capsule.
  { name: "wisp", body: "M12 4.5a5 5 0 0 1 5 5v5a5 5 0 0 1-10 0v-5a5 5 0 0 1 5-5z", eyes: [11.4, 8] },
  // A drop.
  { name: "dew", body: "M12 4c3 3.6 6 6.6 6 10a6 6 0 0 1-12 0c0-3.4 3-6.4 6-10z", eyes: [11.6, 11.2] },
  // A rounded square.
  { name: "moss", body: "M8 4.5h8A3.5 3.5 0 0 1 19.5 8v8a3.5 3.5 0 0 1-3.5 3.5H8A3.5 3.5 0 0 1 4.5 16V8A3.5 3.5 0 0 1 8 4.5z", eyes: [12.6, 7.6] },
  // A cloud.
  { name: "nimbus", body: "M7.5 18.5a4 4 0 0 1-.7-7.94A5.5 5.5 0 0 1 17.4 9.6 4.5 4.5 0 0 1 16.5 18.5z", eyes: [11.6, 9.4] },
  // A flat pebble.
  { name: "pebble", body: "M12 6.5c5 0 9 2.5 9 5.5s-4 5.5-9 5.5S3 15 3 12s4-5.5 9-5.5z", eyes: [12.8, 8.8] },
  // A pentagon.
  { name: "luna", body: "M12 4.5 19.6 10 16.7 19H7.3L4.4 10z", eyes: [12, 8.6] },
  // A hexagon.
  { name: "nova", body: "M12 4.2 18.8 8.1v7.8L12 19.8 5.2 15.9V8.1z", eyes: [12.4, 7.8] },
  // A diamond.
  { name: "flint", body: "M12 4 20 12 12 20 4 12z", eyes: [11.6, 8.8] },
  // A hill.
  { name: "tide", body: "M12 5.5 19.5 18.5h-15z", eyes: [11, 11.6] },
];

/** The avatar by name; an unknown one falls back to the first. */
export function agentAvatar(name?: string | null): AgentAvatar {
  return (
    AGENT_AVATARS.find((avatar) => avatar.name === name) ?? AGENT_AVATARS[0]
  );
}

/** The name an agent goes by until the user names it: "Ember", "Wisp". */
export function defaultAgentName(avatar: string): string {
  const { name } = agentAvatar(avatar);
  return name.charAt(0).toUpperCase() + name.slice(1);
}
