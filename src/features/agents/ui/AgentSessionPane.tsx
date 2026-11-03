import { Modal } from "../../../shared/ui/Modal";
import { ReadOnly } from "../../../shared/ui/ReadOnly";
import type { ComponentProps } from "react";
import { SessionPane } from "../../sessions/ui/SessionPane";
import { agentLook, type Agent, type AgentState } from "../model/agent";
import { markAgentAccessMigrated } from "../model/agentAccess";
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
  /**
   * Nothing can be sent or changed (another device's conversation while that
   * device is offline). Reading, and showing archived history, still work.
   */
  readOnly?: boolean;
};

/** Keeps an agent's composer and settings inside its movable workspace pane. */
export function AgentSessionPane({ agent, state, sessionPaneProps, detailsOpen, onToggleDetails, onReset, onDelete, onPickFolders, onLoadEarlier, readOnly = false }: Props) {
  const { session, focused, onFocus, onPaneDragStart, onModelChange, onModelSettingsChange, onRuntimeModeChange, recents } = sessionPaneProps;
  return (
    <AgentView agent={agent} state={state} focused={focused} onFocus={() => onFocus(session.id)}
      onPaneDragStart={onPaneDragStart}
      detailsOpen={detailsOpen} onToggleDetails={onToggleDetails} onLoadEarlier={onLoadEarlier}
      details={<Modal title={`${agentLook(agent).name} settings`} onClose={onToggleDetails} fitViewport minimalHeader size="lg" className="agent-settings-modal h-[min(680px,calc(100dvh-32px))]"><ReadOnly readOnly={readOnly}><AgentDetails agent={agent} session={session} recents={recents} refreshKey={session.busy}
        onModelChange={(harness, model) => onModelChange(session.id, harness, model)}
        onModelSettingsChange={(settings) => onModelSettingsChange(session.id, settings)}
        onRuntimeModeChange={(mode) => {
          onRuntimeModeChange(session.id, mode);
          // Choosing here is the mentor's access from now on, migration included.
          markAgentAccessMigrated(agent.id);
        }}
        onPickFolders={onPickFolders} onReset={onReset} onDelete={onDelete} onClose={onToggleDetails} /></ReadOnly></Modal>}>
      <ReadOnly readOnly={readOnly}><SessionPane {...sessionPaneProps} onRuntimeModeChange={(id, mode) => {
        sessionPaneProps.onRuntimeModeChange(id, mode);
        markAgentAccessMigrated(agent.id);
      }} hidePaneHeader hideProjectPicker
        runnerAvatar={<AgentAvatar name={agent.avatar} color={agent.color} className="size-4" />}
        emptyIntro={<AgentIntro agent={agent} />}
        chatPlaceholder={`Message ${agentLook(agent).name}`} /></ReadOnly>
    </AgentView>
  );
}
