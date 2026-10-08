import { useEffect, useRef, useState } from "react";
import { Modal } from "../../../shared/ui/Modal";
import { Check } from "../../../shared/ui/icons";
import type { Canvas } from "../canvas";

type Props = {
  canvases: Canvas[];
  onSelect: (canvasId: string) => void;
  onCancel: () => void;
};

export function SelectCanvasDialog({ canvases, onSelect, onCancel }: Props) {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const selected = listRef.current?.querySelector<HTMLButtonElement>("[data-selected=true]");
    if (selected) {
      selected.focus({ preventScroll: true });
      selected.scrollIntoView({ block: "nearest" });
    }
  }, [selectedIndex]);

  return (
    <Modal
      onClose={onCancel}
      title="Save to Canvas"
      description={`Choose one of ${canvases.length} available canvas${canvases.length === 1 ? "" : "es"}`}
      size="sm"
      fitViewport
    >
      <div className="flex flex-col gap-0">
        <div ref={listRef} className="max-h-[320px] overflow-y-auto" onKeyDown={(event) => {
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            setSelectedIndex((i) => Math.max(0, Math.min(i + (event.key === "ArrowDown" ? 1 : -1), canvases.length - 1)));
          } else if (event.key === "Enter") {
            event.preventDefault();
            if (canvases[selectedIndex]) onSelect(canvases[selectedIndex].id);
          }
        }}>
          {canvases.map((canvas, index) => {
            const isSelected = index === selectedIndex;
            const formattedDate = new Date(canvas.updatedAt).toLocaleDateString(
              "en-US",
              { month: "short", day: "numeric" }
            );
            return (
              <button
                key={canvas.id}
                data-selected={isSelected}
                type="button"
                aria-pressed={isSelected}
                onFocus={() => setSelectedIndex(index)}
                onClick={() => {
                  setSelectedIndex(index);
                  onSelect(canvas.id);
                }}
                className={`w-full px-4 py-3 text-left transition-colors duration-150 ${
                  isSelected
                    ? "bg-accent/15 text-accent"
                    : "hover:bg-content/5 text-content"
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <h3 className="truncate font-medium text-base leading-tight">
                        {canvas.title}
                      </h3>
                      {isSelected && (
                        <Check className="size-4 shrink-0 text-accent" strokeWidth={2} />
                      )}
                    </div>
                    {canvas.tags.length > 0 && (
                      <div className="mt-1 flex flex-wrap gap-1">
                        {canvas.tags.slice(0, 3).map((tag) => (
                          <span
                            key={tag}
                            className="inline-block rounded bg-content/8 px-2 py-0.5 text-xs text-content/60"
                          >
                            {tag}
                          </span>
                        ))}
                        {canvas.tags.length > 3 && (
                          <span className="text-xs text-content/40">
                            +{canvas.tags.length - 3}
                          </span>
                        )}
                      </div>
                    )}
                  </div>
                  <div className="shrink-0 text-right text-xs text-content/50">
                    <div>{formattedDate}</div>
                  </div>
                </div>
              </button>
            );
          })}
        </div>

        <div className="mt-2 border-t border-content/7 px-4 py-3 flex justify-end gap-2">
          <button
            type="button"
            onClick={onCancel}
            className="rounded-md px-4 py-2 text-sm text-content/70 hover:bg-content/8 transition-colors"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!canvases[selectedIndex]}
            onClick={() => onSelect(canvases[selectedIndex].id)}
            className="rounded-md px-4 py-2 text-sm bg-accent text-background font-medium hover:bg-accent/90 transition-colors"
          >
            Save to Canvas
          </button>
        </div>
      </div>
    </Modal>
  );
}
