import { createContext, useContext, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { AgentSettings } from "../../../shared/ui/icons";
import { PaneHeader, PaneHeaderChrome } from "../../../shared/ui/PaneHeader";
import { agentLook, type Agent, type AgentState } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";
import { AgentStatus } from "./AgentStatus";
import "./AgentSurface.css";

/** Controls a surface adds after the conversation header's own, such as hiding the conversation. */
export const AgentHeaderExtra = createContext<ReactNode>(null);

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
  const extra = useContext(AgentHeaderExtra);
  return (
    <section className="flex h-full min-h-0 min-w-0 flex-1 flex-col text-content" aria-label={look.name} data-agent-view={agent.id} data-focused={focused}
      onPointerDown={() => { if (!focused) onFocus(); }}>
      <PaneHeader onPaneDragStart={onPaneDragStart} className="agent-chat-header">
        <div className="flex min-w-0 flex-1 items-center gap-2" title={look.role}>
          <AgentAvatar name={look.avatar} color={look.color} className="size-4 shrink-0" />
          <h1 className="min-w-0 truncate text-[13px] font-semibold" title={look.name}>{look.name}</h1>
          <AgentStatus state={state} />
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button type="button" data-no-drag title="Settings" aria-label="Agent settings" aria-pressed={detailsOpen} onClick={onToggleDetails}
            className={`grid size-7 place-items-center rounded-md hover:bg-content/8 hover:text-content ${detailsOpen ? "bg-content/8 text-content" : "text-content/65"}`}>
            <AgentSettings className="size-4" />
          </button>
          {extra}
        </div>
      </PaneHeader>
      {/* Embedded readers and settings have toolbars below the window titlebar. */}
      <PaneHeaderChrome.Provider value={null}>
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
      </PaneHeaderChrome.Provider>
    </section>
  );
}
