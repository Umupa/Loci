// @vitest-environment happy-dom
import { expect, it } from "vitest";
import { registerCanvasRenderer } from "./renderScheduling";

type RenderWindow = Window & { EXCALIDRAW_THROTTLE_RENDER?: boolean };
const target = window as RenderWindow;

it("coalesces a single editor but protects simultaneous editors from shared RAF queues", () => {
  const releaseFirst = registerCanvasRenderer();
  expect(target.EXCALIDRAW_THROTTLE_RENDER).toBe(true);
  const releaseSecond = registerCanvasRenderer();
  expect(target.EXCALIDRAW_THROTTLE_RENDER).toBe(false);
  releaseFirst();
  expect(target.EXCALIDRAW_THROTTLE_RENDER).toBe(true);
  releaseSecond();
  expect(target).not.toHaveProperty("EXCALIDRAW_THROTTLE_RENDER");
});

it("restores an existing render setting after the final editor closes", () => {
  target.EXCALIDRAW_THROTTLE_RENDER = false;
  const release = registerCanvasRenderer();
  expect(target.EXCALIDRAW_THROTTLE_RENDER).toBe(true);
  release();
  expect(target.EXCALIDRAW_THROTTLE_RENDER).toBe(false);
  delete target.EXCALIDRAW_THROTTLE_RENDER;
});
