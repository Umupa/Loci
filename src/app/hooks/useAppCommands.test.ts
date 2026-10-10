// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession } from "../../features/sessions/model/session";
import { saveKeybindingOverride } from "../../features/settings/model/settings";
import { leaf, newTab } from "../../features/workspace/model/layout";
import { useAppCommands } from "./useAppCommands";

const native = vi.hoisted(() => ({
  handlers: new Map<string, Set<(event: { payload: unknown }) => void>>(),
  invoke: vi.fn(async () => undefined),
  unminimize: vi.fn(async () => undefined),
  focus: vi.fn(async () => undefined),
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
vi.mock("../../features/notifications/model/notifications", () => ({
  NOTIFICATION_CLICK_EVENT: "loci:notification-click", setWindowFocused: vi.fn(),
}));

type Options = Parameters<typeof useAppCommands>[0];
let roots: Root[];
let now: number;

function options(id = "s1") {
  const session = { ...newSession("claude", "/project"), id, busy: true };
  const tab = { ...newTab(id), id: `tab-${id}` };
  const workspace = {
    activeSession: session, activeTab: tab, activeTabId: tab.id,
    activeTabIdRef: { current: tab.id }, tabsRef: { current: [tab] },
    visibleTabs: [tab], recents: [{ path: "/project" }, { path: "/other" }], projectCwd: "/project",
    createSession: vi.fn(), closePane: vi.fn(), closeTabs: vi.fn(), cycleTab: vi.fn(),
    focusDirection: vi.fn(), activateTab: vi.fn(), visit: vi.fn(), split: vi.fn(),
    archiveSession: vi.fn(async () => undefined), openSession: vi.fn(async () => undefined),
    openSessionInCurrentTab: vi.fn(async () => undefined), openProject: vi.fn(), pickProject: vi.fn(),
  };
  return {
    workspace: workspace as unknown as Options["workspace"],
    submission: { stop: vi.fn(async () => undefined) } as unknown as Options["submission"],
    sessionsRef: { current: [session] }, surfaceOpen: false,
    closeSurface: vi.fn(), openSearch: vi.fn(), openSettings: vi.fn(), openNotes: vi.fn(),
    openTabSwitcher: vi.fn(), jumpToAttention: vi.fn(), openTabOverview: vi.fn(),
    toggleProjectRail: vi.fn(), toggleSessionSidebar: vi.fn(), reload: vi.fn(),
    sessionOrder: [id, "s2"],
  } satisfies Options;
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

beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  roots = [];
  now = 100;
  vi.spyOn(performance, "now").mockImplementation(() => now);
  native.handlers.clear();
  native.invoke.mockClear(); native.unminimize.mockClear(); native.focus.mockClear();
});
afterEach(async () => {
  await act(async () => roots.forEach((root) => root.unmount()));
  document.body.replaceChildren();
  vi.restoreAllMocks();
});

describe("application command routing", () => {
  it("deduplicates keyboard and native tab commands under the same name", async () => {
    const value = options();
    await mount(value);
    key({ key: "t", code: "KeyT", metaKey: true });
    emit("new_tab");
    expect(value.workspace.createSession).toHaveBeenCalledOnce();
    now += 81;
    emit("new_tab");
    expect(value.workspace.createSession).toHaveBeenCalledTimes(2);
    now += 81;
    key({ key: "Tab", code: "Tab", ctrlKey: true });
    emit("next_tab");
    expect(value.workspace.cycleTab).toHaveBeenCalledExactlyOnceWith(1);
  });

  it("deduplicates an app shortcut and its native menu event", async () => {
    const value = options();
    await mount(value);
    key({ key: "b", code: "KeyB", metaKey: true });
    emit("toggle_sidebar");
    expect(value.toggleProjectRail).toHaveBeenCalledOnce();
  });

  it("honors disabled and rebound keys without overriding IME or recording", async () => {
    const value = options();
    await mount(value);
    saveKeybindingOverride("Tab: New", { shortcut: "Command+Shift+KeyY" });
    key({ key: "t", code: "KeyT", metaKey: true });
    expect(value.workspace.createSession).not.toHaveBeenCalled();
    key({ key: "Y", code: "KeyY", metaKey: true, shiftKey: true, isComposing: true });
    expect(value.workspace.createSession).not.toHaveBeenCalled();
    key({ key: "Y", code: "KeyY", metaKey: true, shiftKey: true });
    expect(value.workspace.createSession).toHaveBeenCalledOnce();
    now += 81;
    saveKeybindingOverride("Tab: New", { disabled: true });
    key({ key: "Y", code: "KeyY", metaKey: true, shiftKey: true });
    expect(value.workspace.createSession).toHaveBeenCalledOnce();
    const recorder = document.createElement("div");
    recorder.dataset.shortcutRecorderActive = "true";
    document.body.append(recorder);
    key({ key: "b", code: "KeyB", metaKey: true });
    expect(value.toggleProjectRail).not.toHaveBeenCalled();
  });

  it("lets a picker own numbered selection and preserves text-navigation focus", async () => {
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
    expect(value.workspace.activateTab).not.toHaveBeenCalled();
    key({ key: "ArrowDown", code: "ArrowDown", metaKey: true, shiftKey: true }, input);
    expect(value.workspace.openSession).not.toHaveBeenCalled();
    const composer = document.createElement("textarea");
    composer.dataset.composerEmpty = "true";
    document.body.append(composer);
    key({ key: "ArrowDown", code: "ArrowDown", metaKey: true }, composer);
    expect(value.workspace.openSessionInCurrentTab).toHaveBeenCalledExactlyOnceWith("s2");
    expect(value.workspace.openSession).not.toHaveBeenCalled();
  });

  it("does not archive while a rename field or visible overlay owns the key", async () => {
    const value = options();
    await mount(value);
    const rename = document.createElement("input");
    document.body.append(rename);
    key({ key: "A", code: "KeyA", metaKey: true, shiftKey: true }, rename);
    expect(value.workspace.archiveSession).not.toHaveBeenCalled();
    const composer = document.createElement("textarea");
    composer.dataset.composer = "true";
    document.body.append(composer);
    const dialog = document.createElement("div");
    dialog.setAttribute("role", "dialog");
    vi.spyOn(dialog, "getClientRects").mockReturnValue([{}] as unknown as DOMRectList);
    document.body.append(dialog);
    key({ key: "A", code: "KeyA", metaKey: true, shiftKey: true }, composer);
    expect(value.workspace.archiveSession).not.toHaveBeenCalled();
    dialog.remove();
    const accepted = key({ key: "A", code: "KeyA", metaKey: true, shiftKey: true }, composer);
    expect(accepted.defaultPrevented).toBe(true);
    expect(value.workspace.archiveSession).toHaveBeenCalledExactlyOnceWith("s1", true);
  });

  it("routes agent pane close and directional focus without touching the hidden session tab", async () => {
    const value: Options = {
      ...options(), surfaceOpen: true,
      agentPane: {
        focusedId: "document:doc1", layout: leaf("agent-session"),
        onClosePane: vi.fn(), onFocusDirection: vi.fn(),
      },
    };
    await mount(value);
    key({ key: "w", code: "KeyW", metaKey: true });
    emit("close_tab");
    expect(value.agentPane?.onClosePane).toHaveBeenCalledExactlyOnceWith("document:doc1");
    expect(value.workspace.closePane).not.toHaveBeenCalled();
    expect(value.closeSurface).not.toHaveBeenCalled();
    emit("focus_right");
    expect(value.agentPane?.onFocusDirection).toHaveBeenCalledExactlyOnceWith("right");
    expect(value.workspace.focusDirection).not.toHaveBeenCalled();
  });

  it("does not split or bulk-close hidden project sessions from an agent workspace", async () => {
    const value: Options = {
      ...options(), surfaceOpen: true,
      agentPane: {
        focusedId: "agent-session", layout: leaf("agent-session"),
        onClosePane: vi.fn(), onFocusDirection: vi.fn(),
      },
    };
    await mount(value);
    emit("split_right");
    emit("split_down");
    expect(value.workspace.split).not.toHaveBeenCalled();
    emit("close_other_tabs");
    emit("close_all_tabs");
    expect(value.workspace.closeTabs).not.toHaveBeenCalled();
    key({ key: "A", code: "KeyA", metaKey: true, shiftKey: true });
    expect(value.workspace.archiveSession).not.toHaveBeenCalled();
    emit("new_tab");
    expect(value.workspace.createSession).toHaveBeenCalledOnce();
  });

  it("closes an app surface without closing its hidden project session", async () => {
    const value = { ...options(), surfaceOpen: true };
    await mount(value);
    emit("close_tab");
    expect(value.closeSurface).toHaveBeenCalledOnce();
    expect(value.workspace.closePane).not.toHaveBeenCalled();
  });

  it("defers Escape until later listeners and verifies the same pane is still focused", async () => {
    const value = options();
    await mount(value);
    const consume = (event: KeyboardEvent) => event.preventDefault();
    window.addEventListener("keydown", consume);
    key({ key: "Escape", code: "Escape" });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).not.toHaveBeenCalled();
    window.removeEventListener("keydown", consume);
    key({ key: "Escape", code: "Escape" });
    value.workspace.activeTabIdRef.current = "another-tab";
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).not.toHaveBeenCalled();
    value.workspace.activeTabIdRef.current = "tab-s1";
    key({ key: "Escape", code: "Escape" });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).toHaveBeenCalledExactlyOnceWith("s1");
  });

  it("stops only the still focused busy agent conversation after unhandled Escape", async () => {
    const value: Options = {
      ...options(), surfaceOpen: true,
      agentPane: {
        focusedId: "s1", layout: leaf("s1"),
        onClosePane: vi.fn(), onFocusDirection: vi.fn(),
      },
    };
    await mount(value);
    const consume = (event: KeyboardEvent) => event.preventDefault();
    window.addEventListener("keydown", consume);
    key({ key: "Escape", code: "Escape" });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).not.toHaveBeenCalled();
    window.removeEventListener("keydown", consume);
    key({ key: "Escape", code: "Escape" });
    value.agentPane!.focusedId = "document:doc1";
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).not.toHaveBeenCalled();
    value.agentPane!.focusedId = "s1";
    key({ key: "Escape", code: "Escape" });
    const pane = value.agentPane;
    value.agentPane = undefined;
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).not.toHaveBeenCalled();
    value.agentPane = pane;
    key({ key: "Escape", code: "Escape" });
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 5)); });
    expect(value.submission.stop).toHaveBeenCalledExactlyOnceWith("s1");
  });

  it("routes a broadcast notification click only to the window holding its session", async () => {
    const first = options("first");
    const second = options("second");
    await mount(first);
    await mount(second);
    emit("loci:notification-click", "second");
    await act(async () => { await Promise.resolve(); });
    expect(first.workspace.openSession).not.toHaveBeenCalled();
    expect(second.workspace.openSession).toHaveBeenCalledExactlyOnceWith("second");
    expect(native.unminimize).toHaveBeenCalledOnce();
    expect(native.focus).toHaveBeenCalledOnce();
  });
});
