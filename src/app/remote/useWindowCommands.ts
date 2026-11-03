import { useEffect, useRef } from "react";
import { resolveAppShortcut } from "../../features/settings/model/appShortcuts";
import { transport } from "../../platform/transport";

type WindowCommands = {
  /** App: Settings (⌘, unless changed), and the menu's Settings. */
  openSettings: () => void;
  /** App: Search (⌘K unless changed), and the menu's Search: opens or closes it. */
  toggleSearch: () => void;
};

/**
 * Settings and Search, opened the ways a window of this device opens them:
 * its shortcuts, and the menu, which sends `open_settings` (or
 * `sidebar_opacity`, which lands on Settings too) and `open_search`. Menus and
 * shortcuts are this device's own, so they reach this window directly.
 */
export function useWindowCommands(commands: WindowCommands) {
  const latest = useRef(commands);
  latest.current = commands;
  useEffect(() => {
    const byShortcut: Record<string, () => void> = {
      "App: Settings": () => latest.current.openSettings(),
      "App: Search": () => latest.current.toggleSearch(),
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.isComposing) return;
      const run = byShortcut[resolveAppShortcut(event) ?? ""];
      if (!run) return;
      event.preventDefault();
      event.stopPropagation();
      run();
    };
    window.addEventListener("keydown", onKey, true);
    const listening = [
      transport.listen("open_settings", () => latest.current.openSettings()),
      transport.listen("sidebar_opacity", () => latest.current.openSettings()),
      transport.listen("open_search", () => latest.current.toggleSearch()),
    ];
    return () => {
      window.removeEventListener("keydown", onKey, true);
      void Promise.all(listening).then((stops) => stops.forEach((stop) => stop()), () => undefined);
    };
  }, []);
}
