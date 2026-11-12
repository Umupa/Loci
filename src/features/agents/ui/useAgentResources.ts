import { useEffect, useState } from "react";
import { COURSES_CHANGED_EVENT, loadCourseSummaries, type CourseChangedDetail, type CourseSummary } from "../../learning/model/course";
import { PROGRESS_EVENT } from "../../learning/ui/CoursePane";
import { listAgentNotes, NOTES_CHANGED_EVENT, type Note } from "../../notes";
import { listAgentDocuments, subscribeAgentDocuments, type StoredDocument } from "../model/agentDocuments";

type Resources = { courses: CourseSummary[]; documents: StoredDocument[]; notes: Note[] };
type Kind = keyof Resources;
type Snapshot = { agentId: string; data: Partial<Resources>; errors: Partial<Record<Kind, string>> };

/** Metadata lists refresh independently, and late replies cannot cross agent boundaries. */
export function useAgentResources(agentId: string) {
  const [snapshot, setSnapshot] = useState<Snapshot>({ agentId, data: {}, errors: {} });
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    const requests: Record<Kind, number> = { courses: 0, documents: 0, notes: 0 };
    const readers = {
      courses: async () => (await loadCourseSummaries()).filter((course) => course.agentId === agentId),
      documents: () => listAgentDocuments(agentId),
      notes: () => listAgentNotes(agentId),
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
    all();
    const stopDocuments = subscribeAgentDocuments(() => load("documents"));
    window.addEventListener(COURSES_CHANGED_EVENT, courses);
    window.addEventListener(PROGRESS_EVENT, courses);
    window.addEventListener(NOTES_CHANGED_EVENT, notes);
    window.addEventListener("focus", all);
    return () => {
      live = false;
      stopDocuments();
      window.removeEventListener(COURSES_CHANGED_EVENT, courses);
      window.removeEventListener(PROGRESS_EVENT, courses);
      window.removeEventListener(NOTES_CHANGED_EVENT, notes);
      window.removeEventListener("focus", all);
    };
  }, [agentId, revision]);
  const shown: Snapshot = snapshot.agentId === agentId ? snapshot : { agentId, data: {}, errors: {} };
  return { ...shown, reload: () => setRevision((value) => value + 1) };
}
