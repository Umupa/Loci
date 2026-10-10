import { invoke } from "@tauri-apps/api/core";
import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { GripVertical, MessageSquarePlus, Mortarboard, X } from "../../../shared/ui/icons";
import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { courseItems, loadCourse, NAVIGATE_CONCEPT_EVENT, OPEN_COURSE_EVENT, type CourseConcept, type CourseWithProgress, type LearningStatus, type NavigateConceptDetail, type OpenCourseDetail } from "../model/course";
import { upsertLearningWidget } from "../model/learningStore";
import { openLearningSource } from "../model/navigation";
import { askAboutWidget } from "../model/widgetContext";
import { adoptStoredWidget, useWidget } from "../model/widgetRuntime";
import { parseWidget, widgetRef } from "../model/widgets";
import type { StoredWidget } from "../model/types";
import { DiffCard } from "./DiffCard";
import { WidgetFrame } from "./WidgetFrame";
import "./CoursePane.css";

type Props = {
  courseId: string; agentId: string; title?: string; sourceSessionId?: string;
  focused: boolean; onFocus: () => void; onClose: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
};
type SyncFailure = { itemId: string; status: LearningStatus; message: string };
const PROGRESS_EVENT = "loci:course-progress";
type ProgressDetail = { courseId: string; agentId: string; itemId: string; status: LearningStatus };
const message = (cause: unknown) => cause instanceof Error ? cause.message : String(cause);

