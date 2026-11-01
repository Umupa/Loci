import { cloneElement, Fragment, useEffect, useId, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type RefObject, type PointerEvent as ReactPointerEvent, type ReactElement, type ReactNode } from "react";
import { ArrowHorizontal, ChatQuestion, Check, Highlighter, ChevronDown, ChevronLeft, ChevronRight, MessageSquarePlus, MoreHorizontal, Mortarboard, SidebarLeft, X } from "../../../shared/ui/icons";
import { ResourceHeader, RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { Popover } from "../../../shared/ui/Popover";
import { useReadingWide } from "../../../shared/lib/readingWidth";
import { findAgent } from "../../agents/model/agent";
import { readAgentDocument, subscribeAgentDocuments } from "../../agents/model/agentDocuments";
import { DocumentBody, shownDocument } from "../../agents/ui/DocumentBody";
import { requestOpenFile } from "../../files/model/filePlace";
import { shortCommit } from "../../../platform/tauri/code";
import type { AgentDocument } from "../../sessions/model/cards";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { CodeReader } from "../../../shared/ui/CodeReader";
import { COURSES_CHANGED_EVENT, courseItems, loadCourse, NAVIGATE_CONCEPT_EVENT, OPEN_COURSE_EVENT, setLessonStatus, type ComparePart, type CourseChangedDetail, type CourseLesson, type CourseWithProgress, type LearningStatus, type NavigateConceptDetail, type OpenCourseDetail } from "../model/course";
import { inLesson } from "../model/annotationCounts";
import { DiffCard } from "./DiffCard";
import { useFileSelection } from "../../files/hooks/useFileSelection";
import { linesOf } from "../model/textAnchor";
import { ReadingSelectionMenu } from "./ReadingSelectionMenu";
import { useReadingMarks, type MarkSpec, type MarksListRequest } from "./useReadingMarks";
import { CourseToc } from "./CourseToc";
import { PinNotice, usePinnedCode } from "./usePinnedCode";
import { CompareLesson, PartHeader, partWhere, type PartChrome } from "./CompareLesson";
import { useCodeNavigation } from "../../files/ui/useCodeNavigation";
import { CourseOutline, PROGRESS_EVENT, type ProgressDetail } from "./CourseOutline";
import "./CoursePane.css";

type Props = {
  courseId: string; agentId: string; title?: string; sourceSessionId?: string;
  itemId?: string;
  /** An explicit reopen may select the same requested lesson again. */
  openRequest?: number;
  onBack?: () => void;
  focused: boolean; onFocus: () => void; onClose: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  /** Extra header buttons, before Close; the Courses page puts its own here. */
  actions?: ReactNode;
  /** After a discussion draft is queued, show the conversation it went to. */
  onDiscussed?: () => void;
  /** The lesson on screen, so the conversation beside it knows what is being read. */
  onLessonChange?: (lesson: { id: string; title: string; compare?: ComparePart[] } | null) => void;
  /**
   * Shown as the window's one reader: its outline lives outside, so the pane
   * has no sidebar and no Back, only Close.
   */
  reader?: boolean;
};
type SyncFailure = { itemId: string; status: LearningStatus; message: string };
export { PROGRESS_EVENT };
const message = (cause: unknown) => cause instanceof Error ? cause.message : String(cause);
/** How close to the end of a lesson counts as having reached it. */
const READ_END_SLACK = 48;
/** A lesson that just replaced another scrolls; its own events settle first. */
const READ_SWITCH_SETTLE_MS = 250;
/** A lesson that fits without scrolling counts as read after this long open. */
const SHORT_LESSON_DWELL_MS = 8000;

export function CoursePane({ courseId, agentId, title, sourceSessionId, focused, onFocus, onClose, onPaneDragStart, actions, onDiscussed, onLessonChange, itemId, openRequest, onBack, reader = false }: Props) {
  const embedded = reader || !!onBack;
  const scope = JSON.stringify([agentId, courseId]);
  const [loaded, setLoaded] = useState<{ scope: string; course: CourseWithProgress | null; error: string | null }>({ scope, course: null, error: null });
  const [reload, setReload] = useState(0);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(!embedded);
  const sidebarId = useId();
  const [saving, setSaving] = useState<Set<string>>(new Set());
  const [actionError, setActionError] = useState<string | null>(null);
  const [syncFailures, setSyncFailures] = useState<Map<string, SyncFailure>>(new Map());
  const pendingWrites = useRef(new Map<string, { scope: string; itemId: string }>());
  const scrollRef = useRef<HTMLElement>(null);
  const lessonMenu = useRef<HTMLButtonElement>(null);
  const [marksOpen, setMarksOpen] = useState(false);
  const [marks, setMarks] = useState(0);
  const pendingConcept = useRef<NavigateConceptDetail | null>(null);
  const pendingProgress = useRef<{ scope: string; items: Map<string, LearningStatus> }>({ scope, items: new Map() });
  const courseLoad = useRef<{ scope: string; promise: Promise<CourseWithProgress | null> } | null>(null);
  const generation = useRef(0);
  const selected = useRef<{ scope: string; id: string | null }>({ scope, id: null });
  const latest = useRef({ scope, course: loaded.course, mounted: true });
  const course = loaded.scope === scope ? loaded.course : null;
  if (course) selected.current = { scope, id: activeId };
  const pendingItem = useRef(itemId);
  const requestKey = JSON.stringify([scope, itemId, openRequest]);
  const lastRequest = useRef(requestKey);
  if (lastRequest.current !== requestKey) { lastRequest.current = requestKey; pendingItem.current = itemId; }
  useEffect(() => {
    if (itemId && course && courseItems(course.data).some((item) => item.id === itemId)) {
      // Choosing a lesson from outside is opening it, as choosing it here is.
      select(itemId);
      pendingItem.current = undefined;
    }
    // Only an explicit navigation changes selection; ordinary revisions keep it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestKey]);
  const renderGeneration = generation.current;
  latest.current.scope = scope; latest.current.course = course;
  useEffect(() => { latest.current.mounted = true; return () => { latest.current.mounted = false; }; }, []);

  useEffect(() => {
    let current = true;
    generation.current += 1;
    pendingProgress.current = { scope, items: new Map() };
    setLoaded({ scope, course: null, error: null });
    setActionError(null);
    setSaving(new Set([...pendingWrites.current.values()].filter((write) => write.scope === scope).map((write) => write.itemId)));
    setSyncFailures(new Map());
    const promise = loadCourse(courseId, agentId).then((found) => {
      if (!current) return null;
      if (!found) { setLoaded({ scope, course: null, error: "This course is no longer available." }); return null; }
      const items = courseItems(found.data);
      if (pendingProgress.current.scope === scope) {
        for (const [id, status] of pendingProgress.current.items) if (items.some((item) => item.id === id)) found.progress.set(id, status);
        pendingProgress.current.items.clear();
      }
      setLoaded({ scope, course: found, error: null });
      const pending = pendingConcept.current;
      const navigable = pending?.courseId === found.id && (!pending.agentId || pending.agentId === found.agentId) && found.data.engine === "reading" && (!pending.canvasId || pending.canvasId === found.data.canvasId) && items.some((item) => item.id === pending.conceptId);
      pendingConcept.current = null;
      const previousSelection = selected.current.scope === scope && items.some((item) => item.id === selected.current.id) ? selected.current.id : null;
      setActiveId(navigable ? pending!.conceptId : (pendingItem.current && items.some((item) => item.id === pendingItem.current) ? pendingItem.current : previousSelection) ?? items.find((item) => found.progress.get(item.id) !== "mastered")?.id ?? items[0].id);
      pendingItem.current = undefined;
      return found;
    }).catch((cause: unknown) => { if (current) setLoaded({ scope, course: null, error: `Could not load course: ${message(cause)}` }); return null; });
    courseLoad.current = { scope, promise };
    return () => { current = false; };
  }, [scope, reload]);

  useEffect(() => {
    const navigate = (event: Event) => {
      const detail = (event as CustomEvent<NavigateConceptDetail>).detail;
      if (!detail || detail.courseId !== courseId || (detail.agentId && detail.agentId !== agentId) || typeof detail.conceptId !== "string") return;
      const found = latest.current.course;
      if (!found) { pendingConcept.current = detail; return; }
      if (found.data.engine !== "reading" || (detail.canvasId && detail.canvasId !== found.data.canvasId)) return;
      if (courseItems(found.data).some((lesson) => lesson.id === detail.conceptId)) setActiveId(detail.conceptId);
    };
    const opened = (event: Event) => {
      const detail = (event as CustomEvent<OpenCourseDetail>).detail;
      if (detail?.courseId === courseId && detail.agentId === agentId) setReload((value) => value + 1);
    };
    const changed = (event: Event) => {
      const detail = (event as CustomEvent<CourseChangedDetail>).detail;
      if (detail?.agentId === agentId && (detail.courseId === undefined || detail.courseId === courseId)) setReload((value) => value + 1);
    };
    const progressed = (event: Event) => {
      const detail = (event as CustomEvent<ProgressDetail>).detail;
      if (detail?.courseId !== courseId || detail.agentId !== agentId) return;
      if (!latest.current.course && pendingProgress.current.scope === scope) pendingProgress.current.items.set(detail.itemId, detail.status);
      setLoaded((previous) => {
        if (previous.scope !== scope) return previous;
        if (!previous.course) { if (pendingProgress.current.scope === scope) pendingProgress.current.items.set(detail.itemId, detail.status); return previous; }
        if (!courseItems(previous.course.data).some((item) => item.id === detail.itemId)) return previous;
        const progress = new Map(previous.course.progress); progress.set(detail.itemId, detail.status);
        return { ...previous, course: { ...previous.course, progress } };
      });
    };
    window.addEventListener(NAVIGATE_CONCEPT_EVENT, navigate);
    window.addEventListener(OPEN_COURSE_EVENT, opened);
    window.addEventListener(COURSES_CHANGED_EVENT, changed);
    window.addEventListener(PROGRESS_EVENT, progressed);
    return () => { window.removeEventListener(NAVIGATE_CONCEPT_EVENT, navigate); window.removeEventListener(OPEN_COURSE_EVENT, opened); window.removeEventListener(COURSES_CHANGED_EVENT, changed); window.removeEventListener(PROGRESS_EVENT, progressed); };
  }, [scope]);

  const isScopeCurrent = () => latest.current.mounted && latest.current.scope === scope;
  const isCurrent = () => isScopeCurrent() && generation.current === renderGeneration;
  const syncConcept = async (itemId: string, status: LearningStatus) => {
    // A committed save can outlive a course reload. Reconcile again if another
    // revision arrives while its canvas write is queued or in progress.
    const currentLoad = () => isScopeCurrent() && courseLoad.current?.scope === scope ? courseLoad.current : null;
    while (true) {
      const request = currentLoad();
      let found: CourseWithProgress | null;
      try {
        // Closing or navigating away must not cancel the saved progress's map
        // update. Its detached operation reads the original course from storage.
        found = request ? await request.promise : await loadCourse(courseId, agentId);
      } catch { return; }
      if (currentLoad() !== request) continue;
      if (!found || found.data.engine !== "reading" || !found.data.canvasId || !courseItems(found.data).some((lesson) => lesson.id === itemId)) return;
      let failure: SyncFailure | undefined;
      try {
        const { setConceptStatus } = await import("../../canvas/concepts");
        if (currentLoad() !== request) continue;
        await setConceptStatus(found.data.canvasId, found.id, itemId, status, agentId);
      } catch (cause) {
        failure = { itemId, status, message: message(cause) };
      }
      if (currentLoad() !== request) continue;
      if (isScopeCurrent()) setSyncFailures((previous) => {
        const next = new Map(previous);
        if (failure) next.set(itemId, failure); else next.delete(itemId);
        return next;
      });
      return;
    }
  };
  const markStatus = async (itemId: string, status: LearningStatus) => {
    if (!course) return;
    const writeKey = JSON.stringify([scope, itemId]);
    if (pendingWrites.current.has(writeKey)) return;
    pendingWrites.current.set(writeKey, { scope, itemId }); setSaving((previous) => new Set(previous).add(itemId)); setActionError(null);
    try {
      await setLessonStatus(courseId, agentId, itemId, status);
      // Progress is already committed. A drawing failure is shown separately and
      // retrying the drawing must never undo or duplicate that native write.
      await syncConcept(itemId, status);
    } catch (cause) {
      if (isCurrent()) setActionError(`Could not save progress: ${message(cause)}`);
    } finally {
      pendingWrites.current.delete(writeKey);
      // This item remains locked across a same-course reload until its IPC
      // operation settles. Only the lock is released across generations.
      if (latest.current.mounted && latest.current.scope === scope) setSaving((previous) => { const next = new Set(previous); next.delete(itemId); return next; });
    }
  };
  const retrySync = async (failure: SyncFailure) => {
    const writeKey = JSON.stringify([scope, failure.itemId]);
    if (pendingWrites.current.has(writeKey)) return;
    pendingWrites.current.set(writeKey, { scope, itemId: failure.itemId });
    setSaving((previous) => new Set(previous).add(failure.itemId));
    try { await syncConcept(failure.itemId, course?.progress.get(failure.itemId) ?? failure.status); }
    finally {
      pendingWrites.current.delete(writeKey);
      if (latest.current.mounted && latest.current.scope === scope) setSaving((previous) => { const next = new Set(previous); next.delete(failure.itemId); return next; });
    }
  };
  const discuss = () => {
    if (!course || !activeId) return;
    const targetSessionId = findAgent(agentId)?.sessionId ?? sourceSessionId;
    if (!targetSessionId) { setActionError("Open the course's original conversation before discussing progress."); return; }
    const currentItem = courseItems(course.data).find((item) => item.id === activeId)!;
    const reading = course.data.engine === "reading";
    const prompt = reading
      ? `I'm studying course "${course.title}" (courseId: ${course.id}). Current lesson: "${currentItem.title}" (${activeId}), status: ${course.progress.get(activeId) ?? "untouched"}. Test my understanding with 1–2 practical questions or edge-case scenarios about this material, and highlight what to watch out for.`
      : `I'm working on step "${currentItem.title}" in course "${course.title}" (courseId: ${course.id}). Current step: "${currentItem.title}" (${activeId}), status: ${course.progress.get(activeId) ?? "untouched"}. Let's discuss the key design decisions, trade-offs and next steps.`;
    requestAddToChat(prompt, "plain", { targetSessionId });
    setActionError(null);
    onDiscussed?.();
  };
  // Opening a lesson is starting to read it, at its own beginning.
  const switchedAt = useRef(0);
  const select = (id: string) => {
    if (id !== activeId) {
      switchedAt.current = Date.now();
      if (scrollRef.current) scrollRef.current.scrollTop = 0;
    }
    setActiveId(id);
    if (course?.data.engine === "reading" && (course.progress.get(id) ?? "untouched") === "untouched") void markStatus(id, "learning");
  };
  const reading = course?.data.engine === "reading";
  const activeStatus = course?.progress.get(activeId ?? "") ?? "untouched";
  const items = course ? courseItems(course.data) : [];
  const currentIndex = items.findIndex((item) => item.id === activeId);
  const nextItem = currentIndex >= 0 && currentIndex < items.length - 1 ? items[currentIndex + 1] : null;
  const previousItem = currentIndex > 0 ? items[currentIndex - 1] : null;
  const sidebarLabel = `${sidebarOpen ? "Hide" : "Show"} course sidebar`;
  // Reaching the end of a lesson is reading it; a lesson too short to scroll
  // counts once it has been open a while.
  const readThrough = () => {
    const main = scrollRef.current;
    if (!reading || !activeId || activeStatus === "mastered" || !main) return;
    // The old lesson's offset being clamped to the new one's length is not reading it.
    if (Date.now() - switchedAt.current < READ_SWITCH_SETTLE_MS) return;
    if (main.scrollTop + main.clientHeight >= main.scrollHeight - READ_END_SLACK) void markStatus(activeId, "mastered");
  };
  useEffect(() => {
    const main = scrollRef.current;
    if (!reading || !activeId || activeStatus === "mastered" || !main) return;
    const timer = window.setTimeout(() => { if (main.scrollHeight <= main.clientHeight + READ_END_SLACK) void markStatus(activeId, "mastered"); }, SHORT_LESSON_DWELL_MS);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeId, activeStatus, reading]);
  const activeTitle = items[currentIndex]?.title;
  // A comparison tells the conversation which places it puts side by side.
  const activeCompare = reading && currentIndex >= 0 ? (items[currentIndex] as CourseLesson).compare : undefined;
  const compareKey = activeCompare ? JSON.stringify(activeCompare.map(({ note: _note, ...place }) => place)) : "";
  useEffect(() => {
    onLessonChange?.(activeId && activeTitle ? { id: activeId, title: activeTitle, ...(compareKey ? { compare: JSON.parse(compareKey) as ComparePart[] } : {}) } : null);
  }, [activeId, activeTitle, compareKey]); // eslint-disable-line react-hooks/exhaustive-deps
  const iconButton = embedded ? RESOURCE_ACTION : "course-pane__close";
  const controls = course ? <>
    <button type="button" data-no-drag className={iconButton} title={previousItem ? `Previous: ${previousItem.title}` : "Previous"} disabled={!previousItem} onClick={() => previousItem && select(previousItem.id)}><ChevronLeft className="size-4" /><span className="sr-only">Previous</span></button>
    <button type="button" data-no-drag className={iconButton} title={nextItem ? `Next: ${nextItem.title}` : "Next"} disabled={!nextItem} onClick={() => nextItem && select(nextItem.id)}><ChevronRight className="size-4" /><span className="sr-only">Next</span></button>
    <button type="button" data-no-drag className={`${iconButton}${activeStatus === "mastered" ? " course-pane__read" : ""}`} title={activeStatus === "mastered" ? (reading ? "Read" : "Mastered") : reading ? "Mark as read" : "Mark as mastered"} disabled={!activeId || saving.has(activeId) || activeStatus === "mastered"} onClick={() => activeId && void markStatus(activeId, "mastered")}><Check className="size-3.5" /><span className="sr-only">{activeId && saving.has(activeId) ? "Saving…" : activeStatus === "mastered" ? (reading ? "Read ✓" : "Mastered ✓") : reading ? "Mark as read" : "Mark as mastered"}</span></button>
    <button type="button" data-no-drag className={iconButton} title={reading ? "Test my understanding with the agent" : "Discuss this step with the agent"} onClick={discuss}><MessageSquarePlus className="size-3.5" /><span className="sr-only">{reading ? "Test understanding" : "Discuss step"}</span></button>
  </> : null;
  const [readingWide, setReadingWide] = useReadingWide();
  const markLabel = activeId && saving.has(activeId) ? "Saving…" : activeStatus === "mastered" ? (reading ? "Read ✓" : "Mastered ✓") : reading ? "Mark as read" : "Mark as mastered";
  // Beside a conversation the header keeps to moving through the course; the
  // rest waits in a menu, since reaching a lesson's end already marks it read.
  const overviewControls = course ? <>
    <button type="button" className={RESOURCE_ACTION} title={previousItem ? `Previous: ${previousItem.title}` : "Previous"} disabled={!previousItem} onClick={() => previousItem && select(previousItem.id)}><ChevronLeft className="size-4" /><span className="sr-only">Previous</span></button>
    <button type="button" className={RESOURCE_ACTION} title={nextItem ? `Next: ${nextItem.title}` : "Next"} disabled={!nextItem} onClick={() => nextItem && select(nextItem.id)}><ChevronRight className="size-4" /><span className="sr-only">Next</span></button>
    <LessonMenu trigger={lessonMenu} items={[
      // A reading is marked read by reaching its end; only steps are marked by hand.
      ...(reading ? [] : [{ label: markLabel, icon: <Check />, disabled: !activeId || saving.has(activeId) || activeStatus === "mastered", onSelect: () => { if (activeId) void markStatus(activeId, "mastered"); } }]),
      { label: reading ? "Test my understanding" : "Discuss this step", icon: <ChatQuestion />, onSelect: discuss },
      ...(reading ? [{ label: "Highlights & notes", icon: <Highlighter />, meta: marks || undefined, disabled: !activeId, onSelect: () => setMarksOpen(true) }] : []),
      { label: "Full-width text", icon: <ArrowHorizontal />, checked: readingWide, separated: true, onSelect: () => setReadingWide(!readingWide) },
    ]} />
  </> : null;
  const alerts = actionError || syncFailures.size ? <div className="course-pane__alerts">{actionError ? <p role="alert" className="course-error">{actionError}</p> : null}{[...syncFailures.values()].map((failure) => <div key={failure.itemId} role="alert" className="course-error">Progress saved for {items.find((item) => item.id === failure.itemId)?.title ?? failure.itemId}, but the concept map could not update: {failure.message}<button type="button" className="course-button course-button--quiet" disabled={saving.has(failure.itemId)} onClick={() => void retrySync(failure)}>Retry map update</button></div>)}</div> : null;

  return <aside aria-label={course?.title ?? title ?? "Course"} className={`course-pane${embedded ? " course-pane--overview" : ""}`} onPointerDown={() => { if (!focused) onFocus(); }}>
    {embedded ? <ResourceHeader title={course?.title ?? title ?? "Course"} titleContent={course ? <CourseContentsDropdown course={course} activeId={activeId} onSelect={select} /> : undefined} backLabel="Back to courses" onBack={onBack} onClose={onClose}>
      {overviewControls}
      {actions}
    </ResourceHeader> : <>
    <PaneHeader className="course-pane__header" onPaneDragStart={onPaneDragStart}>
      {course ? <button type="button" data-no-drag aria-label={sidebarLabel} title={sidebarLabel} aria-expanded={sidebarOpen} aria-controls={sidebarId} className="course-pane__sidebar-toggle" onClick={() => setSidebarOpen((open) => !open)}><SidebarLeft className="size-4" /></button> : null}
      <Mortarboard className={`size-4 shrink-0 ${focused ? "text-content/70" : "text-content/40"}`} /><span className="course-pane__title">{course?.title ?? title ?? "Course"}</span>{controls ? <span data-no-drag className="flex shrink-0 items-center gap-0.5">{controls}</span> : null}{actions ? <span data-no-drag className="flex shrink-0 items-center gap-1">{actions}</span> : null}<button type="button" data-no-drag aria-label="Close course" className="course-pane__close" onClick={onClose}><X className="size-4" /></button>
    </PaneHeader>
    </>}
    {course ? <>
      <div className="course-pane__body">{!embedded ? <CourseOutline course={course} activeId={activeId} onSelect={select} id={sidebarId} hidden={!sidebarOpen} /> : null}<div className="course-pane__right"><div className="course-pane__reader"><main ref={scrollRef} className="course-pane__main" onScroll={readThrough}><CourseContent course={course} activeId={activeId} onMarks={setMarks}
        marksList={marksOpen ? { anchor: lessonMenu, onClose: () => setMarksOpen(false), title: "Highlights & notes in this lesson" } : undefined} /></main>{reading ? <CourseToc scrollRef={scrollRef} /> : null}</div>{alerts}</div></div>
    </> : <div className="course-pane__empty" role={loaded.scope === scope && loaded.error ? "alert" : undefined}><p>{loaded.scope === scope ? loaded.error ?? "Opening course…" : "Opening course…"}</p>{loaded.scope === scope && loaded.error ? <button type="button" className="course-button" onClick={() => setReload((value) => value + 1)}>Retry</button> : null}</div>}
  </aside>;
}

type LessonMenuItem = {
  label: string;
  icon: ReactElement<{ className?: string }>;
  disabled?: boolean;
  /** A count shown at the end of the row. */
  meta?: number;
  /** A setting that stays on: a tick shows when it is. */
  checked?: boolean;
  /** Starts a new group, below a rule. */
  separated?: boolean;
  onSelect: () => void;
};

function LessonMenu({ items, trigger }: { items: LessonMenuItem[]; trigger: RefObject<HTMLButtonElement | null> }) {
  const [open, setOpen] = useState(false);
  return <>
    <button ref={trigger} type="button" className={RESOURCE_ACTION} title="Lesson actions" aria-label="Lesson actions" aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((value) => !value)}><MoreHorizontal className="size-4" /></button>
    {open ? <Popover anchor={trigger} side="bottom" align="end" width={224} role="menu" aria-label="Lesson actions" onDismiss={() => setOpen(false)} className="lesson-menu p-1 font-sans">
      {items.map((item) => <Fragment key={item.label}>
        {item.separated ? <div role="separator" className="lesson-menu__rule" /> : null}
        <button type="button" role={item.checked === undefined ? "menuitem" : "menuitemcheckbox"} aria-checked={item.checked} disabled={item.disabled}
          onClick={() => { setOpen(false); item.onSelect(); }} className="lesson-menu__item">
          {cloneElement(item.icon, { className: "lesson-menu__icon" })}
          <span className="lesson-menu__label">{item.label}</span>
          {item.meta ? <span className="lesson-menu__meta">{item.meta}</span> : null}
          {item.checked ? <Check className="lesson-menu__check" strokeWidth={2} /> : null}
        </button>
      </Fragment>)}
    </Popover> : null}
  </>;
}

function CourseContentsDropdown({ course, activeId, onSelect }: { course: CourseWithProgress; activeId: string | null; onSelect: (id: string) => void }) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const popup = useRef<HTMLDivElement>(null);
  const id = useId();
  useEffect(() => {
    if (!open) return;
    const selected = popup.current?.querySelector<HTMLButtonElement>('button[aria-current="step"]') ?? popup.current?.querySelector<HTMLButtonElement>("nav button");
    selected?.focus({ preventScroll: true });
    selected?.scrollIntoView({ block: "nearest" });
  }, [open]);
  const close = () => { setOpen(false); trigger.current?.focus({ preventScroll: true }); };
  const navigate = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
    const buttons = [...event.currentTarget.querySelectorAll<HTMLButtonElement>("nav button")];
    if (!buttons.length) return;
    event.preventDefault();
    const current = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const index = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1 : (current + (event.key === "ArrowDown" ? 1 : -1) + buttons.length) % buttons.length;
    buttons[index].focus();
  };
  return <>
    <button ref={trigger} type="button" data-tauri-drag-region="false" data-no-drag className="course-pane__contents-trigger" aria-label="Course contents" title="Course contents" aria-haspopup="dialog" aria-expanded={open} aria-controls={open ? id : undefined} onClick={() => setOpen((value) => !value)} onKeyDown={(event) => { if (event.key === "ArrowDown") { event.preventDefault(); setOpen(true); } }}>
      <span>{course.title}</span><ChevronDown className="size-3.5 shrink-0 text-content/45" aria-hidden="true" />
    </button>
    {open ? <Popover ref={popup} anchor={trigger} id={id} role="dialog" aria-label="Course contents" side="bottom" align="start" width={320} maxHeight={420} className="course-pane__contents" onKeyDown={navigate} onDismiss={(reason) => { if (reason === "escape") close(); else setOpen(false); }}>
      <CourseOutline course={course} activeId={activeId} onSelect={(item) => { onSelect(item); close(); }} />
    </Popover> : null}
  </>;
}

