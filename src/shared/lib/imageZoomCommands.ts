export const IMAGE_ZOOM_EVENT = "loci:image-zoom";
export type ImageZoomAction = "zoom-in" | "zoom-out" | "zoom-reset";

export function getImageZoomTarget(): HTMLElement | null {
  const modals = document.querySelectorAll<HTMLElement>('[data-image-zoom="modal"]');
  const modal = modals.item(modals.length - 1);
  if (!modal && document.querySelector('[role="dialog"]')) return null;
  return modal ?? document.querySelector<HTMLElement>('[data-image-zoom="focused"]');
}

/** Give the visible image priority over interface zoom, including native menus. */
export function requestImageZoom(action: ImageZoomAction): boolean {
  const target = getImageZoomTarget();
  if (!target) return false;
  return !target.dispatchEvent(new CustomEvent<ImageZoomAction>(IMAGE_ZOOM_EVENT, {
    detail: action,
    cancelable: true,
  }));
}