export function CoursePane({ courseId, agentId, title, sourceSessionId, focused, onFocus, onClose, onPaneDragStart }: Props) {
  const scope = JSON.stringify([agentId, courseId]);
  const [loaded, setLoaded] = useState<{ scope: string; course: CourseWithProgress | null; error: string | null }>({ scope, course: null, error: null });
  const [reload, setReload] = useState(0);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [saving, setSaving] = useState<Set<string>>(new Set());
  const [actionError, setActionError] = useState<string | null>(null);
  const [syncFailures, setSyncFailures] = useState<Map<string, SyncFailure>>(new Map());
  const pendingWrites = useRef(new Map<string, { scope: string; itemId: string }>());
  const pendingConcept = useRef<NavigateConceptDetail | null>(null);
  const pendingProgress = useRef<{ scope: string; items: Map<string, LearningStatus> }>({ scope, items: new Map() });
  const courseLoad = useRef<{ scope: string; promise: Promise<CourseWithProgress | null> } | null>(null);
  const generation = useRef(0);
  const selected = useRef<{ scope: string; id: string | null }>({ scope, id: null });
  const latest = useRef({ scope, course: loaded.course, mounted: true });
  const course = loaded.scope === scope ? loaded.course : null;
  if (course) selected.current = { scope, id: activeId };
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
      const navigable = pending?.courseId === found.id && (!pending.agentId || pending.agentId === found.agentId) && found.data.engine === "domain-navigation" && (!pending.canvasId || pending.canvasId === found.data.canvasId) && items.some((item) => item.id === pending.conceptId);
      pendingConcept.current = null;
      const previousSelection = selected.current.scope === scope && items.some((item) => item.id === selected.current.id) ? selected.current.id : null;
      setActiveId(navigable ? pending!.conceptId : previousSelection ?? items.find((item) => found.progress.get(item.id) !== "mastered")?.id ?? items[0].id);
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
      if (found.data.engine !== "domain-navigation" || (detail.canvasId && detail.canvasId !== found.data.canvasId)) return;
      if (found.data.concepts.some((concept) => concept.id === detail.conceptId)) setActiveId(detail.conceptId);
    };
    const opened = (event: Event) => {
      const detail = (event as CustomEvent<OpenCourseDetail>).detail;
      if (detail?.courseId === courseId && detail.agentId === agentId) setReload((value) => value + 1);
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
    window.addEventListener(PROGRESS_EVENT, progressed);
    return () => { window.removeEventListener(NAVIGATE_CONCEPT_EVENT, navigate); window.removeEventListener(OPEN_COURSE_EVENT, opened); window.removeEventListener(PROGRESS_EVENT, progressed); };
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
      if (!found || found.data.engine !== "domain-navigation" || !found.data.canvasId || !found.data.concepts.some((concept) => concept.id === itemId)) return;
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
    const progress = courseItems(course.data).map((item) => ({ id: item.id, title: item.title, status: course.progress.get(item.id) ?? "untouched" }));
    const canvasId = course.data.engine === "domain-navigation" ? course.data.canvasId : undefined;
    const itemKind = course.data.engine === "build-your-own" ? "step" : "concept";
    requestAddToChat(`I'm studying course "${course.title}" (courseId: ${course.id}). Current ${itemKind}: "${currentItem.title}" (${activeId}), status: ${course.progress.get(activeId) ?? "untouched"}. Please explain the current content in the context of my progress and suggest what to do next.${canvasId ? `\nConcept map canvasId: ${canvasId}; please update node colors to reflect mastered concepts.` : ""}\n\nProgress:\n${JSON.stringify(progress, null, 2)}`, "plain", { targetSessionId });
    setActionError(null);
  };

  return <aside aria-label={course?.title ?? title ?? "Course"} className="course-pane" onPointerDown={() => { if (!focused) onFocus(); }}>
    <header className={`course-pane__header${onPaneDragStart ? " course-pane__header--draggable" : ""}`} onPointerDown={(event) => { if (!(event.target as HTMLElement).closest("[data-no-drag]")) onPaneDragStart?.(event); }}>
      {onPaneDragStart ? <GripVertical className="size-3.5 shrink-0 text-content/35" /> : null}<Mortarboard className={`size-3.5 shrink-0 ${focused ? "text-content/70" : "text-content/40"}`} /><span className="course-pane__title">{course?.title ?? title ?? "Course"}</span><button type="button" data-no-drag aria-label="Close course" className="course-pane__close" onClick={onClose}><X className="size-3.5" /></button>
    </header>
    {course ? <>
      <div className="course-pane__body"><CourseNav course={course} activeId={activeId} onSelect={setActiveId} /><div className="course-pane__right"><main className="course-pane__main"><CourseContent course={course} activeId={activeId} sourceSessionId={sourceSessionId} /></main><footer className="course-pane__status-actions"><span className="course-pane__status-label">{course.progress.get(activeId ?? "") ?? "untouched"}</span><button type="button" className="course-button" disabled={!activeId || saving.has(activeId) || course.progress.get(activeId) === "mastered"} onClick={() => activeId && void markStatus(activeId, "mastered")}>{activeId && saving.has(activeId) ? "Saving…" : course.progress.get(activeId ?? "") === "mastered" ? "Mastered ✓" : "Mark as mastered"}</button>{activeId && (course.progress.get(activeId) ?? "untouched") === "untouched" ? <button type="button" className="course-button course-button--quiet" disabled={saving.has(activeId)} onClick={() => void markStatus(activeId, "learning")}>Mark as learning</button> : activeId ? <button type="button" className="course-button course-button--quiet" disabled={saving.has(activeId)} onClick={() => void markStatus(activeId, "untouched")}>Reset progress</button> : null}<button type="button" className="course-button course-button--quiet" onClick={discuss}><MessageSquarePlus className="size-3.5" />Discuss progress</button>{actionError ? <p role="alert" className="course-error">{actionError}</p> : null}{[...syncFailures.values()].map((failure) => <div key={failure.itemId} role="alert" className="course-error">Progress saved for {courseItems(course.data).find((item) => item.id === failure.itemId)?.title ?? failure.itemId}, but the concept map could not update: {failure.message}<button type="button" className="course-button course-button--quiet" disabled={saving.has(failure.itemId)} onClick={() => void retrySync(failure)}>Retry map update</button></div>)}</footer></div></div>
    </> : <div className="course-pane__empty" role={loaded.scope === scope && loaded.error ? "alert" : undefined}><p>{loaded.scope === scope ? loaded.error ?? "Opening course…" : "Opening course…"}</p>{loaded.scope === scope && loaded.error ? <button type="button" className="course-button" onClick={() => setReload((value) => value + 1)}>Retry</button> : null}</div>}
  </aside>;
}

