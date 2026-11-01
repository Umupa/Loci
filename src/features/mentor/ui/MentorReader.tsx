import { lazy, Suspense, type ReactNode } from "react";
import { basename } from "../../../platform/tauri/fs";
import { peekCanvases, type Canvas } from "../../canvas/canvas";
import type { OpenFileFn } from "../../files/model/filePlace";
import { CoursePane } from "../../learning/ui/CoursePane";
import { NotePane } from "../../notes/ui/NotePane";
import { agentLook, type Agent } from "../../agents/model/agent";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { AgentDocumentReader } from "../../agents/ui/AgentDocumentReader";
import { ResourceBar, ResourceHeader } from "../../../shared/ui/ResourceHeader";
import type { MentorLesson, MentorPage } from "../model/mentorPage";

const CanvasPane = lazy(() => import("../../canvas/ui/CanvasPane").then((m) => ({ default: m.CanvasPane })));
const FilePane = lazy(() => import("../../files/ui/FilePane").then((m) => ({ default: m.FilePane })));

type Props = {
  agent: Agent;
  page?: MentorPage;
  /** Bumped by every explicit opening, so the same lesson can be asked for again. */
  request: number;
  canvases: readonly Canvas[];
  onClose: () => void;
  onLessonChange: (lesson: MentorLesson | null) => void;
  onBeforeLeave: (save: (() => Promise<boolean>) | null) => void;
  onCanvasAddToChat: (text: string) => void;
  onCanvasTitleChange: (id: string, title: string) => void;
  onOpenFile: OpenFileFn;
  /** A conversation shown as the reader, with the app's session wiring. */
  renderSession: (id: string) => ReactNode;
  /** A conversation's title, for its reader header. */
  sessionTitle: (id: string) => string;
};

const noop = () => {};

/** The reader's own word for a page whose code is still on its way. */
function ReaderLoading({ label }: { label: string }) {
  return <><ResourceBar /><div role="status" className="mentor-reader-empty"><p>{label}</p></div></>;
}

/** The one reader in the middle of a mentor's workspace. Whatever opens replaces it. */
export function MentorReader({ agent, page, request, canvases, onClose, onLessonChange, onBeforeLeave, onCanvasAddToChat, onCanvasTitleChange, onOpenFile, renderSession, sessionTitle }: Props) {
  const mentorName = agentLook(agent).name;
  if (!page) return <>
    <ResourceBar />
    <div className="mentor-reader-empty" data-tauri-drag-region="deep">
      <p>Open a lesson, a source, a note or a canvas from the library, or ask {agent.name || "your mentor"} to prepare one.</p>
    </div>
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
  if (page.kind === "canvas") {
    const canvas = canvases.find((entry) => entry.id === page.id);
    if (canvas) return <Suspense fallback={<ReaderLoading label="Opening drawing…" />}><CanvasPane key={canvas.id} canvas={canvas} reader focused onFocus={noop} onClose={onClose}
      onAddToChat={onCanvasAddToChat} chatTarget="agent" chatName={mentorName} chatIcon={<AgentAvatar name={agent.avatar} color={agent.color} className="size-4 shrink-0" />}
      onTitleChange={onCanvasTitleChange} /></Suspense>;
    // The app lists drawings after launch. Until that list is known, a remembered
    // drawing is opening, not gone: offering Close here would forget the page.
    if (!canvases.length && !peekCanvases()) return <ReaderLoading label="Opening drawing…" />;
    return <><ResourceBar /><div role="status" className="mentor-reader-empty"><p>This drawing is no longer available. <button type="button" className="underline" onClick={onClose}>Close</button></p></div></>;
  }
  return <Suspense fallback={<ReaderLoading label={`Opening ${basename(page.path)}…`} />}><FilePane key={page.path} path={page.path} cwd="" preview={false} focused onFocus={noop} onPin={noop}
    onClose={onClose} onOpenFile={onOpenFile} onBeforeLeave={onBeforeLeave} askLabel={`Ask ${mentorName}`} chatName={mentorName} reader /></Suspense>;
}
