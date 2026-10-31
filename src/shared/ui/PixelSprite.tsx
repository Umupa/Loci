import { PIXEL_GRID, ROBOT_SPRITE } from "../lib/pixelSprite";

/** The robot sprite in the current text color; `active` swaps its frames on a loop. */
export function PixelRobot({ className = "size-3 shrink-0", active = false, color }: { className?: string; active?: boolean; color?: string }) {
  return (
    <svg aria-hidden viewBox={`0 0 ${PIXEL_GRID} ${PIXEL_GRID}`} shapeRendering="crispEdges"
      className={`${className} ${active ? "mascot-active" : ""}`} fill="currentColor" style={color ? { color } : undefined}>
      {active ? <>
        <path className="mascot-rest" d={ROBOT_SPRITE.rest} />
        <path className="mascot-talk" d={ROBOT_SPRITE.talk} />
      </> : <path d={ROBOT_SPRITE.rest} />}
    </svg>
  );
}
