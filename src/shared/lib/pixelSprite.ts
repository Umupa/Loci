/**
 * 8×8 pixel sprites drawn as SVG paths. '#' paints the current color and '.'
 * stays transparent. The composer's runner and a sub-agent's row use one.
 */
export const PIXEL_GRID = 8;

/** SVG path data for rows of '#' and '.', over an 8×8 viewBox. */
export function pixelPath(rows: readonly string[]): string {
  let path = "";
  rows.forEach((row, y) => {
    let x = 0;
    while (x < row.length) {
      if (row[x] !== "#") {
        x += 1;
        continue;
      }
      let run = 1;
      while (row[x + run] === "#") run += 1;
      path += `M${x} ${y}h${run}v1h-${run}z`;
      x += run;
    }
  });
  return path;
}

/** A small robot with two frames: at rest, and its second frame while it works. */
export const ROBOT_SPRITE = {
  rest: pixelPath([
    "...#....",
    ".######.",
    ".#.##.#.",
    ".######.",
    ".#....#.",
    ".######.",
    "..#..#..",
    "........",
  ]),
  talk: pixelPath([
    "....#...",
    ".######.",
    ".#.##.#.",
    ".######.",
    ".##..##.",
    ".######.",
    ".#....#.",
    "........",
  ]),
};
