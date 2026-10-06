import { useMemo, useState } from "react";
import type { Canvas } from "../canvas";
import { LoaderCircle, ExcalidrawIcon, Plus, Search } from "../../../shared/ui/icons";
import { OverlayNav } from "../../../app/shell/TitleBar";
import { WindowControls } from "../../../app/shell/WindowControls";
import { IS_MAC } from "../../../platform/tauri/platform";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { projectName } from "../../../shared/lib/paths";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { CanvasPane } from "./CanvasPane";
import { looksLikeProject, sameProjectPath } from "../../projects/model/recents";

const MIN_WIDTH = 240;
const MAX_WIDTH = 420;
const DEFAULT_WIDTH = 280;
let rememberedWidth = DEFAULT_WIDTH;
let rememberedCanvasId: string | null = null;

type Props = {
  canvases: Canvas[];
  cwd?: string;
  besideRail: boolean;
  compactRail: boolean;
  onClose: () => void;
  onToggleSidebar: () => void;
  onOpenCanvas: (id: string) => void;
  onNewCanvas: () => Promise<Canvas | undefined>;
  onTitleChange: (id: string, title: string) => void;
  onAddToChat: (text: string) => void;
  onRegisterAppend: (canvasId: string, fn: ((text: string) => void) | null) => void;
};

export function CanvasesView({ canvases, cwd, besideRail, compactRail, onClose, onToggleSidebar, onOpenCanvas, onNewCanvas, onTitleChange, onAddToChat, onRegisterAppend }: Props) {
  const [query, setQuery] = useState("");
  const projectCwd = cwd && looksLikeProject(cwd) ? cwd : undefined;
  const [selectedId, setSelectedId] = useState(() => rememberedCanvasId ?? canvases[0]?.id ?? null);
  const [creating, setCreating] = useState(false);
  const listLock = useLockOverscroll<HTMLDivElement>();
  const resize = useDragResize({ min: MIN_WIDTH, max: () => Math.min(MAX_WIDTH, Math.round(window.innerWidth * 0.5)), defaultWidth: DEFAULT_WIDTH, initial: rememberedWidth, onCommit: (width) => { rememberedWidth = width; } });
  const drawings = useMemo(() => canvases.filter((canvas) =>
    (!projectCwd || !!canvas.cwd && sameProjectPath(canvas.cwd, projectCwd)) &&
    `${canvas.title} ${canvas.cwd ?? ""}`.toLowerCase().includes(query.trim().toLowerCase())
  ).sort((a, b) => b.updatedAt - a.updatedAt), [canvases, query, projectCwd]);
  const selected = drawings.find((canvas) => canvas.id === selectedId) ?? drawings[0];
  const select = (id: string) => { rememberedCanvasId = id; setSelectedId(id); };
  const create = async () => {
    setCreating(true);
    try {
      const canvas = await onNewCanvas();
      if (canvas) { setQuery(""); select(canvas.id); }
    } finally { setCreating(false); }
  };

  return <section className="flex min-h-0 min-w-0 flex-1 flex-col text-content" aria-label="Excalidraw">
    <div className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
      {IS_MAC && compactRail ? <div className="w-4 shrink-0" /> : null}
      {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
      {besideRail ? null : <OverlayNav onBack={onClose} onToggleSidebar={onToggleSidebar} />}
      <div className="flex min-w-0 flex-1 items-center gap-2 px-3 text-[13px]"><ExcalidrawIcon className="size-3.5 shrink-0 text-content/45" />Excalidraw</div>
      {IS_MAC ? null : <WindowControls />}
    </div>
    <div className="flex min-h-0 min-w-0 flex-1">
      <aside ref={resize.setPaneRef} aria-label="Drawings" className="relative flex h-full min-h-0 shrink-0 flex-col border-r border-stroke">
        <div className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
          <div className="relative flex h-7 min-w-0 flex-1 items-center">
            <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
            <input aria-label="Filter drawings" placeholder="Filter drawings" value={query} onChange={(event) => setQuery(event.target.value)} spellCheck={false} autoComplete="off" className="h-7 w-full rounded-md bg-transparent pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/40" />
          </div>
          <button type="button" aria-label="New drawing" title="New drawing" disabled={creating} onClick={() => void create()} className="grid size-6 shrink-0 place-items-center rounded-md text-content/45 hover:bg-content/10 hover:text-content disabled:opacity-40">
            {creating ? <LoaderCircle className="size-3.5 animate-spin" /> : <Plus className="size-3.5" />}
          </button>
        </div>
        <div ref={listLock} className="min-h-0 flex-1 overflow-y-auto overscroll-none">
          {drawings.length ? <ul className="flex flex-col gap-0.5 p-1.5">
            {drawings.map((canvas) => <li key={canvas.id}><button type="button" aria-current={canvas.id === selected?.id ? "true" : undefined} title={canvas.title} onClick={() => select(canvas.id)} className={`flex w-full flex-col rounded-md border border-transparent px-2.5 py-2 text-left ${canvas.id === selected?.id ? "bg-selection text-content" : "text-content/80 hover:bg-content/5 hover:text-content"}`}>
              <span className="flex w-full items-center gap-2"><span className="min-w-0 flex-1 truncate text-[11px] text-content/50">{canvas.cwd ? projectName(canvas.cwd) : "No project"}</span><span className="shrink-0 text-[11px] tabular-nums text-content/45">{formatRelativeTime(new Date(canvas.updatedAt).toISOString())}</span></span>
              <span className="mt-1 flex w-full min-w-0 items-center gap-1.5 text-[13px] font-semibold leading-snug"><ExcalidrawIcon className="size-3 shrink-0 text-content/40" /><span className="truncate">{canvas.title}</span></span>
            </button></li>)}
          </ul> : <p className="px-3 py-2 text-[12px] text-content/50">{query ? "No matching drawings" : "No drawings yet. Create one to start sketching."}</p>}
        </div>
        <div role="separator" aria-orientation="vertical" aria-label="Resize drawings list" className={`absolute inset-y-0 -right-px z-10 w-1.5 cursor-col-resize touch-none ${resize.dragging ? "bg-content/15" : "hover:bg-content/10"}`} onPointerDown={resize.onPointerDown} onDoubleClick={resize.onDoubleClick} />
      </aside>
      <div className="min-h-0 min-w-0 flex-1">
        {selected ? <CanvasPane key={selected.id} canvas={selected} focused onFocus={() => {}} onTitleChange={onTitleChange} onAddToChat={onAddToChat} onRegisterAppend={onRegisterAppend} onOpenInWorkspace={() => onOpenCanvas(selected.id)} />
          : <div className="grid h-full place-items-center text-sm text-content/40">Create a drawing to start sketching</div>}
      </div>
    </div>
  </section>;
}
