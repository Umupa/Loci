import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Archive, Check, Pin, PinOff, Search, X } from "../../shared/ui/icons";
import { Modal } from "../../shared/ui/Modal";
import { useFlip } from "../../shared/hooks/useFlip";
import { useLockOverscroll } from "../../shared/hooks/useLockOverscroll";
import { boxOf, flyGhost, motionAllowed } from "../../shared/lib/ghostFly";
import { IS_MAC } from "../../platform/tauri/platform";
import { sameProjectPath } from "../../features/projects/model/recents";
import { tabStatusLabel, type Tab } from "../../features/workspace/model/tabSummary";
import { defaultScope, moveInGrid, overviewCards, type OverviewCard, type OverviewScope } from "../../features/workspace/model/tabOverview";
import { STATUS_TEXT, TabGlyph } from "./TabParts";

type Props = {
  tabs: readonly Tab[];
  activeId: string;
  projectPath: string;
  recent: readonly string[];
  onActivate: (id: string) => void;
  onCloseTabs: (ids: string[]) => void;
  onParkTabs: (ids: string[]) => void;
  onPinTabs: (ids: string[], pinned: boolean) => void;
  onDismiss: () => void;
};

const CARD_MIN_WIDTH = 248;
const GRID_GAP = 12;
const COMMAND_KEY = IS_MAC ? "⌘" : "Ctrl";
/** How long a card takes to leave before its tab is closed. */
const EXIT_MS = 150;

const ACCENT_BAR: Record<string, string> = {
  approval: "bg-amber-400",
  busy: "bg-accent",
  done: "bg-teal-400",
};

/**
 * Every open tab as a card, to see at a glance what each agent is doing and to
 * tidy many at once: select with the checkbox, space, or a modified click,
 * then pin, put away, or close them together. Built for the moment there are
 * more tabs than a strip can say anything useful about.
 */
