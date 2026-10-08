import { t, useLocale, getLocale } from "../../../shared/i18n/locale";
import { useEffect, useMemo, useState, type MouseEvent as ReactMouseEvent } from "react";
import type { Canvas } from "../canvas";
import { canvasMcpProblem } from "../mcpServer";
import { useCanvasMcpEnabled } from "../../settings/model/builtinMcp";
import { LoaderCircle, ExcalidrawIcon, Plus, Search, ListFilter } from "../../../shared/ui/icons";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { OverlayNav } from "../../../app/shell/TitleBar";
import { CollapsiblePane, SecondarySidebarToggle, useSecondarySidebar } from "../../../app/shell/SecondarySidebar";
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

type TimeFilter = "all" | "today" | "7d" | "30d";

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
  onDeleteCanvas: (id: string) => void;
  onAddToChat: (text: string) => void;
};

export function CanvasesView({ canvases, cwd, besideRail, compactRail, onClose, onToggleSidebar, onOpenCanvas, onNewCanvas, onTitleChange, onDeleteCanvas, onAddToChat }: Props) {
  useLocale();
  const [query, setQuery] = useState("");
  const projectCwd = cwd && looksLikeProject(cwd) ? cwd : undefined;
  const [selectedId, setSelectedId] = useState(() => rememberedCanvasId ?? canvases[0]?.id ?? null);
  const [creating, setCreating] = useState(false);
  const [listOpen, toggleList] = useSecondarySidebar("canvases");
  const [canvasMenu, setCanvasMenu] = useState<{ x: number; y: number; id: string } | null>(null);
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [timeFilter, setTimeFilter] = useState<TimeFilter>("all");
  const [filterAnchor, setFilterAnchor] = useState<HTMLButtonElement | null>(null);
  // Agents draw through a built-in MCP server that needs a JavaScript runtime.
  const [agentProblem, setAgentProblem] = useState<string | null>(null);
  const canvasMcpEnabled = useCanvasMcpEnabled();
  useEffect(() => {
    let current = true;
    void canvasMcpProblem().then((problem) => { if (current) setAgentProblem(problem); });
    return () => { current = false; };
  }, [canvasMcpEnabled]);
  const listLock = useLockOverscroll<HTMLDivElement>();
  const resize = useDragResize({ min: MIN_WIDTH, max: () => Math.min(MAX_WIDTH, Math.round(window.innerWidth * 0.5)), defaultWidth: DEFAULT_WIDTH, initial: rememberedWidth, onCommit: (width) => { rememberedWidth = width; } });

  const drawings = useMemo(() => {
    const now = Date.now();
    const since = timeFilter === "today" ? new Date(now).setHours(0, 0, 0, 0)
      : timeFilter === "7d" ? now - 604800000
      : timeFilter === "30d" ? now - 2592000000
      : 0;
    return canvases.filter((canvas) =>
      (!projectCwd || !!canvas.cwd && sameProjectPath(canvas.cwd, projectCwd)) &&
      `${canvas.title} ${canvas.cwd ?? ""}`.toLowerCase().includes(query.trim().toLowerCase()) &&
      (since === 0 || canvas.updatedAt >= since)
    ).sort((a, b) => b.updatedAt - a.updatedAt);
  }, [getLocale(), canvases, query, projectCwd, timeFilter]);

  const selected = drawings.find((canvas) => canvas.id === selectedId) ?? drawings[0];
  const select = (id: string) => { rememberedCanvasId = id; setSelectedId(id); };

  const create = async () => {
    setCreating(true);
    try {
      const canvas = await onNewCanvas();
      if (canvas) { setQuery(""); select(canvas.id); }
    } finally { setCreating(false); }
  };

  const commitRename = (id: string) => {
    const title = renameDraft.trim() || t("Untitled drawing");
    if (title !== (canvases.find((c) => c.id === id)?.title ?? "")) onTitleChange(id, title);
    setRenamingId(null);
  };

  const canvasMenuItems: ContextMenuItem[] = [
    { kind: "item", id: "rename", label: t("Rename") },
    { kind: "sep" },
    { kind: "item", id: "delete", label: t("Delete"), danger: true },
  ];

  const filterItems: ContextMenuItem[] = [
    { kind: "item", id: "all", label: t("All time"), checked: timeFilter === "all" },
    { kind: "item", id: "today", label: t("Today"), checked: timeFilter === "today" },
    { kind: "item", id: "7d", label: t("Last 7 days"), checked: timeFilter === "7d" },
    { kind: "item", id: "30d", label: t("Last 30 days"), checked: timeFilter === "30d" },
  ];

  return <section className="flex min-h-0 min-w-0 flex-1 flex-col text-content" aria-label="Excalidraw">
    <div className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
      {IS_MAC && compactRail ? <div className="w-4 shrink-0" /> : null}
      {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
      {besideRail ? null : <OverlayNav onBack={onClose} onToggleSidebar={onToggleSidebar} />}
      <div className="flex shrink-0 items-center px-1.5"><SecondarySidebarToggle open={listOpen} onToggle={toggleList} name="drawings list" /></div>
      <div className="flex min-w-0 flex-1 items-center gap-2 pr-3 text-[13px]"><ExcalidrawIcon className="size-3.5 shrink-0 text-content/45" />Excalidraw</div>
      {IS_MAC ? null : <WindowControls />}
    </div>
    <div className="flex min-h-0 min-w-0 flex-1">
      <CollapsiblePane open={listOpen}>
        <aside ref={resize.setPaneRef} aria-label={t("Drawings")} className="relative flex h-full min-h-0 shrink-0 flex-col border-r border-stroke">
          <div className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
            <div className="relative flex h-7 min-w-0 flex-1 items-center">
              <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
              <input aria-label={t("Filter drawings")} placeholder={t("Filter drawings")} value={query} onChange={(event) => setQuery(event.target.value)} spellCheck={false} autoComplete="off" className="h-7 w-full rounded-md bg-transparent pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/40" />
            </div>
            <button type="button" aria-label={t("Filter by time")} title={t("Filter drawings")} onClick={(e: ReactMouseEvent<HTMLButtonElement>) => setFilterAnchor(e.currentTarget)} className={`grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content ${timeFilter !== "all" ? "text-accent" : "text-content/45"}`}>
              <ListFilter className="size-3.5" />
            </button>
            <button type="button" aria-label={t("New drawing")} title={t("New drawing")} disabled={creating} onClick={() => void create()} className="grid size-6 shrink-0 place-items-center rounded-md text-content/45 hover:bg-content/10 hover:text-content disabled:opacity-40">
              {creating ? <LoaderCircle className="size-3.5 animate-spin" /> : <Plus className="size-3.5" />}
            </button>
          </div>
          {agentProblem ? <p role="status" className={`shrink-0 border-b border-stroke px-3 py-2 text-[11px] leading-snug ${canvasMcpEnabled ? "text-amber-400" : "text-content/55"}`}>{canvasMcpEnabled ? t("Agents cannot draw yet. ") : ""}{agentProblem}</p> : null}
          <div ref={listLock} className="min-h-0 flex-1 overflow-y-auto overscroll-none">
            {drawings.length ? <ul className="flex flex-col gap-0.5 p-1.5">
              {drawings.map((canvas) => <li key={canvas.id}>
                {renamingId === canvas.id ? (
                  <div className={`flex w-full flex-col rounded-md border px-2.5 py-2 ${canvas.id === selected?.id ? "border-transparent bg-selection" : "border-stroke"}`}>
                    <span className="flex w-full items-center gap-2">
                      <span className="min-w-0 flex-1 truncate text-[11px] text-content/50">{canvas.cwd ? projectName(canvas.cwd) : t("No project")}</span>
                    </span>
                    <span className="mt-1 flex w-full min-w-0 items-center gap-1.5">
                      <ExcalidrawIcon className="size-3 shrink-0 text-content/40" />
                      <input
                        autoFocus
                        aria-label={t("Rename drawing")}
                        value={renameDraft}
                        onChange={(e) => setRenameDraft(e.target.value)}
                        onBlur={() => commitRename(canvas.id)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") e.currentTarget.blur();
                          if (e.key === "Escape") { e.preventDefault(); setRenamingId(null); }
                        }}
                        className="min-w-0 flex-1 bg-transparent text-[13px] font-semibold text-content outline-none"
                      />
                    </span>
                  </div>
                ) : (
                  <button
                    type="button"
                    aria-current={canvas.id === selected?.id ? "true" : undefined}
                    title={canvas.title}
                    onClick={() => select(canvas.id)}
                    onContextMenu={(e: ReactMouseEvent<HTMLButtonElement>) => {
                      e.preventDefault();
                      select(canvas.id);
                      setCanvasMenu({ x: e.clientX, y: e.clientY, id: canvas.id });
                    }}
                    className={`flex w-full flex-col rounded-md border border-transparent px-2.5 py-2 text-left ${canvas.id === selected?.id ? "bg-selection text-content" : "text-content/80 hover:bg-content/5 hover:text-content"}`}
                  >
                    <span className="flex w-full items-center gap-2"><span className="min-w-0 flex-1 truncate text-[11px] text-content/50">{canvas.cwd ? projectName(canvas.cwd) : t("No project")}</span><span className="shrink-0 text-[11px] tabular-nums text-content/45">{formatRelativeTime(new Date(canvas.updatedAt).toISOString())}</span></span>
                    <span className="mt-1 flex w-full min-w-0 items-center gap-1.5 text-[13px] font-semibold leading-snug"><ExcalidrawIcon className="size-3 shrink-0 text-content/40" /><span className="truncate">{canvas.title}</span></span>
                  </button>
                )}
              </li>)}
            </ul> : <p className="px-3 py-2 text-[12px] text-content/50">{query || timeFilter !== "all" ? t("No matching drawings") : t("No drawings yet. Create one to start sketching.")}</p>}
          </div>
          <div role="separator" aria-orientation="vertical" aria-label={t("Resize drawings list")} className={`absolute inset-y-0 -right-px z-10 w-1.5 cursor-col-resize touch-none ${resize.dragging ? "bg-content/15" : "hover:bg-content/10"}`} onPointerDown={resize.onPointerDown} onDoubleClick={resize.onDoubleClick} />
        </aside>
      </CollapsiblePane>
      <div className="min-h-0 min-w-0 flex-1">
        {selected ? <CanvasPane key={selected.id} canvas={selected} focused onFocus={() => {}} onTitleChange={onTitleChange} onAddToChat={onAddToChat} onOpenInWorkspace={() => onOpenCanvas(selected.id)} />
          : <div className="grid h-full place-items-center text-sm text-content/40">{t("Create a drawing to start sketching")}</div>}
      </div>
    </div>
    {canvasMenu ? <ContextMenu x={canvasMenu.x} y={canvasMenu.y} items={canvasMenuItems} onPick={(id) => {
      if (id === "rename") {
        const canvas = canvases.find((c) => c.id === canvasMenu.id);
        if (canvas) { setRenamingId(canvas.id); setRenameDraft(canvas.title); }
      } else if (id === "delete") {
        onDeleteCanvas(canvasMenu.id);
        if (selectedId === canvasMenu.id) {
          const next = drawings.find((c) => c.id !== canvasMenu.id);
          if (next) select(next.id);
        }
      }
      setCanvasMenu(null);
    }} onClose={() => setCanvasMenu(null)} /> : null}
    {filterAnchor ? <ContextMenu anchor={filterAnchor} items={filterItems} onPick={(id) => {
      setTimeFilter(id as TimeFilter);
      setFilterAnchor(null);
    }} onClose={() => setFilterAnchor(null)} /> : null}
  </section>;
}
