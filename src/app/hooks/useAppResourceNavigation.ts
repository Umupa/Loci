import { canvasScopeAgentId } from "../../features/agents/model/agent";
import { useEffect, useRef } from "react";
import { APP_RESOURCE_OPEN_EVENT, fileResourcePath, parseAppResourceUrl, resourceUrl, type AppResource } from "../../shared/lib/appResourceLinks";
import { requestFilePlace } from "../../features/files/model/filePlace";
import { CANVAS_OPEN_CHECKPOINT_EVENT, checkpointCanvasId, getCanvas, type Canvas } from "../../features/canvas/canvas";
import { getLearningSource, getReadingDocument } from "../../features/learning/model/learningStore";
import { openUrl } from "@tauri-apps/plugin-opener";
import { requestTranscriptJump } from "../../features/sessions/model/transcriptJump";
import { getNote } from "../../features/notes";
import { joinPath } from "../../shared/lib/paths";
import { findAgent } from "../../features/agents/model/agent";

type Options = {
  openSession(id: string): Promise<void>;
  openFile(path: string): void;
  /** The folder relative file links resolve against: that of the conversation on screen. */
  fileBase(): string | undefined;
  /** `owner` is the agent that keeps the drawing, when one does. */
  openCanvas(canvas: Canvas, owner?: string): Promise<void>;
  /** `owner` is the agent that keeps the note, when one does. */
  openNote(id: string, owner?: string): Promise<void>;
  onOpenConversation?: (id: string, blockId?: string, isCurrent?: () => boolean) => Promise<void>;
  onError(error: unknown): void;
};

/** Replies and old checkpoint buttons share the current window's navigation. */
export function useAppResourceNavigation(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  useEffect(() => {
    let request = 0;
    const navigate = async (resource: AppResource, checkpoint = false) => {
      const current = ++request;
      try {
        if (resource.kind === "note") {
          const note = await getNote(resource.id);
          if (current !== request) return;
          if (!note) throw new Error("This note no longer exists.");
          await latest.current.openNote(note.id, note.agentId && findAgent(note.agentId) ? note.agentId : undefined);
          return;
        }
        if (resource.kind === "session") {
          await latest.current.openSession(resource.id);
          return;
        }
        if (resource.kind === "source") {
          const source = await getLearningSource(resource.id);
          if (current !== request) return;
          if (!source) throw new Error("This learning source is no longer available.");
          if (source.kind === "web") { await openUrl(source.url); return; }
          if (source.kind === "conversation") {
            if (latest.current.onOpenConversation) await latest.current.onOpenConversation(source.sessionId, source.blockId, () => current === request);
            else await latest.current.openSession(source.sessionId);
            if (current !== request) return;
            requestTranscriptJump(source.sessionId, source.blockId, source.quote);
            return;
          }
          if (source.kind === "document") throw new Error("This passage is in a library document that can't be opened here.");
          let path = source.path;
          if (source.kind === "pdf") {
            const document = await getReadingDocument(source.documentId);
            if (current !== request) return;
            if (!document) throw new Error("This PDF is no longer registered.");
            path = document.path;
            requestFilePlace(path, { page: source.anchors[0]?.page ?? 1, ...(source.annotationId ? { annotationId: source.annotationId } : {}) });
          } else if (source.lines) requestFilePlace(path, { lines: source.lines });
          latest.current.openFile(path);
          return;
        }
        if (resource.kind === "file") {
          // File links are relative to the folder they were written in: the conversation on screen's.
          const relative = fileResourcePath(resource);
          const cwd = latest.current.fileBase();
          if (!relative || !cwd || cwd === "~") throw new Error("This file link points into a folder that is not open here.");
          const path = joinPath(cwd, relative);
          if (resource.place) requestFilePlace(path, resource.place);
          latest.current.openFile(path);
          return;
        }
        const id = checkpoint ? await checkpointCanvasId(resource.id) : resource.id;
        if (!id) throw new Error("This drawing no longer exists.");
        const canvas = await getCanvas(id);
        if (current !== request) return;
        if (!canvas) throw new Error("This drawing no longer exists.");
        const owner = canvasScopeAgentId(canvas.cwd);
        await latest.current.openCanvas(canvas, owner && findAgent(owner) ? owner : undefined);
      } catch (error) {
        if (current === request) latest.current.onError(error);
      }
    };
    const open = (event: Event) => {
      const resource = (event as CustomEvent<AppResource>).detail;
      if (!resource || typeof resource.id !== "string") return;
      const parsed = parseAppResourceUrl(resourceUrl(resource));
      if (parsed) void navigate(parsed);
    };
    const openCheckpoint = (event: Event) => {
      const id = (event as CustomEvent<string>).detail;
      if (typeof id === "string") void navigate({ kind: "canvas", id }, true);
    };
    window.addEventListener(APP_RESOURCE_OPEN_EVENT, open);
    window.addEventListener(CANVAS_OPEN_CHECKPOINT_EVENT, openCheckpoint);
    return () => {
      request++;
      window.removeEventListener(APP_RESOURCE_OPEN_EVENT, open);
      window.removeEventListener(CANVAS_OPEN_CHECKPOINT_EVENT, openCheckpoint);
    };
  }, []);
}