type MarksProps = { marksList?: MarksListRequest; onMarks?: (count: number) => void };

function CourseContent({ course, activeId, marksList, onMarks }: { course: CourseWithProgress; activeId: string | null } & MarksProps) {
  if (course.data.engine === "build-your-own") {
    const step = course.data.steps.find((item) => item.id === activeId);
    return step ? <article className="course-pane__content" key={step.id}><h2>{step.title}</h2><p className="course-pane__summary">{step.summary}</p><DiffCard {...step} id={`${course.id}-${step.id}`} /><AgentMarkdown text={step.explanation} wholeDocument /></article> : null;
  }
  const lesson = course.data.chapters.flatMap((chapter) => chapter.lessons).find((item) => item.id === activeId);
  if (!lesson) return null;
  if (lesson.compare) return <CompareContent course={course} lesson={lesson} marksList={marksList} onMarks={onMarks} />;
  return lesson.file !== undefined ? <LessonFile agentId={course.agentId} lesson={lesson} marksList={marksList} onMarks={onMarks} />
    : <LessonDocument agentId={course.agentId} lesson={lesson} marksList={marksList} onMarks={onMarks} />;
}

/**
 * A comparison: each part is read as its own lesson would be, framed as a
 * part. The lesson's marks are its parts' marks; the list shows the first
 * part that has any.
 */
