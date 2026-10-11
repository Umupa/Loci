export type ImageSize = { width: number; height: number };
export type ImageViewState = { scale: number; x: number; y: number; fit: boolean };
export const IMAGE_ZOOM_STEP = 1.25;
export const MAX_IMAGE_SCALE = 16;

export function imageFitScale(image: ImageSize, viewport: ImageSize): number {
  return Math.min(1, viewport.width / image.width, viewport.height / image.height);
}

export function clampImageView(view: ImageViewState, image: ImageSize, viewport: ImageSize): ImageViewState {
  const fitScale = imageFitScale(image, viewport);
  const scale = view.fit ? fitScale : Math.min(MAX_IMAGE_SCALE, Math.max(Math.min(0.05, fitScale), view.scale));
  const maxX = Math.max(0, (image.width * scale - viewport.width) / 2);
  const maxY = Math.max(0, (image.height * scale - viewport.height) / 2);
  return {
    scale, fit: view.fit,
    x: view.fit ? 0 : Math.max(-maxX, Math.min(maxX, view.x)),
    y: view.fit ? 0 : Math.max(-maxY, Math.min(maxY, view.y)),
  };
}

/** The image pixel under the pointer stays put unless an edge needs clamping. */
export function zoomImageAt(view: ImageViewState, scale: number, point: { x: number; y: number }, image: ImageSize, viewport: ImageSize): ImageViewState {
  const next = clampImageView({ ...view, scale, fit: false }, image, viewport);
  const ratio = next.scale / view.scale;
  return clampImageView({ ...next, x: point.x - ratio * (point.x - view.x), y: point.y - ratio * (point.y - view.y) }, image, viewport);
}
