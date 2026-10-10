import { invoke } from "@tauri-apps/api/core";
import { useContext, useEffect, useMemo, useRef, useState } from "react";
import { ChevronRight, CircleDashed, Mortarboard } from "../../../shared/ui/icons";
import { openCourse, parseCourse } from "../model/course";
import { WidgetHostContext } from "../model/widgets";
import "./CoursePane.css";

export { OPEN_COURSE_EVENT, openCourse, type OpenCourseDetail } from "../model/course";

export function CourseCard({ source, incomplete }: { source: string; incomplete: boolean }) {
  const result = useMemo(() => parseCourse(source), [source]);
  const host = useContext(WidgetHostContext);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const current = useRef({ source, owner: host?.owner.id, mounted: true });
  current.current.source = source;
  current.current.owner = host?.owner.id;
  useEffect(() => { current.current.mounted = true; return () => { current.current.mounted = false; }; }, []);
  useEffect(() => { setError(null); setBusy(false); }, [source, host?.owner.id]);

  if (incomplete) {
    const count = (source.match(/"id"\s*:\s*"[^"\n]+"/g) ?? []).length;
    return <div data-card="course" className="course-card course-card--generating" aria-busy="true"><CircleDashed className="size-4" /><span>Generating course…{count ? ` ${count} item${count === 1 ? "" : "s"} so far` : ""}</span></div>;
  }
  if (!result.course) return <div data-card="course" className="course-card"><p role="alert" className="course-error">{result.error}</p><details className="course-source"><summary>View source</summary><pre>{source}</pre></details></div>;
  const { course } = result;
  const count = course.data.engine === "build-your-own" ? course.data.steps.length : course.data.concepts.length;
  const kind = course.engine === "build-your-own" ? "step" : "concept";
  const handleOpen = async () => {
    if (!host || busy) return;
    const owner = host.owner.id;
    setBusy(true);
    setError(null);
    try {
      await invoke("course_upsert", { course: { id: course.id, agentId: owner, engine: course.engine, title: course.title, dataJson: JSON.stringify(course.data) } });
      if (current.current.mounted && current.current.source === source && current.current.owner === owner) {
        openCourse({ courseId: course.id, agentId: owner, title: course.title, sourceSessionId: host.sourceSessionId });
      }
    } catch (cause) {
      if (current.current.mounted && current.current.source === source && current.current.owner === owner) setError(`Could not open course: ${cause instanceof Error ? cause.message : String(cause)}`);
    } finally {
      if (current.current.mounted && current.current.source === source && current.current.owner === owner) setBusy(false);
    }
  };
  return <div data-card="course" className="course-card">
    <div className="course-card__heading"><Mortarboard className="size-5" /><span className="course-card__engine-badge">{course.engine === "build-your-own" ? "Build Your Own" : "Domain Navigation"}</span></div>
    <h3 className="course-card__title">{course.title}</h3>
    <div className="course-card__footer"><span>{count} {kind}{count === 1 ? "" : "s"}</span><button type="button" disabled={!host || busy} className="course-button" onClick={() => void handleOpen()}>{busy ? "Opening…" : "Open Course"}<ChevronRight className="size-3.5" /></button></div>
    {!host ? <p className="course-card__hint">Open this course in its original conversation to begin.</p> : null}
    {error ? <p role="alert" className="course-error">{error}</p> : null}
  </div>;
}
