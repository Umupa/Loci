/**
 * An agent's face: an 8×8 pixel head in its own color with a pair of white
 * eyes. It is drawn on the same grid as a project's mascot, so the two sit
 * side by side on the rail at the same size and weight; what tells them apart
 * is that a mascot is one flat color with holes for eyes, and an agent always
 * looks back at you.
 *
 * '#' paints the head, 'o' an eye, '.' stays transparent.
 */
const GRID = 8;

type AvatarRows = readonly string[];

export type AgentAvatar = {
  name: string;
  rows: AvatarRows;
  /** SVG path data over an 8×8 viewBox: the whole head, eyes included. */
  headPath: string;
  eyesPath: string;
};

const ROWS: Record<string, AvatarRows> = {
  // A round head.
  ember: [
    "..####..",
    ".######.",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    ".######.",
    "..####..",
  ],
  // An antenna.
  wisp: [
    "...#....",
    "...#....",
    ".######.",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    ".######.",
  ],
  // A drop.
  dew: [
    "...##...",
    "..####..",
    "..####..",
    ".######.",
    "##o##o##",
    "##o##o##",
    "########",
    ".######.",
  ],
  // A block.
  moss: [
    ".######.",
    "########",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    "########",
    ".######.",
  ],
  // A cloud.
  nimbus: [
    "..##.##.",
    ".#######",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    "########",
    ".######.",
  ],
  // A low, wide stone.
  pebble: [
    "........",
    "........",
    ".######.",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    ".######.",
  ],
  // Two horns.
  luna: [
    "#......#",
    "##....##",
    "########",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    ".######.",
  ],
  // A crown.
  nova: [
    "#.#..#.#",
    "########",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    "########",
    ".######.",
  ],
  // A gem.
  flint: [
    "...##...",
    "..####..",
    ".######.",
    "##o##o##",
    "##o##o##",
    ".######.",
    "..####..",
    "...##...",
  ],
  // A jelly, trailing.
  tide: [
    ".######.",
    "########",
    "##o##o##",
    "##o##o##",
    "########",
    "########",
    "#.#..#.#",
    "#.#..#.#",
  ],
};

/** Merges each row's runs of the given cells into one rect so the path stays short. */
export function avatarPath(rows: AvatarRows, cells: string): string {
  let path = "";
  rows.forEach((row, y) => {
    let x = 0;
    while (x < row.length) {
      if (!cells.includes(row[x])) {
        x += 1;
        continue;
      }
      let run = 1;
      while (x + run < row.length && cells.includes(row[x + run])) run += 1;
      path += `M${x} ${y}h${run}v1h-${run}z`;
      x += run;
    }
  });
  return path;
}

export const AGENT_AVATARS: readonly AgentAvatar[] = Object.entries(ROWS).map(
  ([name, rows]) => ({
    name,
    rows,
    // The head runs under the eyes, so no seam shows between the two fills.
    headPath: avatarPath(rows, "#o"),
    eyesPath: avatarPath(rows, "o"),
  }),
);

export const AVATAR_GRID = GRID;

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
