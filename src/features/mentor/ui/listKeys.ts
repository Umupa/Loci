import type { KeyboardEvent } from "react";

/** The rows a list's arrow keys move between: visible buttons marked as items. */
export const LIST_ITEM = "[data-library-item]";

function items(list: HTMLElement): HTMLElement[] {
  return [...list.querySelectorAll<HTMLElement>(LIST_ITEM)].filter((item) => !item.closest("[hidden]") && !(item as HTMLButtonElement).disabled);
}

/** Focuses the first row of a list, as ↓ from its filter does. */
export function focusFirstItem(list: HTMLElement | null): boolean {
  const first = list ? items(list)[0] : undefined;
  first?.focus();
  return !!first;
}

/**
 * ↑/↓ move between a list's rows, Home and End go to either end. Enter and
 * Space open a row, as any button does.
 */
export function listKeyDown(event: KeyboardEvent<HTMLElement>) {
  if (event.defaultPrevented || event.altKey || event.metaKey || event.ctrlKey) return;
  const keys = ["ArrowDown", "ArrowUp", "Home", "End"];
  if (!keys.includes(event.key)) return;
  const all = items(event.currentTarget);
  const at = all.indexOf(document.activeElement as HTMLElement);
  if (at < 0 && (event.key === "ArrowUp" || event.key === "ArrowDown")) return;
  const next = event.key === "Home" ? 0 : event.key === "End" ? all.length - 1
    : Math.max(0, Math.min(all.length - 1, at + (event.key === "ArrowDown" ? 1 : -1)));
  if (!all[next]) return;
  event.preventDefault();
  all[next].focus();
}
