import { Fragment, type ReactNode } from "react";
import type { MentorPage } from "../model/mentorPage";
import { listKeyDown } from "./listKeys";

export type LibraryEntry = {
  kind: "document" | "note" | "canvas" | "course";
  id: string;
  icon: ReactNode;
  title: string;
  subtitle: string;
  target: MentorPage;
  /** A heading the row is listed under; rows of one group are kept together, in the order given. */
  group?: string;
};

/** Whether an entry matches a filter: every word appears in its title or subtitle. */
export function matchesFilter(entry: Pick<LibraryEntry, "title" | "subtitle">, query: string): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const text = `${entry.title}\n${entry.subtitle}`.toLowerCase();
  return words.every((word) => text.includes(word));
}

type Props = {
  entries: LibraryEntry[] | undefined;
  query: string;
  isCurrent: (target: MentorPage) => boolean;
  onOpen: (page: MentorPage) => void;
  /** One line said when there is nothing yet. */
  empty: string;
  /** What this list holds, as a load failure names it. */
  subject: string;
  /** Why this list could not be read, if it could not. */
  error?: string;
  onRetry?: () => void;
  /** A row saved by the turn that is running now. */
  isNew?: (entry: LibraryEntry) => boolean;
};

/** A list that failed to load, said in the panel that wanted it. */
export function LibraryLoadError({ subject, onRetry }: { subject: string; onRetry?: () => void }) {
  return <div role="alert" className="mentor-library-error">
    <p>Couldn't load {subject}.</p>
    {onRetry ? <button type="button" onClick={onRetry}>Retry</button> : null}
  </div>;
}

/** One kind of thing the mentor keeps, filtered; ↑/↓ move between rows. */
export function LibraryList({ entries, query, isCurrent, onOpen, empty, subject, error, onRetry, isNew }: Props) {
  if (entries === undefined && error) return <LibraryLoadError subject={subject} onRetry={onRetry} />;
  if (entries === undefined) return <p role="status" className="mentor-library-empty">Loading…</p>;
  if (!entries.length) return <>
    {error ? <LibraryLoadError subject={subject} onRetry={onRetry} /> : null}
    <p className="mentor-library-empty">{empty}</p>
  </>;
  const shown = query.trim() ? entries.filter((entry) => matchesFilter(entry, query)) : entries;
  if (!shown.length) return <p className="mentor-library-empty">Nothing matches “{query.trim()}”.</p>;
  return <div className="mentor-library-body" onKeyDown={listKeyDown}>
    {error ? <LibraryLoadError subject={subject} onRetry={onRetry} /> : null}
    {shown.map((entry, at) => <Fragment key={`${entry.kind}:${entry.id}`}>
      {entry.group && entry.group !== shown[at - 1]?.group ? <p className="mentor-library-group" data-library-group={entry.group}>{entry.group}</p> : null}
      <button type="button" className="mentor-library-row" data-library-item
      data-resource-kind={entry.kind} data-resource-id={entry.id} data-library-new={isNew?.(entry) || undefined}
      aria-label={`${entry.kind}: ${entry.title}${isNew?.(entry) ? " (new)" : ""}`}
      aria-current={isCurrent(entry.target) || undefined} title={entry.subtitle ? `${entry.title}\n${entry.subtitle}` : entry.title}
      onClick={() => onOpen(entry.target)}>
      <span aria-hidden className="mentor-library-icon">{entry.icon}</span>
      <span className="mentor-library-copy"><span className="mentor-library-title"><span className="mentor-library-title-text">{entry.title}</span>{isNew?.(entry) ? <span className="mentor-library-new">New</span> : null}</span>{entry.subtitle ? <span className="mentor-library-subtitle">{entry.subtitle}</span> : null}</span>
    </button></Fragment>)}
  </div>;
}
