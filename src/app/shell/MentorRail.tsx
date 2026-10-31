import { useMemo, useState, useSyncExternalStore } from "react";
import { useAnimatedReorder } from "../../shared/hooks/useAnimatedReorder";
import { CircleAlert, CircleDashed, Pencil, Plus, Search, Settings, SlidersHorizontal, Trash2 } from "../../shared/ui/icons";
import { Popover, type PopoverAnchor } from "../../shared/ui/Popover";
import { AgentAvatar } from "../../features/agents/ui/AgentAvatar";
import { IS_MAC } from "../../platform/tauri/platform";
import { prettyCwd } from "../../shared/lib/paths";
import { AGENT_STATUS_LABEL, agentLook, agentsSnapshot, listAgents, reorderAgents, subscribeAgents, type AgentState } from "../../features/agents/model/agent";
import "./MentorRail.css";

type Props = {
  /** The mentor the window shows, if any. */
  activeId?: string;
  /** What each mentor is doing, by agent id; missing reads as idle. */
  states: ReadonlyMap<string, AgentState>;
  /** Mentors that said something the user has not looked at yet. */
  unseenIds?: ReadonlySet<string>;
  settingsOpen: boolean;
  onOpen: (agentId: string) => void;
  onOpenDetails: (agentId: string) => void;
  /** Opens the gallery of mentor templates. */
  onCreate: () => void;
  onDelete: (agentId: string) => void;
  onSearch?: () => void;
  onOpenSettings: () => void;
};

const IDLE: AgentState = { status: "idle" };

export type RailPhase = "thinking" | "working" | "responding" | "needs-you" | "updated" | "idle";

export function railPhase(state: AgentState, unseen: boolean): RailPhase {
  if (state.status === "needs-you") return "needs-you";
  if (state.status === "working") {
    if (state.activity === "Thinking") return "thinking";
    if (state.activity === "Writing a reply") return "responding";
    return "working";
  }
  return unseen ? "updated" : "idle";
}

const SIGNAL_TITLE: Record<RailPhase, string> = {
  thinking: "Thinking", working: "Working", responding: "Replying", "needs-you": "Needs you", updated: "New update", idle: "Idle",
};

/** The face identifies the mentor; this small badge says what it is doing. */
function RailSignal({ phase }: { phase: RailPhase }) {
  if (phase === "idle") return null;
  return <span data-agent-rail-signal aria-hidden title={SIGNAL_TITLE[phase]} className="mentor-rail-signal">
    {phase === "thinking" ? <span data-agent-rail-dots className="flex items-center gap-[2px]"><span /><span /><span /></span>
      : phase === "working" ? <CircleDashed data-agent-rail-spinner className="size-3" strokeWidth={2} />
      : phase === "responding" ? <Pencil data-agent-rail-pencil className="size-3" strokeWidth={2} />
      : phase === "needs-you" ? <CircleAlert className="size-3" strokeWidth={2} />
      : <span data-agent-rail-update className="size-1.5 rounded-full bg-current" />}
  </span>;
}

/**
 * The far-left rail: one face per mentor, each a topic of its own, then a
 * way to add one and the settings.
 */
export function MentorRail({ activeId, states, unseenIds, settingsOpen, onOpen, onOpenDetails, onCreate, onDelete, onSearch, onOpenSettings }: Props) {
  const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const agents = useMemo(() => listAgents(), [snapshot]);
  const sortable = useAnimatedReorder(agents.map((agent) => agent.id), reorderAgents, "y");
  const [menu, setMenu] = useState<{ id: string; anchor: PopoverAnchor }>();
  const menuAgent = menu ? agents.find((agent) => agent.id === menu.id) : undefined;
  return <nav className="mentor-rail" data-mac={IS_MAC || undefined} aria-label="Mentors" data-agent-rail>
    <div className="mentor-rail-top" data-tauri-drag-region="deep" />
    <div className="mentor-rail-list">
      {agents.map((agent, index) => {
        const look = agentLook(agent);
        const state = states.get(agent.id) ?? IDLE;
        const selected = agent.id === activeId && !settingsOpen;
        const unseen = agent.id !== activeId && !!unseenIds?.has(agent.id);
        const phase = railPhase(state, unseen);
        const status = [AGENT_STATUS_LABEL[state.status], state.activity].filter(Boolean).join(" · ");
        const label = [look.name, status, unseen ? "New update" : undefined].filter(Boolean).join(", ");
        return <div key={agent.id} ref={(el) => sortable.setItemRef(agent.id, el)} className="mentor-rail-item reorder-item"
          data-agent-id={agent.id} data-selected={selected || undefined} data-agent-status={state.status} data-agent-rail-phase={phase}
          onPointerDown={(event) => { if (event.button === 0) sortable.onItemPointerDown(agent.id, event); }}
          onContextMenu={(event) => { event.preventDefault(); setMenu({ id: agent.id, anchor: { x: event.clientX, y: event.clientY } }); }}>
          <button type="button" className="mentor-rail-button" aria-label={label} aria-current={selected ? "true" : undefined}
            title={[look.role ? `${look.name} · ${look.role}` : look.name, status, look.workdir ? prettyCwd(look.workdir) : undefined, index < 9 ? `${IS_MAC ? "⌘" : "Ctrl+"}${index + 1}` : undefined].filter(Boolean).join("\n")}
            onClick={() => { if (!sortable.consumeClick()) onOpen(agent.id); }}>
            <AgentAvatar name={look.avatar} color={look.color} className="size-8" />
            <RailSignal phase={phase} />
          </button>
        </div>;
      })}
      <button type="button" className="mentor-rail-action" aria-label="New mentor" title="New mentor" onClick={onCreate}>
        <Plus className="size-4" strokeWidth={1.75} />
      </button>
    </div>
    <div className="mentor-rail-bottom">
      {onSearch ? <button type="button" className="mentor-rail-action" aria-label="Search" title={`Search (${IS_MAC ? "⌘" : "Ctrl+"}K)`} onClick={onSearch}>
        <Search className="size-4" strokeWidth={1.75} />
      </button> : null}
      <button type="button" className="mentor-rail-action" aria-label="Settings" title="Settings" aria-pressed={settingsOpen} onClick={onOpenSettings}>
        <Settings className="size-4" strokeWidth={1.75} />
      </button>
    </div>
    {menu && menuAgent ? <Popover anchor={menu.anchor} side="right" align="start" gap={0} width={200} constrainHeight={false}
      onDismiss={() => setMenu(undefined)} role="menu" aria-label={`${agentLook(menuAgent).name} options`}
      onContextMenu={(event) => event.preventDefault()} className="p-1.5">
      <button type="button" role="menuitem" onClick={() => { setMenu(undefined); onOpenDetails(menu.id); }}
        className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left text-[13px] text-content/85 hover:bg-content/8">
        <SlidersHorizontal className="size-3.5 shrink-0" strokeWidth={1.75} />Settings
      </button>
      <button type="button" role="menuitem" onClick={() => { setMenu(undefined); onDelete(menu.id); }}
        className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left text-[13px] text-red-400 hover:bg-content/8">
        <Trash2 className="size-3.5 shrink-0" strokeWidth={1.75} />Delete mentor…
      </button>
    </Popover> : null}
  </nav>;
}