function CourseNav({ course, activeId, onSelect }: { course: CourseWithProgress; activeId: string | null; onSelect: (id: string) => void }) {
  const items = courseItems(course.data);
  const mastered = items.filter((item) => course.progress.get(item.id) === "mastered").length;
  return <nav className="course-pane__nav" aria-label="Course navigation"><div className="course-pane__nav-intro"><span>{course.data.engine === "build-your-own" ? "Build Your Own" : "Domain Navigation"}</span><p>{mastered} / {items.length} mastered</p><progress max={items.length} value={mastered} aria-label="Course completion" /></div><ol>{items.map((item, index) => {
    const status = course.progress.get(item.id) ?? "untouched";
    return <li key={item.id}><button type="button" className={`course-pane__nav-item${activeId === item.id ? " course-pane__nav-item--active" : ""}`} aria-current={activeId === item.id ? "step" : undefined} aria-label={`${item.title}, ${status}`} onClick={() => onSelect(item.id)}><span className={`course-status course-status--${status}`} aria-hidden="true">{status === "mastered" ? "✓" : ""}</span><span className="course-pane__nav-label">{course.data.engine === "build-your-own" ? <span className="course-pane__step-number">{String(index + 1).padStart(2, "0")}</span> : null}{item.title}</span></button></li>;
  })}</ol></nav>;
}

function CourseContent({ course, activeId, sourceSessionId }: { course: CourseWithProgress; activeId: string | null; sourceSessionId?: string }) {
  if (course.data.engine === "build-your-own") {
    const step = course.data.steps.find((item) => item.id === activeId);
    return step ? <article className="course-pane__content" key={step.id}><h2>{step.title}</h2><p className="course-pane__summary">{step.summary}</p><DiffCard {...step} id={`${course.id}-${step.id}`} /><AgentMarkdown text={step.explanation} wholeDocument /></article> : null;
  }
  const concept = course.data.concepts.find((item) => item.id === activeId);
  if (!concept) return null;
  const titles = new Map(course.data.concepts.map((item) => [item.id, item.title]));
  return <article className="course-pane__content" key={concept.id}><h2>{concept.title}</h2>{concept.prerequisites.length ? <p className="course-pane__relations">Prerequisites: {concept.prerequisites.map((id) => titles.get(id)).join(" · ")}</p> : null}<AgentMarkdown text={concept.content} wholeDocument />{concept.simulationHtml ? <CourseSimulation course={course} concept={concept} sourceSessionId={sourceSessionId} /> : null}{concept.leadsTo.length ? <p className="course-pane__relations">Leads to: {concept.leadsTo.map((id) => titles.get(id)).join(" · ")}</p> : null}</article>;
}

function CourseSimulation({ course, concept, sourceSessionId }: { course: CourseWithProgress; concept: CourseConcept; sourceSessionId?: string }) {
  const [stored, setStored] = useState<StoredWidget | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let current = true;
    // The native widget source_at comparison must follow course revisions,
    // even when an older IPC write arrives after a newer simulation version.
    const sourceAt = course.updatedAt;
    setStored(null); setError(null);
    void (async () => {
      const agent = findAgent(course.agentId);
      const sessionId = agent?.sessionId ?? sourceSessionId ?? course.agentId;
      // Widget ids have an 80-character native limit. Hash the course/concept
      // tuple so repeated concept ids and long course ids remain independent.
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify([course.id, concept.id])));
      if (!current) return;
      const widgetId = `course-${Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
      const parsed = parseWidget(`---\nid: ${widgetId}\ntitle: Simulation\n---\n${concept.simulationHtml}`);
      if (!parsed.spec) throw new Error(parsed.error);
      const owner = { kind: agent ? "agent" as const : "session" as const, id: course.agentId };
      const widget = await upsertLearningWidget(owner, { ...parsed.spec, title: concept.title.slice(0, 200) }, sessionId, widgetId, sourceAt);
      if (current) { adoptStoredWidget(widget); setStored(widget); }
    })().catch((cause: unknown) => { if (current) setError(`Could not open simulation: ${message(cause)}`); });
    return () => { current = false; };
  }, [course.id, course.agentId, course.updatedAt, concept.id, concept.title, concept.simulationHtml, sourceSessionId]);
  return <section className="course-pane__simulation" aria-label={`${concept.title} simulation`}>{stored ? <ReadySimulation stored={stored} /> : <p className={error ? "course-error" : "course-pane__relations"} role={error ? "alert" : undefined}>{error ?? "Opening simulation…"}</p>}</section>;
}

function ReadySimulation({ stored }: { stored: StoredWidget }) {
  const ref = useMemo(() => widgetRef(stored), [stored]);
  const widget = useWidget(ref, stored, stored.sourceSessionId);
  return <WidgetFrame widget={widget} onAsk={(text, selection) => askAboutWidget(widget, text, selection)} onOpenSource={openLearningSource} />;
}
