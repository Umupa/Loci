import { lazy, Suspense } from "react";
import type { Canvas } from "../../canvas/canvas";
import type { OpenFileFn } from "../../files/model/filePlace";
import { CoursePane } from "../../learning/ui/CoursePane";
import { NotePane } from "../../notes/ui/NotePane";
import type { RecentProject } from "../../projects/model/recents";
import type { Agent } from "../../agents/model/agent";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { AgentDocumentReader } from "../../agents/ui/AgentDocumentReader";
import type { MentorLesson, MentorPage } from "../model/mentorPage";

const CanvasPane = lazy(() => import("../../canvas/ui/CanvasPane").then((m) => ({ default: m.CanvasPane })));
const FilePane = lazy(() => import("../../files/ui/FilePane").then((m) => ({ default: m.FilePane })));

type Props = {
  agent: Agent;
  page?: MentorPage;
  /** Bumped by every explicit opening, so the same lesson can be asked for again. */
  request: number;
  recents: readonly RecentProject[];
  canvases: readonly Canvas[];
  onClose: () => void;
  onLessonChange: (lesson: MentorLesson | null) => void;
  onBeforeLeave: (save: (() => Promise<boolean>) | null) => void;
  onCanvasAddToChat: (text: string) => void;
  onCanvasTitleChange: (id: string, title: string) => void;
  onOpenFile: OpenFileFn;
};

const noop = () => {};

/** The one reader in the middle of a mentor's workspace. Whatever opens replaces it. */
export function MentorReader({ agent, page, request, recents, canvases, onClose, onLessonChange, onBeforeLeave, onCanvasAddToChat, onCanvasTitleChange, onOpenFile }: Props) {
  if (!page) return <div className="mentor-reader-empty" data-tauri-drag-region="deep">
    <p>Open a lesson, a source, a note or a canvas from the library, or ask {agent.name || "your mentor"} to prepare one.</p>
  </div>;
  if (page.kind === "course") return <CoursePane key={`${agent.id}/${page.course.courseId}`} {...page.course} openRequest={request}
    sourceSessionId={agent.sessionId} reader focused onFocus={noop} onClose={onClose} onLessonChange={onLessonChange} />;
  if (page.kind === "document") return <AgentDocumentReader key={`${agent.id}/${page.document.id}`} agentId={agent.id} document={page.document}
    reader focused onFocus={noop} onClose={onClose} />;
  if (page.kind === "note") return <NotePane key={page.id} noteId={page.id} agentId={agent.id} recents={recents}
    reader focused onFocus={noop} onClose={onClose} onBeforeLeave={onBeforeLeave} />;
  if (page.kind === "canvas") {
    const canvas = canvases.find((entry) => entry.id === page.id);
    return canvas ? <Suspense fallback={null}><CanvasPane key={canvas.id} canvas={canvas} focused onFocus={noop} onClose={onClose}
      onAddToChat={onCanvasAddToChat} chatTarget="agent" chatIcon={<AgentAvatar name={agent.avatar} color={agent.color} className="size-4 shrink-0" />}
      onTitleChange={onCanvasTitleChange} /></Suspense>
      : <p role="status" className="mentor-reader-empty">This drawing is no longer available. <button type="button" className="underline" onClick={onClose}>Close</button></p>;
  }
  return <Suspense fallback={null}><FilePane key={page.path} path={page.path} cwd="" preview={false} focused onFocus={noop} onPin={noop}
    onClose={onClose} onOpenFile={onOpenFile} /></Suspense>;
}
