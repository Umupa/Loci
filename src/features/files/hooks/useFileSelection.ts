import { useCallback, useEffect, useState, type RefObject } from "react";

export type FileSelection = { text: string; rect: DOMRect; range: Range };

function rangeRect(range: Range): DOMRect | null {
  for (const rect of range.getClientRects()) {
    if (rect.width > 0 || rect.height > 0) return rect;
  }
  const rect = range.getBoundingClientRect();
  return rect.width > 0 || rect.height > 0 ? rect : null;
}

/**
 * The text currently selected inside a file viewer, once the pointer or the
 * keyboard has finished selecting. Selecting nothing, or leaving the viewer,
 * clears it.
 */
export function useFileSelection(root: RefObject<HTMLElement | null>, enabled: boolean) {
  const [selection, setSelection] = useState<FileSelection | null>(null);
  const dismiss = useCallback(() => setSelection(null), []);

  useEffect(() => {
    const el = root.current;
    if (!enabled || !el) {
      setSelection(null);
      return;
    }
    let pointerSelecting = false;
    let frame = 0;
    const report = () => {
      frame = 0;
      const native = window.getSelection();
      const range = native && native.rangeCount > 0 ? native.getRangeAt(0) : null;
      const text = native?.toString().trim() ?? "";
      const inside = !!range && el.contains(range.commonAncestorContainer);
      const rect = range && inside && text && !native?.isCollapsed ? rangeRect(range) : null;
      setSelection(rect && range ? { text, rect, range: range.cloneRange() } : null);
    };
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(report);
    };
    const onPointerDown = (event: PointerEvent) => {
      pointerSelecting = el.contains(event.target as Node);
      // A new press ends the previous selection's menu.
      if (pointerSelecting) setSelection(null);
    };
    const onPointerUp = () => {
      if (!pointerSelecting) return;
      pointerSelecting = false;
      schedule();
    };
    const onSelectionChange = () => {
      if (!pointerSelecting) schedule();
    };
    document.addEventListener("pointerdown", onPointerDown, { passive: true });
    document.addEventListener("pointerup", onPointerUp, { passive: true });
    document.addEventListener("selectionchange", onSelectionChange);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("pointerup", onPointerUp);
      document.removeEventListener("selectionchange", onSelectionChange);
    };
  }, [root, enabled]);

  return { selection, dismiss };
}
