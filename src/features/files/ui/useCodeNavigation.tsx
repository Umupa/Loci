import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent, type ReactNode, type RefObject } from "react";
import { IS_MAC } from "../../../platform/tauri/platform";
import { codeDefinition, codeReferences, codeSymbols, type CodeHit, type CodeSymbol } from "../../../platform/tauri/code";
import { Popover } from "../../../shared/ui/Popover";
import { RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { ListBullet } from "../../../shared/ui/icons";
import type { FileSelection } from "../hooks/useFileSelection";
import type { SelectionAction } from "../../learning/ui/ReadingSelectionMenu";
import "./CodeNavigation.css";

/** Files the code reader reads symbols in. */
const CODE_FILE = /\.(go|rs|c|h|ts|mts|cts|tsx|js|mjs|cjs|jsx|py|pyi)$/i;
export const navigableCode = (path: string) => CODE_FILE.test(path);

/** Where navigation goes: a file, a line in it, and the commit it is read at. */
export type CodeTarget = { file: string; line: number; commit?: string };

type Params = {
  file: string;
  /** The commit the code is read at; none for the working tree. */
  commit?: string;
  /** The `<pre>` holding the code's exact text, and the file line its first line is. */
  codeRef: RefObject<HTMLElement | null>;
  firstLine?: number;
  enabled: boolean;
  /** Opens a target in place of the page; `from` is the line navigation left. */
  onGo: (target: CodeTarget, from: number) => void;
  /** Scrolls the page to a line of its own file (for the outline). */
  onShowLine?: (line: number) => void;
};

type Found =
  | { kind: "definition"; name: string; hits: CodeHit[]; from: number; at: { x: number; y: number } }
  | { kind: "references"; name: string; hits: CodeHit[]; total: number; truncated: boolean; from: number; at: { x: number; y: number } }
  | { kind: "error"; message: string; at: { x: number; y: number } };

/** The file line and 1-based character column of a DOM position inside `root`. */
export function placeIn(root: HTMLElement, node: Node, offset: number, firstLine = 1): { line: number; column: number } | null {
  if (!root.contains(node)) return null;
  const before = document.createRange();
  before.selectNodeContents(root);
  try { before.setEnd(node, offset); } catch { return null; }
  const text = before.toString();
  const newline = text.lastIndexOf("\n");
  const lines = text.split("\n").length - 1;
  return { line: firstLine + lines, column: [...text.slice(newline + 1)].length + 1 };
}

/** The caret under a point, in WebKit and in browsers with the standard API. */
function caretAt(x: number, y: number): { node: Node; offset: number } | null {
  const doc = document as Document & { caretRangeFromPoint?: (x: number, y: number) => Range | null; caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null };
  const range = doc.caretRangeFromPoint?.(x, y);
  if (range) return { node: range.startContainer, offset: range.startOffset };
  const position = doc.caretPositionFromPoint?.(x, y);
  return position ? { node: position.offsetNode, offset: position.offset } : null;
}

const message = (cause: unknown) => cause instanceof Error ? cause.message : String(cause);
const where = (hit: CodeHit) => hit.pathInRepo ?? hit.file.split(/[\\/]/).pop() ?? hit.file;

/**
 * Go to definition (⌘-click, or Definition on a selection), find references
 * and the file's outline, for a code reader. Every result opens in place of
 * the page; several candidates or references are listed to choose from.
 */
export function useCodeNavigation({ file, commit, codeRef, firstLine = 1, enabled, onGo, onShowLine }: Params) {
  const active = enabled && navigableCode(file);
  const [found, setFound] = useState<Found | null>(null);
  const turn = useRef(0);
  useEffect(() => { turn.current += 1; setFound(null); }, [file, commit]);

  const go = useCallback((hit: CodeHit, from: number) => {
    setFound(null);
    onGo({ file: hit.file, line: hit.line, ...(commit ? { commit } : {}) }, from);
  }, [commit, onGo]);

  const search = useCallback(async (kind: "definition" | "references", place: { line: number; column: number }, at: { x: number; y: number }) => {
    const mine = ++turn.current;
    try {
      const query = { file, line: place.line, column: place.column, ...(commit ? { commit } : {}) };
      if (kind === "definition") {
        const result = await codeDefinition(query);
        if (mine !== turn.current) return;
        if (result.definitions.length === 1) { go(result.definitions[0], place.line); return; }
        setFound(result.definitions.length ? { kind, name: result.name, hits: result.definitions, from: place.line, at }
          : { kind: "error", message: `No definition of ${result.name} found in this repository.`, at });
      } else {
        const result = await codeReferences({ ...query, limit: 500 });
        if (mine !== turn.current) return;
        setFound({ kind, name: result.name, hits: result.references, total: result.total, truncated: result.truncated, from: place.line, at });
      }
    } catch (cause) {
      if (mine === turn.current) setFound({ kind: "error", message: message(cause), at });
    }
  }, [commit, file, go]);

  /** ⌘-click (Ctrl-click elsewhere) on a name goes to its definition. */
  const onClick = useCallback((event: ReactMouseEvent) => {
    if (!active || !(IS_MAC ? event.metaKey : event.ctrlKey) || event.altKey || event.shiftKey) return;
    const root = codeRef.current;
    const caret = caretAt(event.clientX, event.clientY);
    const place = root && caret ? placeIn(root, caret.node, caret.offset, firstLine) : null;
    if (!place) return;
    event.preventDefault();
    void search("definition", place, { x: event.clientX, y: event.clientY });
  }, [active, codeRef, firstLine, search]);

  const selectionActions = useMemo((): SelectionAction[] => {
    if (!active) return [];
    const at = (passage: FileSelection) => {
      const root = codeRef.current;
      const place = root ? placeIn(root, passage.range.startContainer, passage.range.startOffset, firstLine) : null;
      if (!place) throw new Error("Select a name in the code.");
      return { place, point: { x: passage.rect.left, y: passage.rect.bottom } };
    };
    return [
      { label: "Definition", title: `Go to where this is defined (${IS_MAC ? "⌘" : "Ctrl"}-click a name)`, run: (passage) => { const { place, point } = at(passage); void search("definition", place, point); } },
      { label: "References", title: "Where this name is used in the repository (matched by name)", run: (passage) => { const { place, point } = at(passage); void search("references", place, point); } },
    ];
  }, [active, codeRef, firstLine, search]);

  const results: ReactNode = found ? <Popover anchor={found.at} side="bottom" align="start" width={460} maxHeight={420} role="dialog"
    aria-label={found.kind === "error" ? "Code navigation" : found.kind === "definition" ? `Definitions of ${found.name}` : `References to ${found.name}`}
    onDismiss={() => setFound(null)} className="code-nav">
    {found.kind === "error" ? <p className="code-nav__note" role="alert">{found.message}</p> : <>
      <p className="code-nav__head">{found.kind === "definition"
        ? `${found.hits.length} definitions of ${found.name}`
        : `${found.total} uses of ${found.name}, by name${found.truncated ? ` (first ${found.hits.length})` : ""}`}</p>
      <HitList hits={found.hits} onPick={(hit) => go(hit, found.from)} grouped={found.kind === "references"} />
    </>}
  </Popover> : null;

  return { active, onClick, selectionActions, results, outline: active ? <SymbolsButton file={file} commit={commit} onShowLine={onShowLine} /> : null };
}

function HitList({ hits, onPick, grouped }: { hits: CodeHit[]; onPick: (hit: CodeHit) => void; grouped: boolean }) {
  const groups = useMemo(() => {
    const out: { path: string; hits: CodeHit[] }[] = [];
    for (const hit of hits) {
      const path = where(hit);
      const last = out[out.length - 1];
      if (grouped && last?.path === path) last.hits.push(hit);
      else out.push({ path, hits: [hit] });
    }
    return out;
  }, [hits, grouped]);
  return <ul className="code-nav__list">
    {groups.map((group, index) => <li key={`${group.path}:${index}`}>
      {grouped ? <p className="code-nav__file" title={group.path}>{group.path}</p> : null}
      {group.hits.map((hit) => <button key={`${hit.file}:${hit.line}:${hit.column}`} type="button" className="code-nav__hit" onClick={() => onPick(hit)}
        title={`${where(hit)}:${hit.line}`}>
        <span className="code-nav__where">{grouped ? hit.line : `${where(hit)}:${hit.line}`}{!grouped && hit.kind ? <em> {hit.container ? `${hit.container}.` : ""}{hit.kind}</em> : null}</span>
        <code className="code-nav__preview">{hit.preview}</code>
      </button>)}
    </li>)}
  </ul>;
}

/** The reader header's Symbols button and the file's outline. */
function SymbolsButton({ file, commit, onShowLine }: { file: string; commit?: string; onShowLine?: (line: number) => void }) {
  const button = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [filter, setFilter] = useState("");
  const [symbols, setSymbols] = useState<{ key: string; list?: CodeSymbol[]; error?: string }>();
  const key = `${file}\u0000${commit ?? ""}`;
  useEffect(() => {
    if (!open) return;
    let live = true;
    void codeSymbols(file, commit).then((found) => { if (live) setSymbols({ key, list: found.symbols }); },
      (cause: unknown) => { if (live) setSymbols({ key, error: message(cause) }); });
    return () => { live = false; };
  }, [open, file, commit, key]);
  const loaded = symbols?.key === key ? symbols : undefined;
  const shown = (loaded?.list ?? []).filter((symbol) => !filter || symbol.name.toLowerCase().includes(filter.toLowerCase()));
  return <>
    <button ref={button} type="button" data-tauri-drag-region="false" className={RESOURCE_ACTION} aria-label="Symbols" title="Symbols in this file"
      aria-haspopup="dialog" aria-expanded={open} onClick={() => setOpen((value) => !value)}><ListBullet className="size-4" /></button>
    {open ? <Popover anchor={button} side="bottom" align="end" width={320} maxHeight={460} role="dialog" aria-label="Symbols" className="code-nav"
      onDismiss={() => { setOpen(false); setFilter(""); }}>
      <input className="code-nav__filter" autoFocus placeholder="Filter symbols" aria-label="Filter symbols" value={filter} onChange={(event) => setFilter(event.target.value)}
        onKeyDown={(event) => { if (event.key === "Enter" && shown[0]) { onShowLine?.(shown[0].line); setOpen(false); setFilter(""); } }} />
      {!loaded ? <p className="code-nav__note">Reading symbols…</p>
        : loaded.error ? <p className="code-nav__note" role="alert">{loaded.error}</p>
        : !shown.length ? <p className="code-nav__note">{filter ? "No symbol matches." : "No symbols found."}</p>
        : <ul className="code-nav__list" role="list">{shown.map((symbol) => <li key={`${symbol.name}:${symbol.line}:${symbol.column}`}>
          <button type="button" className="code-nav__symbol" style={{ paddingLeft: 8 + (filter ? 0 : symbol.depth) * 12 }}
            onClick={() => { onShowLine?.(symbol.line); setOpen(false); setFilter(""); }} title={`${symbol.kind} · line ${symbol.line}`}>
            <span>{symbol.name}</span><em>{symbol.kind}</em><span className="code-nav__line">{symbol.line}</span>
          </button>
        </li>)}</ul>}
    </Popover> : null}
  </>;
}
