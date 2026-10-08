import { memo, useMemo, useState, type MouseEvent as ReactMouseEvent, type ReactNode } from "react";
import type { Canvas } from "../canvas";
import { DashboardSquare, ExcalidrawIcon, LoaderCircle, Plus } from "../../../shared/ui/icons";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { sameProjectPath } from "../../projects/model/recents";

type Props = {
  canvases: Canvas[];
  cwd: string;
  /** The drawing in the focused pane, if any. */
  activeId?: string;
  onOpen: (id: string) => void;
  onOpenInTab: (id: string) => void;
  onNew: () => Promise<Canvas | undefined>;
  onRename: (id: string, title: string) => void;
  onDelete: (id: string) => void;
  /** Every project's drawings, on the full Excalidraw page. */
  onOpenAll?: () => void;
};

const MENU_ITEMS: ContextMenuItem[] = [
  { kind: "item", id: "open", label: "Open" },
  { kind: "item", id: "open-tab", label: "Open in New Tab" },
  { kind: "sep" },
  { kind: "item", id: "rename", label: "Rename" },
  { kind: "item", id: "delete", label: "Delete", danger: true },
];

/** The current project's drawings, as a sidebar list that opens them in panes. */
export const CanvasList = memo(function CanvasList({ canvases, cwd, activeId, onOpen, onOpenInTab, onNew, onRename, onDelete, onOpenAll }: Props) {
  const [creating, setCreating] = useState(false);
  const [menu, setMenu] = useState<{ x: number; y: number; id: string } | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const drawings = useMemo(
    () => canvases.filter((canvas) => !!canvas.cwd && sameProjectPath(canvas.cwd, cwd)).sort((a, b) => b.updatedAt - a.updatedAt),
    [canvases, cwd],
  );

  const create = async () => {
    setCreating(true);
    try {
      const canvas = await onNew();
      if (canvas) onOpen(canvas.id);
    } finally { setCreating(false); }
  };

  const commitRename = (canvas: Canvas) => {
    const title = renameDraft.trim() || "Untitled drawing";
    if (title !== canvas.title) onRename(canvas.id, title);
    setRenamingId(null);
  };

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex h-9 shrink-0 items-center gap-px border-b border-stroke px-2">
        <HeaderIcon label="New Drawing" disabled={creating} onClick={() => void create()}>
          {creating ? <LoaderCircle className="size-3.5 animate-spin" /> : <Plus className="size-3.5" strokeWidth={1.75} />}
        </HeaderIcon>
        {onOpenAll ? (
          <HeaderIcon label="All Drawings" onClick={onOpenAll}>
            <DashboardSquare className="size-3.5" strokeWidth={1.75} />
          </HeaderIcon>
        ) : null}
      </div>
      <div ref={lockOverscroll} className="min-h-0 flex-1 overflow-y-auto overscroll-none py-1">
        {drawings.length === 0 ? (
          <p className="px-3 py-2 text-[12px] text-content/50">No drawings in this project yet.</p>
        ) : null}
        {drawings.map((canvas) => renamingId === canvas.id ? (
          <div key={canvas.id} className="flex h-7.5 w-full items-center gap-1.5 bg-content/10 pl-3 pr-2">
            <ExcalidrawIcon className="size-3.5 shrink-0 text-content/50" />
            <input
              autoFocus
              aria-label="Rename drawing"
              value={renameDraft}
              spellCheck={false}
              onFocus={(event) => event.currentTarget.select()}
              onChange={(event) => setRenameDraft(event.target.value)}
              onBlur={() => commitRename(canvas)}
              onKeyDown={(event) => {
                if (event.nativeEvent.isComposing) return;
                if (event.key === "Enter") event.currentTarget.blur();
                if (event.key === "Escape") { event.preventDefault(); setRenamingId(null); }
              }}
              className="h-5 min-w-0 flex-1 rounded-sm bg-content/10 px-1 text-[14px] leading-none text-content outline-none ring-1 ring-accent"
            />
          </div>
        ) : (
          <button
            key={canvas.id}
            type="button"
            title={canvas.title}
            aria-current={canvas.id === activeId ? "true" : undefined}
            onClick={() => onOpen(canvas.id)}
            onDoubleClick={() => onOpenInTab(canvas.id)}
            onContextMenu={(event: ReactMouseEvent) => {
              event.preventDefault();
              setMenu({ x: event.clientX, y: event.clientY, id: canvas.id });
            }}
            className={`flex h-7.5 w-full cursor-default items-center gap-1.5 pl-3 pr-2 text-left text-[14px] leading-none ${
              canvas.id === activeId ? "bg-selection text-content" : "text-content hover:bg-content/5"
            }`}
          >
            <ExcalidrawIcon className="size-3.5 shrink-0 text-content/50" />
            <span className="min-w-0 flex-1 truncate leading-label">{canvas.title}</span>
            <span className="shrink-0 text-[11px] tabular-nums text-content/45">{formatRelativeTime(new Date(canvas.updatedAt).toISOString())}</span>
          </button>
        ))}
      </div>
      {menu ? (
        <ContextMenu x={menu.x} y={menu.y} items={MENU_ITEMS} ariaLabel="Drawing actions"
          onPick={(id) => {
            const canvas = drawings.find((entry) => entry.id === menu.id);
            setMenu(null);
            if (!canvas) return;
            if (id === "open") onOpen(canvas.id);
            else if (id === "open-tab") onOpenInTab(canvas.id);
            else if (id === "rename") { setRenameDraft(canvas.title); setRenamingId(canvas.id); }
            else if (id === "delete" && window.confirm(`Delete drawing “${canvas.title}”? This can’t be undone.`)) onDelete(canvas.id);
          }}
          onClose={() => setMenu(null)} />
      ) : null}
    </div>
  );
});

function HeaderIcon({ label, onClick, disabled, children }: { label: string; onClick: () => void; disabled?: boolean; children: ReactNode }) {
  return (
    <button type="button" title={label} aria-label={label} disabled={disabled} onMouseDown={(event) => event.preventDefault()} onClick={onClick}
      className="flex h-6 min-w-0 flex-1 items-center justify-center self-center rounded-md text-content/50 hover:bg-content/5 hover:text-content disabled:opacity-40">
      {children}
    </button>
  );
}
