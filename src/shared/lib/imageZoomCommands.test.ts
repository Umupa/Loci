// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import { IMAGE_ZOOM_EVENT, requestImageZoom } from "./imageZoomCommands";

afterEach(() => document.body.replaceChildren());

function viewer(mode: "modal" | "focused") {
  const element = document.createElement("div");
  element.dataset.imageZoom = mode;
  const handle = vi.fn((event: Event) => event.preventDefault());
  element.addEventListener(IMAGE_ZOOM_EVENT, handle);
  document.body.append(element);
  return { element, handle };
}

describe("image zoom command routing", () => {
  it("allows interface zoom when no image accepts the command", () => {
    expect(requestImageZoom("zoom-in")).toBe(false);
    const idle = document.createElement("div");
    idle.dataset.imageZoom = "focused";
    document.body.append(idle);
    expect(requestImageZoom("zoom-out")).toBe(false);
  });

  it("delivers the requested action to the focused image", () => {
    const focused = viewer("focused");
    expect(requestImageZoom("zoom-reset")).toBe(true);
    expect(focused.handle).toHaveBeenCalledOnce();
    expect((focused.handle.mock.calls[0][0] as CustomEvent).detail).toBe("zoom-reset");
  });

  it("gives the last mounted modal priority over other images", () => {
    const focused = viewer("focused");
    const first = viewer("modal");
    const top = viewer("modal");
    expect(requestImageZoom("zoom-in")).toBe(true);
    expect(top.handle).toHaveBeenCalledOnce();
    expect(first.handle).not.toHaveBeenCalled();
    expect(focused.handle).not.toHaveBeenCalled();
    top.element.remove();
    expect(requestImageZoom("zoom-out")).toBe(true);
    expect(first.handle).toHaveBeenCalledOnce();
  });

  it("does not zoom a focused image behind another dialog", () => {
    const focused = viewer("focused");
    const dialog = document.createElement("div");
    dialog.setAttribute("role", "dialog");
    document.body.append(dialog);
    expect(requestImageZoom("zoom-in")).toBe(false);
    expect(focused.handle).not.toHaveBeenCalled();
    dialog.append(viewer("modal").element);
    expect(requestImageZoom("zoom-in")).toBe(true);
  });
});
