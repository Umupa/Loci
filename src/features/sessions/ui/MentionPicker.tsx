import { Fragment, useEffect, useRef, type MouseEvent as ReactMouseEvent, type Ref } from "react";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { translate, useLocale } from "../../../shared/i18n/locale";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { Bookmark, Compass, File, Highlighter, Mortarboard, StickyNote } from "../../../shared/ui/icons";
import { MatchText } from "../../../shared/ui/MatchText";
import type { MentionCandidate, MentionGroup, MentionGroupId, MentionKind } from "../model/mentionSources";

/** Group headings; the translations are in zh-CN.json. */
export const MENTION_GROUP_NAMES: Record<MentionGroupId, string> = {
  recent: "Recently opened",
  course: "Courses",
  lesson: "Lessons",
  source: "Sources",
  guide: "Guides",
  note: "Notes",
  highlight: "Highlights",
  file: "Files",
};

const KIND_ICONS = { course: Mortarboard, lesson: Bookmark, source: File, guide: Compass, note: StickyNote, highlight: Highlighter } as const;

/** The icon a mention of this kind is drawn with, in the picker and in the composer's text. */
export function MentionIcon({ kind, name, isDir, size }: { kind: MentionKind; name: string; isDir?: boolean; size: number }) {
  if (kind === "file") return <FileTypeIcon name={name} isDir={Boolean(isDir)} size={size} />;
  const Icon = KIND_ICONS[kind];
  return <Icon className={size >= 13 ? "size-3.5" : "size-3"} />;
}

type Props = {
  groups: MentionGroup[];
  query: string;
  active: number;
  loading?: boolean;
  onActive: (index: number) => void;
  onPick: (item: MentionCandidate) => void;
};

export function MentionPicker({ groups, query, active, loading, onActive, onPick }: Props) {
  const locale = useLocale();
  const t = (source: string) => translate(locale, source);
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const activeRef = useRef<HTMLButtonElement>(null);
  const pointer = useRef({ x: Number.NaN, y: Number.NaN, allow: false });
  const fromPointer = useRef(false);

  useEffect(() => {
    pointer.current.allow = false;
  }, [groups]);

  useEffect(() => {
    if (fromPointer.current) {
      fromPointer.current = false;
      return;
    }
    pointer.current.allow = false;
    activeRef.current?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const onListMouseMove = (e: ReactMouseEvent<HTMLDivElement>) => {
    if (e.clientX === pointer.current.x && e.clientY === pointer.current.y) return;
    pointer.current = { x: e.clientX, y: e.clientY, allow: true };
  };

  const onRowEnter = (index: number) => {
    if (!pointer.current.allow) return;
    fromPointer.current = true;
    onActive(index);
  };

  const searching = Boolean(query.trim());
  let index = -1;
  return (
    <div
      data-mention-picker
      className="overflow-hidden rounded-lg border border-content/10 bg-content/5 backdrop-blur-xl"
    >
      {groups.length === 0 ? (
        <p className="px-3 py-2.5 text-[12px] text-content/50">
          {loading ? t("Loading…") : searching ? t("No matches") : t("Nothing to mention yet")}
        </p>
      ) : (
        <div
          ref={lockOverscroll}
          role="listbox"
          aria-label={t("Mention")}
          onMouseMove={onListMouseMove}
          className="max-h-[min(320px,45vh)] overflow-y-auto overscroll-none px-1 py-1"
        >
          {groups.map((group) => (
            <Fragment key={group.id}>
              <div role="presentation" className="px-2 pb-0.5 pt-1.5 text-[11px] text-content/40 first:pt-0.5">
                {t(MENTION_GROUP_NAMES[group.id])}
              </div>
              {group.items.map((item) => {
                index += 1;
                const row = index;
                return (
                  <MentionRow
                    key={`${group.id}:${item.path}`}
                    item={item}
                    searching={searching}
                    highlighted={row === active}
                    rowRef={row === active ? activeRef : undefined}
                    onEnter={() => onRowEnter(row)}
                    onPick={() => onPick(item)}
                  />
                );
              })}
            </Fragment>
          ))}
        </div>
      )}
    </div>
  );
}

function MentionRow({ item, searching, highlighted, rowRef, onEnter, onPick }: {
  item: MentionCandidate;
  searching: boolean;
  highlighted: boolean;
  rowRef?: Ref<HTMLButtonElement>;
  onEnter: () => void;
  onPick: () => void;
}) {
  // A file's match positions index its whole relative path; split them between its name and folder.
  const file = item.kind === "file";
  const slash = file ? item.relative.lastIndexOf("/") : -1;
  const where = file ? (slash === -1 ? "" : item.relative.slice(0, slash)) : item.where ?? "";
  const nameOffset = slash + 1;
  const namePositions = file
    ? item.positions.filter((pos) => pos >= nameOffset).map((pos) => pos - nameOffset)
    : item.positions;
  return (
    <button
      ref={rowRef}
      type="button"
      role="option"
      aria-selected={highlighted}
      onMouseDown={(e) => e.preventDefault()}
      onMouseEnter={onEnter}
      onClick={onPick}
      className={`flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-[13px] leading-none ${
        highlighted ? "bg-selection text-content" : "text-content"
      }`}
    >
      <span className="shrink-0 text-content/60">
        <MentionIcon kind={item.kind} name={item.name} isDir={item.isDir} size={15} />
      </span>
      <span className={`min-w-0 flex-1 truncate ${highlighted ? "text-mention" : ""}`}>
        <MatchText text={item.name} positions={namePositions} active={searching} />
        {item.isDir ? "/" : null}
      </span>
      {where ? (
        <span className={`min-w-0 max-w-[45%] truncate text-[11px] text-content/40 ${file ? "font-mono" : ""}`}>
          {file ? (
            <MatchText text={where} positions={item.positions.filter((pos) => pos < slash)} active={searching} />
          ) : where}
        </span>
      ) : null}
    </button>
  );
}
