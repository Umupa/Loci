// Excalidraw 0.18's RAF queues are shared across instances. Enable its built-in
// render coalescing only for a single visible editor so split panes cannot
// overwrite each other's pending frames.
type RenderWindow = Window & { EXCALIDRAW_THROTTLE_RENDER?: boolean };
let editors = 0;
let previous: boolean | undefined;

export function registerCanvasRenderer(): () => void {
  const target = window as RenderWindow;
  if (editors === 0) previous = target.EXCALIDRAW_THROTTLE_RENDER;
  editors += 1;
  target.EXCALIDRAW_THROTTLE_RENDER = editors === 1;
  return () => {
    editors -= 1;
    if (editors === 0) {
      if (previous === undefined) delete target.EXCALIDRAW_THROTTLE_RENDER;
      else target.EXCALIDRAW_THROTTLE_RENDER = previous;
    } else {
      target.EXCALIDRAW_THROTTLE_RENDER = editors === 1;
    }
  };
}
