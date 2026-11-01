import { createContext, useContext, type ComponentProps, type PointerEvent as ReactPointerEvent } from "react";
import { GripVertical } from "./icons";
import "./PaneHeader.css";

/** Only panes against the window's top edge share its native titlebar. */
export const PaneHeaderChrome = createContext<{ windowTop: boolean; leadingInset: number } | null>(null);

type Props = Omit<ComponentProps<"header">, "onPointerDown"> & {
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
};

export function PaneHeader({ children, className = "", style, onPaneDragStart, ...props }: Props) {
  const chrome = useContext(PaneHeaderChrome);
  return (
    <header {...props} data-pane-header data-window-titlebar={chrome?.windowTop || undefined}
      data-tauri-drag-region={chrome?.windowTop ? "deep" : undefined}
      className={`pane-header flex min-w-0 shrink-0 select-none items-center gap-1.5 border-b border-stroke px-2 ${chrome?.windowTop ? "h-10" : "h-9"} ${!chrome && onPaneDragStart ? "cursor-grab active:cursor-grabbing touch-none" : ""} ${className}`}
      style={{ ...style, ...(chrome?.windowTop ? { paddingLeft: chrome.leadingInset + 8 } : {}) }}
      onPointerDown={(event) => {
        if (event.button !== 0 || (event.target as HTMLElement).closest("[data-no-drag], button, input, select, textarea, a")) return;
        // Within a window titlebar, its background moves the window. The grip
        // alone moves the pane, including after that pane moves below the top.
        if (chrome && !(event.target as HTMLElement).closest("[data-pane-drag-handle]")) return;
        onPaneDragStart?.(event);
      }}>
      {onPaneDragStart ? (
        <span data-pane-drag-handle data-tauri-drag-region={chrome ? "false" : undefined}
          title="Drag to move pane" className="grid size-5 shrink-0 cursor-grab place-items-center text-content/35 active:cursor-grabbing touch-none">
          <GripVertical className="size-4" strokeWidth={1.5} />
        </span>
      ) : null}
      {children}
    </header>
  );
}
