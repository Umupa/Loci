import { useMemo, useSyncExternalStore } from "react";
import { Plus } from "../../shared/ui/icons";
import { AgentAvatar } from "../../features/agents/ui/AgentAvatar";
import { AgentStatusDot } from "../../features/agents/ui/AgentStatus";
import {
  AGENT_STATUS_LABEL,
  agentLook,
  agentProjectsPhrase,
  agentsSnapshot,
  listAgents,
  subscribeAgents,
  type AgentState,
} from "../../features/agents/model/agent";

type Props = {
  /** The agent open in the main area, if any. */
  activeId?: string;
  /** What each agent is doing, by agent id; missing reads as idle. */
  states: ReadonlyMap<string, AgentState>;
  onOpen: (agentId: string) => void;
  onCreate: () => void;
};

const IDLE: AgentState = { status: "idle" };

/**
 * The user's agents, above the projects. Each opens like a project does, but
 * into its conversation; none belongs to a project, so they get a section of
 * their own and a framed avatar rather than a project's flat mascot.
 */
export function AgentRailSection({ activeId, states, onOpen, onCreate }: Props) {
  const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const agents = useMemo(() => listAgents(), [snapshot]);
  return (
    <div className="mb-2 shrink-0" data-agent-rail>
      <div className="flex items-center gap-1 px-3 pb-1.5 pt-1">
        <span className="min-w-0 flex-1 truncate px-1 text-xs text-content/50">
          Agents
        </span>
        {/* With none yet, the row below is the way to add one. */}
        {agents.length ? (
          <button
            type="button"
            title="New agent"
            aria-label="New agent"
            onClick={onCreate}
            className="grid size-5 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content"
          >
            <Plus className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
      </div>
      <div className="flex flex-col gap-px px-2">
        {agents.length === 0 ? (
          <button
            type="button"
            title="New agent"
            aria-label="New agent"
            onClick={onCreate}
            className="grid h-8 w-full cursor-default place-items-center rounded-md border border-dashed border-content/15 text-content/50 hover:border-content/30 hover:text-content"
          >
            <Plus className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
        {agents.map((agent) => {
          const look = agentLook(agent);
          const state = states.get(agent.id) ?? IDLE;
          const selected = agent.id === activeId;
          const projects = agentProjectsPhrase(look.projects);
          return (
            <button
              key={agent.id}
              type="button"
              data-selected={selected || undefined}
              aria-current={selected || undefined}
              title={[
                look.name,
                projects,
                state.activity ?? AGENT_STATUS_LABEL[state.status],
              ]
                .filter(Boolean)
                .join("\n")}
              onClick={() => onOpen(agent.id)}
              className={`flex h-8 w-full cursor-default items-center gap-2 rounded-md px-2 text-left ${
                selected
                  ? "bg-selection-strong text-content"
                  : "opacity-65 hover:opacity-100"
              }`}
            >
              <span className="relative grid size-4 shrink-0 place-items-center">
                <AgentAvatar
                  name={look.avatar}
                  color={look.color}
                  className="size-4"
                />
                <AgentStatusDot
                  status={state.status}
                  color={look.color}
                  className="-right-1 -top-1 size-1.5"
                />
              </span>
              <span className="min-w-0 flex-1 truncate text-[13px]">
                {look.name}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
