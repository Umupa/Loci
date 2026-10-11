import { useEffect, useId, useRef, useState, type RefObject } from "react";

type Heading = { element: HTMLElement; title: string; level: number };
const HEADING_INSET = 24;

/** The outline follows rendered headings, including asynchronously loaded library documents. */
export function CourseToc({ scrollRef }: { scrollRef: RefObject<HTMLElement | null> }) {
  const [headings, setHeadings] = useState<Heading[]>([]);
  const [active, setActive] = useState<HTMLElement | null>(null);
  const [expanded, setExpanded] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLElement>(null);
  const listRef = useRef<HTMLOListElement>(null);
  const pendingFocus = useRef<"rail" | "contents" | null>(null);
  const panelId = useId();

  useEffect(() => {
    const scroll = scrollRef.current;
    if (!scroll) return;
    let entries: Heading[] = [];
    let article: HTMLElement | null = null;
    let frame = 0;
    const updateActive = () => {
      frame = 0;
      if (scroll.clientHeight === 0) return;
      const top = scroll.getBoundingClientRect().top + HEADING_INSET + 1;
      let current = entries[0]?.element ?? null;
      for (const entry of entries) {
        if (entry.element.getBoundingClientRect().top > top) break;
        current = entry.element;
      }
      if (scroll.scrollHeight > scroll.clientHeight && scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 2) {
        current = entries[entries.length - 1]?.element ?? null;
      }
      setActive(current);
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(updateActive); };
    const resize = new ResizeObserver(schedule);
    const collect = () => {
      const nextArticle = scroll.querySelector<HTMLElement>(".course-pane__reading");
      if (article !== nextArticle) {
        if (article) resize.unobserve(article);
        article = nextArticle;
        if (article) resize.observe(article);
      }
      const next = [...scroll.querySelectorAll<HTMLElement>(".course-pane__reading .agent-markdown :is(h1, h2, h3, h4, h5, h6)")]
        .filter((element) => !element.closest("[data-footnotes]"))
        .map((element) => ({ element, title: element.textContent?.replace(/\s+/g, " ").trim() ?? "", level: Number(element.tagName[1]) }))
        .filter((entry) => entry.title);
      if (next.length !== entries.length || next.some((entry, index) => entry.element !== entries[index].element || entry.title !== entries[index].title || entry.level !== entries[index].level)) {
        entries = next;
        setHeadings(next);
        if (!next.length) { pendingFocus.current = null; setExpanded(false); }
      }
      schedule();
    };
    const mutation = new MutationObserver(collect);
    mutation.observe(scroll, { childList: true, subtree: true, characterData: true });
    resize.observe(scroll);
    scroll.addEventListener("scroll", schedule, { passive: true });
    collect();
    return () => {
      mutation.disconnect();
      resize.disconnect();
      scroll.removeEventListener("scroll", schedule);
      cancelAnimationFrame(frame);
    };
  }, [scrollRef]);

  useEffect(() => {
    if (!expanded) return;
    const list = listRef.current;
    const item = list?.querySelector<HTMLElement>('[aria-current="location"]');
    if (!list || !item) return;
    const listRect = list.getBoundingClientRect();
    const itemRect = item.getBoundingClientRect();
    if (itemRect.top < listRect.top) list.scrollTop += itemRect.top - listRect.top;
    else if (itemRect.bottom > listRect.bottom) list.scrollTop += itemRect.bottom - listRect.bottom;
  }, [active, expanded]);

  useEffect(() => {
    if (pendingFocus.current === "rail" && !expanded) {
      toggleRef.current?.focus();
      pendingFocus.current = null;
    } else if (pendingFocus.current === "contents" && expanded) {
      const item = listRef.current?.querySelector<HTMLButtonElement>('[aria-current="location"]') ?? listRef.current?.querySelector<HTMLButtonElement>("button");
      item?.focus();
      pendingFocus.current = null;
    }
  }, [expanded]);

  useEffect(() => {
    if (!expanded) return;
    const dismiss = (event: PointerEvent) => {
      if (!panelRef.current?.parentElement?.contains(event.target as Node)) setExpanded(false);
    };
    document.addEventListener("pointerdown", dismiss, true);
    return () => document.removeEventListener("pointerdown", dismiss, true);
  }, [expanded]);

  if (!headings.length) return null;
  const baseLevel = Math.min(...headings.map((heading) => heading.level));
  const collapse = () => { pendingFocus.current = "rail"; setExpanded(false); };
  const railStart = Math.max(0, Math.min(headings.findIndex((heading) => heading.element === active) - 5, headings.length - 12));
  const jump = (heading: Heading) => {
    const scroll = scrollRef.current;
    if (!scroll) return;
    scroll.scrollTo({
      top: Math.max(0, scroll.scrollTop + heading.element.getBoundingClientRect().top - scroll.getBoundingClientRect().top - HEADING_INSET),
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth",
    });
    collapse();
  };

  return <div className={`course-toc${expanded ? " course-toc--expanded" : ""}`} onPointerEnter={(event) => {
    if (event.pointerType === "mouse") setExpanded(true);
  }} onPointerLeave={() => {
    if (!panelRef.current?.contains(document.activeElement)) setExpanded(false);
  }} onBlur={(event) => {
    // Hover expansion hides the trigger, which blurs it before the pointer leaves.
    if (panelRef.current?.contains(event.target) && !event.currentTarget.contains(event.relatedTarget)) setExpanded(false);
  }} onKeyDown={(event) => {
    if (event.key === "Escape" && expanded) { event.preventDefault(); event.stopPropagation(); collapse(); }
  }}>
    <nav ref={panelRef} id={panelId} aria-label="Table of contents" hidden={!expanded} className="course-toc__panel">
      <ol ref={listRef} className="course-toc__list">
        {headings.map((heading, index) => <li key={index}>
          <button type="button" className="course-toc__item" title={heading.title} style={{ paddingInlineStart: `${8 + Math.min(heading.level - baseLevel, 3) * 12}px` }} aria-current={active === heading.element ? "location" : undefined} onClick={() => jump(heading)}>
            <span>{heading.title}</span>
          </button>
        </li>)}
      </ol>
    </nav>
    <button ref={toggleRef} type="button" className="course-toc__toggle" aria-label="Show table of contents" aria-expanded={expanded} aria-controls={panelId} onClick={() => { pendingFocus.current = "contents"; setExpanded(true); }}>
      {headings.slice(railStart, railStart + 12).map((heading, index) => <span key={index} aria-hidden="true" className="course-toc__line" data-current={heading.element === active ? "" : undefined} style={{ width: `${20 - Math.min(heading.level - baseLevel, 3) * 4}px` }} />)}
    </button>
  </div>;
}
