// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MentorRail } from "./MentorRail";

vi.mock("../../platform/tauri/platform", () => ({ IS_MAC: false }));

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

function mount(updateVersion: string | null) {
  const onViewUpdate = vi.fn();
  const onOpenSettings = vi.fn();
  act(() => root.render(createElement(MentorRail, {
    states: new Map(),
    settingsOpen: false,
    onOpen: vi.fn(),
    onOpenDetails: vi.fn(),
    onCreate: vi.fn(),
    onDelete: vi.fn(),
    onOpenSettings,
    updateVersion,
    onViewUpdate,
  })));
  return { onViewUpdate, onOpenSettings };
}

describe("the rail's update indicator", () => {
  it("puts a dot on Settings that opens the prompt, not Settings", () => {
    const { onViewUpdate, onOpenSettings } = mount("0.3.0");
    const badge = host.querySelector<HTMLButtonElement>("[data-update-indicator]")!;
    expect(badge).not.toBeNull();
    expect(badge.getAttribute("aria-label")).toBe("Update available: Loci 0.3.0");
    act(() => badge.click());
    expect(onViewUpdate).toHaveBeenCalledTimes(1);
    expect(onOpenSettings).not.toHaveBeenCalled();
  });

  it("leaves Settings alone when there is no release", () => {
    const { onOpenSettings } = mount(null);
    expect(host.querySelector("[data-update-indicator]")).toBeNull();
    act(() => host.querySelector<HTMLButtonElement>('[aria-label="Settings"]')!.click());
    expect(onOpenSettings).toHaveBeenCalledTimes(1);
  });
});