function CompareContent({ course, lesson, marksList, onMarks }: { course: CourseWithProgress; lesson: CourseLesson } & MarksProps) {
  const [counts, setCounts] = useState<{ lesson: string; counts: number[] }>({ lesson: lesson.id, counts: [] });
  const shown = counts.lesson === lesson.id ? counts.counts : [];
  const total = shown.reduce((sum, count) => sum + (count ?? 0), 0);
  useEffect(() => { onMarks?.(total); }, [onMarks, total]);
  const listed = Math.max(0, shown.findIndex((count) => count > 0));
  const counter = useMemo(() => (lesson.compare ?? []).map((_, index) => (count: number) => setCounts((before) => {
    const next = before.lesson === lesson.id ? [...before.counts] : [];
    if (next[index] === count) return before;
    next[index] = count;
    return { lesson: lesson.id, counts: next };
  })), [lesson.id, lesson.compare]);
  return <CompareLesson agentId={course.agentId} courseId={course.id} lesson={lesson} renderPart={(part, chrome) => {
    const place: CourseLesson = { id: `${lesson.id}:${chrome.index}`, title: part.label,
      ...(part.document ? { document: part.document, ...(part.section ? { section: part.section } : {}) } : { file: part.file!, ...(part.lines ? { lines: part.lines } : {}), ...(part.commit ? { commit: part.commit } : {}) }),
      ...(part.pages ? { pages: part.pages } : {}) };
    const list = marksList && chrome.index === listed ? { ...marksList, title: `Highlights & notes in ${part.label}` } : undefined;
    return part.document ? <LessonDocument agentId={course.agentId} lesson={place} part={chrome} marksList={list} onMarks={counter[chrome.index]} />
      : <LessonFile agentId={course.agentId} lesson={place} part={chrome} marksList={list} onMarks={counter[chrome.index]} />;
  }} />;
}

