import { useEffect, useRef } from "react";
import { APP_RESOURCE_OPEN_EVENT, fileResourcePath, parseAppResourceUrl, resourceUrl, type AppResource } from "../../shared/lib/appResourceLinks";
import { joinPath } from "../../shared/lib/paths";
import { requestFilePlace } from "../../features/files/model/filePlace";
import { CANVAS_OPEN_CHECKPOINT_EVENT, checkpointCanvasId, getCanvas } from "../../features/canvas/canvas";
import { sameProjectPath } from "../../features/projects/model/recents";
import type { useAppWorkspace } from "./useAppWorkspace";

type Options = {
  workspace: Pick<ReturnType<typeof useAppWorkspace>, "projectCwdRef" | "isCanvasOpen" | "openCanvas" | "showCanvas" | "openSession" | "openFile" | "setError">;
  notesEnabled: boolean;
  onOpenNote(id: string): void;
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
          if (!latest.current.notesEnabled) throw new Error("Notes are disabled in Settings.");
          latest.current.onOpenNote(resource.id);
          return;
        }
        if (resource.kind === "session") {
          await latest.current.workspace.openSession(resource.id);
          return;
        }
        if (resource.kind === "file") {
          // File links are relative to the project they were written in: the one on screen.
          const relative = fileResourcePath(resource);
          const cwd = latest.current.workspace.projectCwdRef.current;
          if (!relative || !cwd) throw new Error("Open the project this file belongs to first.");
          const path = joinPath(cwd, relative);
          if (resource.place) requestFilePlace(path, resource.place);
          latest.current.workspace.openFile(path, true);
          return;
        }
        const id = checkpoint ? await checkpointCanvasId(resource.id) : resource.id;
        if (!id) throw new Error("This drawing no longer exists.");
        const canvas = await getCanvas(id);
        if (current !== request) return;
        if (!canvas) throw new Error("This drawing no longer exists.");
        const view = latest.current.workspace;
        if (view.isCanvasOpen(canvas.id) || !canvas.cwd || !sameProjectPath(canvas.cwd, view.projectCwdRef.current)) {
          view.openCanvas(canvas.id, canvas.cwd);
        } else view.showCanvas(canvas.id);
      } catch (error) {
        if (current === request) latest.current.workspace.setError(String(error));
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
