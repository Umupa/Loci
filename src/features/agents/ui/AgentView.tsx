import type { ReactNode } from "react";
import { OverlayNav } from "../../../app/shell/TitleBar";
import { WindowControls } from "../../../app/shell/WindowControls";
import { IS_MAC } from "../../../platform/tauri/platform";
import { SlidersHorizontal } from "../../../shared/ui/icons";
import { agentLook, agentProjectsPhrase, type Agent, type AgentState } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";
import { AgentStatus } from "./AgentStatus";

type Props = {
  agent: Agent;
  state: AgentState;
  detailsOpen: boolean;
  /** Whether the project rail is beside the view, and in its narrow form. */
  besideRail: boolean;
  compactRail: boolean;
  onToggleSidebar: () => void;
  onToggleDetails: () => void;
  onClose: () => void;
  /** Reads the next archived page back into view, when older turns exist. */
  onLoadEarlier?: () => void;
  /** The conversation itself. */
  children: ReactNode;
  /** The details panel, beside the conversation. */
  details?: ReactNode;
};

/**
 * An agent's conversation in the main area. It covers the workspace rather
 * than joining its tabs: an agent belongs to no project.
 */
export function AgentView({ agent, state, detailsOpen, besideRail, compactRail, onToggleSidebar, onToggleDetails, onClose, onLoadEarlier, children, details }: Props) {
  const look = agentLook(agent);
  const projects = agentProjectsPhrase(look.projects);
  return (
    <section className="flex min-h-0 min-w-0 flex-1 flex-col text-content" aria-label={look.name} data-agent-view={agent.id}>
      <header className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
        {IS_MAC && compactRail ? <div className="w-4 shrink-0" /> : null}
        {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
        {besideRail ? null : <OverlayNav onBack={onClose} onToggleSidebar={onToggleSidebar} />}
        <div className="flex min-w-0 flex-1 items-center gap-2.5 px-3">
          <AgentAvatar name={look.avatar} color={look.color} className="size-4 shrink-0" />
          <h1 className="shrink-0 truncate text-[13px] font-medium">{look.name}</h1>
          <AgentStatus state={state} />
          {projects ? <span className="min-w-0 truncate text-xs text-content/35">{projects}</span> : null}
        </div>
        <div className="flex shrink-0 items-center gap-1 px-2">
          <button type="button" title="Details" aria-label="Details" aria-pressed={detailsOpen} onClick={onToggleDetails}
            className={`grid size-6 place-items-center rounded-md hover:bg-content/8 hover:text-content ${detailsOpen ? "bg-content/8 text-content" : "text-content/50"}`}>
            <SlidersHorizontal className="size-3.5" strokeWidth={1.75} />
          </button>
        </div>
        {IS_MAC ? null : <WindowControls />}
      </header>
      <div className="flex min-h-0 min-w-0 flex-1">
        <div className="flex min-h-0 min-w-0 flex-1 flex-col">
          {onLoadEarlier ? (
            <div className="flex shrink-0 justify-center border-b border-stroke py-1">
              <button type="button" onClick={onLoadEarlier}
                className="rounded-md px-2 py-0.5 text-xs text-content/50 hover:bg-content/8 hover:text-content">
                Show archived history
              </button>
            </div>
          ) : null}
          {children}
        </div>
        {detailsOpen ? details : null}
      </div>
    </section>
  );
}
