import { t, useLocale, getLocale } from "../../shared/i18n/locale";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Archive, Pin, PinOff, RotateCcw, Search, X } from "../../shared/ui/icons";
import { Modal } from "../../shared/ui/Modal";
import { MatchText } from "../../shared/ui/MatchText";
import { fuzzyMatch } from "../../shared/lib/fuzzy";
import { useLockOverscroll } from "../../shared/hooks/useLockOverscroll";
import { IS_MAC } from "../../platform/tauri/platform";
import { sameProjectPath } from "../../features/projects/model/recents";
import type { ClosedTab } from "../../features/workspace/model/closedTabs";
import { shortAge, tabStatusLabel, type Tab } from "../../features/workspace/model/tabSummary";
import { buildSwitcher, flattenSwitcher, initialSelection, type SwitcherRow } from "../../features/workspace/model/tabSwitcher";
import { STATUS_TEXT, TabGlyph } from "./TabParts";

type Props = {
  tabs: readonly Tab[];
  activeId: string;
  projectPath: string;
  recent: readonly string[];
  closed: readonly ClosedTab[];
  onActivate: (id: string) => void;
  onCloseTab: (id: string) => void;
  onPin: (id: string, pinned: boolean) => void;
  onReopen: (batch: number) => void;
  /** Leave for the overview, where many tabs can be seen and tidied at once. */
  onOpenOverview?: () => void;
  onDismiss: () => void;
};

const COMMAND_KEY = IS_MAC ? "⌘" : "Ctrl";

/**
 * Every open tab in one searchable list: what needs you first, then this
 * project, then the rest, with what was closed last at the bottom. Typing
 * filters, arrows move, Enter goes. It is the way to reach a tab that the
 * strip has folded into an icon.
 */
