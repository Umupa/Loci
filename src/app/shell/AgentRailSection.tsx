import { useMemo, useState, useSyncExternalStore } from "react";
import { useAnimatedReorder } from "../../shared/hooks/useAnimatedReorder";
import { MoreHorizontal, Plus, SlidersHorizontal, Trash2 } from "../../shared/ui/icons";
import { Popover, type PopoverAnchor } from "../../shared/ui/Popover";
import { Shimmer } from "../../shared/ui/Shimmer";
import { AGENT_TEMPLATES } from "../../features/agents/model/agentTemplates";
import { AgentAvatar } from "../../features/agents/ui/AgentAvatar";
import { AgentStatusDot } from "../../features/agents/ui/AgentStatus";
import {
  AGENT_STATUS_LABEL,
  agentLook,
  agentProjectsPhrase,
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
  /** Makes an agent: from a built-in template, or blank to settle its job in the chat. */
  onCreate: (templateId?: string) => void;
  onDelete: (agentId: string) => void;
};

const IDLE: AgentState = { status: "idle" };

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
  const [creating, setCreating] = useState<PopoverAnchor>();
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
            aria-haspopup="menu"
            onClick={(event) => setCreating(event.currentTarget)}
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
            aria-haspopup="menu"
            onClick={(event) => setCreating(event.currentTarget)}
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
          const unseen = !selected && !!unseenIds?.has(agent.id);
          const preview = previews[agent.id];
          const status = state.status === "idle" ? undefined : (state.activity ?? AGENT_STATUS_LABEL[state.status]);
          return (
            <div
              key={agent.id}
              ref={(el) => sortable.setItemRef(agent.id, el)}
              data-selected={selected || undefined}
              data-agent-status={state.status}
              className={`reorder-item project-reorder-item group relative flex h-8 cursor-default touch-none items-stretch rounded-md px-2 ${
                selected ? "bg-selection-strong text-content" : "opacity-65"
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
                title={[look.role ? `${look.name} · ${look.role}` : look.name, projects || "No projects yet", status ?? (preview ? `${preview.text}${preview.at != null ? ` · ${previewTimeLabel(preview.at)}` : ""}` : undefined)].filter(Boolean).join("\n")}
                aria-label={[look.name, status ?? "idle", projects || "no projects yet"].join(", ")}
                aria-current={selected ? "true" : undefined}
                className="flex min-w-0 flex-1 cursor-default items-center gap-2 text-left group-hover:pr-6 group-has-[:focus-visible]:pr-6"
              >
                {/* The same size and place as a project's mascot, so the rail reads as one list. */}
                <span className="relative grid size-4 shrink-0 place-items-center">
                  <AgentAvatar name={look.avatar} color={look.color} className="size-4" />
                  {state.status === "idle" ? null : (
                    <AgentStatusDot status={state.status} color={look.color} className="-right-1 -top-1 size-1.5" />
                  )}
                </span>
                {state.status === "working" ? (
                  <Shimmer as="span" duration={1.4} className="min-w-0 flex-1 truncate text-[13px]">{look.name}</Shimmer>
                ) : (
                  <span className="min-w-0 flex-1 truncate text-[13px]">{look.name}</span>
                )}
                {unseen ? <span aria-hidden className="size-1.5 shrink-0 rounded-full bg-content/60 group-hover:hidden group-has-[:focus-visible]:hidden" /> : null}
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
      {creating ? (
        <Popover anchor={creating} side="right" align="start" gap={6} width={320} constrainHeight={false}
          onDismiss={() => setCreating(undefined)} role="menu" aria-label="New agent" className="p-1.5">
          <button type="button" role="menuitem" onClick={() => { setCreating(undefined); onCreate(); }}
            className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-left hover:bg-content/8">
            <span className="grid size-6 shrink-0 place-items-center rounded-md bg-content/8 text-content/70"><Plus className="size-3.5" strokeWidth={1.75} /></span>
            <span className="flex min-w-0 flex-col">
              <span className="text-[13px] text-content">New agent</span>
              <span className="truncate text-xs text-content/45">Tell it what its job is.</span>
            </span>
          </button>
          <div className="px-2.5 pb-1 pt-2 text-[11px] text-content/40">Start from a template</div>
          {AGENT_TEMPLATES.map((template) => (
            <button key={template.id} type="button" role="menuitem" onClick={() => { setCreating(undefined); onCreate(template.id); }}
              className="flex w-full flex-col rounded-lg px-2.5 py-1.5 text-left hover:bg-content/8">
              <span className="text-[13px] text-content">{template.name} <span className="text-content/45">· {template.role}</span></span>
              <span className="truncate text-xs text-content/45">{template.description}</span>
            </button>
          ))}
        </Popover>
      ) : null}
    </div>
  );
}
