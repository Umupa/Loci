import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect, useRef, type RefObject } from "react";
import { NOTIFICATION_CLICK_EVENT, setWindowFocused } from "../../features/notifications/model/notifications";
import { archiveFocusedSession } from "../../features/sessions/model/archiveShortcut";
import type { Session } from "../../features/sessions/model/session";
import { resolveAppShortcut } from "../../features/settings/model/appShortcuts";
import { keybindingPressed, loadKeybindingOverrides, matchCustomKeybinding } from "../../features/settings/model/settings";
import { applyUiScale, loadUiScale, saveUiScale, UI_SCALE_DEFAULT, zoomInUiScale, zoomOutUiScale } from "../../features/settings/model/uiScale";
import { resolveZoomKeybinding } from "../../features/settings/model/zoomKeybinding";
import {
  adjacentItemId, deferUnhandledEscape, focusedBusyAgentSessionId,
  shouldHandleListNavigation, shouldStopFocusedTurnOnEscape,
  tabCommand, tabCommandForKeybinding, tabCommandKeybinding, type TabCommand,
} from "../../features/workspace/model/tabKeys";
import type { useAppWorkspace } from "./useAppWorkspace";
import type { SessionSubmission } from "./useSessionSubmission";

type Options = {
  workspace: ReturnType<typeof useAppWorkspace>;
  submission: SessionSubmission;
  sessionsRef: RefObject<Session[]>;
  surfaceOpen: boolean;
  closeSurface: () => void;
  openSearch: () => void;
  openSettings: () => void;
  openNotes: () => void;
  toggleProjectRail: () => void;
  toggleSessionSidebar: () => void;
  openTabSwitcher: () => void;
  jumpToAttention: () => void;
  reload: () => void;
  sessionOrder: readonly string[];
};

