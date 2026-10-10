import { useEffect, useRef, useState } from "react";
import { AiIdea,CircleDashed } from "../../../shared/ui/icons";
import { planTitle } from "../model/plan";

import { AgentMarkdown } from "./AgentMarkdown";
import "./PlanPreview.css";

type Props = {
  text: string;
  streaming?: boolean;
  /** Only newly arrived visible plans enter; opening history stays still. */
  revealOnMount?: boolean;
  visible?: boolean;
};

export function PlanPreview({
  text,
  streaming = false,
  revealOnMount = false,
  visible = true,
}: Props) {
  const [entering, setEntering] = useState(revealOnMount && visible);
  const [settling, setSettling] = useState(false);
  const previous = useRef({ streaming, visible });

  useEffect(() => {
    if (!entering) return;
    if (!visible) {
      setEntering(false);
      return;
    }
    const timer = window.setTimeout(() => setEntering(false), 220);
    return () => window.clearTimeout(timer);
  }, [entering, visible]);

  useEffect(() => {
    const was = previous.current;
    previous.current = { streaming, visible };
    // Ready means the stream ended, including cancellation, not task success.
    const readyInView = was.streaming && was.visible && visible && !streaming;
    setSettling(readyInView);
    if (!readyInView) return;
    const timer = window.setTimeout(() => setSettling(false), 700);
    return () => window.clearTimeout(timer);
  }, [streaming, visible]);

  const title = planTitle(text);
  return (
    <div
      data-plan-preview
      data-plan-entering={(entering && visible) || undefined}
      data-plan-streaming={(streaming && visible) || undefined}
      data-plan-settling={(settling && visible) || undefined}
      className="plan-preview mb-2 overflow-hidden rounded-[12px] border border-content/10 bg-content/7"
    >
      <div className="flex items-start gap-2.5 px-3 py-2.5">
        <span data-plan-icon aria-hidden className="mt-0.5 inline-flex size-4 shrink-0 items-center justify-center text-content/40">
          {streaming ? (
            <CircleDashed className="size-4" strokeWidth={1.75} />
          ) : (
            <AiIdea className="size-4" strokeWidth={1.75} />
          )}
        </span>
        <div className="min-w-0 flex-1">
          <span className="block truncate font-sans text-[13px] font-medium text-content/90" title={title}>{title}</span>
          <AgentMarkdown text={text} streaming={streaming} revealOnMount={false} className="mt-1 text-content/70" />
        </div>
      </div>
    </div>
  );
}
