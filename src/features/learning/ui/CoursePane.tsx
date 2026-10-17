import { invoke } from "@tauri-apps/api/core";
import { useEffect, useId, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { ChevronDown, Maximize2, MessageSquarePlus, Mortarboard, SidebarLeft, X } from "../../../shared/ui/icons";
import { ResourceHeader, RESOURCE_ACTION } from "../../../shared/ui/ResourceHeader";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { Popover } from "../../../shared/ui/Popover";
import { findAgent } from "../../agents/model/agent";
import { readAgentDocument, subscribeAgentDocuments } from "../../agents/model/agentDocuments";
import { DocumentBody, shownDocument } from "../../agents/ui/DocumentBody";
import { requestOpenFile } from "../../files/model/filePlace";
import type { AgentDocument } from "../../sessions/model/cards";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { COURSES_CHANGED_EVENT, courseItems, loadCourse, NAVIGATE_CONCEPT_EVENT, OPEN_COURSE_EVENT, type CourseChangedDetail, type CourseLesson, type CourseWithProgress, type LearningStatus, type NavigateConceptDetail, type OpenCourseDetail } from "../model/course";
import { DiffCard } from "./DiffCard";
import { CourseToc } from "./CourseToc";
import "./CoursePane.css";

type Props = {
  courseId: string; agentId: string; title?: string; sourceSessionId?: string;
  itemId?: string;
  /** An explicit reopen may select the same requested lesson again. */
  openRequest?: number;
  onBack?: () => void;
  onExpand?: (itemId?: string) => void;
  focused: boolean; onFocus: () => void; onClose: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  /** Extra header buttons, before Close; the Courses page puts its own here. */
  actions?: ReactNode;
  /** After a discussion draft is queued, show the conversation it went to. */
  onDiscussed?: () => void;
};
type SyncFailure = { itemId: string; status: LearningStatus; message: string };
/** Fired on `window` when a lesson's status changes in any pane. */
export const PROGRESS_EVENT = "loci:course-progress";
type ProgressDetail = { courseId: string; agentId: string; itemId: string; status: LearningStatus };
const message = (cause: unknown) => cause instanceof Error ? cause.message : String(cause);
/** What a status is called where the work is reading. */
const READING_STATUS: Record<LearningStatus, string> = { untouched: "Not started", learning: "Reading", mastered: "Read" };

export function CoursePane({ courseId, agentId, title, sourceSessionId, focused, onFocus, onClose, onPaneDragStart, actions, onDiscussed, itemId, openRequest, onBack, onExpand }: Props) {
  const scope = JSON.stringify([agentId, courseId]);
  const [loaded, setLoaded] = useState<{ scope: string; course: CourseWithProgress | null; error: string | null }>({ scope, course: null, error: null });
  const [reload, setReload] = useState(0);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(!onBack);
  const sidebarId = useId();
  const [saving, setSaving] = useState<Set<string>>(new Set());
  const [actionError, setActionError] = useState<string | null>(null);
  const [syncFailures, setSyncFailures] = useState<Map<string, SyncFailure>>(new Map());
  const pendingWrites = useRef(new Map<string, { scope: string; itemId: string }>());
  const scrollRef = useRef<HTMLElement>(null);
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
      setActiveId(itemId);
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
      await invoke("course_progress_set", { courseId, agentId, itemId, status });
      window.dispatchEvent(new CustomEvent<ProgressDetail>(PROGRESS_EVENT, { detail: { courseId, agentId, itemId, status } }));
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
  // Opening a lesson is starting to read it.
  const select = (id: string) => {
    setActiveId(id);
    if (course?.data.engine === "reading" && (course.progress.get(id) ?? "untouched") === "untouched") void markStatus(id, "learning");
  };
  const reading = course?.data.engine === "reading";
  const activeStatus = course?.progress.get(activeId ?? "") ?? "untouched";
  const items = course ? courseItems(course.data) : [];
  const currentIndex = items.findIndex((item) => item.id === activeId);
  const nextItem = currentIndex >= 0 && currentIndex < items.length - 1 ? items[currentIndex + 1] : null;
  const sidebarLabel = `${sidebarOpen ? "Hide" : "Show"} course sidebar`;

  return <aside aria-label={course?.title ?? title ?? "Course"} className={`course-pane${onBack ? " course-pane--overview" : ""}`} onPointerDown={() => { if (!focused) onFocus(); }}>
    {onBack ? <ResourceHeader title={course?.title ?? title ?? "Course"} titleContent={course ? <CourseContentsDropdown course={course} activeId={activeId} onSelect={select} /> : undefined} backLabel="Back to courses" onBack={onBack} onClose={onClose}>
      {onExpand ? <button type="button" aria-label="Expand course to pane" title="Expand to pane" className={RESOURCE_ACTION} onClick={() => onExpand(activeId ?? undefined)}><Maximize2 className="size-3.5" /></button> : null}
      {actions}
    </ResourceHeader> : <>
    <PaneHeader className="course-pane__header" onPaneDragStart={onPaneDragStart}>
      {course ? <button type="button" data-no-drag aria-label={sidebarLabel} title={sidebarLabel} aria-expanded={sidebarOpen} aria-controls={sidebarId} className="course-pane__sidebar-toggle" onClick={() => setSidebarOpen((open) => !open)}><SidebarLeft className="size-3.5" /></button> : null}
      <Mortarboard className={`size-3.5 shrink-0 ${focused ? "text-content/70" : "text-content/40"}`} /><span className="course-pane__title">{course?.title ?? title ?? "Course"}</span>{onExpand ? <button type="button" aria-label="Expand course to pane" title="Expand to pane" className="course-pane__close" onClick={() => onExpand(activeId ?? undefined)}><Maximize2 className="size-3.5" /></button> : null}{actions ? <span data-no-drag className="flex shrink-0 items-center gap-1">{actions}</span> : null}<button type="button" data-no-drag aria-label="Close course" className="course-pane__close" onClick={onClose}><X className="size-3.5" /></button>
    </PaneHeader>
    </>}
    {course ? <>
      <div className="course-pane__body">{!onBack ? <CourseNav course={course} activeId={activeId} onSelect={select} id={sidebarId} hidden={!sidebarOpen} /> : null}<div className="course-pane__right"><div className="course-pane__reader"><main ref={scrollRef} className="course-pane__main"><CourseContent course={course} activeId={activeId} />{nextItem && !onBack ? <div className="course-pane__content"><div className="course-pane__next-card"><div className="course-pane__next-card-info"><span className="course-pane__next-card-label">Next {reading ? "lesson" : "step"}</span><h4 className="course-pane__next-card-title">{nextItem.title}</h4></div><button type="button" className="course-button course-button--primary" onClick={() => { if (activeId && activeStatus !== "mastered") void markStatus(activeId, "mastered"); select(nextItem.id); }}>{activeStatus === "mastered" ? (reading ? "Next lesson →" : "Next step →") : (reading ? "Mark read & Next →" : "Complete & Next →")}</button></div></div> : null}</main>{reading ? <CourseToc scrollRef={scrollRef} /> : null}</div><footer className="course-pane__status-actions"><span className="course-pane__status-label">{items.length > 0 && currentIndex >= 0 ? <span className="course-pane__position">{String(currentIndex + 1).padStart(2, "0")} / {String(items.length).padStart(2, "0")} · </span> : null}{reading ? READING_STATUS[activeStatus] : activeStatus}</span><button type="button" className="course-button course-button--quiet" title={reading ? "Test understanding with agent" : "Discuss step with agent"} onClick={discuss}><MessageSquarePlus className="size-3.5" />{reading ? "Test understanding" : "Discuss step"}</button>{activeStatus === "mastered" && activeId ? <button type="button" className="course-button course-button--quiet course-pane__reset-button" disabled={saving.has(activeId)} onClick={() => void markStatus(activeId, "untouched")} title="Reset progress for this item">Reset</button> : null}<button type="button" className={`course-button${activeStatus !== "mastered" ? " course-button--primary" : ""}`} disabled={!activeId || saving.has(activeId) || activeStatus === "mastered"} onClick={() => activeId && void markStatus(activeId, "mastered")}>{activeId && saving.has(activeId) ? "Saving…" : activeStatus === "mastered" ? (reading ? "Read ✓" : "Mastered ✓") : reading ? "Mark as read" : "Mark as mastered"}</button>{nextItem ? <button type="button" className="course-button" title={`Continue to: ${nextItem.title}`} onClick={() => { if (activeId && activeStatus !== "mastered") void markStatus(activeId, "mastered"); select(nextItem.id); }}><span>Next →</span></button> : null}{actionError ? <p role="alert" className="course-error">{actionError}</p> : null}{[...syncFailures.values()].map((failure) => <div key={failure.itemId} role="alert" className="course-error">Progress saved for {items.find((item) => item.id === failure.itemId)?.title ?? failure.itemId}, but the concept map could not update: {failure.message}<button type="button" className="course-button course-button--quiet" disabled={saving.has(failure.itemId)} onClick={() => void retrySync(failure)}>Retry map update</button></div>)}</footer></div></div>
    </> : <div className="course-pane__empty" role={loaded.scope === scope && loaded.error ? "alert" : undefined}><p>{loaded.scope === scope ? loaded.error ?? "Opening course…" : "Opening course…"}</p>{loaded.scope === scope && loaded.error ? <button type="button" className="course-button" onClick={() => setReload((value) => value + 1)}>Retry</button> : null}</div>}
  </aside>;
}

function StatusMark({ status }: { status: LearningStatus }) {
  return <span className={`course-status course-status--${status}`} aria-hidden="true">{status === "mastered" ? "✓" : ""}</span>;
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
      <CourseNav course={course} activeId={activeId} onSelect={(item) => { onSelect(item); close(); }} />
    </Popover> : null}
  </>;
}

