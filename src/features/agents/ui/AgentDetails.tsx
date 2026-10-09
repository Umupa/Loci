import { useEffect, useRef, useState, type ReactNode } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { ChevronLeft, ChevronRight, Plus, RotateCcw, Trash2, X } from "../../../shared/ui/icons";
import type { RecentProject } from "../../projects/model/recents";
import type { HarnessId, RuntimeMode, Session } from "../../sessions/model/session";
import { AccessPicker } from "../../sessions/ui/AccessPicker";
import { ModelPicker } from "../../sessions/ui/ModelPicker";
import { addAgentProject, agentLook, removeAgentProject, updateAgent, type Agent } from "../model/agent";
import { defaultAgentName } from "../model/agentAvatars";
import {
  AgentFileConflict,
  editAgentFile,
  loadAgentFiles,
  memoryWithinBudget,
  saveAgentFile,
  subscribeAgentFiles,
  type AgentFiles,
} from "../model/agentFiles";
import { loadHabits, subscribeHabitsRunning } from "../model/agentHabits";
import { addMemoryEntry, memoryDate, memoryEntry, memoryLines, withoutLine } from "../model/agentMemory";
import { AgentAvatar } from "./AgentAvatar";
import { AgentHabits } from "./AgentHabits";
import { ColorPicker, FacePicker, ProjectsField } from "./agentPanelParts";

type Props = {
  agent: Agent;
  /** Its conversation, whose model and permissions are set here rather than in the composer. */
  session: Pick<Session, "harness" | "model" | "modelSettings" | "runtimeMode" | "busy">;
  onModelChange: (harness: HarnessId, model: string) => void;
  onModelSettingsChange: (settings: Record<string, string>) => void;
  onRuntimeModeChange: (mode: RuntimeMode) => void;
  recents: readonly RecentProject[];
  /** Bumped when the agent finishes a turn, since it may have rewritten its files. */
  refreshKey: unknown;
  onPickFolders: () => Promise<string[]>;
  onReset: () => void;
  onDelete: () => void;
  onClose: () => void;
};

type Page = "soul" | "habits" | "memory";

const PAGE_TITLE: Record<Page, string> = { soul: "Soul", habits: "Habits", memory: "Memory" };

/** The agent's files, reloaded when it finishes a turn, a save lands or the app regains focus. */
function useAgentFiles(agentId: string, refreshKey: unknown) {
  const [files, setFiles] = useState<AgentFiles>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    let current = true;
    const load = () =>
      loadAgentFiles(agentId).then(
        (loaded) => {
          if (!current) return;
          setFiles(loaded);
          setError(undefined);
        },
        (reason: unknown) => {
          if (current) setError(String(reason));
        },
      );
    void load();
    const unsubscribe = subscribeAgentFiles(() => void load());
    window.addEventListener("focus", load);
    return () => {
      current = false;
      unsubscribe();
      window.removeEventListener("focus", load);
    };
  }, [agentId, refreshKey]);
  return { files, error };
}

/** How many habits it has, kept current as they are added, removed or run. */
function useHabitCount(agentId: string): number | undefined {
  const [count, setCount] = useState<number>();
  useEffect(() => {
    let current = true;
    const load = () => void loadHabits(agentId).then((habits) => { if (current) setCount(habits.length); }, () => undefined);
    load();
    const stopFiles = subscribeAgentFiles(load);
    const stopRuns = subscribeHabitsRunning(load);
    return () => {
      current = false;
      stopFiles();
      stopRuns();
    };
  }, [agentId]);
  return count;
}

const fieldClass =
  "w-full rounded-lg border border-stroke bg-content/5 px-2.5 py-1.5 text-[13px] text-content outline-none placeholder:text-content/35 focus:border-content/30";
const iconButton = "grid size-6 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content";

/**
 * Who the agent is and what it works with, on one page; its soul, habits and
 * memory each open as a page of their own, so none of them crowds the others.
 */
