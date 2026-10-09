/**
 * 10×10 pixel avatars for agents, each drawn as a framed tile: the agent's
 * color fills the ground, the figure is inked in black and filled in white.
 * A project's mascot is one flat color on a transparent 8×8 grid, so the
 * frame and the three tones are what tell an agent from a project at a glance.
 *
 * '.' is the ground, '#' ink, 'o' the figure's fill, '+' its shading.
 */
const GRID = 10;
/** The ink frame around the tile, in grid units. */
const FRAME = 1;

type AvatarRows = readonly string[];

export type AgentAvatar = {
  name: string;
  rows: AvatarRows;
  /** SVG path data over the tile's viewBox, frame included. */
  inkPath: string;
  fillPath: string;
  shadePath: string;
};

const ROWS: Record<string, AvatarRows> = {
  ember: [
    "....##....",
    "...#oo#...",
    "...#oo#...",
    "..#ooo#.#.",
    ".#oooo##o#",
    ".#o++oooo#",
    ".#o+++o+o#",
    ".#oo+++oo#",
    "..#oooo##.",
    "...####...",
  ],
  wisp: [
    "....##....",
    "...#oo#...",
    "...#oo#...",
    ".##oooo##.",
    "#oo#oo#oo#",
    "#oooooooo#",
    ".##oooo##.",
    "...#oo#...",
    "...#oo#...",
    "....##....",
  ],
  dew: [
    "....##....",
    "...#oo#...",
    "...#oo#...",
    "..#oooo#..",
    "..#oooo#..",
    ".#o+oooo#.",
    ".#o+oooo#.",
    ".#oo+ooo#.",
    "..#oooo#..",
    "...####...",
  ],
  moss: [
    "......####",
    "....##ooo#",
    "...#oooo+#",
    "..#ooo+oo#",
    ".#ooo+ooo#",
    ".#oo+ooo#.",
    ".#o+ooo#..",
    ".#+ooo#...",
    "#+####....",
    "#.........",
  ],
  nimbus: [
    "..........",
    "....###...",
    "...#ooo#..",
    ".###oooo#.",
    "#oooooooo#",
    "#oooooooo#",
    "#o++++++o#",
    ".########.",
    "..........",
    "..........",
  ],
  pebble: [
    "..........",
    "...#####..",
    "..#ooooo#.",
    ".#ooooooo#",
    ".#o#ooo#o#",
    "#oooooooo#",
    "#oo+++ooo#",
    "#oooooooo#",
    ".########.",
    "..........",
  ],
  luna: [
    "...####...",
    "..#ooo#...",
    ".#ooo#....",
    ".#oo#.....",
    ".#oo#.....",
    ".#oo#....#",
    ".#ooo#..##",
    "..#ooo##o#",
    "...#oooo#.",
    "....####..",
  ],
  nova: [
    ".#..##..#.",
    "..#....#..",
    "...####...",
    "..#oooo#..",
    "#.#oooo#.#",
    "#.#oooo#.#",
    "..#oooo#..",
    "...####...",
    "..#....#..",
    ".#..##..#.",
  ],
  flint: [
    "..........",
    "..######..",
    ".#oo++oo#.",
    "#oo+oo+oo#",
    "##########",
    ".#oo++oo#.",
    "..#o++o#..",
    "...#oo#...",
    "....##....",
    "..........",
  ],
  tide: [
    "..........",
    "....####..",
    "..##oooo#.",
    ".#ooo##oo#",
    "#ooo#..#o#",
    "#oo#....#.",
    "#oo#......",
    "#ooo##..##",
    "#ooooo##oo",
    "##########",
  ],
};

/** Merges each row's runs of `tone` into one rect, offset inside the frame. */
export function avatarPath(rows: AvatarRows, tone: string): string {
  let path = "";
  rows.forEach((row, y) => {
    let x = 0;
    while (x < row.length) {
      if (row[x] !== tone) {
        x += 1;
        continue;
      }
      let run = 1;
      while (row[x + run] === tone) run += 1;
      path += `M${x + FRAME} ${y + FRAME}h${run}v1h-${run}z`;
      x += run;
    }
  });
  return path;
}

export const AGENT_AVATARS: readonly AgentAvatar[] = Object.entries(ROWS).map(
  ([name, rows]) => ({
    name,
    rows,
    inkPath: avatarPath(rows, "#"),
    fillPath: avatarPath(rows, "o"),
    shadePath: avatarPath(rows, "+"),
  }),
);

export const AVATAR_GRID = GRID;
export const AVATAR_FRAME = FRAME;
/** The whole tile: the figure's grid plus the frame on every side. */
export const AVATAR_TILE = GRID + FRAME * 2;

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
