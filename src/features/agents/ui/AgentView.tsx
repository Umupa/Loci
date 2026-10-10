import type { PointerEvent as ReactPointerEvent, ReactNode } from "react";
import { GripVertical, SlidersHorizontal } from "../../../shared/ui/icons";
import { agentLook, agentProjectsPhrase, type Agent, type AgentState } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";
import { AgentStatus } from "./AgentStatus";

type Props = {
  agent: Agent;
  state: AgentState;
  detailsOpen: boolean;
  focused: boolean;
  onFocus: () => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  onToggleDetails: () => void;
  /** Reads the next archived page back into view, when older turns exist. */
  onLoadEarlier?: () => void;
  /** The conversation itself. */
  children: ReactNode;
  /** The details panel, beside the conversation. */
  details?: ReactNode;
};

/** An agent's conversation and details, with the workspace's pane controls. */
export function AgentView({ agent, state, detailsOpen, focused, onFocus, onPaneDragStart, onToggleDetails, onLoadEarlier, children, details }: Props) {
  const look = agentLook(agent);
  const projects = agentProjectsPhrase(look.projects);
  return (
    <section className="flex h-full min-h-0 min-w-0 flex-1 flex-col text-content" aria-label={look.name} data-agent-view={agent.id}
      onPointerDown={() => { if (!focused) onFocus(); }}>
      <header className={`flex h-9 shrink-0 select-none touch-none items-center gap-1.5 border-b border-stroke px-2 ${onPaneDragStart ? "cursor-grab active:cursor-grabbing" : ""}`}
        onPointerDown={(event) => {
          if (event.button !== 0 || (event.target as HTMLElement).closest("[data-no-drag]")) return;
          onPaneDragStart?.(event);
        }}>
        {onPaneDragStart ? <GripVertical className="size-3.5 shrink-0 text-content/35" strokeWidth={1.75} /> : null}
        <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} />
        <div className="flex min-w-0 flex-1 items-center gap-2">
          <AgentAvatar name={look.avatar} color={look.color} className="size-5 shrink-0" />
          <h1 className="min-w-0 truncate text-xs font-medium">{look.name}</h1>
          {look.role ? <span className="shrink-0 rounded-md bg-content/8 px-1.5 py-px text-[11px] text-content/60">{look.role}</span> : null}
          <AgentStatus state={state} />
          {projects ? <span className="min-w-0 truncate text-xs text-content/35">{projects}</span> : null}
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button type="button" data-no-drag title="Details" aria-label="Details" aria-pressed={detailsOpen} onClick={onToggleDetails}
            className={`grid size-6 place-items-center rounded-md hover:bg-content/8 hover:text-content ${detailsOpen ? "bg-content/8 text-content" : "text-content/50"}`}>
            <SlidersHorizontal className="size-3.5" strokeWidth={1.75} />
          </button>
        </div>
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
