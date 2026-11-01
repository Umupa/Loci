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

const roster = [
  { id: "a1", name: "Ada", avatar: "loci", color: "#123456", projects: [] },
  { id: "a2", name: "Bea", avatar: "loci", color: "#654321", projects: [] },
];

function mountRoster(activeId = "a1") {
  localStorage.setItem("loci:agent-roster", JSON.stringify(roster));
  const handlers = { onOpen: vi.fn(), onOpenDetails: vi.fn(), onDelete: vi.fn() };
  act(() => root.render(createElement(MentorRail, {
    activeId, states: new Map(), settingsOpen: false, ...handlers,
    onCreate: vi.fn(), onOpenSettings: vi.fn(),
  })));
  return handlers;
}
const mentorButton = (name: string) => host.querySelector<HTMLButtonElement>(`[data-agent-rail] button[aria-label^="${name}"]`)!;

describe("the rail's keyboard navigation", () => {
  it("keeps one tab stop and moves it with the arrow keys", () => {
    mountRoster("a1");
    expect(mentorButton("Ada").tabIndex).toBe(0);
    expect(mentorButton("Bea").tabIndex).toBe(-1);
    act(() => mentorButton("Ada").focus());
    act(() => { mentorButton("Ada").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })); });
    expect(document.activeElement).toBe(mentorButton("Bea"));
    expect(mentorButton("Bea").tabIndex).toBe(0);
    expect(mentorButton("Ada").tabIndex).toBe(-1);
    act(() => { mentorButton("Bea").dispatchEvent(new KeyboardEvent("keydown", { key: "End", bubbles: true })); });
    expect(document.activeElement).toBe(mentorButton("Bea"));
  });

  it("opens the mentor's menu from its … button, with the first item focused, and returns focus on Escape", async () => {
    const handlers = mountRoster("a1");
    const more = mentorButton("Ada").parentElement!.querySelector<HTMLButtonElement>('[aria-haspopup="menu"]')!;
    expect(more.getAttribute("aria-expanded")).toBe("false");
    act(() => more.click());
    expect(more.getAttribute("aria-expanded")).toBe("true");
    const items = () => [...document.querySelectorAll<HTMLElement>('[role="menu"] [role="menuitem"]')];
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
    expect(items().map((item) => item.textContent)).toEqual(["Settings", "Delete mentor…"]);
    expect(document.activeElement).toBe(items()[0]);
    act(() => { items()[0].dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
    expect(document.querySelector('[role="menu"]')).toBeNull();
    expect(document.activeElement).toBe(more);
    expect(handlers.onOpenDetails).not.toHaveBeenCalled();
  });

  it("opens the menu from the keyboard with Shift+F10", async () => {
    mountRoster("a1");
    act(() => mentorButton("Ada").focus());
    act(() => { mentorButton("Ada").dispatchEvent(new KeyboardEvent("keydown", { key: "F10", shiftKey: true, bubbles: true })); });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 0)); });
    const items = [...document.querySelectorAll<HTMLElement>('[role="menu"] [role="menuitem"]')];
    expect(items.map((item) => item.textContent)).toEqual(["Settings", "Delete mentor…"]);
    expect(document.activeElement).toBe(items[0]);
  });
});

describe("the rail's update indicator", () => {
  it("puts a dot beside Settings that opens the prompt, not Settings", () => {
    const { onViewUpdate, onOpenSettings } = mount("0.3.0");
    const badge = host.querySelector<HTMLButtonElement>("[data-update-indicator]")!;
    expect(badge).not.toBeNull();
    // Its own target, not a corner of the gear.
    const settings = host.querySelector<HTMLButtonElement>('[aria-label="Settings"]')!;
    expect(settings.contains(badge)).toBe(false);
    expect(settings.parentElement).toBe(badge.parentElement);
    expect(settings.nextElementSibling).toBe(badge);
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
