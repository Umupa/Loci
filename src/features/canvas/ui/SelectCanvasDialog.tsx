import { useEffect, useRef, useState } from "react";
import { Popover, type PopoverAnchor } from "../../../shared/ui/Popover";
import type { Canvas } from "../canvas";

type Props = {
  canvases: Canvas[];
  anchor: PopoverAnchor;
  onSelect: (canvasId: string) => void;
  onCancel: () => void;
};

export function SelectCanvasDialog({ canvases, anchor, onSelect, onCancel }: Props) {
  const [focusedIndex, setFocusedIndex] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const focused = listRef.current?.querySelector<HTMLButtonElement>("[data-focused=true]");
    focused?.focus({ preventScroll: true });
  }, [focusedIndex]);

  return (
    <Popover
      anchor={anchor}
      side="top"
      align="start"
      width={220}
      constrainHeight={false}
      onDismiss={onCancel}
      autoFocus
    >
      <div
        ref={listRef}
        className="py-1.5"
        onKeyDown={(event) => {
          if (event.key === "ArrowDown") {
            event.preventDefault();
            setFocusedIndex((i) => Math.min(i + 1, canvases.length - 1));
          } else if (event.key === "ArrowUp") {
            event.preventDefault();
            setFocusedIndex((i) => Math.max(i - 1, 0));
          } else if (event.key === "Enter") {
            event.preventDefault();
            if (canvases[focusedIndex]) onSelect(canvases[focusedIndex].id);
          }
        }}
      >
        {canvases.map((canvas, index) => {
          const isFocused = index === focusedIndex;
          return (
            <button
              key={canvas.id}
              type="button"
              data-focused={isFocused}
              onFocus={() => setFocusedIndex(index)}
              onClick={() => onSelect(canvas.id)}
              className={`relative w-full flex items-center gap-2.5 px-3 py-2 text-left transition-colors duration-100 ${
                isFocused
                  ? "bg-accent/12 text-content"
                  : "text-content/60 hover:bg-content/5 hover:text-content/85"
              }`}
            >
              {isFocused && (
                <span className="absolute left-0 inset-y-1.5 w-[2px] rounded-full bg-accent" />
              )}
              <span className="min-w-0 truncate text-[13px] font-medium leading-none">
                {canvas.title}
              </span>
            </button>
          );
        })}
      </div>
    </Popover>
  );
}
