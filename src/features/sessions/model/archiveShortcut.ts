type ArchiveContext = {
  activeTabId: string;
  tabs: readonly { id: string; focusedId: string }[];
  sessions: readonly { id: string }[];
  surfaceOpen: boolean;
};

/** Archive only after confirming that the focused conversation owns the key. */
export function archiveFocusedSession(
  event: KeyboardEvent,
  context: ArchiveContext,
  archive: (sessionId: string) => void,
): void {
  if (
    event.defaultPrevented ||
    context.surfaceOpen
  )
    return;

  const tab = context.tabs.find((entry) => entry.id === context.activeTabId);
  if (!tab) return;
  const session = context.sessions.find((entry) => entry.id === tab.focusedId);
  if (!session) return;

  const target = event.target instanceof Element ? event.target : null;
  if (
    target?.closest('input, textarea, select, [contenteditable="true"]') &&
    !target.closest("[data-composer]")
  )
    return;

  // Popovers can leave focus in the composer. Check the whole document,
  // excluding overlays in hidden or inactive surfaces.
  const overlayOpen = Array.from(
    document.querySelectorAll(
      '[data-popover-side], [role="dialog"], [role="alertdialog"], [role="menu"], [data-skill-picker], [data-mention-picker]',
    ),
  ).some(
    (element) =>
      element.getClientRects().length > 0 &&
      getComputedStyle(element).visibility !== "hidden" &&
      !element.closest('[hidden], [inert], [aria-hidden="true"]'),
  );
  if (overlayOpen) return;

  event.preventDefault();
  event.stopPropagation();
  archive(session.id);
}
