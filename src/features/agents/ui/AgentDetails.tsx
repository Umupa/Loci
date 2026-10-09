import { useEffect, useRef, useState, type ReactNode } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { projectKey, projectName } from "../../../shared/lib/paths";
import { Plus, Trash2, X } from "../../../shared/ui/icons";
import type { RecentProject } from "../../projects/model/recents";
import { isHarnessAvailable } from "../../../integrations/harness/core/availability";
import { modelsFor, preferredModelId, resolveModel } from "../../sessions/model/models";
import {
  HARNESSES, HARNESS_TITLE, RUNTIME_MODES, RUNTIME_MODE_HINT, RUNTIME_MODE_LABEL,
  type HarnessId, type RuntimeMode, type Session,
} from "../../sessions/model/session";
import {
  AGENT_COLORS,
  addAgentProject,
  agentLook,
  agentWorksOn,
  removeAgentProject,
  updateAgent,
  type Agent,
} from "../model/agent";
import { AGENT_AVATARS, defaultAgentName } from "../model/agentAvatars";
import {
  AgentFileConflict,
  editAgentFile,
  loadAgentFiles,
  memoryWithinBudget,
  saveAgentFile,
  subscribeAgentFiles,
  type AgentFiles,
} from "../model/agentFiles";
import {
  addMemoryEntry,
  memoryDate,
  memoryEntry,
  memoryLines,
  withoutLine,
} from "../model/agentMemory";
import { AgentAvatar } from "./AgentAvatar";
import { AgentHabits } from "./AgentHabits";

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

function Section({ title, hint, children }: { title: string; hint?: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2 border-t border-stroke px-4 py-3.5 first:border-t-0">
      <div className="flex items-baseline gap-2">
        <h3 className="text-xs font-medium text-content/70">{title}</h3>
        {hint ? <span className="min-w-0 truncate text-[11px] text-content/40">{hint}</span> : null}
      </div>
      {children}
    </section>
  );
}

const fieldClass =
  "w-full rounded-md border border-stroke bg-content/5 px-2 py-1.5 text-[13px] text-content outline-none placeholder:text-content/35 focus:border-content/30";

