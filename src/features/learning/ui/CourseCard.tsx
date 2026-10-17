import { useContext, useEffect, useMemo, useRef, useState } from "react";
import { ChevronRight, CircleDashed, Mortarboard } from "../../../shared/ui/icons";
import { courseItems, loadCourse, openCourse, parseCourse, parseCourseLink, saveCourse, type CourseData } from "../model/course";
import { CourseHostContext } from "../model/courseContext";
import "./CoursePane.css";

export { OPEN_COURSE_EVENT, openCourse, type OpenCourseDetail } from "../model/course";

type Shown = { id: string; title: string; engine: CourseData["engine"]; data: CourseData };

export function CourseCard({ source, incomplete }: { source: string; incomplete: boolean }) {
  const link = useMemo(() => parseCourseLink(source), [source]);
  const result = useMemo(() => (link ? null : parseCourse(source)), [link, source]);
  const host = useContext(CourseHostContext);
  // Courses live in an agent's library; an ordinary conversation can only preview one.
  const agentId = host?.agentId;
  const [stored, setStored] = useState<{ key: string; course: Shown | null; error?: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const current = useRef({ source, owner: agentId, mounted: true });
  current.current.source = source;
  current.current.owner = agentId;
  useEffect(() => { current.current.mounted = true; return () => { current.current.mounted = false; }; }, []);
  useEffect(() => { setError(null); setBusy(false); }, [source, agentId]);

  const linkKey = link && agentId ? `${agentId}/${link.id}` : null;
  useEffect(() => {
    if (!link || !agentId || !linkKey) return;
    let live = true;
    void loadCourse(link.id, agentId).then(
      (found) => { if (live) setStored({ key: linkKey, course: found && { id: found.id, title: found.title, engine: found.data.engine, data: found.data } }); },
      (cause: unknown) => { if (live) setStored({ key: linkKey, course: null, error: cause instanceof Error ? cause.message : String(cause) }); },
    );
    return () => { live = false; };
  }, [link, agentId, linkKey]);

  if (incomplete) {
    const count = (source.match(/"id"\s*:\s*"[^"\n]+"/g) ?? []).length;
    return <div data-card="course" className="course-card course-card--generating" aria-busy="true"><CircleDashed className="size-4" /><span>Generating course…{count ? ` ${count} item${count === 1 ? "" : "s"} so far` : ""}</span></div>;
  }
  if (result && !result.course) return <div data-card="course" className="course-card"><p role="alert" className="course-error">{result.error}</p><details className="course-source"><summary>View source</summary><pre>{source}</pre></details></div>;

  const linked = link && stored?.key === linkKey ? stored : null;
  const shown: Shown | null = result?.course ?? linked?.course ?? null;
  const title = shown?.title ?? link?.title ?? "Course";
  const handleOpen = async () => {
    if (!agentId || busy) return;
    const owner = agentId;
    const fresh = () => current.current.mounted && current.current.source === source && current.current.owner === owner;
    setBusy(true);
    setError(null);
    try {
      // A fence that still carries its body is saved when opened; a link already is.
      if (result?.course) await saveCourse(owner, result.course);
      if (fresh()) openCourse({ courseId: shown?.id ?? link!.id, agentId: owner, title, sourceSessionId: host?.sourceSessionId });
    } catch (cause) {
      if (fresh()) setError(`Could not open course: ${cause instanceof Error ? cause.message : String(cause)}`);
    } finally {
      if (fresh()) setBusy(false);
    }
  };

  const count = shown ? courseItems(shown.data).length : 0;
  const kind = shown?.engine === "build-your-own" ? "step" : "lesson";
  const chapters = shown?.data.engine === "reading" ? shown.data.chapters.length : 0;
  const missing = link && linked && !linked.course;
  const hint = !agentId
    ? "Courses belong to an agent. Ask an agent to write this one to keep it."
    : missing ? linked?.error ?? "This course is not in the agent's library." : null;
  if (agentId) return <div data-card="course" className="agent-course-attachment">
    <button type="button" className="agent-resource-chip" aria-label={`Open course ${title}`} title={`${chapters ? `${chapters} chapters · ` : ""}${count} ${kind}${count === 1 ? "" : "s"}`}
      disabled={busy || !!missing} onClick={() => void handleOpen()}><Mortarboard /><span>{busy ? "Opening…" : title}</span></button>
    {hint ? <p className="course-error">{hint}</p> : null}{error ? <p role="alert" className="course-error">{error}</p> : null}
  </div>;
  return <div data-card="course" className="course-card">
    <div className="course-card__heading"><Mortarboard className="size-5" /><span className="course-card__engine-badge">{shown?.engine === "build-your-own" ? "Build Your Own" : "Course"}</span></div>
    <h3 className="course-card__title">{title}</h3>
    <div className="course-card__footer"><span>{shown ? `${chapters ? `${chapters} chapter${chapters === 1 ? "" : "s"} · ` : ""}${count} ${kind}${count === 1 ? "" : "s"}` : ""}</span><button type="button" disabled={!agentId || busy || !!missing} className="course-button" onClick={() => void handleOpen()}>{busy ? "Opening…" : "Open Course"}<ChevronRight className="size-3.5" /></button></div>
    {hint ? <p className="course-card__hint">{hint}</p> : null}
    {error ? <p role="alert" className="course-error">{error}</p> : null}
  </div>;
}
