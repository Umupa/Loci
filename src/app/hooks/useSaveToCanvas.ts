import { useEffect, useRef, useState } from "react";
import { agentCanvasScope } from "../../features/agents/model/agent";
import type { Canvas } from "../../features/canvas/canvas";
import { appendCanvasText } from "../../features/canvas/saveToCanvas";

type Options = {
  canvases: Canvas[];
};
type Selection = {
  canvases: Canvas[];
  anchor?: HTMLElement | null;
  resolver: (id: string) => void;
  rejecter: (error: Error) => void;
};

/** Saved drawings are available even when their editors are not mounted. */
export function useSaveToCanvas({ canvases }: Options) {
  const [selection, setSelection] = useState<Selection | null>(null);
  const pending = useRef<Selection | null>(null);
  useEffect(() => () => {
    pending.current?.rejecter(new DOMException("Cancelled", "AbortError"));
  }, []);

  const saveToCanvas = async (text: string, agentId: string, anchor?: HTMLElement | null): Promise<string> => {
    const scope = agentCanvasScope(agentId);
    const available = canvases.filter((canvas) => canvas.cwd === scope);
    if (!available.length) throw new Error("No available Canvas in this agent's library. Ask the agent to create a drawing first.");
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
