// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession } from "../../features/sessions/model/session";
import { saveKeybindingOverride } from "../../features/settings/model/settings";
import { useAppCommands } from "./useAppCommands";
import { IMAGE_ZOOM_EVENT } from "../../shared/lib/imageZoomCommands";
import { loadUiScale } from "../../features/settings/model/uiScale";

const native = vi.hoisted(() => ({
  handlers: new Map<string, Set<(event: { payload: unknown }) => void>>(),
  invoke: vi.fn(async () => undefined),
  unminimize: vi.fn(async () => undefined),
  focus: vi.fn(async () => undefined),
  zoom: vi.fn(async () => undefined),
}));
vi.mock("@tauri-apps/api/core", () => ({ invoke: native.invoke }));
vi.mock("@tauri-apps/api/event", () => ({
  listen: vi.fn(async (name: string, handler: (event: { payload: unknown }) => void) => {
    const handlers = native.handlers.get(name) ?? new Set();
    handlers.add(handler);
    native.handlers.set(name, handlers);
    return () => { handlers.delete(handler); };
  }),
}));
vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    unminimize: native.unminimize, setFocus: native.focus,
    isFocused: async () => true, onFocusChanged: async () => () => undefined,
  }),
}));
vi.mock("@tauri-apps/api/webview", () => ({ getCurrentWebview: () => ({ setZoom: native.zoom }) }));
vi.mock("../../features/notifications/model/notifications", () => ({
  NOTIFICATION_CLICK_EVENT: "loci:notification-click", setWindowFocused: vi.fn(),
}));

type Options = Parameters<typeof useAppCommands>[0];
let roots: Root[];
let now: number;

function options(id = "s1") {
  const session = { ...newSession("claude", "/project"), id, busy: true };
  let active: string | null = "ada";
  let focused: string | null = id;
  const value = {
    submission: { stop: vi.fn(async () => undefined) } as unknown as Options["submission"],
    sessionsRef: { current: [session] },
    mentorIds: () => ["ada", "bea", "cy"],
    activeMentorId: () => active,
    focusedSessionId: () => focused,
    openMentor: vi.fn((next: string) => { active = next; }),
    newMentor: vi.fn(), closeReader: vi.fn(() => true), closeWindow: vi.fn(),
    toggleLibrary: vi.fn(), toggleChat: vi.fn(), openSearch: vi.fn(), openSettings: vi.fn(),
    openSession: vi.fn(), reload: vi.fn(),
    setFocused: (next: string | null) => { focused = next; },
  };
  return value satisfies Options;
}

async function mount(value: Options) {
  function Harness() { useAppCommands(value); return null; }
  const element = document.createElement("div");
  document.body.append(element);
  const root = createRoot(element);
  roots.push(root);
  await act(async () => root.render(createElement(Harness)));
}

function key(value: KeyboardEventInit, target: Element = document.body) {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...value });
  act(() => target.dispatchEvent(event));
  return event;
}
function emit(name: string, payload?: unknown) {
  act(() => { for (const handler of native.handlers.get(name) ?? []) handler({ payload }); });
}
const later = () => act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  roots = [];
  now = 100;
  vi.spyOn(performance, "now").mockImplementation(() => now);
  native.handlers.clear();
  native.invoke.mockClear(); native.unminimize.mockClear(); native.focus.mockClear();
  native.zoom.mockClear();
});
afterEach(async () => {
  await act(async () => roots.forEach((root) => root.unmount()));
  document.body.replaceChildren();
  vi.restoreAllMocks();
});