export function AgentDetails({ agent, session, onModelChange, onModelSettingsChange, onRuntimeModeChange, recents, refreshKey, onPickFolders, onReset, onDelete, onClose }: Props) {
  const look = agentLook(agent);
  const { files, error } = useAgentFiles(agent.id, refreshKey);
  const habits = useHabitCount(agent.id);
  const [page, setPage] = useState<Page>();
  // Another agent's details start from the top.
  useEffect(() => setPage(undefined), [agent.id]);
  const facts = files ? memoryLines(files.memory).filter((fact) => !fact.struck).length : undefined;

  return (
    <aside aria-label={`${look.name} details`} className="flex w-[340px] shrink-0 flex-col border-l border-stroke bg-background-base/70 backdrop-blur-xl">
      <header className="flex h-11 shrink-0 items-center gap-1.5 px-3">
        {page ? (
          <button type="button" title="Back" aria-label="Back to details" onClick={() => setPage(undefined)} className={iconButton}>
            <ChevronLeft className="size-4" strokeWidth={1.75} />
          </button>
        ) : null}
        <h2 className="min-w-0 flex-1 truncate px-1 text-[13px] font-medium">{page ? PAGE_TITLE[page] : "Details"}</h2>
        <button type="button" title="Close details" aria-label="Close details" onClick={onClose} className={iconButton}>
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </header>

      {page === "soul" ? (
        files ? <SoulPage key={agent.id} agentId={agent.id} files={files} /> : <PageNote>{error ?? "Loading…"}</PageNote>
      ) : page === "memory" ? (
        files ? <MemoryPage agentId={agent.id} files={files} /> : <PageNote>{error ?? "Loading…"}</PageNote>
      ) : page === "habits" ? (
        <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-4 pb-4">
          <p className="text-xs leading-snug text-content/45">What it does on its own, on a schedule, while Loci is open. It writes to this chat only when there is something to say.</p>
          <AgentHabits key={agent.id} agentId={agent.id} />
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="flex flex-col items-center gap-3 px-4 pb-5 pt-3">
            <AgentAvatar name={look.avatar} color={look.color} className="size-10" />
            <NameField key={agent.id} agent={agent} />
            <FacePicker current={agent.avatar} color={agent.color} onPick={(avatar) => updateAgent(agent.id, (current) => ({ ...current, avatar }))} />
            <ColorPicker current={agent.color} onPick={(color) => updateAgent(agent.id, (current) => ({ ...current, color }))} />
          </div>

          <div className="flex flex-col gap-1 border-t border-stroke px-4 py-3">
            <Property label="Model">
              <ModelPicker harness={session.harness} model={session.model} values={session.modelSettings}
                onChange={onModelChange} onSettingsChange={onModelSettingsChange} />
            </Property>
            <Property label="Permissions">
              <AccessPicker value={session.runtimeMode} busy={!!session.busy} onChange={onRuntimeModeChange} />
            </Property>
            <Property label="Projects" top>
              <ProjectsField projects={agent.projects} recents={recents} onPickFolders={onPickFolders}
                onAdd={(path) => addAgentProject(agent.id, path)} onRemove={(path) => removeAgentProject(agent.id, path)} />
            </Property>
          </div>

          <div className="flex flex-col border-t border-stroke p-2">
            <PageRow title="Soul" description="Who it is and the rules it always follows." onOpen={() => setPage("soul")} />
            <PageRow title="Habits" description="Recurring tasks it runs on its own." count={habits} onOpen={() => setPage("habits")} />
            <PageRow title="Memory" description="Facts and preferences it remembers." count={facts} onOpen={() => setPage("memory")} />
          </div>

          <div className="flex flex-col border-t border-stroke p-2">
            <ActionRow icon={<RotateCcw className="size-3.5" strokeWidth={1.75} />} onClick={onReset}
              title="Reset conversation" description="Clears the messages. Its soul, memory and habits stay." />
            <ActionRow danger icon={<Trash2 className="size-3.5" strokeWidth={1.75} />} onClick={onDelete}
              title="Delete agent" description="Removes it and its conversation." />
          </div>
          {error ? <p className="px-4 pb-3 text-xs text-red-400/90">{error}</p> : null}
        </div>
      )}
    </aside>
  );
}

function PageNote({ children }: { children: ReactNode }) {
  return <p className="px-4 py-3 text-xs text-content/45">{children}</p>;
}

/** One labelled setting: the label in a fixed column, its control beside it. */
function Property({ label, top = false, children }: { label: string; top?: boolean; children: ReactNode }) {
  return (
    <div className={`flex min-h-8 gap-2 ${top ? "items-start" : "items-center"}`}>
      <span className={`w-24 shrink-0 text-[13px] text-content/50 ${top ? "pt-1.5" : ""}`}>{label}</span>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}

/** A row that opens a page: its name, what it holds, how many, and a chevron. */
function PageRow({ title, description, count, onOpen }: { title: string; description: string; count?: number; onOpen: () => void }) {
  return (
    <button type="button" onClick={onOpen} className="flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-content/6">
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="text-[13px] text-content">{title}</span>
        <span className="truncate text-xs text-content/45">{description}</span>
      </span>
      {count ? <span className="shrink-0 text-xs tabular-nums text-content/45">{count}</span> : null}
      <ChevronRight className="size-3.5 shrink-0 text-content/35" strokeWidth={1.75} />
    </button>
  );
}

function ActionRow({ title, description, icon, danger = false, onClick }: { title: string; description: string; icon: ReactNode; danger?: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick}
      className={`flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-content/6 ${danger ? "text-red-400" : "text-content/80"}`}>
      <span className="grid size-5 shrink-0 place-items-center">{icon}</span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="text-[13px]">{title}</span>
        <span className="truncate text-xs text-content/45">{description}</span>
      </span>
    </button>
  );
}

/** The agent's name under its face, edited in place; empty goes back to its face's name. */
function NameField({ agent }: { agent: Agent }) {
  const [name, setName] = useState(agent.name ?? "");
  const save = () => updateAgent(agent.id, (current) => ({ ...current, name: name.trim() }));
  return (
    <input aria-label="Name" value={name} maxLength={40} placeholder={defaultAgentName(agent.avatar)}
      className="w-full rounded-lg bg-transparent px-2 py-1 text-center text-[15px] font-medium text-content outline-none placeholder:text-content/60 hover:bg-content/5 focus:bg-content/6"
      onChange={(event) => setName(event.target.value)} onBlur={save}
      onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent)) event.currentTarget.blur(); }} />
  );
}

