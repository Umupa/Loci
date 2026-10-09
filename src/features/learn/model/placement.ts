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

/** Where a node with nothing to connect to goes: rows of four from `left`, under the mission text. */
export function placeInRows(taken: readonly Box[], top: number, size: { width: number; height: number }, left = 0): { x: number; y: number } {
  for (let row = 0; row < 200; row++) {
    for (let column = 0; column < 4; column++) {
      const candidate = { x: left + column * STEP_X, y: top + row * STEP_Y, ...size };
      if (!taken.some((box) => overlaps(candidate, box))) return { x: candidate.x, y: candidate.y };
    }
  }
  return { x: left, y: top };
}

/**
 * A roadmap stage is a band of topics in rows. Topics sit closer than the
 * learner's own nodes do, so that the whole road can be seen at once. The gap
 * between bands holds the next stage's name, which Excalidraw draws above its
 * frame at the same size however far the learner zooms out.
 */
export const STAGE = { columns: 5, stepX: 300, stepY: 130, pad: 30, gap: 90 } as const;
/** Room between the roadmap and what the learner grows beside it. */
const BESIDE = 120;

type Size = { width: number; height: number };

/** The frame of a stage with this many rows of topics. */
export function stageSize(rows: number, node: Size): Size {
  return { width: STAGE.pad * 2 + (STAGE.columns - 1) * STAGE.stepX + node.width, height: STAGE.pad * 2 + (rows - 1) * STAGE.stepY + node.height };
}

export function stageCell(frame: { x: number; y: number }, column: number, row: number): { x: number; y: number } {
  return { x: frame.x + STAGE.pad + column * STAGE.stepX, y: frame.y + STAGE.pad + row * STAGE.stepY };
}

/** Where a new stage goes: under the last one, lined up with it, and below anything already in the way. */
export function placeStage(bodies: readonly Box[], stages: readonly Box[], top: number, size: Size): { x: number; y: number } {
  const last = [...stages].sort((a, b) => a.y + a.height - (b.y + b.height)).pop();
  const band = { x: last?.x ?? 0, y: last ? last.y + last.height + STAGE.gap : top, ...size };
  for (let pass = 0; pass < 1000; pass++) {
    const hit = [...bodies, ...stages].filter((box) => overlaps(band, box));
    if (!hit.length) break;
    band.y = Math.max(...hit.map((box) => box.y + box.height)) + STAGE.gap;
  }
  return { x: band.x, y: band.y };
}

/**
 * The next free cell of a stage that is already on the map: in its rows first,
 * then in a new row under them when nothing is there, otherwise further along
 * its first row. Nothing moves; the caller grows the frame to hold the cell.
 */
export function placeInStage(bodies: readonly Box[], others: readonly Box[], frame: Box, node: Size): { x: number; y: number } {
  const rows = Math.max(1, Math.round((frame.height - STAGE.pad * 2 - node.height) / STAGE.stepY) + 1);
  const columns = Math.max(STAGE.columns, Math.round((frame.width - STAGE.pad * 2 - node.width) / STAGE.stepX) + 1);
  const free = (cell: { x: number; y: number }, outside: boolean) => {
    const box = { ...cell, ...node };
    return !bodies.some((body) => overlaps(box, body)) && (!outside || !others.some((other) => overlaps(box, other)));
  };
  for (let row = 0; row < rows; row++)
    for (let column = 0; column < columns; column++)
      if (free(stageCell(frame, column, row), false)) return stageCell(frame, column, row);
  for (let column = 0; column < STAGE.columns; column++)
    if (free(stageCell(frame, column, rows), true)) return stageCell(frame, column, rows);
  for (let column = columns; column < columns + 200; column++)
    if (free(stageCell(frame, column, 0), true)) return stageCell(frame, column, 0);
  return stageCell(frame, columns, 0);
}

/** Where the learner's own node goes when it hangs off a topic of the roadmap: right of that stage, level with the topic. */
export function placeBeside(taken: readonly Box[], frame: Box, anchor: Box, size: Size): { x: number; y: number } {
  const y = anchor.y + anchor.height / 2 - size.height / 2;
  let spot = { x: frame.x + frame.width + BESIDE, y };
  for (let column = 0; column < 200; column++) {
    spot = { x: frame.x + frame.width + BESIDE + column * STEP_X, y };
    const candidate = { ...spot, ...size };
    if (!taken.some((box) => overlaps(candidate, box))) return spot;
  }
  return spot;
}

/** The left edge for nodes that belong to no stage, once there is a roadmap: they go beside it, not under it. */
export function besideStages(stages: readonly Box[]): number {
  return Math.max(...stages.map((stage) => stage.x + stage.width)) + BESIDE;
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
