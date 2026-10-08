import { useEffect, useRef, useState, type RefObject } from "react";
import type { Canvas } from "../../features/canvas/canvas";
import { appendCanvasText } from "../../features/canvas/saveToCanvas";
import { looksLikeProject, sameProjectPath } from "../../features/projects/model/recents";

type Options = {
  canvases: Canvas[];
  workspaceRef: RefObject<{ projectCwdRef: RefObject<string> } | null>;
};
type Selection = {
  canvases: Canvas[];
  anchor?: HTMLElement | null;
  resolver: (id: string) => void;
  rejecter: (error: Error) => void;
};

/** Saved drawings are available even when their editors are not mounted. */
export function useSaveToCanvas({ canvases, workspaceRef }: Options) {
  const [selection, setSelection] = useState<Selection | null>(null);
  const pending = useRef<Selection | null>(null);
  useEffect(() => () => {
    pending.current?.rejecter(new DOMException("Cancelled", "AbortError"));
  }, []);

  const saveToCanvas = async (text: string, anchor?: HTMLElement | null): Promise<string> => {
    const cwd = workspaceRef.current?.projectCwdRef.current;
    const available = canvases.filter((canvas) => !cwd || !looksLikeProject(cwd) ||
      !!canvas.cwd && sameProjectPath(canvas.cwd, cwd));
    if (!available.length) throw new Error("No available Canvas. Create a drawing in this project first.");
    pending.current?.rejecter(new DOMException("Cancelled", "AbortError"));
    const id = available.length === 1 ? available[0].id : await new Promise<string>((resolve, reject) => {
      const request: Selection = {
        canvases: available,
        anchor,
        resolver: (id) => { pending.current = null; setSelection(null); resolve(id); },
        rejecter: (error) => { pending.current = null; setSelection(null); reject(error); },
      };
      pending.current = request;
      setSelection(request);
    });
    await appendCanvasText(id, text);
    return id;
  };
  return { saveToCanvas, selection };
}