/** Who the agent is, what it works on, its standing instructions and what it remembers. */
export function AgentDetails({ agent, session, onModelChange, onModelSettingsChange, onRuntimeModeChange, recents, refreshKey, onPickFolders, onReset, onDelete, onClose }: Props) {
  const look = agentLook(agent);
  const { files, error } = useAgentFiles(agent.id, refreshKey);
  const candidates = recents.filter((recent) => !agentWorksOn(agent, recent.path));
  return (
    <aside aria-label={`${look.name} details`} className="flex w-80 shrink-0 flex-col border-l border-stroke bg-background-base/60">
      <header className="flex h-11 shrink-0 items-center gap-2 px-4">
        <h2 className="min-w-0 flex-1 truncate text-[13px] font-medium">Details</h2>
        <button type="button" title="Close details" aria-label="Close details" onClick={onClose}
          className="grid size-6 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content">
          <X className="size-3.5" strokeWidth={1.75} />
        </button>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto">
        <Section title="Identity">
          <NameField key={agent.id} agent={agent} />
          <div role="radiogroup" aria-label="Avatar" className="grid grid-cols-5 gap-1.5">
            {AGENT_AVATARS.map((avatar) => (
              <button key={avatar.name} type="button" role="radio" aria-checked={avatar.name === agent.avatar}
                title={defaultAgentName(avatar.name)} aria-label={defaultAgentName(avatar.name)}
                onClick={() => updateAgent(agent.id, (current) => ({ ...current, avatar: avatar.name }))}
                className={`grid place-items-center rounded-md p-1 ${avatar.name === agent.avatar ? "bg-selection-strong" : "hover:bg-content/8"}`}>
                <AgentAvatar name={avatar.name} color={agent.color} className="size-9" />
              </button>
            ))}
          </div>
          <div role="radiogroup" aria-label="Color" className="flex flex-wrap gap-1.5">
            {AGENT_COLORS.map((color) => (
              <button key={color} type="button" role="radio" aria-checked={color === agent.color} aria-label={color}
                onClick={() => updateAgent(agent.id, (current) => ({ ...current, color }))}
                className={`size-5 rounded-full ring-offset-2 ring-offset-background-base ${color === agent.color ? "ring-2 ring-content/60" : ""}`}
                style={{ backgroundColor: color }} />
            ))}
          </div>
        </Section>

        <Section title="Model" hint={session.busy ? "Applies from its next reply" : undefined}>
          <ModelFields session={session} onModelChange={onModelChange} onModelSettingsChange={onModelSettingsChange} onRuntimeModeChange={onRuntimeModeChange} />
        </Section>

        <Section title="Projects" hint="Where it may read, start and message sessions">
          {look.projects.length === 0 ? <p className="text-xs text-content/45">None yet. It can still talk, but cannot reach any project.</p> : null}
          <ul className="flex flex-col gap-px">
            {look.projects.map((project) => (
              <li key={projectKey(project.path)} className="group flex h-7 items-center gap-2 rounded-md px-1.5 hover:bg-content/5" title={project.path}>
                <span className="min-w-0 flex-1 truncate text-[13px]">{project.name}</span>
                <button type="button" title="Remove project" aria-label={`Remove ${project.name}`}
                  onClick={() => removeAgentProject(agent.id, project.path)}
                  className="grid size-5 place-items-center rounded text-content/40 opacity-0 hover:text-content focus-visible:opacity-100 group-hover:opacity-100">
                  <X className="size-3" strokeWidth={1.75} />
                </button>
              </li>
            ))}
          </ul>
          <div className="flex gap-1.5">
            {candidates.length ? (
              <select aria-label="Add a recent project" value="" className={`${fieldClass} min-w-0 flex-1`}
                onChange={(event) => { if (event.target.value) addAgentProject(agent.id, event.target.value); }}>
                <option value="">Add a project…</option>
                {candidates.map((recent) => <option key={recent.path} value={recent.path}>{projectName(recent.path)}</option>)}
              </select>
            ) : null}
            <button type="button" onClick={() => void onPickFolders().then((paths) => { for (const path of paths) addAgentProject(agent.id, path); })}
              className="shrink-0 rounded-md border border-stroke px-2 py-1.5 text-xs text-content/70 hover:bg-content/8 hover:text-content">
              Choose folder…
            </button>
          </div>
        </Section>

        {error ? <p className="px-4 py-3 text-xs text-red-400/90">{error}</p> : null}
        {files ? <SoulSection key={`soul:${agent.id}`} agentId={agent.id} files={files} /> : null}
        {files ? <MemorySection agentId={agent.id} files={files} /> : null}
        <Section title="Habits" hint="What it does on its own while Loci is open">
          <AgentHabits key={agent.id} agentId={agent.id} />
        </Section>

        <Section title="Conversation">
          <div className="flex gap-1.5">
            <button type="button" onClick={onReset}
              className="rounded-md border border-stroke px-2 py-1.5 text-xs text-content/70 hover:bg-content/8 hover:text-content">
              Reset conversation
            </button>
            <button type="button" onClick={onDelete}
              className="inline-flex items-center gap-1.5 rounded-md border border-stroke px-2 py-1.5 text-xs text-content/70 hover:bg-content/8 hover:text-red-400">
              <Trash2 className="size-3" strokeWidth={1.75} /> Delete agent
            </button>
          </div>
          <p className="text-[11px] leading-snug text-content/40">Resetting clears the messages and keeps its soul and memory.</p>
        </Section>
      </div>
    </aside>
  );
}

/** The provider, model, its settings and how much the agent may do unasked. */
function ModelFields({ session, onModelChange, onModelSettingsChange, onRuntimeModeChange }: Pick<Props, "session" | "onModelChange" | "onModelSettingsChange" | "onRuntimeModeChange">) {
  const harnesses = HARNESSES.filter((harness) => harness === session.harness || isHarnessAvailable(harness));
  const models = modelsFor(session.harness);
  const model = resolveModel(session.harness, session.model);
  const row = "flex items-center gap-2";
  const label = "w-20 shrink-0 text-xs text-content/50";
  return (
    <div className="flex flex-col gap-1.5">
      <label className={row}>
        <span className={label}>Provider</span>
        <select value={session.harness} className={`${fieldClass} min-w-0 flex-1`}
          onChange={(event) => { const harness = event.target.value as HarnessId; onModelChange(harness, preferredModelId(harness)); }}>
          {harnesses.map((harness) => <option key={harness} value={harness}>{HARNESS_TITLE[harness]}</option>)}
        </select>
      </label>
      <label className={row}>
        <span className={label}>Model</span>
        <select value={model.id} className={`${fieldClass} min-w-0 flex-1`} onChange={(event) => onModelChange(session.harness, event.target.value)}>
          {models.map((entry) => <option key={entry.id} value={entry.id}>{entry.name}</option>)}
        </select>
      </label>
      {(model.settings ?? []).filter((setting) => setting.options.length > 1).map((setting) => (
        <label key={setting.id} className={row}>
          <span className={label}>{setting.label}</span>
          <select value={session.modelSettings[setting.id] ?? setting.value} className={`${fieldClass} min-w-0 flex-1`}
            onChange={(event) => onModelSettingsChange({ ...session.modelSettings, [setting.id]: event.target.value })}>
            {setting.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </label>
      ))}
      <label className={row} title={RUNTIME_MODE_HINT[session.runtimeMode]}>
        <span className={label}>Permissions</span>
        <select value={session.runtimeMode} className={`${fieldClass} min-w-0 flex-1`} onChange={(event) => onRuntimeModeChange(event.target.value as RuntimeMode)}>
          {RUNTIME_MODES.map((mode) => <option key={mode} value={mode}>{RUNTIME_MODE_LABEL[mode]}</option>)}
        </select>
      </label>
    </div>
  );
}

/** The agent's name, edited in place; empty goes back to its avatar's name. */
function NameField({ agent }: { agent: Agent }) {
  const [name, setName] = useState(agent.name ?? "");
  const save = () => updateAgent(agent.id, (current) => ({ ...current, name: name.trim() }));
  return (
    <input aria-label="Name" value={name} maxLength={40} placeholder={defaultAgentName(agent.avatar)} className={fieldClass}
      onChange={(event) => setName(event.target.value)} onBlur={save}
      onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent)) event.currentTarget.blur(); }} />
  );
}

