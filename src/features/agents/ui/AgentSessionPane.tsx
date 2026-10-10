import type { ComponentProps } from "react";
import { SessionPane } from "../../sessions/ui/SessionPane";
import { agentLook, type Agent, type AgentState } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";
import { AgentDetails } from "./AgentDetails";
import { AgentIntro } from "./AgentIntro";
import { AgentView } from "./AgentView";

type Props = {
  agent: Agent;
  state: AgentState;
  sessionPaneProps: ComponentProps<typeof SessionPane>;
  detailsOpen: boolean;
  onToggleDetails: () => void;
  onReset: () => void;
  onDelete: () => void;
  onPickFolders: () => Promise<string[]>;
  onLoadEarlier?: () => void;
};

/** Keeps an agent's composer and settings inside its movable workspace pane. */
export function AgentSessionPane({ agent, state, sessionPaneProps, detailsOpen, onToggleDetails, onReset, onDelete, onPickFolders, onLoadEarlier }: Props) {
  const { session, focused, onFocus, onPaneDragStart, onModelChange, onModelSettingsChange, onRuntimeModeChange, recents } = sessionPaneProps;
  return (
    <AgentView agent={agent} state={state} focused={focused} onFocus={() => onFocus(session.id)}
      onPaneDragStart={onPaneDragStart}
      detailsOpen={detailsOpen} onToggleDetails={onToggleDetails} onLoadEarlier={onLoadEarlier}
      details={<AgentDetails agent={agent} session={session} recents={recents} refreshKey={session.busy}
        onModelChange={(harness, model) => onModelChange(session.id, harness, model)}
        onModelSettingsChange={(settings) => onModelSettingsChange(session.id, settings)}
        onRuntimeModeChange={(mode) => onRuntimeModeChange(session.id, mode)}
        onPickFolders={onPickFolders} onReset={onReset} onDelete={onDelete} onClose={onToggleDetails} />}>
      <SessionPane {...sessionPaneProps} hidePaneHeader hideProjectPicker
        runnerAvatar={<AgentAvatar name={agent.avatar} color={agent.color} className="size-4" />}
        emptyIntro={<AgentIntro agent={agent} />}
        chatPlaceholder={`Message ${agentLook(agent).name}`} />
    </AgentView>
  );
}
