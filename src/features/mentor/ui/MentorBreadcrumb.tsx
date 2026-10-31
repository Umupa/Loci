import { ChevronRight } from "../../../shared/ui/icons";
import { agentLook, type Agent } from "../../agents/model/agent";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { fileName, type MentorLesson, type MentorPage } from "../model/mentorPage";
import type { LibraryData } from "./MentorLibrary";

/** The titles from the mentor down to what is being read. */
export function mentorCrumbs(agent: Agent, page: MentorPage | undefined, lesson: MentorLesson | undefined, data: LibraryData, sessionTitle: (id: string) => string = () => "Conversation"): string[] {
  const crumbs = [agentLook(agent).name];
  if (page?.kind === "course") {
    crumbs.push(data.courses?.find((course) => course.id === page.course.courseId)?.title ?? page.course.title ?? page.course.courseId);
    if (lesson) crumbs.push(lesson.title);
  } else if (page?.kind === "document") crumbs.push(data.documents?.find((document) => document.id === page.document.id)?.title ?? page.document.title);
  else if (page?.kind === "note") crumbs.push(data.notes?.find((note) => note.id === page.id)?.title || "Note");
  else if (page?.kind === "canvas") crumbs.push(data.canvases?.find((canvas) => canvas.id === page.id)?.title || "Drawing");
  else if (page?.kind === "file") crumbs.push(fileName(page.path));
  else if (page?.kind === "session") crumbs.push(sessionTitle(page.id));
  return crumbs;
}

export function MentorBreadcrumb({ agent, crumbs }: { agent: Agent; crumbs: readonly string[] }) {
  return <ol className="mentor-breadcrumb" aria-label="Location" data-tauri-drag-region="deep">
    {crumbs.map((crumb, index) => <li key={index} className="mentor-breadcrumb-item" aria-current={index === crumbs.length - 1 ? "page" : undefined} data-tauri-drag-region="deep">
      {index === 0 ? <AgentAvatar name={agent.avatar} color={agent.color} className="size-4 shrink-0" /> : <ChevronRight aria-hidden className="mentor-breadcrumb-separator" />}
      <span className="min-w-0 truncate" title={crumb} data-tauri-drag-region="deep">{crumb}</span>
    </li>)}
  </ol>;
}
