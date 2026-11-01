import { Fragment, useCallback, useEffect, useId, useMemo, useState, type ReactNode } from "react";
import { ChevronDown, PenLine } from "../../../shared/ui/icons";
import { shortCommit, type RepoPlace } from "../../../platform/tauri/code";
import { publishCompareView, type ComparePartView } from "../model/compareView";
import type { ComparePart, CourseLesson } from "../model/course";
import "./CompareLesson.css";

/** How a part is framed in a comparison: its label, the mentor's note, and whether it is folded. */
export type PartChrome = {
  label: string; note?: string; index: number; id: string;
  collapsed: boolean; onToggle: () => void;
  /** The part says what it shows, for `reader show` and tests. */
  onShown: (view: Omit<ComparePartView, "label" | "collapsed">) => void;
};

type Props = {
  agentId: string; courseId: string; lesson: CourseLesson;
  renderPart: (part: ComparePart, chrome: PartChrome) => ReactNode;
};

/**
 * A comparison lesson: the same mechanism in 2–4 places, one under another
 * on one page, each with a compact header and foldable. A row at the top
 * jumps to a part.
 */
export function CompareLesson({ agentId, courseId, lesson, renderPart }: Props) {
  const parts = useMemo(() => lesson.compare ?? [], [lesson.compare]);
  const base = useId();
  const [collapsed, setCollapsed] = useState<{ lesson: string; folded: Set<number> }>({ lesson: lesson.id, folded: new Set() });
  const folded = collapsed.lesson === lesson.id ? collapsed.folded : new Set<number>();
  const [shown, setShown] = useState<{ lesson: string; parts: Map<number, Omit<ComparePartView, "label" | "collapsed">> }>({ lesson: lesson.id, parts: new Map() });
  const toggle = (index: number) => setCollapsed(() => {
    const next = new Set(folded);
    if (next.has(index)) next.delete(index); else next.add(index);
    return { lesson: lesson.id, folded: next };
  });
  const partId = (index: number) => `${base}-part-${index}`;
  const jump = (index: number) => {
    if (folded.has(index)) toggle(index);
    const target = document.getElementById(partId(index));
    target?.scrollIntoView?.({ block: "start", behavior: window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
  };
  const report = useCallback((index: number, view: Omit<ComparePartView, "label" | "collapsed">) => setShown((before) => {
    const parts = new Map(before.lesson === lesson.id ? before.parts : []);
    if (JSON.stringify(parts.get(index)) === JSON.stringify(view)) return before;
    parts.set(index, view);
    return { lesson: lesson.id, parts };
  }), [lesson.id]);
  const views = parts.map((part, index): ComparePartView => ({
    label: part.label, collapsed: folded.has(index),
    ...(shown.lesson === lesson.id ? shown.parts.get(index) : undefined) ?? (part.document ? { document: part.document, ...(part.section ? { section: part.section } : {}), ...(part.pages ? { pages: part.pages } : {}) } : { file: part.file! }),
  }));
  const viewsKey = JSON.stringify(views);
  useEffect(() => {
    publishCompareView(agentId, { courseId, lessonId: lesson.id, parts: views });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [agentId, courseId, lesson.id, viewsKey]);
  useEffect(() => () => publishCompareView(agentId, undefined, { courseId, lessonId: lesson.id }), [agentId, courseId, lesson.id]);

  return <article className="course-pane__content course-pane__reading course-compare reader-body reader-measure" key={lesson.id} data-compare-lesson={lesson.id}>
    <h2>{lesson.title}</h2>
    <nav className="course-compare__jump" aria-label="Parts of this comparison">
      <span className="course-compare__jump-label">Compare</span>
      {parts.map((part, index) => <button key={index} type="button" className="course-compare__jump-item" onClick={() => jump(index)}>{part.label}</button>)}
    </nav>
    {parts.map((part, index) => <div key={`${lesson.id}:${index}`}>{renderPart(part, {
      label: part.label, ...(part.note ? { note: part.note } : {}), index, id: partId(index),
      collapsed: folded.has(index), onToggle: () => toggle(index), onShown: (view) => report(index, view),
    })}</div>)}
  </article>;
}

/** Where a part reads, in a few words: `repo@sha · path:40–88`. */
export function partWhere(file: string, place: RepoPlace | undefined, commit: string | undefined, lines: [number, number] | undefined): { repo?: string; path: string; lines?: string } {
  let repo: string | undefined;
  let path: string;
  if (place) {
    const root = place.repoRoot.replace(/\\/g, "/").replace(/\/+$/, "");
    const inRepos = root.lastIndexOf("/repos/");
    repo = inRepos >= 0 ? root.slice(inRepos + "/repos/".length) : root.split("/").pop();
    path = place.pathInRepo;
  } else {
    const flat = file.replace(/\\/g, "/");
    const inRepos = flat.lastIndexOf("/repos/");
    path = inRepos >= 0 ? flat.slice(inRepos + "/repos/".length) : flat.split("/").pop() ?? flat;
  }
  return {
    ...(repo ? { repo: commit ? `${repo}@${shortCommit(commit)}` : repo } : commit ? { repo: `@${shortCommit(commit)}` } : {}),
    path,
    ...(lines ? { lines: lines[0] === lines[1] ? `${lines[0]}` : `${lines[0]}–${lines[1]}` } : {}),
  };
}

/** A part's compact header (label · repo@sha · path:lines, then actions), and the mentor's note under it. */
export function PartHeader({ chrome, where, title, actions, bodyId }: { chrome: PartChrome; where: { repo?: string; path: string; lines?: string; section?: string }; title?: string; actions?: ReactNode; bodyId: string }) {
  return <>
    <header className="course-compare__head">
      <button type="button" className="course-compare__toggle" aria-expanded={!chrome.collapsed} aria-controls={bodyId}
        title={chrome.collapsed ? `Show ${chrome.label}` : `Fold ${chrome.label}`} onClick={chrome.onToggle}>
        <ChevronDown aria-hidden className={`size-3.5 shrink-0 course-compare__chevron${chrome.collapsed ? " is-folded" : ""}`} />
        <span className="course-compare__label">{chrome.label}</span>
      </button>
      <span className="course-compare__where" title={title}>
        {where.repo ? <span className="course-compare__repo">{where.repo}</span> : null}
        <span className="course-compare__path">{where.path.split("/").map((piece, index) => <Fragment key={index}>{index ? <>/<wbr /></> : null}{piece}</Fragment>)}{where.lines ? <>:{where.lines}</> : null}</span>
        {where.section ? <span className="course-compare__section">§ {where.section}</span> : null}
      </span>
      {actions ? <span className="course-compare__actions">{actions}</span> : null}
    </header>
    {chrome.note && !chrome.collapsed ? <p className="course-compare__note" data-compare-note>
      <span className="course-compare__note-label"><PenLine aria-hidden className="size-3 shrink-0" />Mentor's note</span>
      <span>{chrome.note}</span>
    </p> : null}
  </>;
}
