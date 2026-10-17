import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { CheckCheck, Chatting, LoaderCircle, Newspaper, RefreshCw, Search } from "../../../shared/ui/icons";
import { ACTION_GHOST, EmptyDetail, IconButton } from "../../../shared/ui/inboxParts";
import { agentLook, agentsSnapshot, listAgents, subscribeAgents, type Agent } from "../../agents/model/agent";
import { AgentAvatar } from "../../agents/ui/AgentAvatar";
import { loadNotes, NOTES_CHANGED_EVENT, type Note } from "../../notes";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { BRIEFING_TAG, isBriefing, loadSeenBriefings, saveSeenBriefings } from "../model/briefings";

type Props = {
  /** Show the agent's conversation, where a question about a briefing was put. */
  onOpenAgent: (agentId: string) => void;
};

/**
 * Reports agents file on a schedule: notes tagged `briefing`, newest first,
 * read here like any other feed and discussed with the agent that wrote them.
 */
export function BriefingsView({ onOpenAgent }: Props) {
  const roster = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  const agents = useMemo(() => new Map(listAgents().map((agent) => [agent.id, agent])), [roster]);
  const [notes, setNotes] = useState<Note[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [seen, setSeen] = useState(loadSeenBriefings);

  const refresh = useCallback(() => {
    setLoading(true);
    void loadNotes(true).then((all) => setNotes(all.filter(isBriefing).sort((a, b) => b.createdAt - a.createdAt)))
      .finally(() => setLoading(false));
  }, []);
  useEffect(() => {
    refresh();
    window.addEventListener(NOTES_CHANGED_EVENT, refresh);
    return () => window.removeEventListener(NOTES_CHANGED_EVENT, refresh);
  }, [refresh]);

  const markSeen = (ids: string[]) => setSeen((current) => {
    const next = new Set([...current, ...ids]);
    saveSeenBriefings(next);
    return next;
  });
  const needle = query.trim().toLowerCase();
  const shown = (notes ?? []).filter((note) => !needle || note.title.toLowerCase().includes(needle) || note.body.toLowerCase().includes(needle));
  const unread = shown.filter((note) => !seen.has(note.id));
  const selected = shown.find((note) => note.id === selectedId);
  const select = (note: Note) => { setSelectedId(note.id); markSeen([note.id]); };
  const owner = selected?.agentId ? agents.get(selected.agentId) : undefined;
  const discuss = (note: Note, agent: Agent) => {
    if (!agent.sessionId) return;
    requestAddToChat(`About the briefing "${note.title}" (loci://note/${note.id}):`, "plain", { targetSessionId: agent.sessionId });
    onOpenAgent(agent.id);
  };

  return <div className="flex min-h-0 min-w-0 flex-1">
    <div className="relative flex h-full min-h-0 w-[300px] shrink-0 flex-col border-r border-stroke">
      <form onSubmit={(event) => event.preventDefault()} className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
        <div className="relative flex h-7 min-w-0 flex-1 items-center">
          <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
          <input value={query} onChange={(event) => setQuery(event.target.value)} spellCheck={false} autoComplete="off"
            placeholder="Filter briefings" aria-label="Filter briefings"
            className="h-7 w-full rounded-md bg-transparent pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/40" />
        </div>
        <IconButton label="Mark all as read" disabled={!unread.length} onClick={() => markSeen(unread.map((note) => note.id))}>
          <CheckCheck className="size-3.5" />
        </IconButton>
        <IconButton label="Refresh" onClick={refresh}>
          {loading ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />}
        </IconButton>
      </form>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-none">
        {notes === null ? <div className="flex justify-center py-10 text-content/40"><LoaderCircle className="size-4 animate-spin" /></div>
          : !shown.length ? <p className="px-3 py-2 text-[12px] leading-relaxed text-content/50">
            {needle ? "No matching briefings" : `Nothing yet. An agent's habit files a briefing by saving a note tagged “${BRIEFING_TAG}”.`}</p>
          : <ul className="flex flex-col gap-0.5 p-1.5">{shown.map((note) => {
            const agent = note.agentId ? agents.get(note.agentId) : undefined;
            const look = agent ? agentLook(agent) : undefined;
            return <li key={note.id}><button type="button" aria-current={note.id === selectedId ? "true" : undefined} onClick={() => select(note)} data-briefing={note.id}
              className={`flex w-full flex-col rounded-md px-2.5 py-2 text-left ${note.id === selectedId ? "bg-selection text-content" : "text-content/80 hover:bg-content/5 hover:text-content"}`}>
              <span className="flex items-center gap-1.5 text-[11px] text-content/50">
                {look ? <AgentAvatar name={look.avatar} color={look.color} className="size-3.5 shrink-0" /> : null}
                <span className="min-w-0 flex-1 truncate">{look?.name ?? "Briefing"}</span>
                <span className="shrink-0 tabular-nums">{formatRelativeTime(new Date(note.createdAt).toISOString())}</span>
              </span>
              <span className={`mt-1 line-clamp-2 text-[13px] leading-snug ${seen.has(note.id) ? "text-content/70" : "font-semibold text-content"}`}>{note.title}</span>
            </button></li>;
          })}</ul>}
      </div>
    </div>
    <div className="relative flex min-h-0 min-w-0 flex-1 flex-col">
      {selected ? <>
        <div className="flex h-9 shrink-0 items-center gap-2 border-b border-stroke px-3">
          <span className="min-w-0 flex-1 truncate text-[12px] text-content/55">{new Date(selected.createdAt).toLocaleString()}</span>
          {owner?.sessionId ? <button type="button" className={ACTION_GHOST} onClick={() => discuss(selected, owner)}>
            <Chatting className="size-3.5" /> Ask {agentLook(owner).name}
          </button> : null}
        </div>
        <article className="min-h-0 flex-1 select-text overflow-y-auto px-8 py-6">
          <div className="mx-auto max-w-3xl"><AgentMarkdown text={selected.body.trimStart().startsWith("# ") ? selected.body : `# ${selected.title}\n\n${selected.body}`} wholeDocument /></div>
        </article>
      </> : <EmptyDetail icon={<Newspaper className="size-6" />}>Select a briefing</EmptyDetail>}
    </div>
  </div>;
}
