/**
 * Window keybindings:
 *   New mentor          cmd-t
 *   Close the reader    cmd-w (the window when the reader is empty)
 *   Next mentor         shift-cmd-}
 *   Previous mentor     shift-cmd-{
 *   Mentor 1–9          cmd-1 … cmd-9
 *   Stop focused turn   escape
 * Library, conversation, search, settings and zoom go through `appShortcuts`
 * and `zoomKeybinding`.
 */
export type AppCommand = "new-mentor" | "close-reader" | "next-mentor" | "prev-mentor" | { activate: number };

export function appCommand(e: KeyboardEvent): AppCommand | null {
  if (e.isComposing) return null;
  if (!(e.metaKey || e.ctrlKey) || e.altKey) return null;
  const key = e.key.toLowerCase();
  if (e.shiftKey) {
    if (e.key === "]" || e.key === "}") return "next-mentor";
    if (e.key === "[" || e.key === "{") return "prev-mentor";
    return null;
  }
  if (key === "t" && !e.repeat) return "new-mentor";
  if (key === "w") return "close-reader";
  if (key >= "1" && key <= "9" && key.length === 1) return { activate: Number(key) - 1 };
  return null;
}

const KEYBINDING_OF: Record<Exclude<AppCommand, object>, string> = {
  "new-mentor": "Mentor: New",
  "close-reader": "Reader: Close",
  "next-mentor": "Mentor: Next",
  "prev-mentor": "Mentor: Previous",
};
const COMMAND_OF = new Map<string, AppCommand>(Object.entries(KEYBINDING_OF).map(([command, binding]) => [binding, command as Exclude<AppCommand, object>]));

export function appCommandKeybinding(command: AppCommand): string {
  return typeof command === "object" ? "Mentor: Activate 1–9" : KEYBINDING_OF[command];
}

export function appCommandForKeybinding(binding: string, event: Pick<KeyboardEvent, "code">): AppCommand | null {
  if (binding === "Mentor: Activate 1–9") {
    const digit = /^Digit([1-9])$/.exec(event.code)?.[1];
    return digit ? { activate: Number(digit) - 1 } : null;
  }
  return COMMAND_OF.get(binding) ?? null;
}

/** The next id in a list, wrapping around; the first or last when the current one is not in it. */
export function adjacentItemId(ids: readonly string[], current: string | null, delta: number): string | null {
  if (ids.length === 0) return null;
  const index = current ? ids.indexOf(current) : -1;
  if (index < 0) return delta < 0 ? ids[ids.length - 1] : ids[0];
  return ids[(index + (delta < 0 ? -1 : 1) + ids.length) % ids.length] ?? null;
}

type EscapeKeyEvent = Pick<KeyboardEvent, "key" | "isComposing" | "defaultPrevented" | "repeat" | "metaKey" | "ctrlKey" | "altKey" | "shiftKey">;

function isPlainEscape(e: EscapeKeyEvent): boolean {
  return e.key === "Escape" && !e.isComposing && !e.repeat && !e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey;
}

export function shouldStopFocusedTurnOnEscape(e: EscapeKeyEvent, options: { focusedSessionBusy: boolean }): boolean {
  return isPlainEscape(e) && !e.defaultPrevented && options.focusedSessionBusy;
}

export function deferUnhandledEscape(e: EscapeKeyEvent, run: () => void,
  // A microtask can run between window keydown listeners, before a later
  // surface (such as Settings) has prevented the same Escape event.
  defer: (callback: () => void) => void = (callback) => setTimeout(callback, 0)): void {
  if (!isPlainEscape(e) || e.defaultPrevented) return;
  defer(() => { if (!e.defaultPrevented) run(); });
}
