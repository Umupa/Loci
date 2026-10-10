import { useId, useState } from "react";
import { AiIdea, Chatting, ChevronDown, File, Globe, X } from "../../../shared/ui/icons";
import type { LearningMessageContext, LearningSource } from "../model/types";
import { learningSourceLabel } from "../model/learningContext";
import { openLearningSource } from "../model/navigation";
import { registerLearningSource } from "../model/learningStore";
import "./SourceChips.css";

const sourceIcons = { file: File, pdf: File, web: Globe, conversation: Chatting };

function SourceChip({ source, onRemove, onError }: {
  source: LearningSource;
  onRemove?: (id: string) => void;
  onError: (message: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const passageId = useId();
  const Icon = sourceIcons[source.kind];
  const label = learningSourceLabel(source);
  const location = label === source.title ? undefined : label.slice(source.title.length + 3);

  const open = async () => {
    try {
      await registerLearningSource(source);
      onError("");
      openLearningSource(source.id);
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    }
  };

  return (
    <div className={`learning-source-chip${expanded ? " learning-source-chip--expanded" : ""}`}>
      <div className="learning-source-chip__row">
        <button type="button" onClick={() => void open()} title={label} aria-label={`Open source ${label}`} className="learning-source-chip__open">
          <Icon aria-hidden className="size-3.5 shrink-0" strokeWidth={1.75} />
          <span className="learning-source-chip__title">{source.title}</span>
          {location ? <span className="learning-source-chip__location">{location}</span> : null}
        </button>
        {source.quote ? (
          <button type="button" aria-label={`Quoted passage from ${source.title}`} aria-expanded={expanded} aria-controls={passageId}
            title={expanded ? "Hide passage" : "Show passage"} onClick={() => setExpanded((value) => !value)}
            className="learning-source-chip__action learning-source-chip__disclosure">
            <ChevronDown aria-hidden className="size-3" strokeWidth={1.75} />
          </button>
        ) : null}
        {onRemove ? (
          <button type="button" aria-label={`Remove source ${source.title}`} title="Remove source" onClick={() => onRemove(source.id)} className="learning-source-chip__action learning-source-chip__remove">
            <X aria-hidden className="size-3" strokeWidth={1.75} />
          </button>
        ) : null}
      </div>
      {expanded ? <blockquote id={passageId} className="learning-source-chip__passage">{source.quote}</blockquote> : null}
    </div>
  );
}

export function SourceChips({ sources, widgetContext, onRemoveSource, onRemoveWidget }: LearningMessageContext & {
  onRemoveSource?: (id: string) => void;
  onRemoveWidget?: () => void;
}) {
  const [error, setError] = useState("");
  if (!sources?.length && !widgetContext) return null;
  return (
    <div className="learning-context-chips" aria-label="Learning context">
      {sources?.map((source) => <SourceChip key={source.id} source={source} onRemove={onRemoveSource} onError={setError} />)}
      {widgetContext ? (
        <div className="learning-source-chip learning-source-chip--widget">
          <div className="learning-source-chip__row">
            <span className="learning-source-chip__widget" title={widgetContext.selection || widgetContext.title}>
              <AiIdea aria-hidden className="size-3.5 shrink-0" strokeWidth={1.75} />
              <span className="learning-source-chip__title">{widgetContext.title}</span>
              <span className="learning-source-chip__location">State</span>
            </span>
            {onRemoveWidget ? (
              <button type="button" aria-label="Remove widget context" title="Remove explanation context" onClick={onRemoveWidget} className="learning-source-chip__action learning-source-chip__remove">
                <X aria-hidden className="size-3" strokeWidth={1.75} />
              </button>
            ) : null}
          </div>
        </div>
      ) : null}
      {error ? <span role="alert" className="learning-context-chips__error text-red-400">{error}</span> : null}
    </div>
  );
}