export function TabOverview({ tabs, activeId, projectPath, recent, onActivate, onCloseTabs, onParkTabs, onPinTabs, onDismiss }: Props) {
  const [query, setQuery] = useState("");
  const [scope, setScope] = useState<OverviewScope>(() => defaultScope(tabs, projectPath));
  const [selected, setSelected] = useState<ReadonlySet<string>>(() => new Set());
  const [cursorId, setCursorId] = useState<string | null>(null);
  const [columns, setColumns] = useState(3);
  const [now] = useState(() => Date.now());
  const [leaving, setLeaving] = useState<ReadonlySet<string>>(() => new Set());
  const gridRef = useRef<HTMLDivElement | null>(null);
  const cancelEntrance = useRef<(() => void) | null>(null);
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();

  const cards = useMemo(() => overviewCards({ tabs, scope, projectPath, query, recent }), [tabs, scope, projectPath, query, recent]);
  const first = cards.find((card) => card.tab.id !== activeId) ?? cards[0];
  const cursorIndex = Math.max(0, cards.findIndex((card) => card.tab.id === (cursorId ?? first?.tab.id)));
  const cursor = cards[cursorIndex];

  // Cards that change place (a tab closed, a search, a wider window) glide there.
  const cardKey = cards.map((card) => card.tab.id).join("\0");
  const cardRevision = `${cardKey}|${columns}`;
  useFlip(gridRef, cardRevision);
  const entranceState = useRef({ query, scope, cardKey });

  useLayoutEffect(() => {
    const before = entranceState.current;
    if (before.query !== query || before.scope !== scope || before.cardKey !== cardKey) cancelEntrance.current?.();
    entranceState.current = { query, scope, cardKey };
  }, [query, scope, cardKey]);

  // On opening, every card flies out of its tab in the strip into its place,
  // each a moment after the one before: the tabs spread out into the overview.
  useLayoutEffect(() => {
    const grid = gridRef.current;
    if (!grid || !motionAllowed()) return;
    const strip = document.querySelector("[data-title-tab-strip]");
    const stripBox = strip ? boxOf(strip) : { left: window.innerWidth / 2, top: 0, width: 0, height: 40 };
    const tabElements = [...document.querySelectorAll<HTMLElement>("[data-title-tab-id]")];
    const onScreen = [...grid.querySelectorAll<HTMLElement>("[data-overview-tab]")].filter((el) => {
      const box = el.getBoundingClientRect();
      return box.bottom > 0 && box.top < window.innerHeight;
    });
    const animations: Animation[] = [];
    let cancelled = false;
    onScreen.forEach((el, index) => {
      const tabElement = tabElements.find((tab) => tab.dataset.titleTabId === el.dataset.overviewTab);
      // A tab that is folded away or in another project leaves from the middle of the strip.
      const from = tabElement ? boxOf(tabElement) : { left: stripBox.left + stripBox.width / 2 - 20, top: stripBox.top + 5, width: 40, height: 30 };
      const base = boxOf(el);
      el.style.visibility = "hidden";
      const animation = flyGhost({
        source: el, base, from, to: base,
        duration: 520, delay: Math.min(index * 24, 280), fadeIn: true,
        onDone: () => { if (!cancelled) el.style.visibility = ""; },
      });
      if (animation) animations.push(animation);
    });
    const cancel = () => {
      if (cancelled) return;
      cancelled = true;
      for (const animation of animations) animation.cancel();
      for (const element of onScreen) element.style.visibility = "";
    };
    cancelEntrance.current = cancel;
    return cancel;
  }, []);

  useEffect(() => {
    const grid = gridRef.current;
    if (!grid) return;
    let measuredWidth = grid.clientWidth;
    const measure = () => {
      const width = grid.clientWidth;
      // Initial column measurement is bookkeeping; only a real resize
      // invalidates the geometry the opening flight was given.
      if (width !== measuredWidth) cancelEntrance.current?.();
      measuredWidth = width;
      setColumns(Math.max(1, Math.floor((width + GRID_GAP) / (CARD_MIN_WIDTH + GRID_GAP))));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(grid);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    gridRef.current?.querySelector("[data-cursor='true']")?.scrollIntoView({ block: "nearest" });
  }, [cursor?.tab.id]);

  // Tabs closed from here drop out of the selection with them.
  useEffect(() => {
    setSelected((current) => {
      const live = new Set(tabs.map((tab) => tab.id));
      const kept = [...current].filter((id) => live.has(id));
      return kept.length === current.size ? current : new Set(kept);
    });
  }, [tabs]);

  const toggle = (id: string) => setSelected((current) => {
    const next = new Set(current);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    return next;
  });
  const open = (card: OverviewCard | undefined) => {
    if (!card) return;
    // The card grows into the window it opens, fading out as that window takes over.
    const element = [...(gridRef.current?.querySelectorAll<HTMLElement>("[data-overview-tab]") ?? [])].find((el) => el.dataset.overviewTab === card.tab.id);
    const stage = document.querySelector("main");
    if (element && stage) {
      const base = boxOf(element);
      flyGhost({ source: element, base, from: base, to: boxOf(stage), duration: 380, fadeOut: true });
    }
    onDismiss();
    onActivate(card.tab.id);
  };
  /** Let the cards go before their tabs do, so the rest can close up around the gap. */
  const closeAfterExit = (ids: string[], run: (ids: string[]) => void) => {
    if (!motionAllowed()) {
      run(ids);
      return;
    }
    setLeaving(new Set(ids));
    window.setTimeout(() => {
      run(ids);
      setLeaving(new Set());
    }, EXIT_MS);
  };
  const chosen = [...selected];
  const act = (run: (ids: string[]) => void, closes = false) => {
    setSelected(new Set());
    if (closes) closeAfterExit(chosen, run);
    else run(chosen);
  };
  const allPinned = chosen.length > 0 && chosen.every((id) => tabs.find((tab) => tab.id === id)?.pinned);

  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.nativeEvent.isComposing) return;
    const typing = query.length > 0;
    if (event.key === "ArrowUp" || event.key === "ArrowDown" || (!typing && (event.key === "ArrowLeft" || event.key === "ArrowRight"))) {
      event.preventDefault();
      const next = cards[moveInGrid(cursorIndex, event.key, columns, cards.length)];
      if (next) setCursorId(next.tab.id);
    } else if (event.key === "Enter") {
      event.preventDefault();
      open(cursor);
    } else if (event.key === " " && !typing && cursor) {
      event.preventDefault();
      toggle(cursor.tab.id);
    } else if ((event.metaKey || event.ctrlKey) && event.key === "Backspace") {
      event.preventDefault();
      const ids = selected.size ? [...selected] : cursor ? [cursor.tab.id] : [];
      if (ids.length) closeAfterExit(ids, onCloseTabs);
      setSelected(new Set());
    }
  };

  const needYou = tabs.filter((tab) => tab.status === "approval" || tab.status === "done").length;
  const working = tabs.filter((tab) => tab.status === "busy").length;
  return (
    <Modal title="Tab overview" onClose={onDismiss} size="lg" minimalHeader>
      <div className="flex h-[min(700px,84vh)] flex-col" onKeyDown={onKeyDown} data-tab-overview>
        <div className="flex shrink-0 items-center gap-3 border-b border-stroke py-3 pl-4 pr-12">
          <Search className="size-4 shrink-0 text-content/40" strokeWidth={1.75} />
          <input
            autoFocus
            value={query}
            onChange={(event) => { setQuery(event.target.value); setCursorId(null); }}
            placeholder="Find among tabs…"
            aria-label="Search tabs"
            spellCheck={false}
            autoComplete="off"
            className="min-w-0 flex-1 bg-transparent text-[15px] leading-6 text-content outline-none placeholder:text-content/35"
          />
          <div role="tablist" aria-label="Scope" className="flex shrink-0 rounded-md border border-content/10 bg-content/8 p-0.5">
            {([["project", "This project"], ["all", "All projects"]] as const).map(([id, label]) => (
              <button key={id} type="button" role="tab" aria-selected={scope === id} onClick={() => setScope(id)}
                className={`rounded px-2 py-0.5 text-[11px] ${scope === id ? "bg-selection-strong text-content" : "text-content/50 hover:text-content/80"}`}>{label}</button>
            ))}
          </div>
        </div>
        <p className="shrink-0 px-4 pb-1 pt-2.5 text-[11px] text-content/40">
          {cards.length} {cards.length === 1 ? "tab" : "tabs"}
          {!query && needYou ? <span className="text-amber-400"> · {needYou} need you</span> : null}
          {!query && working ? <span className="text-accent"> · {working} working</span> : null}
        </p>
        <div ref={lockOverscroll} className="min-h-0 flex-1 overflow-y-auto overscroll-none px-4 pb-4 pt-1">
          {cards.length === 0 ? (
            <p className="py-16 text-center text-[13px] text-content/45">{query ? `No tab matches “${query.trim()}”` : "No tabs open here"}</p>
          ) : null}
          <div ref={gridRef} role="listbox" aria-label="Open tabs" aria-multiselectable className="grid gap-3" style={{ gridTemplateColumns: `repeat(auto-fill, minmax(${CARD_MIN_WIDTH}px, 1fr))` }}>
            {cards.map((card) => (
              <CardView
                key={card.tab.id}
                card={card}
                now={now}
                current={card.tab.id === activeId}
                cursor={card.tab.id === cursor?.tab.id}
                selected={selected.has(card.tab.id)}
                selecting={selected.size > 0}
                leaving={leaving.has(card.tab.id)}
                showProject={scope === "all" || (!!card.tab.projectPath && !sameProjectPath(card.tab.projectPath, projectPath))}
                onHover={() => setCursorId(card.tab.id)}
                onOpen={(event) => (event.metaKey || event.ctrlKey || event.shiftKey ? toggle(card.tab.id) : open(card))}
                onToggle={() => toggle(card.tab.id)}
                onPin={() => onPinTabs([card.tab.id], !card.tab.pinned)}
                onClose={() => closeAfterExit([card.tab.id], onCloseTabs)}
              />
            ))}
          </div>
        </div>
        {chosen.length > 0 ? (
          <footer className="flex h-12 shrink-0 items-center gap-2 border-t border-stroke px-4 text-[12px]" data-bulk-bar>
            <span className="mr-2 font-medium text-content">{chosen.length} selected</span>
            <BulkButton onClick={() => act((ids) => onPinTabs(ids, !allPinned))}>{allPinned ? <PinOff className="size-3.5" strokeWidth={1.75} /> : <Pin className="size-3.5" strokeWidth={1.75} />}{allPinned ? "Unpin" : "Pin"}</BulkButton>
            <BulkButton onClick={() => act(onParkTabs, true)}><Archive className="size-3.5" strokeWidth={1.75} />Park</BulkButton>
            <BulkButton onClick={() => act(onCloseTabs, true)} danger><X className="size-3.5" strokeWidth={1.75} />Close</BulkButton>
            <span className="flex-1" />
            <button type="button" onClick={() => setSelected(new Set())} className="rounded-md px-2 py-1 text-content/55 hover:bg-content/8 hover:text-content">Clear</button>
          </footer>
        ) : (
          <footer className="flex h-9 shrink-0 items-center gap-4 border-t border-stroke px-4 text-[11px] text-content/45">
            <Hint keys={["↑", "↓", "←", "→"]} label="Move" />
            <Hint keys={["↵"]} label="Open" />
            <Hint keys={["Space"]} label="Select" />
            <Hint keys={[COMMAND_KEY, "⌫"]} label="Close" />
            <span className="flex-1" />
            <span>{COMMAND_KEY}-click to select several</span>
          </footer>
        )}
      </div>
    </Modal>
  );
}

