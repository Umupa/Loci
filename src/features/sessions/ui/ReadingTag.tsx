import { useEffect, useState, useSyncExternalStore } from "react";
import {
  agentReading,
  agentReadingPlace,
  agentReadingVersion,
  readingSkipped,
  readingTag,
  skipReadingOnce,
  subscribeAgentReading,
  type ReadingTag as Tag,
} from "../../agents/model/agentReading";
import { listAgentDocuments } from "../../agents/model/agentDocuments";
import { loadNotes } from "../../notes";
import { translate, useLocale, type Locale } from "../../../shared/i18n/locale";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { Bookmark, File, Mortarboard, RotateCcw, StickyNote, X } from "../../../shared/ui/icons";

/** Re-renders whenever the mentor's page, place or dismissal changes. */
export function useAgentReadingVersion(): number {
  return useSyncExternalStore(subscribeAgentReading, agentReadingVersion, agentReadingVersion);
}

/** "Firecracker · p. 3 · 2 lines selected", in the interface's language. */
export function readingTagText(tag: Tag, locale: Locale): { title: string; where: string[] } {
  const t = (source: string, ...values: (string | number)[]) => translate(locale, source, ...values);
  const where: string[] = [];
  if (tag.page) where.push(t("p. {0}", tag.page));
  else if (tag.lines) where.push(tag.lines[0] === tag.lines[1] ? `L${tag.lines[0]}` : `L${tag.lines[0]}–${tag.lines[1]}`);
  if (tag.selected) where.push(tag.selected === 1 ? t("1 line selected") : t("{0} lines selected", tag.selected));
  return { title: tag.parent ? `${tag.parent} › ${tag.title}` : tag.title, where };
}

/**
 * The title of a page the reading itself does not name: a note (only its id
 * is known) or a PDF source (opened as its file). Nothing until it is found.
 */
function useReadingTitle(agentId: string, key: string | undefined): string | undefined {
  const [found, setFound] = useState<{ key: string; title: string }>();
  useEffect(() => {
    if (!key) return;
    let live = true;
    const lookup = key.startsWith("note:")
      ? loadNotes().then((notes) => notes.find((note) => `note:${note.id}` === key)?.title)
      : /\.pdf$/i.test(key)
        ? listAgentDocuments(agentId).then((documents) => documents.find((document) => `file:${document.pdf?.path}` === key)?.title)
        : Promise.resolve(undefined);
    void lookup.then((title) => { if (live && title) setFound({ key, title }); }, () => undefined);
    return () => { live = false; };
  }, [agentId, key]);
  return found && found.key === key ? found.title : undefined;
}

function TagIcon({ tag }: { tag: Tag }) {
  if (tag.kind === "file") return <FileTypeIcon name={tag.title} isDir={false} size={12} />;
  const Icon = tag.kind === "course" ? (tag.parent ? Bookmark : Mortarboard) : tag.kind === "note" ? StickyNote : File;
  return <Icon className="size-3" />;
}

/**
 * What the mentor is told is open beside the chat, so the user can see it
 * and, for one message, leave it out. Nothing is shown when nothing is open.
 */
export function ReadingTag({ agentId }: { agentId: string }) {
  useAgentReadingVersion();
  const locale = useLocale();
  const t = (source: string) => translate(locale, source);
  const current = agentReading(agentId);
  const titled = useReadingTitle(agentId, current?.kind === "note" ? `note:${current.id}` : current?.kind === "file" ? `file:${current.path}` : undefined);
  if (!current) return null;
  const skipped = readingSkipped(agentId);
  const tag = readingTag(current, agentReadingPlace(agentId), titled);
  // A PDF source opens as its file; it is known by its title, not the file's name.
  const shown: Tag = current.kind === "file" && titled ? { ...tag, kind: "document", title: titled } : tag;
  const { title, where } = readingTagText(shown, locale);
  const label = [title, ...where].join(" · ");
  return (
    <div data-reading-tag={skipped ? "skipped" : ""} className="flex min-w-0 px-3 pt-2">
      <span
        title={skipped ? t("Not sent with this message") : t("Sent with each message so the mentor knows what you are reading")}
        className={`inline-flex h-5 min-w-0 max-w-full items-center gap-1 rounded border border-content/10 pl-1.5 text-[11px] leading-none ${
          skipped ? "text-content/35" : "text-content/60"
        }`}
      >
        <span className="shrink-0"><TagIcon tag={shown} /></span>
        <span className={`min-w-0 truncate ${skipped ? "line-through" : ""}`}>
          <span className="sr-only">{t("Reading")}: </span>
          {label}
        </span>
        <button
          type="button"
          aria-label={skipped ? t("Send with this message") : t("Leave out of this message")}
          title={skipped ? t("Send with this message") : t("Leave out of this message")}
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => skipReadingOnce(agentId, !skipped)}
          className="grid h-5 w-5 shrink-0 place-items-center rounded-r text-content/40 hover:text-content/80"
        >
          {skipped ? <RotateCcw className="size-3" /> : <X className="size-3" />}
        </button>
      </span>
    </div>
  );
}