/** The soul as its Markdown source; saved when you leave it, never over what the agent wrote meanwhile. */
function SoulPage({ agentId, files }: { agentId: string; files: AgentFiles }) {
  const [text, setText] = useState(files.soul);
  const opened = useRef({ text: files.soul, hash: files.soulHash });
  const [conflict, setConflict] = useState(false);
  // Follow the file while the field is untouched; an unsaved draft is never replaced.
  useEffect(() => {
    if (text === opened.current.text) {
      opened.current = { text: files.soul, hash: files.soulHash };
      setText(files.soul);
      setConflict(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [files.soul, files.soulHash]);
  const save = async () => {
    if (text === opened.current.text) return;
    try {
      const hash = await saveAgentFile(agentId, "soul", text, opened.current.hash);
      opened.current = { text, hash };
      setConflict(false);
    } catch (error) {
      if (!(error instanceof AgentFileConflict)) throw error;
      setConflict(true);
    }
  };
  // Leaving the page is leaving the field.
  const latest = useRef(save);
  latest.current = save;
  useEffect(() => () => void latest.current().catch(() => undefined), []);
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2 px-4 pb-4">
      <p className="text-xs leading-snug text-content/45">Its standing instructions, in Markdown. It reads them at the start of each provider conversation; it changes them only when you ask.</p>
      <textarea aria-label="Soul" value={text} spellCheck={false} className={`${fieldClass} min-h-0 flex-1 resize-none font-mono text-xs leading-relaxed`}
        onChange={(event) => setText(event.target.value)} onBlur={() => void save()} />
      {conflict ? (
        <div className="flex items-center gap-2 text-[11px] text-red-400/90">
          <span className="min-w-0 flex-1">It changed while you were editing.</span>
          <button type="button" className="underline" onClick={() => { opened.current = { text: files.soul, hash: files.soulHash }; setText(files.soul); setConflict(false); }}>Load theirs</button>
          <button type="button" className="underline" onClick={() => { opened.current = { ...opened.current, hash: files.soulHash }; void save(); }}>Keep mine</button>
        </div>
      ) : null}
    </div>
  );
}

/** What the agent remembers, one fact per row. */
function MemoryPage({ agentId, files }: { agentId: string; files: AgentFiles }) {
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string>();
  const facts = memoryLines(files.memory);
  const budget = memoryWithinBudget(files.memory);
  const run = (edit: (text: string) => string) =>
    editAgentFile(agentId, "memory", edit).then(() => setError(undefined), (reason: unknown) => setError(reason instanceof Error ? reason.message : String(reason)));
  const add = () => {
    const fact = draft.trim();
    if (!fact) return;
    setDraft("");
    void run((text) => addMemoryEntry(text, memoryEntry(fact, memoryDate(new Date()))).text);
  };
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2 px-4 pb-4">
      <p className="text-xs leading-snug text-content/45">
        It saves what stays useful as it learns it, and reads this at the start of each provider conversation.
        {budget.droppedLines ? ` ${budget.droppedLines} lines are past what loads.` : ""}
      </p>
      <div className="flex gap-1.5">
        <input aria-label="Add a fact" value={draft} placeholder="Add a fact…" className={`${fieldClass} min-w-0 flex-1`}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent)) add(); }} />
        <button type="button" title="Add" aria-label="Add fact" onClick={add} disabled={!draft.trim()}
          className="grid size-[32px] shrink-0 place-items-center rounded-lg border border-stroke text-content/60 hover:bg-content/8 hover:text-content disabled:opacity-40">
          <Plus className="size-3.5" strokeWidth={1.75} />
        </button>
      </div>
      {error ? <p className="text-[11px] text-red-400/90">{error}</p> : null}
      {facts.length === 0 ? <p className="py-6 text-center text-xs text-content/40">Nothing remembered yet.</p> : null}
      <ul className="-mx-1.5 flex min-h-0 flex-1 flex-col gap-px overflow-y-auto">
        {facts.map((fact) => (
          <li key={`${fact.index}:${fact.text}`} className="group flex items-start gap-2 rounded-lg px-1.5 py-1.5 hover:bg-content/5">
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className={`text-[13px] leading-snug ${fact.struck ? "text-content/35 line-through" : "text-content/85"}`}>{fact.text}</span>
              {fact.date ? <span className="text-[11px] text-content/35">{fact.date}{fact.until ? ` · until ${fact.until}` : ""}</span> : null}
            </span>
            <button type="button" title="Forget" aria-label={`Forget: ${fact.text}`}
              onClick={() => void run((text) => text.split("\n")[fact.index]?.includes(fact.text) ? withoutLine(text, fact.index) : text)}
              className="grid size-5 shrink-0 place-items-center rounded text-content/40 opacity-0 hover:text-content focus-visible:opacity-100 group-hover:opacity-100">
              <X className="size-3" strokeWidth={1.75} />
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