function CourseNav({ course, activeId, onSelect, id, hidden }: { course: CourseWithProgress; activeId: string | null; onSelect: (id: string) => void; id?: string; hidden?: boolean }) {
  const items = courseItems(course.data);
  const reading = course.data.engine === "reading";
  const mastered = items.filter((item) => course.progress.get(item.id) === "mastered").length;
  const row = (item: { id: string; title: string }, index: number) => {
    const status = course.progress.get(item.id) ?? "untouched";
    return <li key={item.id}><button type="button" className={`course-pane__nav-item${activeId === item.id ? " course-pane__nav-item--active" : ""}`} aria-current={activeId === item.id ? "step" : undefined} aria-label={`${item.title}, ${reading ? READING_STATUS[status] : status}`} onClick={() => onSelect(item.id)}><StatusMark status={status} /><span className="course-pane__nav-label"><span className="course-pane__step-number">{String(index + 1).padStart(2, "0")}</span>{item.title}</span></button></li>;
  };
  // Lessons are numbered through the whole course, in the order shown.
  let number = 0;
  return <nav id={id} hidden={hidden} className="course-pane__nav" aria-label="Course navigation"><div className="course-pane__nav-intro">{reading ? null : <span>Build Your Own</span>}<p>{mastered} / {items.length} {reading ? "read" : "mastered"}</p><progress max={items.length} value={mastered} aria-label="Course completion" /></div>{course.data.engine === "reading"
    ? course.data.chapters.map((chapter, at) => <section key={at} className="course-pane__chapter" aria-label={chapter.title}><h3 className="course-pane__chapter-title"><span className="course-pane__chapter-dot" style={{ background: `var(--course-chapter-${at % 6})` }} aria-hidden="true" />{chapter.title}</h3><ol>{chapter.lessons.map((lesson) => row(lesson, number++))}</ol></section>)
    : <ol>{items.map(row)}</ol>}</nav>;
}