/** A lesson read from a file. Source and text files are shown in place; a PDF or other document opens in its own pane, where it can be highlighted. */
function LessonFile({ agentId, lesson, marksList, onMarks, part }: { agentId: string; lesson: CourseLesson; part?: PartChrome } & MarksProps) {
  const file = lesson.file!;
  const excerptRef = useRef<HTMLDivElement>(null);
  const { selection, dismiss } = useFileSelection(excerptRef, true);
  const name = file.split(/[\\/]/).pop() || file;
  const inline = !lesson.pages && isReadableSource(name);
  const pin = usePinnedCode(file, lesson.commit, lesson.lines, inline);
  const shownLines = pin.lines;
  const first = shownLines?.[0] ?? 1;
  // A Markdown file with no range is shown as itself: its code blocks are not the file's lines.
  const fenced = !!lesson.lines || !/\.(md|markdown)$/i.test(file);
  const spec = useMemo((): MarkSpec => ({
    target: { kind: "file", path: file },
    source: (anchor, quote, annotationId) => ({ id: crypto.randomUUID(), kind: "file", path: file, title: `${part ? `${part.label}: ` : ""}${file.split(/[\\/]/).pop() || file}`, quote,
      ...(anchor.lines ? { lines: anchor.lines } : {}), ...(pin.commit ? { commit: pin.commit } : {}), anchor, ...(annotationId ? { annotationId } : {}) }),
    lines: (range) => fenced ? excerptLines(range, first) : undefined,
  }), [file, first, fenced, pin.commit, part?.label]);
  const marks = useReadingMarks(excerptRef, spec, { agentId });
  const preRef = useRef<HTMLPreElement>(null);
  const nav = useCodeNavigation({
    file, commit: pin.commit, codeRef: preRef, firstLine: first, enabled: inline && fenced && !!pin.loaded?.text,
    onGo: (target, from) => requestOpenFile(target.file, { lines: [target.line, target.line] }, { ...(target.commit ? { commit: target.commit } : {}), fromLine: from }),
  });
  // A code-tour lesson reads part of a file: its menu counts and lists that part, as its outline does.
  const shownMarks = useMemo(() => lesson.lines ? marks.annotations.filter((annotation) => inLesson(lesson, annotation)) : marks.annotations,
    [marks.annotations, lesson]);
  const count = shownMarks.length;
  useEffect(() => { onMarks?.(count); }, [onMarks, count]);
  const at = lesson.commit ? ` · @${shortCommit(pin.commit ?? lesson.commit)}` : "";
  const where = lesson.pages ? ` · ${lesson.pages[0] === lesson.pages[1] ? `page ${lesson.pages[0]}` : `pages ${lesson.pages[0]}–${lesson.pages[1]}`}`
    : shownLines ? ` · lines ${shownLines[0]}–${shownLines[1]}` : "";
  const open = <button type="button" className="course-button" onClick={() => requestOpenFile(file, lesson.pages ? { page: lesson.pages[0] } : undefined)}>Open to read</button>;
  const reportShown = part?.onShown;
  const shownKey = JSON.stringify([file, pin.commit, shownLines, pin.status?.state, pin.loaded?.error]);
  useEffect(() => {
    reportShown?.({ file, ...(pin.commit ? { commit: pin.commit } : {}), ...(shownLines ? { lines: shownLines } : {}), ...(pin.status ? { pin: pin.status.state } : {}), ...(pin.loaded?.error ? { error: pin.loaded.error } : {}) });
  }, [shownKey]); // eslint-disable-line react-hooks/exhaustive-deps
  if (part) return <LessonFilePart part={part} file={file} name={name} lesson={lesson} pin={pin} inline={inline} open={open}
    openWhole={nav.active ? () => requestOpenFile(file, shownLines ? { lines: shownLines } : undefined, pin.commit ? { commit: pin.commit } : {}) : undefined}>
    {!pin.loaded ? <p className="course-pane__relations">Opening…</p>
      : pin.loaded.error ? <><p className="course-error" role="alert">Could not read {name}: {pin.loaded.error}</p>{open}</>
      : fenced ? (() => {
        const excerpt = codeExcerpt(pin.loaded.text!, shownLines);
        return <div ref={excerptRef} className="select-text" data-reading-text data-reading-lines-from={first} onClick={nav.onClick}>
          <CodeReader text={excerpt.code} file={name} firstLine={first} preRef={preRef} label={`${part.label}: ${name}, lines ${first}–${first + excerpt.code.split("\n").length - 1}`} />
          {excerpt.shown < excerpt.total ? <p className="course-pane__relations">Showing the first {excerpt.shown} of {excerpt.total} lines.</p> : null}
        </div>;
      })()
      : <div ref={excerptRef} className="select-text" data-reading-text><AgentMarkdown text={pin.loaded.text!} wholeDocument /></div>}
    <ReadingSelectionMenu selection={selection} onDismiss={dismiss} resetKey={`${file}:${pin.view}:${pin.loaded?.text?.length ?? 0}`} askLabel={marks.askLabel} toChat={marks.toChat} onMark={marks.onMark} actions={nav.selectionActions} />
    {marks.popover}
    {nav.results}
    {marksList ? marks.listPopover(marksList.anchor, marksList.onClose, marksList.title, shownMarks) : null}
  </LessonFilePart>;
  if (!inline) return <article className="course-pane__content" key={lesson.id}><h2>{lesson.title}</h2><p className="course-pane__summary" title={file}>{name}{where}</p>{open}</article>;
  const shown = pin.loaded;
  return <article className="course-pane__content course-pane__reading reader-body reader-measure" key={lesson.id} data-pin-view={lesson.commit ? pin.view : undefined}>
    <h2>{lesson.title}</h2>
    <p className="course-pane__summary" title={lesson.commit ? `${file} at ${pin.commit ?? lesson.commit}` : file}>{name}{where}{pin.view === "pinned" ? at : ""}
      {nav.active ? <button type="button" className="course-button course-button--quiet course-pane__pin-action" title="Open the whole file in the reader, with its symbols"
        onClick={() => requestOpenFile(file, shownLines ? { lines: shownLines } : undefined, pin.commit ? { commit: pin.commit } : {})}>Open whole file</button> : null}</p>
    {lesson.commit ? <PinNotice name={name} commit={lesson.commit} pin={pin} /> : null}
    {!shown ? <p className="course-pane__relations">Opening…</p>
      : shown.error ? <><p className="course-error" role="alert">Could not read {name}: {shown.error}</p>{open}</>
      : fenced ? (() => {
        const excerpt = codeExcerpt(shown.text!, shownLines);
        return <div ref={excerptRef} className="select-text" data-reading-text data-reading-lines-from={first} onClick={nav.onClick}>
          <CodeReader text={excerpt.code} file={name} firstLine={first} preRef={preRef} label={`${name}, lines ${first}–${first + excerpt.code.split("\n").length - 1}`} />
          {excerpt.shown < excerpt.total ? <p className="course-pane__relations">Showing the first {excerpt.shown} of {excerpt.total} lines.</p> : null}
        </div>;
      })()
      : <div ref={excerptRef} className="select-text" data-reading-text><AgentMarkdown text={shown.text!} wholeDocument /></div>}
    <ReadingSelectionMenu selection={selection} onDismiss={dismiss} resetKey={`${file}:${pin.view}:${shown?.text?.length ?? 0}`} askLabel={marks.askLabel} toChat={marks.toChat} onMark={marks.onMark} actions={nav.selectionActions} />
    {marks.popover}
    {nav.results}
    {marksList ? marks.listPopover(marksList.anchor, marksList.onClose, marksList.title, shownMarks) : null}
  </article>;
}

