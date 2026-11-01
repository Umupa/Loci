import { useState } from "react";
import { Modal } from "../../../shared/ui/Modal";
import { Plus } from "../../../shared/ui/icons";
import { AGENT_COLORS } from "../model/agent";
import { AGENT_TEMPLATES, type AgentTemplate } from "../templates";
import { AgentAvatar } from "./AgentAvatar";

type Props = {
  /** A template, or `null` for a blank agent. */
  onPick: (template: AgentTemplate | null) => void;
  onClose: () => void;
};

/** Where a new mentor starts: a ready-made one for a kind of work, or a blank one. */
export function AgentGallery({ onPick, onClose }: Props) {
  const [shown, setShown] = useState<string | null>(null);
  const pick = (template: AgentTemplate | null) => { onClose(); onPick(template); };
  return <Modal title="New mentor" description="Start from a mentor made for a kind of work, or from a blank one. You can change its Soul any time in its settings." size="lg" fitViewport onClose={onClose}>
    <ul className="grid gap-2 p-4 pt-1 sm:grid-cols-2" aria-label="Mentor templates">
      {AGENT_TEMPLATES.map((template, index) => <li key={template.id} data-agent-template={template.id}
        className="flex min-w-0 flex-col gap-2 rounded-lg border border-stroke p-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <AgentAvatar name={template.avatar} color={AGENT_COLORS[index % AGENT_COLORS.length]} className="size-8 shrink-0" />
          <div className="min-w-0">
            <h3 className="truncate text-[13px] font-medium text-content">{template.name}</h3>
            <p className="truncate text-[11px] text-content/50">{template.role}</p>
          </div>
        </div>
        <p className="flex-1 text-[12px] leading-relaxed text-content/70">{template.summary}</p>
        {shown === template.id ? <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded-md bg-content/5 p-2 text-[11px] leading-relaxed text-content/70">{template.soul}</pre> : null}
        <div className="flex items-center justify-end gap-1">
          <button type="button" aria-expanded={shown === template.id} onClick={() => setShown((current) => current === template.id ? null : template.id)}
            className="rounded-md px-2 py-1 text-[12px] text-content/55 hover:bg-content/8 hover:text-content">{shown === template.id ? "Hide Soul" : "Read Soul"}</button>
          <button type="button" aria-label={`Add ${template.name}`} onClick={() => pick(template)}
            className="primary-action rounded-md px-2.5 py-1 text-[12px] font-medium">Add</button>
        </div>
      </li>)}
      <li className="flex min-w-0">
        <button type="button" onClick={() => pick(null)}
          className="flex min-h-28 w-full flex-col items-center justify-center gap-1.5 rounded-lg border border-dashed border-stroke p-3 text-[12px] text-content/55 hover:bg-content/5 hover:text-content">
          <Plus className="size-4" /> Blank mentor
        </button>
      </li>
    </ul>
  </Modal>;
}
