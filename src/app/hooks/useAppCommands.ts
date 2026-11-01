import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect, useRef, type RefObject } from "react";
import { NOTIFICATION_CLICK_EVENT, setWindowFocused } from "../../features/notifications/model/notifications";
import type { Session } from "../../features/sessions/model/session";
import { resolveAppShortcut } from "../../features/settings/model/appShortcuts";
import { keybindingPressed, loadKeybindingOverrides, matchCustomKeybinding } from "../../features/settings/model/settings";
import { applyUiScale, loadUiScale, saveUiScale, UI_SCALE_DEFAULT, zoomInUiScale, zoomOutUiScale } from "../../features/settings/model/uiScale";
import { resolveZoomKeybinding } from "../../features/settings/model/zoomKeybinding";
import { requestImageZoom } from "../../shared/lib/imageZoomCommands";
import { adjacentItemId, appCommand, appCommandForKeybinding, appCommandKeybinding, deferUnhandledEscape, shouldStopFocusedTurnOnEscape, type AppCommand } from "../model/appKeys";
import type { SessionSubmission } from "./useSessionSubmission";

type Options = {
  submission: SessionSubmission;
  sessionsRef: RefObject<Session[]>;
  /** The mentors in rail order, and the one on screen. */
  mentorIds: () => readonly string[];
  activeMentorId: () => string | null;
  /** The conversation Escape stops: the open mentor's, or one shown in the reader. */
  focusedSessionId: () => string | null;
  openMentor: (id: string) => void;
  newMentor: () => void;
  /** Closes what the reader shows; false when there was nothing to close. */
  closeReader: () => boolean;
  closeWindow: () => void;
  toggleLibrary: () => void;
  toggleChat: () => void;
  openSearch: () => void;
  openSettings: () => void;
  openSession: (id: string) => void;
  reload: () => void;
};

function openDialog(): Element | null {
  return [...document.querySelectorAll('[role="dialog"]')].find((element) => !element.closest("[inert]")) ?? null;
}

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
      if (requestImageZoom(direction)) return;
      const scale = direction === "zoom-reset" ? UI_SCALE_DEFAULT
        : direction === "zoom-in" ? zoomInUiScale(loadUiScale()) : zoomOutUiScale(loadUiScale());
      void applyUiScale(saveUiScale(scale));
    });
    const dispatch = (command: AppCommand) => {
      const a = latest.current;
      if (typeof command === "object") {
        run(`activate-${command.activate}`, () => {
          const id = a.mentorIds()[command.activate];
          if (id) a.openMentor(id);
        });
        return;
      }
      const handlers: Record<Exclude<AppCommand, object>, () => unknown> = {
        "new-mentor": a.newMentor,
        "close-reader": () => { if (!a.closeReader()) a.closeWindow(); },
        "next-mentor": () => step(1),
        "prev-mentor": () => step(-1),
      };
      run(command, handlers[command]);
    };
    const step = (delta: number) => {
      const a = latest.current;
      const id = adjacentItemId(a.mentorIds(), a.activeMentorId(), delta);
      if (id && id !== a.activeMentorId()) a.openMentor(id);
    };
    const appAction = (name: string) => {
      const a = latest.current;
      const actions: Record<string, () => unknown> = {
        new_window: () => invoke("open_new_window"),
        toggle_library: a.toggleLibrary, toggle_chat: a.toggleChat,
        open_search: a.openSearch, open_settings: a.openSettings,
        sidebar_opacity: a.openSettings, reload: a.reload,
        open_model_picker: () => window.dispatchEvent(new Event("open_model_picker")),
      };
      const action = actions[name];
      if (action) run(name, action);
    };
    const appShortcuts: Record<string, string> = {
      "App: New Window": "new_window",
      "App: Toggle Library": "toggle_library", "App: Toggle Conversation": "toggle_chat",
      "App: Search": "open_search", "App: Settings": "open_settings", "View: Reload": "reload",
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.isComposing || document.querySelector('[data-shortcut-recorder-active="true"]')) return;
      const zoomCommand = resolveZoomKeybinding(event);
      if (zoomCommand) {
        event.preventDefault(); event.stopPropagation(); zoom(zoomCommand); return;
      }
      // A dialog or the palette owns the keyboard while it is open (a closed
      // sheet kept for its animation is inert); its own Escape and keys apply.
      if (openDialog()) return;
      const custom = matchCustomKeybinding(event);
      const command = custom ? appCommandForKeybinding(custom, event) : appCommand(event);
      if (command && keybindingPressed(appCommandKeybinding(command), event, !custom)) {
        const target = event.target instanceof Element ? event.target : null;
        if (typeof command === "object" && target?.closest('[data-model-picker], [data-skill-picker], [data-mention-picker], [data-app-search]')) return;
        event.preventDefault(); event.stopPropagation(); dispatch(command); return;
      }
      const shortcut = resolveAppShortcut(event);
      if (shortcut && appShortcuts[shortcut]) {
        event.preventDefault(); event.stopPropagation(); appAction(appShortcuts[shortcut]); return;
      }
      const sessionId = latest.current.focusedSessionId();
      const busy = !!sessionId && latest.current.sessionsRef.current.some((session) => session.id === sessionId && session.busy);
      if (!sessionId || !shouldStopFocusedTurnOnEscape(event, { focusedSessionBusy: busy })) return;
      // A later surface listener may consume Escape or move focus during the dispatch.
      deferUnhandledEscape(event, () => {
        const current = latest.current;
        if (disposed || current.focusedSessionId() !== sessionId) return;
        if (!current.sessionsRef.current.some((session) => session.id === sessionId && session.busy)) return;
        void current.submission.stop(sessionId);
      });
    };
    window.addEventListener("keydown", onKey, true);

    const menuEvents: Record<string, AppCommand> = {
      new_mentor: "new-mentor", close_reader: "close-reader", next_mentor: "next-mentor", prev_mentor: "prev-mentor",
    };
    const listeners = Object.entries(menuEvents).map(([name, command]) => listen(name, () => dispatch(command)));
    for (const name of ["toggle_library", "toggle_chat", "open_search", "open_settings", "sidebar_opacity", "reload", "open_model_picker"]) {
      listeners.push(listen(name, () => appAction(name)));
    }
    listeners.push(listen("zoom_in", () => zoom("zoom-in")), listen("zoom_out", () => zoom("zoom-out")), listen("zoom_reset", () => zoom("zoom-reset")));
    listeners.push(listen<string>(NOTIFICATION_CLICK_EVENT, ({ payload }) => {
      // Native notification clicks are broadcast; only a window holding this session acts.
      if (!latest.current.sessionsRef.current.some((session) => session.id === payload)) return;
      const win = getCurrentWindow();
      void win.unminimize().then(() => win.setFocus()).catch(() => undefined);
      latest.current.openSession(payload);
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