/** One file part of a comparison: its compact header, its pin notice, and its text, foldable. */
function LessonFilePart({ part, file, name, lesson, pin, inline, open, openWhole, children }: {
  part: PartChrome; file: string; name: string; lesson: CourseLesson; pin: ReturnType<typeof usePinnedCode>; inline: boolean;
  open: ReactNode; openWhole?: () => void; children: ReactNode;
}) {
  const bodyId = `${part.id}-body`;
  const pinned = lesson.commit && pin.view === "pinned" ? pin.commit ?? lesson.commit : undefined;
  // The repository is learnt from a read at the commit; it stays named in the current view.
  const known = useRef<{ file: string; place: NonNullable<typeof pin.place> } | undefined>(undefined);
  if (pin.place) known.current = { file, place: pin.place };
  const where = partWhere(file, pin.place ?? (known.current?.file === file ? known.current.place : undefined), pinned, pin.lines ?? lesson.lines);
  const actions = !inline ? open : openWhole ? <button type="button" className="course-button course-button--quiet course-pane__pin-action" title="Open the whole file in the reader, with its symbols" onClick={openWhole}>Open whole file</button> : null;
  return <section id={part.id} className="course-compare__part" data-compare-part={part.label} data-collapsed={part.collapsed ? "" : undefined} data-pin-view={lesson.commit ? pin.view : undefined}>
    <PartHeader chrome={part} where={where} title={pinned ? `${file} at ${pinned}` : file} actions={actions} bodyId={bodyId} />
    <div id={bodyId} hidden={part.collapsed}>
      {lesson.commit ? <PinNotice name={name} commit={lesson.commit} pin={pin} /> : null}
      {inline ? children : null}
    </div>
  </section>;
}

