import { lazy, Suspense, type ReactNode } from "react";
import { basename } from "../../../platform/tauri/fs";
import type { OpenFileFn } from "../../files/model/filePlace";
import { CoursePane } from "../../learning/ui/CoursePane";
import { NotePane } from "../../notes/ui/NotePane";
import { agentLook, type Agent } from "../../agents/model/agent";
import { AgentDocumentReader } from "../../agents/ui/AgentDocumentReader";
import { ResourceBar, ResourceHeader } from "../../../shared/ui/ResourceHeader";
import type { MentorLesson, MentorPage } from "../model/mentorPage";
import { LearningMap } from "./LearningMap";

const FilePane = lazy(() => import("../../files/ui/FilePane").then((m) => ({ default: m.FilePane })));

type Props = {
  agent: Agent;
  page?: MentorPage;
  /** Bumped by every explicit opening, so the same lesson can be asked for again. */
  request: number;
  onClose: () => void;
  onLessonChange: (lesson: MentorLesson | null) => void;
  onBeforeLeave: (save: (() => Promise<boolean>) | null) => void;
  onOpenFile: OpenFileFn;
  /** A conversation shown as the reader, with the app's session wiring. */
  renderSession: (id: string) => ReactNode;
  /** A conversation's title, for its reader header. */
  sessionTitle: (id: string) => string;
  /** Opens a page in this reader, as the learning map does with a lesson. */
  onOpen: (page: MentorPage) => void;
};

const noop = () => {};

/** The reader's own word for a page whose code is still on its way. */
function ReaderLoading({ label }: { label: string }) {
  return <><ResourceBar /><div role="status" className="mentor-reader-empty"><p>{label}</p></div></>;
}

/** The one reader in the middle of a mentor's workspace. Whatever opens replaces it. */
export function MentorReader({ agent, page, request, onClose, onLessonChange, onBeforeLeave, onOpenFile, renderSession, sessionTitle, onOpen }: Props) {
  const mentorName = agentLook(agent).name;
  if (!page) return <>
    <ResourceBar />
    <LearningMap agent={agent} onOpen={onOpen} />
  </>;
  if (page.kind === "course") return <CoursePane key={`${agent.id}/${page.course.courseId}`} {...page.course} openRequest={request}
    sourceSessionId={agent.sessionId} reader focused onFocus={noop} onClose={onClose} onLessonChange={onLessonChange} />;
  if (page.kind === "document") return <AgentDocumentReader key={`${agent.id}/${page.document.id}`} agentId={agent.id} document={page.document}
    reader focused onFocus={noop} onClose={onClose} />;
  if (page.kind === "note") return <NotePane key={page.id} noteId={page.id} agentId={agent.id}
    reader focused onFocus={noop} onClose={onClose} onBeforeLeave={onBeforeLeave} />;
  if (page.kind === "session") return <>
    <ResourceHeader title={sessionTitle(page.id)} onClose={onClose} />
    {renderSession(page.id)}
  </>;
  return <Suspense fallback={<ReaderLoading label={`Opening ${basename(page.path)}…`} />}><FilePane key={`${page.path}@${page.commit ?? ""}`} path={page.path} commit={page.commit} cwd="" preview={false} focused onFocus={noop} onPin={noop}
    onClose={onClose} onOpenFile={onOpenFile} onBeforeLeave={onBeforeLeave} askLabel={`Ask ${mentorName}`} chatName={mentorName} agentId={agent.id} reader /></Suspense>;
}