export function TabSwitcher({ tabs, activeId, projectPath, recent, closed, onActivate, onCloseTab, onPin, onReopen, onOpenOverview, onDismiss }: Props) {
  useLocale();
  const [query, setQuery] = useState("");
  const [now] = useState(() => Date.now());
  const sections = useMemo(
    () => buildSwitcher({ tabs, activeId, projectPath, recent, closed, query }),
    [getLocale(), tabs, activeId, projectPath, recent, closed, query],
  );
  const rows = useMemo(() => flattenSwitcher(sections), [getLocale(), sections]);
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const selectedIndex = Math.max(0, rows.findIndex((row) => row.key === selectedKey));
  const selected = rows[selectedKey ? selectedIndex : initialSelection(rows)];
  const listRef = useRef<HTMLDivElement | null>(null);
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const pointer = useRef({ x: NaN, y: NaN });

  useEffect(() => {
    listRef.current?.querySelector("[aria-selected='true']")?.scrollIntoView({ block: "nearest" });
  }, [selected?.key]);

  const move = (delta: number) => {
    if (rows.length === 0) return;
    const from = selected ? rows.indexOf(selected) : 0;
    setSelectedKey(rows[(from + delta + rows.length) % rows.length].key);
  };

  const open = (row: SwitcherRow | undefined) => {
    if (!row) return;
    onDismiss();
    if (row.kind === "tab") onActivate(row.tab.id);
    else onReopen(row.closed.batch);
  };

  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.nativeEvent.isComposing) return;
    const mod = event.metaKey || event.ctrlKey;
    if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) {
      event.preventDefault();
      move(1);
    } else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) {
      event.preventDefault();
      move(-1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      open(selected);
    } else if (mod && event.key === "Backspace" && selected?.kind === "tab") {
      event.preventDefault();
      // Closing keeps the list open, and the highlight on the next row.
      const next = rows[rows.indexOf(selected) + 1] ?? rows[rows.indexOf(selected) - 1];
      setSelectedKey(next?.key ?? null);
      onCloseTab(selected.tab.id);
    } else if (event.key === "Tab") {
      event.preventDefault();
      move(event.shiftKey ? -1 : 1);
    }
  };

  const tabCount = tabs.length;
  return (
    <Modal title={t("Switch tabs")} onClose={onDismiss} size="md" minimalHeader>
      <div className="flex max-h-[min(540px,72vh)] flex-col" onKeyDown={onKeyDown} data-tab-switcher-panel>
        <div className="flex shrink-0 items-center gap-2.5 border-b border-stroke py-3 pl-4 pr-12">
          <Search className="size-4 shrink-0 text-content/40" strokeWidth={1.75} />
          <input
            autoFocus
            value={query}
            onChange={(event) => { setQuery(event.target.value); setSelectedKey(null); }}
            placeholder={t("Switch to a tab…")}
            aria-label={t("Search open tabs")}
            spellCheck={false}
            autoComplete="off"
            className="min-w-0 flex-1 bg-transparent text-[15px] leading-6 text-content outline-none placeholder:text-content/35"
          />
        </div>
        <div
          ref={(el) => { listRef.current = el; lockOverscroll(el); }}
          role="listbox"
          aria-label={t("Open tabs")}
          onPointerMove={(event) => { pointer.current = { x: event.clientX, y: event.clientY }; }}
          className="min-h-0 flex-1 overflow-y-auto overscroll-none px-1.5 pb-1.5"
        >
          {rows.length === 0 ? (
            <p className="px-3 py-8 text-center text-[13px] text-content/45">{t("No tab matches “{0}”", query.trim())}</p>
          ) : null}
          {sections.map((section) => (
            <section key={section.id} aria-label={section.label}>
              <h3 className="flex items-center gap-1.5 px-2.5 pb-1 pt-3 text-[11px] font-medium tracking-wide text-content/40">
                {section.id === "attention" ? <span aria-hidden className="size-1.5 rounded-full bg-amber-400" /> : null}
                {section.label}
                <span className="font-normal tabular-nums text-content/30">{section.rows.length}</span>
              </h3>
              {section.rows.map((row) => (
                <SwitcherRowView
                  key={row.key}
                  row={row}
                  query={query.trim()}
                  now={now}
                  selected={row.key === selected?.key}
                  showProject={row.kind === "tab" && !!row.tab.projectPath && !sameProjectPath(row.tab.projectPath, projectPath)}
                  onHover={() => setSelectedKey(row.key)}
                  onOpen={() => open(row)}
                  onClose={row.kind === "tab" ? () => onCloseTab(row.tab.id) : undefined}
                  onPin={row.kind === "tab" ? () => onPin(row.tab.id, !row.tab.pinned) : undefined}
                />
              ))}
            </section>
          ))}
        </div>
        <footer className="flex h-9 shrink-0 items-center gap-3.5 border-t border-stroke px-4 text-[11px] text-content/45">
          <Hint keys={["↑", "↓"]} label={t("Move")} />
          <Hint keys={["↵"]} label={t("Open")} />
          <Hint keys={[COMMAND_KEY, "⌫"]} label={t("Close tab")} />
          <span className="flex-1" />
          {onOpenOverview ? (
            <button type="button" onClick={onOpenOverview} className="flex items-center gap-1.5 rounded-md px-1.5 py-0.5 text-content/55 hover:bg-content/8 hover:text-content">
              {t("Overview")}<kbd className="rounded border border-content/12 bg-content/6 px-1 font-sans text-[10px] leading-4 text-content/60">{COMMAND_KEY}⇧O</kbd>
            </button>
          ) : null}
          <span className="tabular-nums">{t("{0} open", tabCount)}</span>
        </footer>
      </div>
    </Modal>
  );
}