/** The file lines a selection in a lesson's code excerpt covers; none outside code (a Markdown file shown as itself). */
export function excerptLines(range: Range, first: number): [number, number] | undefined {
  const start = range.startContainer instanceof Element ? range.startContainer : range.startContainer.parentElement;
  const code = start?.closest("pre")?.querySelector("code") ?? start?.closest("pre");
  if (!code || !code.contains(range.endContainer)) return undefined;
  const offset = (node: Node, at: number) => { const before = document.createRange(); before.selectNodeContents(code); before.setEnd(node, at); return before.toString().length; };
  const [a, b] = linesOf(code.textContent ?? "", offset(range.startContainer, range.startOffset), offset(range.endContainer, range.endOffset));
  return [a + first - 1, b + first - 1];
}

/** Lines shown in place when a lesson names no range, so a huge file stays readable. */
const SOURCE_LINES_MAX = 1500;
const DOCUMENT_EXTENSIONS = new Set(["pdf", "png", "jpg", "jpeg", "gif", "webp", "svg", "epub", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "zip", "gz"]);

function isReadableSource(name: string): boolean {
  const extension = name.includes(".") ? name.split(".").pop()!.toLowerCase() : "";
  return !DOCUMENT_EXTENSIONS.has(extension);
}

/** The lines a code lesson shows, and how much of the file that leaves out. */
export function codeExcerpt(text: string, lines?: [number, number]): { code: string; total: number; shown: number } {
  const all = text.replace(/\r\n/g, "\n").split("\n");
  const [from, to] = lines ?? [1, Math.min(all.length, SOURCE_LINES_MAX)];
  return { code: all.slice(from - 1, to).join("\n"), total: all.length, shown: to };
}