describe("application command routing", () => {
  it("routes zoom keys and native menus to the active image once, then restores interface zoom", async () => {
    await mount(options());
    const image = document.createElement("div");
    image.dataset.imageZoom = "modal";
    const zoom = vi.fn((event: Event) => event.preventDefault());
    image.addEventListener(IMAGE_ZOOM_EVENT, zoom);
    document.body.append(image);
    const event = key({ key: "=", code: "Equal", metaKey: true });
    emit("zoom_in");
    expect(event.defaultPrevented).toBe(true);
    expect(zoom).toHaveBeenCalledOnce();
    expect((zoom.mock.calls[0][0] as CustomEvent).detail).toBe("zoom-in");
    now += 81;
    emit("zoom_out");
    expect((zoom.mock.calls[1][0] as CustomEvent).detail).toBe("zoom-out");
    expect(native.zoom).not.toHaveBeenCalled();
    expect(loadUiScale()).toBe(1);

    image.remove();
    now += 81;
    emit("zoom_in");
    expect(native.zoom).toHaveBeenCalledExactlyOnceWith(1.1);
    expect(loadUiScale()).toBe(1.1);
  });

  it("preserves custom and disabled zoom bindings while an image owns zoom", async () => {
    await mount(options());
    const image = document.createElement("div");
    image.dataset.imageZoom = "focused";
    const zoom = vi.fn((event: Event) => event.preventDefault());
    image.addEventListener(IMAGE_ZOOM_EVENT, zoom);
    document.body.append(image);
    saveKeybindingOverride("View: Zoom In", { shortcut: "Option+Equal" });
    key({ key: "=", code: "Equal", metaKey: true });
    expect(zoom).not.toHaveBeenCalled();
    key({ key: "=", code: "Equal", altKey: true });
    expect(zoom).toHaveBeenCalledOnce();
    now += 81;
    saveKeybindingOverride("View: Zoom In", { disabled: true });
    key({ key: "=", code: "Equal", altKey: true });
    key({ key: "=", code: "Equal", metaKey: true });
    expect(zoom).toHaveBeenCalledOnce();
    expect(native.zoom).not.toHaveBeenCalled();
  });

  it("opens the mentor gallery once for a key and its native menu event", async () => {
    const value = options();
    await mount(value);
    key({ key: "t", code: "KeyT", metaKey: true });
    emit("new_mentor");
    expect(value.newMentor).toHaveBeenCalledOnce();
    now += 81;
    emit("new_mentor");
    expect(value.newMentor).toHaveBeenCalledTimes(2);
  });

  it("closes the reader, and the window only when the reader is already empty", async () => {
    const value = options();
    await mount(value);
    key({ key: "w", code: "KeyW", metaKey: true });
    expect(value.closeReader).toHaveBeenCalledOnce();
    expect(value.closeWindow).not.toHaveBeenCalled();
    now += 81;
    value.closeReader.mockReturnValue(false);
    emit("close_reader");
    expect(value.closeWindow).toHaveBeenCalledOnce();
  });

  it("moves between mentors by number and in rail order, wrapping around", async () => {
    const value = options();
    await mount(value);
    key({ key: "3", code: "Digit3", metaKey: true });
    expect(value.openMentor).toHaveBeenLastCalledWith("cy");
    now += 81;
    key({ key: "9", code: "Digit9", metaKey: true });
    expect(value.openMentor).toHaveBeenCalledOnce();
    key({ key: "}", code: "BracketRight", metaKey: true, shiftKey: true });
    expect(value.openMentor).toHaveBeenLastCalledWith("ada");
    now += 81;
    emit("prev_mentor");
    expect(value.openMentor).toHaveBeenLastCalledWith("cy");
  });

  it("deduplicates an app shortcut and its native menu event", async () => {
    const value = options();
    await mount(value);
    key({ key: "b", code: "KeyB", metaKey: true });
    emit("toggle_library");
    expect(value.toggleLibrary).toHaveBeenCalledOnce();
    key({ key: "b", code: "KeyB", metaKey: true, shiftKey: true });
    expect(value.toggleChat).toHaveBeenCalledOnce();
  });

  it("ignores tab and pane menu events that no longer exist", async () => {
    await mount(options());
    for (const name of ["new_tab", "close_tab", "split_right", "switch_tab", "tab_overview"]) expect(native.handlers.has(name)).toBe(false);
  });

  it("honors disabled and rebound keys without overriding IME or recording", async () => {
    const value = options();
    await mount(value);
    saveKeybindingOverride("Mentor: New", { shortcut: "Command+Shift+KeyY" });
    key({ key: "t", code: "KeyT", metaKey: true });
    expect(value.newMentor).not.toHaveBeenCalled();
    key({ key: "Y", code: "KeyY", metaKey: true, shiftKey: true, isComposing: true });
    expect(value.newMentor).not.toHaveBeenCalled();
    key({ key: "Y", code: "KeyY", metaKey: true, shiftKey: true });
    expect(value.newMentor).toHaveBeenCalledOnce();
    now += 81;
    saveKeybindingOverride("Mentor: New", { disabled: true });
    key({ key: "Y", code: "KeyY", metaKey: true, shiftKey: true });
    expect(value.newMentor).toHaveBeenCalledOnce();
    const recorder = document.createElement("div");
    recorder.dataset.shortcutRecorderActive = "true";
    document.body.append(recorder);
    key({ key: "b", code: "KeyB", metaKey: true });
    expect(value.toggleLibrary).not.toHaveBeenCalled();
  });

  it("lets a picker own numbered selection", async () => {
    const value = options();
    await mount(value);
    const picker = document.createElement("div");
    picker.dataset.modelPicker = "true";
    const input = document.createElement("input");
    picker.append(input);
    document.body.append(picker);
    const picked = vi.fn((event: KeyboardEvent) => event.preventDefault());
    input.addEventListener("keydown", picked);
    key({ key: "1", code: "Digit1", metaKey: true }, input);
    expect(picked).toHaveBeenCalledOnce();
    expect(value.openMentor).not.toHaveBeenCalled();
  });

  it("stops only the still focused busy conversation after an unhandled Escape", async () => {
    const value = options();
    await mount(value);
    const consume = (event: KeyboardEvent) => event.preventDefault();
    window.addEventListener("keydown", consume);
    key({ key: "Escape", code: "Escape" });
    await later();
    expect(value.submission.stop).not.toHaveBeenCalled();
    window.removeEventListener("keydown", consume);
    key({ key: "Escape", code: "Escape" });
    value.setFocused("another");
    await later();
    expect(value.submission.stop).not.toHaveBeenCalled();
    value.setFocused("s1");
    key({ key: "Escape", code: "Escape" });
    await later();
    expect(value.submission.stop).toHaveBeenCalledExactlyOnceWith("s1");
  });

  it("routes a broadcast notification click only to the window holding its session", async () => {
    const first = options("first");
    const second = options("second");
    await mount(first);
    await mount(second);
    emit("loci:notification-click", "second");
    await act(async () => { await Promise.resolve(); });
    expect(first.openSession).not.toHaveBeenCalled();
    expect(second.openSession).toHaveBeenCalledExactlyOnceWith("second");
    expect(native.unminimize).toHaveBeenCalledOnce();
    expect(native.focus).toHaveBeenCalledOnce();
  });
});