function CourseContent({ course, activeId }: { course: CourseWithProgress; activeId: string | null }) {
  if (course.data.engine === "build-your-own") {
    const step = course.data.steps.find((item) => item.id === activeId);
    return step ? <article className="course-pane__content" key={step.id}><h2>{step.title}</h2><p className="course-pane__summary">{step.summary}</p><DiffCard {...step} id={`${course.id}-${step.id}`} /><AgentMarkdown text={step.explanation} wholeDocument /></article> : null;
  }
  const lesson = course.data.chapters.flatMap((chapter) => chapter.lessons).find((item) => item.id === activeId);
  if (!lesson) return null;
  return lesson.file !== undefined ? <LessonFile lesson={lesson} /> : <LessonDocument agentId={course.agentId} lesson={lesson} />;
}

/** A lesson read from a file, such as a PDF: it opens in its own pane, where it can be highlighted. */
function LessonFile({ lesson }: { lesson: CourseLesson }) {
  const file = lesson.file!;
  const name = file.split(/[\\/]/).pop() || file;
  return <article className="course-pane__content" key={lesson.id}><h2>{lesson.title}</h2><p className="course-pane__summary" title={file}>{name}{lesson.pages ? ` · ${lesson.pages[0] === lesson.pages[1] ? `page ${lesson.pages[0]}` : `pages ${lesson.pages[0]}–${lesson.pages[1]}`}` : ""}</p><button type="button" className="course-button" onClick={() => requestOpenFile(file, lesson.pages ? { page: lesson.pages[0] } : undefined)}>Open to read</button></article>;
}

/** A lesson read from the agent's library: the document itself, from the lesson's heading. */
function LessonDocument({ agentId, lesson }: { agentId: string; lesson: CourseLesson }) {
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
  if (!shown) return <p className="course-pane__relations">Opening…</p>;
  if (!shown.document) return <article className="course-pane__content"><h2>{lesson.title}</h2><p className="course-error" role="alert">{shown.error ? `Could not open this lesson's document: ${shown.error}` : `This lesson's document (${id}) is not in the library. Ask the agent to save it again.`}</p></article>;
  return <article className="course-pane__content course-pane__reading" key={lesson.id}><DocumentBody document={shown.document} agentId={agentId} section={lesson.section} /></article>;
}