/** The keyboard and native menu share one dispatch and duplicate-event guard. */
export function useAppCommands(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const debounce = useRef({ name: "", at: 0 });

  useEffect(() => {
    let disposed = false;
    void invoke("keybindings_set_overrides", { overrides: loadKeybindingOverrides() }).catch(console.error);
    const run = (name: string, work: () => unknown) => {
      const now = performance.now();
      if (name === debounce.current.name && now - debounce.current.at < 80) return;
      debounce.current = { name, at: now };
      work();
    };
    const zoom = (direction: "zoom-in" | "zoom-out" | "zoom-reset") => run(direction, () => {
      const scale = direction === "zoom-reset" ? UI_SCALE_DEFAULT
        : direction === "zoom-in" ? zoomInUiScale(loadUiScale()) : zoomOutUiScale(loadUiScale());
      void applyUiScale(saveUiScale(scale));
    });
    const dispatch = (command: TabCommand) => {
      const { workspace: w, surfaceOpen, closeSurface, sessionOrder } = latest.current;
      if (typeof command === "object") {
        if ("focus" in command) run(`focus-${command.focus}`, () => w.focusDirection(command.focus));
        else run(`activate-${command.activate}`, () => {
          const tab = command.activate < 0 ? w.visibleTabs[w.visibleTabs.length - 1] : w.visibleTabs[command.activate];
          if (tab) w.activateTab(tab.id);
        });
        return;
      }
      if (command.startsWith("prev-session") || command.startsWith("next-session")) {
        run(command, () => {
          const id = adjacentItemId(sessionOrder, w.activeSession?.id ?? null, command.startsWith("prev") ? -1 : 1);
          if (!id || id === w.activeSession?.id) return;
          if (command.endsWith("-in-tab")) void w.openSessionInCurrentTab(id);
          else void w.openSession(id);
        });
        return;
      }
      if (command === "prev-project" || command === "next-project") {
        run(command, () => {
          const path = adjacentItemId(w.recents.map((project) => project.path), w.projectCwd, command === "prev-project" ? -1 : 1);
          if (path && path !== w.projectCwd) w.openProject(path);
        });
        return;
      }
      const handlers: Partial<Record<TabCommand & string, () => unknown>> = {
        new: () => w.createSession(),
        "switch-tab": () => latest.current.openTabSwitcher(),
        "next-attention": () => latest.current.jumpToAttention(),
        "reopen-tab": () => { void w.reopenClosed("latest"); },
        close: () => { if (w.activeSession) w.closePane(w.activeSession.id); },
        // Pinned tabs are what the user chose to keep: bulk closes leave them.
        "close-others": () => w.closeTabs(w.visibleTabs.filter((tab) => tab.id !== w.activeTabId && !tab.pinned).map((tab) => tab.id), w.activeTabId),
        "close-all": () => w.closeTabs(w.visibleTabs.filter((tab) => !tab.pinned).map((tab) => tab.id)),
        next: () => w.cycleTab(1), prev: () => w.cycleTab(-1),
        "cycle-next": () => w.cycleTab(1), "cycle-prev": () => w.cycleTab(-1),
        back: () => surfaceOpen ? closeSurface() : w.visit("back"), forward: () => w.visit("forward"),
        "split-right": () => w.split("right"), "split-down": () => w.split("down"),
      };
      const key = command === "cycle-next" ? "next" : command === "cycle-prev" ? "prev" : command;
      run(key, () => handlers[command]?.());
    };
    const appAction = (name: string) => {
      const a = latest.current;
      const actions: Record<string, () => unknown> = {
        new_window: () => invoke("open_new_window"), open_project: a.workspace.pickProject,
        toggle_sidebar: a.toggleProjectRail, toggle_session_sidebar: a.toggleSessionSidebar,
        open_search: a.openSearch, open_settings: a.openSettings, open_notes: a.openNotes,
        sidebar_opacity: a.openSettings, reload: a.reload,
        open_model_picker: () => window.dispatchEvent(new Event("open_model_picker")),
      };
      const action = actions[name];
      if (action) run(name, action);
    };
    const appShortcuts: Record<string, string> = {
      "App: New Window": "new_window", "App: Open Project": "open_project",
      "App: Toggle Sidebar": "toggle_sidebar", "App: Toggle Session Sidebar": "toggle_session_sidebar",
      "App: Search": "open_search", "App: Settings": "open_settings", "View: Reload": "reload",
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.isComposing || document.querySelector('[data-shortcut-recorder-active="true"]')) return;
      const zoomCommand = resolveZoomKeybinding(event);
      if (zoomCommand) {
        event.preventDefault(); event.stopPropagation(); zoom(zoomCommand); return;
      }
      const custom = matchCustomKeybinding(event);
      const command = custom ? tabCommandForKeybinding(custom, event) : tabCommand(event);
      if (command && keybindingPressed(tabCommandKeybinding(command), event, !custom)) {
        if (command === "archive-session") {
          if (event.repeat) return;
          const a = latest.current;
          archiveFocusedSession(event, {
            activeTabId: a.workspace.activeTabIdRef.current,
            tabs: a.workspace.tabsRef.current,
            sessions: a.sessionsRef.current,
            surfaceOpen: a.surfaceOpen,
          }, (sessionId) => run("archive-session", () => a.workspace.archiveSession(sessionId, true)));
          return;
        }
        const target = event.target instanceof Element ? event.target : null;
        const listNavigation = typeof command === "string" && /^(?:prev|next)-(?:session|project)/.test(command);
        if (listNavigation && !shouldHandleListNavigation({
          blockedTarget: !!target?.closest('input, textarea, select, [contenteditable="true"], [role="dialog"], [data-model-picker], [data-skill-picker], [data-mention-picker], [data-app-search]'),
          emptyComposerTarget: !!target?.matches('textarea[data-composer-empty="true"]'),
          surfaceOpen: latest.current.surfaceOpen,
        })) return;
        if (typeof command === "object" && "activate" in command && target?.closest('[data-model-picker], [data-skill-picker], [data-mention-picker], [data-app-search]')) return;
        event.preventDefault(); event.stopPropagation(); dispatch(command); return;
      }
      const shortcut = resolveAppShortcut(event);
      if (shortcut && appShortcuts[shortcut]) {
        event.preventDefault(); event.stopPropagation(); appAction(appShortcuts[shortcut]); return;
      }
      const a = latest.current;
      const tabId = a.workspace.activeTabIdRef.current;
      const sessionId = focusedBusyAgentSessionId(tabId, a.workspace.tabsRef.current, a.sessionsRef.current);
      if (a.surfaceOpen || !sessionId || !shouldStopFocusedTurnOnEscape(event, { focusedSessionBusy: true })) return;
      // A later surface listener may consume Escape or move focus during the dispatch.
      deferUnhandledEscape(event, () => {
        const current = latest.current;
        const w = current.workspace;
        if (disposed || current.surfaceOpen || w.activeTabIdRef.current !== tabId) return;
        if (focusedBusyAgentSessionId(tabId, w.tabsRef.current, current.sessionsRef.current) !== sessionId) return;
        void current.submission.stop(sessionId);
      });
    };
    window.addEventListener("keydown", onKey, true);

    const tabEvents: Record<string, TabCommand> = {
      new_tab: "new", switch_tab: "switch-tab", next_attention: "next-attention", reopen_tab: "reopen-tab", close_tab: "close", close_other_tabs: "close-others", close_all_tabs: "close-all",
      next_tab: "next", prev_tab: "prev", back_tab: "back", forward_tab: "forward",
      split_right: "split-right", split_down: "split-down",
      focus_left: { focus: "left" }, focus_right: { focus: "right" }, focus_up: { focus: "up" }, focus_down: { focus: "down" },
    };
    const listeners = Object.entries(tabEvents).map(([name, command]) => listen(name, () => dispatch(command)));
    for (const name of ["toggle_sidebar", "toggle_session_sidebar", "open_project", "open_search", "open_notes", "open_settings", "sidebar_opacity", "reload", "open_model_picker"]) {
      listeners.push(listen(name, () => appAction(name)));
    }
    listeners.push(listen("zoom_in", () => zoom("zoom-in")), listen("zoom_out", () => zoom("zoom-out")), listen("zoom_reset", () => zoom("zoom-reset")));
    listeners.push(listen<string>(NOTIFICATION_CLICK_EVENT, ({ payload }) => {
      // Native notification clicks are broadcast; only a window holding this session acts.
      if (!latest.current.sessionsRef.current.some((session) => session.id === payload)) return;
      const win = getCurrentWindow();
      void win.unminimize().then(() => win.setFocus()).catch(() => undefined);
      void latest.current.workspace.openSession(payload);
    }));
    const focusListener = getCurrentWindow().onFocusChanged(({ payload }) => setWindowFocused(payload));
    void getCurrentWindow().isFocused().then((focused) => { if (!disposed) setWindowFocused(focused); });
    return () => {
      disposed = true;
      window.removeEventListener("keydown", onKey, true);
      void Promise.all([...listeners, focusListener]).then((stops) => stops.forEach((stop) => stop()));
    };
  }, []);
}