function SwitcherRowView({ row, query, now, selected, showProject, onHover, onOpen, onClose, onPin }: {
  row: SwitcherRow;
  query: string;
  now: number;
  selected: boolean;
  showProject: boolean;
  onHover: () => void;
  onOpen: () => void;
  onClose?: () => void;
  onPin?: () => void;
}) {
  useLocale();
  if (row.kind === "closed") {
    const { closed } = row;
    const title = closed.title || t("New session");
    return (
      <div role="option" aria-selected={selected} onMouseMove={onHover} onClick={onOpen}
        className={`flex h-12 cursor-default items-center gap-3 rounded-lg px-2.5 ${selected ? "bg-selection" : ""}`}>
        <span className="grid size-4 shrink-0 place-items-center text-content/45">
          {closed.parked ? <Archive className="size-3.5" strokeWidth={1.75} /> : <RotateCcw className="size-3.5" strokeWidth={1.75} />}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] leading-snug text-content/80">{title}</p>
          <p className="truncate text-[11.5px] leading-snug text-content/40">
            {closed.project}{row.alsoClosed ? (closed.parked ? t(" · and {0} more parked with it", row.alsoClosed) : t(" · and {0} more closed with it", row.alsoClosed)) : ""}
          </p>
        </div>
        <span className="shrink-0 text-[11px] text-content/40">{t("{0} {1} ago", closed.parked ? t("Parked") : t("Closed"), shortAge(now - closed.closedAt))}</span>
        <span className={`shrink-0 rounded-md px-1.5 py-0.5 text-[11px] ${selected ? "bg-content/10 text-content" : "text-content/45"}`}>{closed.parked ? t("Restore") : t("Reopen")}</span>
      </div>
    );
  }
  const { tab } = row;
  const title = tab.title || t("New session");
  const hit = query ? fuzzyMatch(query, title) : null;
  const label = tabStatusLabel(tab, now);
  const loud = tab.status === "approval" || tab.status === "done" || tab.status === "busy";
  return (
    <div role="option" aria-selected={selected} data-switcher-tab={tab.id} onMouseMove={onHover} onClick={onOpen}
      style={row.depth ? { marginLeft: Math.min(row.depth, 3) * 20 } : undefined}
      className={`group flex h-12 cursor-default items-center gap-3 rounded-lg px-2.5 ${selected ? "bg-selection" : ""}`}>
      {row.depth ? <span aria-hidden data-family-indent className="-mr-1.5 text-[13px] leading-none text-content/30">↳</span> : null}
      <TabGlyph tab={tab} size="md" />
      <div className="min-w-0 flex-1">
        <p className="flex min-w-0 items-center gap-1.5">
          <span className="min-w-0 truncate text-[13px] leading-snug text-content">
            <MatchText text={title} positions={hit?.positions ?? []} active={!!hit} />
          </span>
          {row.current ? <Chip>{t("Current")}</Chip> : null}
          {tab.pinned ? <Pin className="size-3 shrink-0 text-content/35" strokeWidth={1.75} /> : null}
        </p>
        <p className="truncate text-[11.5px] leading-snug text-content/45">{tab.blank ? "Empty: nothing said yet" : tab.preview || label}</p>
      </div>
      {showProject ? <span className="max-w-28 shrink-0 truncate text-[11px] text-content/40">{tab.project}</span> : null}
      {loud ? <span className={`shrink-0 text-[11px] ${STATUS_TEXT[tab.status ?? "idle"]} ${selected ? "hidden" : "group-hover:hidden"}`}>{tab.status === "busy" ? t("Working") : tab.status === "approval" ? t("Needs you") : t("Finished")}</span> : null}
      <span className={`shrink-0 items-center gap-0.5 ${selected ? "flex" : "hidden group-hover:flex"}`}>
        {onPin ? (
          <RowButton label={tab.pinned ? t("Unpin tab") : t("Pin tab")} onClick={onPin}>
            {tab.pinned ? <PinOff className="size-3.5" strokeWidth={1.75} /> : <Pin className="size-3.5" strokeWidth={1.75} />}
          </RowButton>
        ) : null}
        {onClose ? <RowButton label={t("Close tab")} onClick={onClose}><X className="size-3.5" strokeWidth={1.75} /></RowButton> : null}
      </span>
    </div>
  );
}

function Chip({ children }: { children: ReactNode }) {
  useLocale();
  return <span className="shrink-0 rounded bg-content/10 px-1 py-px text-[10px] leading-4 text-content/60">{children}</span>;
}

function RowButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  useLocale();
  return (
    <button type="button" title={label} aria-label={label} onMouseDown={(event) => event.preventDefault()}
      onClick={(event) => { event.stopPropagation(); onClick(); }}
      className="grid size-6 place-items-center rounded-md text-content/50 hover:bg-content/12 hover:text-content">
      {children}
    </button>
  );
}

function Hint({ keys, label }: { keys: string[]; label: string }) {
  useLocale();
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

