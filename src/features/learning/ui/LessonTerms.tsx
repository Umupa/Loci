import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { courseItems, loadCourse, openCourse } from "../model/course";
import { GLOSSARY_CHANGED_EVENT, loadGlossary, type GlossaryTerm } from "../model/glossary";
import { rangeAt, textIndex } from "../model/textAnchor";
import "./LessonTerms.css";

const HIGHLIGHT = "loci-term";

/** A mentor's glossary, read again when it changes. */
function useGlossary(agentId: string): GlossaryTerm[] {
  const [terms, setTerms] = useState<{ agentId: string; terms: GlossaryTerm[] }>({ agentId: "", terms: [] });
  useEffect(() => {
    let live = true;
    const load = () => void loadGlossary(agentId).then((list) => { if (live) setTerms({ agentId, terms: Array.isArray(list) ? list : [] }); }, () => undefined);
    load();
    const changed = (event: Event) => { if ((event as CustomEvent<{ agentId: string }>).detail?.agentId === agentId) load(); };
    window.addEventListener(GLOSSARY_CHANGED_EVENT, changed);
    return () => { live = false; window.removeEventListener(GLOSSARY_CHANGED_EVENT, changed); };
  }, [agentId]);
  return terms.agentId === agentId ? terms.terms : [];
}

const LATIN = /[A-Za-z0-9]/;
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Where a term is first used in `text`: as a whole word when it is written in
 * Latin letters (any case), anywhere when it is not. Its aliases count too.
 */
export function firstUse(text: string, term: Pick<GlossaryTerm, "term" | "aliases">): [number, number] | null {
  let best: [number, number] | null = null;
  for (const form of [term.term, ...(term.aliases ?? [])].map((value) => value.trim()).filter(Boolean)) {
    const pattern = LATIN.test(form)
      ? new RegExp(`(?<![A-Za-z0-9_])${escape(form)}(?![A-Za-z0-9_])`, "i")
      : new RegExp(escape(form));
    const match = pattern.exec(text);
    if (match && (!best || match.index < best[0])) best = [match.index, match.index + match[0].length];
  }
  return best;
}

type Found = { term: GlossaryTerm; range: Range };

/** The point under the pointer, as a node and offset. */
function caretAt(x: number, y: number): { node: Node; offset: number } | null {
  const doc = document as Document & { caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null };
  if (doc.caretPositionFromPoint) {
    const position = doc.caretPositionFromPoint(x, y);
    return position ? { node: position.offsetNode, offset: position.offset } : null;
  }
  const range = document.caretRangeFromPoint?.(x, y);
  return range ? { node: range.startContainer, offset: range.startOffset } : null;
}

function termAt(found: readonly Found[], x: number, y: number): Found | undefined {
  const caret = caretAt(x, y);
  if (!caret) return undefined;
  return found.find(({ range }) => {
    try {
      if (!range.isPointInRange(caret.node, caret.offset)) return false;
    } catch { return false; }
    return [...range.getClientRects()].some((rect) => x >= rect.left - 1 && x <= rect.right + 1 && y >= rect.top - 1 && y <= rect.bottom + 1);
  });
}

/**
 * The glossary in a lesson's text: each term's first use is underlined
 * (a terms the lesson itself teaches is not), hovering shows its definition
 * and where it is taught, and a click opens that lesson. The text is never
 * rewritten; the underline is a highlight painted over it.
 */
export function LessonTerms({ article, agentId, courseId, lessonId, text: body }: { article: HTMLElement | null; agentId: string; courseId: string; lessonId: string; /** The lesson's Markdown, so a revision is looked through again. */ text: string }) {
  const glossary = useGlossary(agentId);
  const found = useRef<Found[]>([]);
  const [shown, setShown] = useState<{ term: GlossaryTerm; rect: DOMRect; taught?: string } | null>(null);

  useEffect(() => {
    const text = article?.querySelector<HTMLElement>("[data-reading-text]");
    found.current = [];
    if (!text || !glossary.length) return;
    const index = textIndex(text);
    for (const term of glossary) {
      if (term.course === courseId && term.lesson === lessonId) continue;
      const at = firstUse(index.text, term);
      const range = at ? rangeAt(index, at[0], at[1]) : null;
      // Code is quoted as it is; a term in it is the code's word.
      if (!range || (range.startContainer.parentElement?.closest("pre, code, a"))) continue;
      found.current.push({ term, range });
    }
    const highlights = typeof CSS !== "undefined" ? (CSS as unknown as { highlights?: Map<string, unknown> }).highlights : undefined;
    const Highlight = (globalThis as { Highlight?: new (...ranges: Range[]) => unknown }).Highlight;
    const mine = highlights && Highlight && found.current.length ? new Highlight(...found.current.map((entry) => entry.range)) : undefined;
    if (mine) highlights!.set(HIGHLIGHT, mine);
    text.dataset.terms = String(found.current.length);
    // Another lesson's terms may have taken the name since: only ours is taken away.
    return () => { if (mine && highlights?.get(HIGHLIGHT) === mine) highlights.delete(HIGHLIGHT); delete text.dataset.terms; };
  }, [article, glossary, courseId, lessonId, body]);

  useEffect(() => {
    if (!article) return;
    let last: GlossaryTerm | undefined;
    const move = (event: PointerEvent) => {
      const hit = found.current.length ? termAt(found.current, event.clientX, event.clientY) : undefined;
      if (hit?.term === last) return;
      last = hit?.term;
      if (!hit) { setShown(null); return; }
      const rect = hit.range.getBoundingClientRect();
      setShown({ term: hit.term, rect });
      const { course, lesson } = hit.term;
      if (course && lesson) void loadCourse(course, agentId).then((loaded) => {
        const title = loaded ? courseItems(loaded.data).find((item) => item.id === lesson)?.title : undefined;
        if (title) setShown((current) => current?.term === hit.term ? { ...current, taught: title } : current);
      }, () => undefined);
    };
    const leave = () => { last = undefined; setShown(null); };
    const click = (event: MouseEvent) => {
      if (window.getSelection()?.toString()) return;
      const hit = found.current.length ? termAt(found.current, event.clientX, event.clientY) : undefined;
      if (!hit?.term.course || !hit.term.lesson) return;
      event.preventDefault();
      openCourse({ courseId: hit.term.course, agentId, title: hit.term.course, itemId: hit.term.lesson, openRequest: Date.now() });
    };
    article.addEventListener("pointermove", move);
    article.addEventListener("pointerleave", leave);
    article.addEventListener("click", click);
    return () => { article.removeEventListener("pointermove", move); article.removeEventListener("pointerleave", leave); article.removeEventListener("click", click); };
  }, [article, agentId]);

  if (!shown) return null;
  const top = shown.rect.bottom + 8;
  const left = Math.max(8, Math.min(shown.rect.left, window.innerWidth - 268));
  return createPortal(<div className="lesson-term-tip" role="tooltip" data-term-tip style={{ top, left }}>
    <b>{shown.term.term}</b> {shown.term.definition}
    {shown.taught ? <span className="lesson-term-tip__where">{shown.taught}</span> : null}
  </div>, document.body);
}
