import { useEffect, useState } from "react";
import { CANVASES_CHANGED_EVENT, loadCanvases, type Canvas } from "../../canvas/canvas";
import { COURSES_CHANGED_EVENT, loadCourseSummaries, type CourseChangedDetail, type CourseSummary } from "../../learning/model/course";
import { PROGRESS_EVENT } from "../../learning/ui/CoursePane";
import { listAgentNotes, NOTES_CHANGED_EVENT, type Note } from "../../notes";
import { agentCanvasScope } from "../model/agent";
import { listAgentDocuments, subscribeAgentDocuments, type StoredDocument } from "../model/agentDocuments";
import { subscribeAgentFiles } from "../model/agentFiles";
import { loadHabits, subscribeHabitsRunning, type Habit } from "../model/agentHabits";

type Resources = { courses: CourseSummary[]; documents: StoredDocument[]; notes: Note[]; habits: Habit[]; canvases: Canvas[] };
type Kind = keyof Resources;
type Snapshot = { agentId: string; data: Partial<Resources>; errors: Partial<Record<Kind, string>> };

/** Metadata lists refresh independently, and late replies cannot cross agent boundaries. */
export function useAgentResources(agentId: string) {
  const [snapshot, setSnapshot] = useState<Snapshot>({ agentId, data: {}, errors: {} });
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    const requests: Record<Kind, number> = { courses: 0, documents: 0, notes: 0, habits: 0, canvases: 0 };
    const readers = {
      courses: async () => (await loadCourseSummaries()).filter((course) => course.agentId === agentId),
      documents: () => listAgentDocuments(agentId),
      notes: () => listAgentNotes(agentId),
      habits: () => loadHabits(agentId),
      canvases: async () => (await loadCanvases(true)).filter((canvas) => canvas.cwd === agentCanvasScope(agentId)),
    };
    const load = (kind: Kind) => {
      const request = ++requests[kind];
      void readers[kind]().then((items) => {
        if (!live || request !== requests[kind]) return;
        setSnapshot((previous) => {
          const same = previous.agentId === agentId;
          return { agentId, data: { ...(same ? previous.data : {}), [kind]: items }, errors: { ...(same ? previous.errors : {}), [kind]: undefined } };
        });
      }, (cause) => {
        if (!live || request !== requests[kind]) return;
        setSnapshot((previous) => ({ agentId, data: previous.agentId === agentId ? previous.data : {}, errors: { ...(previous.agentId === agentId ? previous.errors : {}), [kind]: String(cause) } }));
      });
    };
    const all = () => { for (const kind of Object.keys(readers) as Kind[]) load(kind); };
    const courses = (event: Event) => {
      const detail = (event as CustomEvent<CourseChangedDetail>).detail;
      if (!detail?.agentId || detail.agentId === agentId) load("courses");
    };
    const notes = () => load("notes");
    const canvases = () => load("canvases");
    const habits = () => load("habits");
    all();
    const stopDocuments = subscribeAgentDocuments(() => load("documents"));
    const stopFiles = subscribeAgentFiles(habits);
    const stopRuns = subscribeHabitsRunning(habits);
    window.addEventListener(COURSES_CHANGED_EVENT, courses);
    window.addEventListener(PROGRESS_EVENT, courses);
    window.addEventListener(NOTES_CHANGED_EVENT, notes);
    window.addEventListener(CANVASES_CHANGED_EVENT, canvases);
    window.addEventListener("focus", all);
    const timer = window.setInterval(habits, 30_000);
    return () => {
      live = false;
      stopDocuments(); stopFiles(); stopRuns();
      window.removeEventListener(COURSES_CHANGED_EVENT, courses);
      window.removeEventListener(PROGRESS_EVENT, courses);
      window.removeEventListener(NOTES_CHANGED_EVENT, notes);
      window.removeEventListener(CANVASES_CHANGED_EVENT, canvases);
      window.removeEventListener("focus", all);
      window.clearInterval(timer);
    };
  }, [agentId, revision]);
  const shown: Snapshot = snapshot.agentId === agentId ? snapshot : { agentId, data: {}, errors: {} };
  return { ...shown, reload: () => setRevision((value) => value + 1) };
}
