// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { ComposerRunner } from "./ComposerRunner";

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it("keeps animating through transcript changes without measuring layout each frame", () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("matchMedia", () => ({ matches: false }));
  vi.spyOn(performance, "now").mockReturnValue(1000);
  let frame: FrameRequestCallback | null = null;
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
    frame = callback;
    return 1;
  });
  vi.stubGlobal("cancelAnimationFrame", () => {});

  const box = document.createElement("div");
  box.dataset.composer = "";
  const measure = vi.spyOn(box, "getBoundingClientRect").mockReturnValue({
    left: 20,
    right: 320,
    top: 400,
    bottom: 480,
    width: 300,
    height: 80,
  } as DOMRect);
  document.body.append(box);
  const host = document.createElement("div");
  document.body.append(host);
  const root = createRoot(host);
  try {
    act(() =>
      root.render(
        createElement(ComposerRunner, {
          boxRef: { current: box },
          cwd: "/work/project",
          busy: true,
          onExited: vi.fn(),
        }),
      ),
    );
    const startedAt = 1000;
    for (let i = 1; i <= 5; i++) {
      box.append(document.createElement("span"));
      act(() => frame?.(startedAt + i * 16));
    }
    expect(measure).toHaveBeenCalledOnce();

    act(() => frame?.(startedAt + 120));
    expect(measure).toHaveBeenCalledTimes(2);
  } finally {
    act(() => root.unmount());
    host.remove();
    box.remove();
  }
});

it("plays its exit once when work finishes, and hides on an inactive pane", () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("matchMedia", () => ({ matches: false }));
  vi.spyOn(performance, "now").mockReturnValue(1000);
  let frame: FrameRequestCallback | null = null;
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { frame = callback; return 1; });
  const cancel = vi.fn();
  vi.stubGlobal("cancelAnimationFrame", cancel);
  const host = document.createElement("div");
  const box = document.createElement("div");
  box.getBoundingClientRect = () => new DOMRect(20, 400, 300, 80);
  document.body.append(host, box);
  const root = createRoot(host);
  const onExited = vi.fn();
  const props = { boxRef: { current: box }, cwd: "/work/project", busy: true, onExited };
  try {
    act(() => root.render(createElement(ComposerRunner, props)));
    const layer = document.querySelector<HTMLElement>(".composer-runner")!;
    expect(layer.style.visibility).toBe("visible");
    act(() => root.render(createElement(ComposerRunner, { ...props, enabled: false })));
    act(() => frame?.(1100));
    expect(layer.style.visibility).toBe("hidden");
    act(() => root.render(createElement(ComposerRunner, { ...props, busy: false })));
    act(() => frame?.(1200));
    expect(onExited).not.toHaveBeenCalled();
    act(() => frame?.(1800));
    expect(onExited).toHaveBeenCalledOnce();
    expect(layer.querySelector<HTMLElement>(".will-change-transform")!.style.getPropertyValue("--runner-clip")).toBe("16px");
    act(() => frame?.(2000));
    expect(onExited).toHaveBeenCalledOnce();
  } finally {
    act(() => root.unmount()); host.remove(); box.remove();
  }
  expect(cancel).toHaveBeenCalled();
  expect(document.querySelector(".composer-runner")).toBeNull();
});