/** A file's lines as a fenced block, highlighted by its extension; Markdown is shown as itself. */
export function sourceExcerpt(text: string, name: string, lines?: [number, number]): string {
  const excerpt = codeExcerpt(text, lines);
  const extension = name.includes(".") ? name.split(".").pop()!.toLowerCase() : "";
  if (!lines && (extension === "md" || extension === "markdown")) return excerpt.code;
  const fence = excerpt.code.includes("```") ? "````" : "```";
  const more = !lines && excerpt.total > excerpt.shown ? `\n\n*Showing the first ${excerpt.shown} of ${excerpt.total} lines.*` : "";
  return `${fence}${extension}\n${excerpt.code}\n${fence}${more}`;
}

/** A lesson read from the agent's library: the document itself, from the lesson's heading. */
function LessonDocument({ agentId, lesson, marksList, onMarks, part }: { agentId: string; lesson: CourseLesson; part?: PartChrome } & MarksProps) {
  const id = lesson.document!;
  const [loaded, setLoaded] = useState<{ id: string; document?: AgentDocument; error?: string }>();
  useEffect(() => {
    let current = true;
    const load = () => void readAgentDocument(agentId, id).then((found) => {
      if (current) setLoaded(found?.body != null ? { id, document: shownDocument({ ...found, body: found.body }) } : { id });
    }, (cause: unknown) => { if (current) setLoaded({ id, error: message(cause) }); });
    load();
    const stop = subscribeAgentDocuments(load);
    return () => { current = false; stop(); };
  }, [agentId, id]);
  const shown = loaded?.id === id ? loaded : undefined;
  const reportShown = part?.onShown;
  const shownKey = JSON.stringify([id, lesson.section, shown?.error, !!shown && !shown.document]);
  useEffect(() => {
    if (shown) reportShown?.({ document: id, ...(lesson.section ? { section: lesson.section } : {}), ...(lesson.pages ? { pages: lesson.pages } : {}), ...(shown.error || !shown.document ? { error: shown.error ?? "not in the library" } : {}) });
  }, [shownKey]); // eslint-disable-line react-hooks/exhaustive-deps
  const pages = lesson.pages ? (lesson.pages[0] === lesson.pages[1] ? `page ${lesson.pages[0]}` : `pages ${lesson.pages[0]}–${lesson.pages[1]}`) : undefined;
  if (part) {
    const bodyId = `${part.id}-body`;
    const pdf = shown?.document?.pdf;
    return <section id={part.id} className="course-compare__part" data-compare-part={part.label} data-collapsed={part.collapsed ? "" : undefined}>
      <PartHeader chrome={part} where={{ path: shown?.document?.title ?? id, ...(lesson.section ? { section: lesson.section } : {}), ...(pages ? { lines: pages } : {}) }} title={`${id}${lesson.section ? `#${lesson.section}` : lesson.pages ? `#p${lesson.pages[0]}${lesson.pages[1] !== lesson.pages[0] ? `-${lesson.pages[1]}` : ""}` : ""}`} bodyId={bodyId} />
      <div id={bodyId} hidden={part.collapsed}>
        {!shown ? <p className="course-pane__relations">Opening…</p>
          : !shown.document ? <p className="course-error" role="alert">{shown.error ? `Could not open ${id}: ${shown.error}` : `${id} is not in the library. Ask the agent to save it again.`}</p>
          // A PDF source is read in the PDF reader, at the part's first page.
          : pdf ? <p className="course-pane__summary" title={pdf.path}>{pdf.path.split(/[\\/]/).pop() || pdf.path}{pages ? ` · ${pages}` : ""} <button type="button" className="course-button" onClick={() => requestOpenFile(pdf.path, lesson.pages ? { page: lesson.pages[0] } : undefined)}>Open to read</button></p>
          : <DocumentBody document={shown.document} agentId={agentId} section={lesson.section} bare inPlace marksList={marksList} onMarks={onMarks} />}
      </div>
    </section>;
  }
  if (!shown) return <p className="course-pane__relations">Opening…</p>;
  if (!shown.document) return <article className="course-pane__content"><h2>{lesson.title}</h2><p className="course-error" role="alert">{shown.error ? `Could not open this lesson's document: ${shown.error}` : `This lesson's document (${id}) is not in the library. Ask the agent to save it again.`}</p></article>;
  // A source kept as a PDF is read in the PDF reader, where it can be highlighted.
  if (shown.document.pdf) {
    const pdf = shown.document.pdf;
    const name = pdf.path.split(/[\\/]/).pop() || pdf.path;
    const where = pages ? ` · ${pages}` : "";
    return <article className="course-pane__content" key={lesson.id}>
      <h2>{lesson.title}</h2>
      <p className="course-pane__summary" title={pdf.path}>{name}{where}</p>
      <button type="button" className="course-button" onClick={() => requestOpenFile(pdf.path, lesson.pages ? { page: lesson.pages[0] } : undefined)}>Open to read</button>
    </article>;
  }
  return <article className="course-pane__content course-pane__reading reader-body reader-measure" key={lesson.id}><DocumentBody document={shown.document} agentId={agentId} section={lesson.section} bare marksList={marksList} onMarks={onMarks} /></article>;
}