/** The soul as its Markdown source; saved when you leave it, never over what the agent wrote meanwhile. */
function SoulSection({ agentId, files }: { agentId: string; files: AgentFiles }) {
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
  return (
    <Section title="Soul" hint="Standing instructions, sent once per provider session">
      <textarea aria-label="Soul" value={text} rows={8} spellCheck={false} className={`${fieldClass} resize-y font-mono text-xs leading-relaxed`}
        onChange={(event) => setText(event.target.value)} onBlur={() => void save()} />
      {conflict ? (
        <div className="flex items-center gap-2 text-[11px] text-red-400/90">
          <span className="min-w-0 flex-1">It changed while you were editing.</span>
          <button type="button" className="underline" onClick={() => { opened.current = { text: files.soul, hash: files.soulHash }; setText(files.soul); setConflict(false); }}>Load theirs</button>
          <button type="button" className="underline" onClick={() => { opened.current = { ...opened.current, hash: files.soulHash }; void save(); }}>Keep mine</button>
        </div>
      ) : null}
    </Section>
  );
}

/** What the agent remembers, one fact per row. */
function MemorySection({ agentId, files }: { agentId: string; files: AgentFiles }) {
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
    <Section title="Memory" hint={budget.droppedLines ? `${budget.droppedLines} lines do not load` : `${facts.length} ${facts.length === 1 ? "fact" : "facts"}`}>
      {facts.length === 0 ? <p className="text-xs text-content/45">Nothing yet. It saves what stays useful as it learns it.</p> : null}
      <ul className="flex flex-col gap-px">
        {facts.map((fact) => (
          <li key={`${fact.index}:${fact.text}`} className="group flex items-start gap-2 rounded-md px-1.5 py-1 hover:bg-content/5">
            <span className={`min-w-0 flex-1 text-xs leading-snug ${fact.struck ? "text-content/35 line-through" : "text-content/80"}`}>
              {fact.text}
              {fact.date ? <span className="ml-1.5 text-[11px] text-content/35">{fact.date}</span> : null}
            </span>
            <button type="button" title="Forget" aria-label={`Forget: ${fact.text}`}
              onClick={() => void run((text) => text.split("\n")[fact.index]?.includes(fact.text) ? withoutLine(text, fact.index) : text)}
              className="grid size-5 shrink-0 place-items-center rounded text-content/40 opacity-0 hover:text-content focus-visible:opacity-100 group-hover:opacity-100">
              <X className="size-3" strokeWidth={1.75} />
            </button>
          </li>
        ))}
      </ul>
      <div className="flex gap-1.5">
        <input aria-label="Add a fact" value={draft} placeholder="Add a fact…" className={`${fieldClass} min-w-0 flex-1`}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent)) add(); }} />
        <button type="button" title="Add" aria-label="Add fact" onClick={add} disabled={!draft.trim()}
          className="grid size-[30px] shrink-0 place-items-center rounded-md border border-stroke text-content/60 hover:bg-content/8 hover:text-content disabled:opacity-40">
          <Plus className="size-3.5" strokeWidth={1.75} />
        </button>
      </div>
      {error ? <p className="text-[11px] text-red-400/90">{error}</p> : null}
    </Section>
  );
}
