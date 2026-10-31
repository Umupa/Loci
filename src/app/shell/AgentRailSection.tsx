import { prettyCwd } from "../../shared/lib/paths";
import { useMemo, useState, useSyncExternalStore } from "react";
import { useAnimatedReorder } from "../../shared/hooks/useAnimatedReorder";
import { CircleAlert, CircleDashed, MoreHorizontal, Pencil, Plus, SlidersHorizontal, Trash2 } from "../../shared/ui/icons";
import { Popover, type PopoverAnchor } from "../../shared/ui/Popover";
import { Shimmer } from "../../shared/ui/Shimmer";
import { AgentAvatar } from "../../features/agents/ui/AgentAvatar";
import "./AgentRailSection.css";
import {
  AGENT_STATUS_LABEL,
  agentLook,
  agentsSnapshot,
  listAgents,
  reorderAgents,
  subscribeAgents,
  type AgentState,
} from "../../features/agents/model/agent";
import {
  agentPreviewsSnapshot,
  loadAgentPreviews,
  previewTimeLabel,
  subscribeAgentPreviews,
} from "../../features/agents/model/agentPreview";

type Props = {
  /** The agent open in the main area, if any. */
  activeId?: string;
  /** What each agent is doing, by agent id; missing reads as idle. */
  states: ReadonlyMap<string, AgentState>;
  /** Agents that said something the user has not looked at yet. */
  unseenIds?: ReadonlySet<string>;
  onOpen: (agentId: string) => void;
  onOpenDetails: (agentId: string) => void;
  /** Makes an agent ready to settle its job in the chat. */
  onCreate: () => void;
  onDelete: (agentId: string) => void;
};

const IDLE: AgentState = { status: "idle" };

type RailPhase = "thinking" | "working" | "responding" | "needs-you" | "updated" | "idle";

function railPhase(state: AgentState, unseen: boolean): RailPhase {
  if (state.status === "needs-you") return "needs-you";
  if (state.status === "working") {
    if (state.activity === "Thinking") return "thinking";
    if (state.activity === "Writing a reply") return "responding";
    return "working";
  }
  return unseen ? "updated" : "idle";
}

const SIGNAL_TITLE: Record<RailPhase, string> = {
  thinking: "Thinking",
  working: "Working",
  responding: "Replying",
  "needs-you": "Needs you",
  updated: "New update",
  idle: "Idle",
};

/** The face identifies the agent; this small signal says what it is doing. */
function AgentRailSignal({ phase }: { phase: RailPhase }) {
  return (
    <span data-agent-rail-signal aria-hidden title={SIGNAL_TITLE[phase]}
      className="grid size-4 shrink-0 place-items-center">
      {phase === "thinking" ? (
        <span data-agent-rail-dots className="flex items-center gap-[2px]">
          <span /><span /><span />
        </span>
      ) : phase === "working" ? (
        <CircleDashed data-agent-rail-spinner className="size-3.5" strokeWidth={1.75} />
      ) : phase === "responding" ? (
        <Pencil data-agent-rail-pencil className="size-3.5" strokeWidth={1.75} />
      ) : phase === "needs-you" ? (
        <CircleAlert className="size-3.5" strokeWidth={1.75} />
      ) : phase === "updated" ? (
        <span data-agent-rail-update className="size-1.5 rounded-full bg-current" />
      ) : null}
    </span>
  );
}

/**
 * The user's agents, above the projects. Each opens like a project does, but
 * into its conversation; none belongs to a project, so they get a section of
 * their own and a face with eyes rather than a project's flat mascot.
 */
