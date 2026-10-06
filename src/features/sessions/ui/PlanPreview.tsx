import { AiIdea,CircleDashed } from "../../../shared/ui/icons";
import { planTitle } from "../model/plan";

import { AgentMarkdown } from "./AgentMarkdown";

type Props = { text: string; streaming?: boolean };

export function PlanPreview({ text, streaming }: Props) {
  const title = planTitle(text);
  return (
    <div className="mb-2 overflow-hidden rounded-[12px] border border-content/10 bg-content/7">
      <div className="flex items-start gap-2.5 px-3 py-2.5">
        {streaming ? (
          <CircleDashed className="mt-0.5 size-4 shrink-0 text-content/40" strokeWidth={1.75} />
        ) : (
          <AiIdea className="mt-0.5 size-4 shrink-0 text-content/40" strokeWidth={1.75} />
        )}
        <div className="min-w-0 flex-1">
          <span className="block truncate font-sans text-[13px] font-medium text-content/90" title={title}>{title}</span>
          <AgentMarkdown text={text} streaming={streaming} className="mt-1 text-content/70" />
        </div>
      </div>
    </div>
  );
}