function CardView({ card, now, current, cursor, selected, selecting, leaving, showProject, onHover, onOpen, onToggle, onPin, onClose }: {
  card: OverviewCard;
  now: number;
  current: boolean;
  cursor: boolean;
  selected: boolean;
  selecting: boolean;
  /** Going away: fades and shrinks while the tab is still closing. */
  leaving: boolean;
  showProject: boolean;
  onHover: () => void;
  onOpen: (event: React.MouseEvent) => void;
  onToggle: () => void;
  onPin: () => void;
  onClose: () => void;
}) {
  const { tab, depth } = card;
  const status = tab.status ?? "idle";
  const label = tabStatusLabel(tab, now);
  return (
    <div
      role="option"
      aria-selected={selected}
      data-overview-tab={tab.id}
      data-cursor={cursor}
      data-selected={selected}
      data-flip-key={tab.id}
      onMouseMove={onHover}
      onClick={onOpen}
      className={`overview-card group relative flex h-[148px] cursor-default flex-col overflow-hidden rounded-xl border p-3 ${
        leaving ? "pointer-events-none scale-90 opacity-0" : ""} ${
        selected ? "border-accent/60 bg-accent/10" : cursor ? "border-content/20 bg-selection" : "border-content/10 bg-content/[0.03]"}`}
    >
      {ACCENT_BAR[status] ? <span aria-hidden className={`absolute inset-y-3 left-0 w-0.5 rounded-full ${ACCENT_BAR[status]}`} /> : null}
      <div className="flex items-start gap-2">
        <span className="relative mt-0.5 grid size-4 shrink-0 place-items-center">
          <span className={selecting || selected ? "invisible" : "group-hover:invisible"}><TabGlyph tab={tab} size="md" /></span>
          <button type="button" role="checkbox" aria-checked={selected} aria-label={selected ? "Deselect tab" : "Select tab"}
            onClick={(event) => { event.stopPropagation(); onToggle(); }}
            className={`absolute inset-0 grid place-items-center rounded border ${selected ? "border-accent bg-accent text-white" : "border-content/30 bg-background-base/60 text-transparent hover:border-content/60"} ${selecting || selected ? "" : "invisible group-hover:visible"}`}>
            <Check className="size-3" strokeWidth={2.5} />
          </button>
        </span>
        <p className="line-clamp-2 min-w-0 flex-1 text-[13px] font-medium leading-snug text-content">
          {depth > 0 ? <span aria-hidden className="mr-1 text-content/30">↳</span> : null}
          {tab.title || "New session"}
        </p>
        <span className="flex shrink-0 items-center gap-0.5">
          {tab.pinned ? <Pin className="size-3 text-content/40 group-hover:hidden" strokeWidth={1.75} /> : null}
          <span className="hidden items-center gap-0.5 group-hover:flex">
            <CardAction label={tab.pinned ? "Unpin tab" : "Pin tab"} onClick={onPin}>{tab.pinned ? <PinOff className="size-3.5" strokeWidth={1.75} /> : <Pin className="size-3.5" strokeWidth={1.75} />}</CardAction>
            <CardAction label="Close tab" onClick={onClose}><X className="size-3.5" strokeWidth={1.75} /></CardAction>
          </span>
        </span>
      </div>
      <p className="mt-2 line-clamp-3 min-h-0 flex-1 text-[12px] leading-[1.5] text-content/55">
        {tab.blank ? "Empty: nothing said yet" : tab.preview || " "}
      </p>
      <div className="mt-2 flex items-center gap-2 text-[11px]">
        <span className={`min-w-0 truncate ${STATUS_TEXT[status]}`}>{label}</span>
        <span className="flex-1" />
        {tab.descendantCount ? <span className="shrink-0 rounded-full bg-content/10 px-1.5 py-px text-[10px] tabular-nums text-content/60" title="Tabs started from this one">↳ {tab.descendantCount}</span> : null}
        {current ? <span className="shrink-0 rounded bg-content/10 px-1 py-px text-[10px] text-content/60">Current</span> : null}
        {showProject ? <span className="max-w-24 shrink-0 truncate text-content/40">{tab.project}</span> : null}
      </div>
    </div>
  );
}

function CardAction({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button type="button" title={label} aria-label={label} onClick={(event) => { event.stopPropagation(); onClick(); }}
      className="grid size-6 place-items-center rounded-md text-content/50 hover:bg-content/12 hover:text-content">{children}</button>
  );
}

function BulkButton({ onClick, danger, children }: { onClick: () => void; danger?: boolean; children: ReactNode }) {
  return (
    <button type="button" onClick={onClick}
      className={`flex h-7 items-center gap-1.5 rounded-md bg-content/10 px-2.5 hover:bg-content/15 ${danger ? "text-red-400" : "text-content"}`}>{children}</button>
  );
}

function Hint({ keys, label }: { keys: string[]; label: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className="flex items-center gap-0.5">
        {keys.map((key) => (
          <kbd key={key} className="min-w-4 rounded border border-content/12 bg-content/6 px-1 text-center font-sans text-[10px] leading-4 text-content/60">{key}</kbd>
        ))}
      </span>
      {label}
    </span>
  );
}