export function AgentRailSection({ activeId, states, unseenIds, onOpen, onOpenDetails, onCreate, onDelete }: Props) {
  const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  const previewSnapshot = useSyncExternalStore(subscribeAgentPreviews, agentPreviewsSnapshot);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const previews = useMemo(() => loadAgentPreviews(), [previewSnapshot]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const agents = useMemo(() => listAgents(), [snapshot]);
  const sortable = useAnimatedReorder(agents.map((agent) => agent.id), reorderAgents, "y");
  const [menu, setMenu] = useState<{ id: string; anchor: PopoverAnchor }>();
  const menuAgent = menu ? agents.find((agent) => agent.id === menu.id) : undefined;
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
            onClick={() => onCreate()}
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
            onClick={() => onCreate()}
            className="grid h-8 w-full cursor-default place-items-center rounded-md border border-dashed border-content/15 text-content/50 hover:border-content/30 hover:text-content"
          >
            <Plus className="size-3.5" strokeWidth={1.75} />
          </button>
        ) : null}
        {agents.map((agent) => {
          const look = agentLook(agent);
          const state = states.get(agent.id) ?? IDLE;
          const selected = agent.id === activeId;
          const unseen = !selected && !!unseenIds?.has(agent.id);
          const preview = previews[agent.id];
          const phase = railPhase(state, unseen);
          const status = [AGENT_STATUS_LABEL[state.status], state.activity].filter(Boolean).join(" · ");
          return (
            <div
              key={agent.id}
              ref={(el) => sortable.setItemRef(agent.id, el)}
              data-selected={selected || undefined}
              data-agent-id={agent.id}
              data-agent-status={state.status}
              data-agent-rail-phase={phase}
              className={`agent-rail-row reorder-item project-reorder-item group relative flex h-8 cursor-default touch-none items-stretch rounded-md px-2 ${
                selected ? "bg-selection-strong text-content" : ""
              }`}
              onPointerDown={(event) => {
                if (event.button !== 0) return;
                if ((event.target as HTMLElement | null)?.closest("[data-no-drag]")) return;
                sortable.onItemPointerDown(agent.id, event);
              }}
              onClick={(event) => {
                if ((event.target as HTMLElement | null)?.closest("[data-no-drag]")) return;
                if (sortable.consumeClick()) return;
                onOpen(agent.id);
              }}
              onContextMenu={(event) => {
                event.preventDefault();
                setMenu({ id: agent.id, anchor: { x: event.clientX, y: event.clientY } });
              }}
            >
              <button
                type="button"
                title={[look.role ? `${look.name} · ${look.role}` : look.name, status, unseen ? "New update" : undefined, look.workdir ? prettyCwd(look.workdir) : undefined, state.status === "idle" && preview ? `${preview.text}${preview.at != null ? ` · ${previewTimeLabel(preview.at)}` : ""}` : undefined].filter(Boolean).join("\n")}
                aria-label={[look.name, status, unseen ? "New update" : undefined].filter(Boolean).join(", ")}
                aria-current={selected ? "true" : undefined}
                className="flex min-w-0 flex-1 cursor-default items-center gap-2 pr-6 text-left"
              >
                {/* The same size and place as a project's mascot, so the rail reads as one list. */}
                <span className="grid size-6 shrink-0 place-items-center">
                  <AgentAvatar name={look.avatar} color={look.color} className="size-6" />
                </span>
                {state.status === "working" ? (
                  <Shimmer as="span" duration={1.4} className="min-w-0 flex-1 truncate text-[13px]">
                    {look.name}
                  </Shimmer>
                ) : (
                  <span className="min-w-0 flex-1 truncate text-[13px]">{look.name}</span>
                )}
                <AgentRailSignal phase={phase} />
              </button>
              <button
                type="button"
                data-no-drag
                title="Agent options"
                aria-label={`${look.name} options`}
                aria-haspopup="menu"
                onPointerDown={(event) => event.stopPropagation()}
                onClick={(event) => {
                  event.stopPropagation();
                  setMenu({ id: agent.id, anchor: event.currentTarget });
                }}
                className="absolute right-1 top-1/2 hidden size-6 -translate-y-1/2 place-items-center rounded-md text-content/55 hover:bg-content/8 hover:text-content focus-visible:grid group-hover:grid"
              >
                <MoreHorizontal className="size-4" strokeWidth={1.75} />
              </button>
            </div>
          );
        })}
      </div>
      {menu && menuAgent ? (
        <Popover anchor={menu.anchor} side="right" align="start" gap={0} width={200} constrainHeight={false}
          onDismiss={() => setMenu(undefined)} role="menu" aria-label={`${agentLook(menuAgent).name} options`}
          onContextMenu={(event) => event.preventDefault()} className="p-1.5">
          <button type="button" role="menuitem" onClick={() => { setMenu(undefined); onOpenDetails(menu.id); }}
            className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left text-[13px] text-content/85 hover:bg-content/8">
            <SlidersHorizontal className="size-3.5 shrink-0" strokeWidth={1.75} />
            Details
          </button>
          <button type="button" role="menuitem" onClick={() => { setMenu(undefined); onDelete(menu.id); }}
            className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left text-[13px] text-red-400 hover:bg-content/8">
            <Trash2 className="size-3.5 shrink-0" strokeWidth={1.75} />
            Delete agent…
          </button>
        </Popover>
      ) : null}
    </div>
  );
}
