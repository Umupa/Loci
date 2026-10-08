export type Box = { x: number; y: number; width: number; height: number };

/** Room kept clear around a new node. */
const GAP = 30;
// Wide enough between neighbours for an arrow labelled in the learner's words.
const STEP_X = 380;
const STEP_Y = 180;
const RINGS = 12;

function overlaps(a: Box, b: Box): boolean {
  return a.x < b.x + b.width + GAP && b.x < a.x + a.width + GAP && a.y < b.y + b.height + GAP && b.y < a.y + a.height + GAP;
}

/** Grid cells one ring out from the origin: right, below, left, above, then the nearest of the rest, lower rows first. */
function ringCells(ring: number): Array<[number, number]> {
  const cells: Array<[number, number]> = [];
  for (let column = -ring; column <= ring; column++)
    for (let row = -ring; row <= ring; row++)
      if (Math.max(Math.abs(column), Math.abs(row)) === ring) cells.push([column, row]);
  const axis = ([column, row]: [number, number]) =>
    row === 0 && column === ring ? 0 : column === 0 && row === ring ? 1 : row === 0 && column === -ring ? 2 : column === 0 && row === -ring ? 3 : 4;
  const distance = ([column, row]: [number, number]) => Math.abs(column) + Math.abs(row);
  // A map grows downwards from its mission text, so a cell below is preferred to one above.
  return cells.sort((a, b) => axis(a) - axis(b) || distance(a) - distance(b) || b[1] - a[1] || b[0] - a[0]);
}

/**
 * Where a new node goes beside the one it connects to. Existing elements are
 * never moved: the first free cell of a grid centred on the anchor is taken.
 */
export function placeNear(taken: readonly Box[], anchor: Box, size: { width: number; height: number }): { x: number; y: number } {
  const centre = { x: anchor.x + anchor.width / 2, y: anchor.y + anchor.height / 2 };
  let spot = { x: anchor.x + STEP_X, y: anchor.y };
  for (let ring = 1; ring <= RINGS; ring++) {
    for (const [column, row] of ringCells(ring)) {
      spot = { x: centre.x + column * STEP_X - size.width / 2, y: centre.y + row * STEP_Y - size.height / 2 };
      const candidate = { ...spot, ...size };
      if (!taken.some((box) => overlaps(candidate, box))) return spot;
    }
  }
  return spot;
}

/** Where a node with nothing to connect to goes: rows of four under the mission text. */
export function placeInRows(taken: readonly Box[], top: number, size: { width: number; height: number }): { x: number; y: number } {
  for (let row = 0; row < 200; row++) {
    for (let column = 0; column < 4; column++) {
      const candidate = { x: column * STEP_X, y: top + row * STEP_Y, ...size };
      if (!taken.some((box) => overlaps(candidate, box))) return { x: candidate.x, y: candidate.y };
    }
  }
  return { x: 0, y: top };
}

/** An arrow from the side of `from` that faces `to`, to the facing side of `to`. */
export function connect(from: Box, to: Box): { x: number; y: number; points: [[number, number], [number, number]] } {
  const a = { x: from.x + from.width / 2, y: from.y + from.height / 2 };
  const b = { x: to.x + to.width / 2, y: to.y + to.height / 2 };
  const horizontal = Math.abs(b.x - a.x) * (from.height + to.height) >= Math.abs(b.y - a.y) * (from.width + to.width);
  const start = horizontal
    ? { x: b.x >= a.x ? from.x + from.width : from.x, y: a.y }
    : { x: a.x, y: b.y >= a.y ? from.y + from.height : from.y };
  const end = horizontal
    ? { x: b.x >= a.x ? to.x : to.x + to.width, y: b.y }
    : { x: b.x, y: b.y >= a.y ? to.y : to.y + to.height };
  return { x: start.x, y: start.y, points: [[0, 0], [end.x - start.x, end.y - start.y]] };
}
