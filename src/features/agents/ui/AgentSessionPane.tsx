import { ReadOnly } from "../../../shared/ui/ReadOnly";
import type { ComponentProps } from "react";
import { SessionPane } from "../../sessions/ui/SessionPane";
import { agentLook, type Agent, type AgentState } from "../model/agent";
import { markAgentAccessMigrated } from "../model/agentAccess";
import { AgentAvatar } from "./AgentAvatar";
import { AgentIntro } from "./AgentIntro";
import { AgentView } from "./AgentView";

type Props = {
  agent: Agent;
  state: AgentState;
  sessionPaneProps: ComponentProps<typeof SessionPane>;
  /** Opens this mentor's page in Settings. */
  onOpenSettings: () => void;
  onLoadEarlier?: () => void;
  /**
   * Nothing can be sent or changed (another device's conversation while that
   * device is offline). Reading, and showing archived history, still work.
   */
  readOnly?: boolean;
};

/** Keeps an agent's composer inside its movable workspace pane. */
export function AgentSessionPane({ agent, state, sessionPaneProps, onOpenSettings, onLoadEarlier, readOnly = false }: Props) {
  const { session, focused, onFocus, onPaneDragStart } = sessionPaneProps;
  return (
    <AgentView agent={agent} state={state} focused={focused} onFocus={() => onFocus(session.id)}
      onPaneDragStart={onPaneDragStart}
      onOpenSettings={onOpenSettings} onLoadEarlier={onLoadEarlier}>
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
