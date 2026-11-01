import { useEffect, useRef, useState, type ReactNode } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { Pencil, Plus, Settings, Sparkles, StickyNote, X } from "../../../shared/ui/icons";
import type { RecentProject } from "../../projects/model/recents";
import type { HarnessId, RuntimeMode, Session } from "../../sessions/model/session";
import { AccessPicker } from "../../sessions/ui/AccessPicker";
import { ModelPicker, ModelSettingRows } from "../../sessions/ui/ModelPicker";
import { addAgentProject, agentLook, removeAgentProject, updateAgent, type Agent } from "../model/agent";
import { ensureAgentWorkdir, folderHolds, setAgentWorkdir } from "../model/agentWorkdir";
import { pickFolder, revealPath } from "../../../platform/tauri/fs";
import { prettyCwd } from "../../../shared/lib/paths";
import { defaultAgentName } from "../model/agentAvatars";
import {
  AgentFileConflict,
  editAgentFile,
  loadAgentFiles,
  memoryForContext,
  memoryWithinBudget,
  saveAgentFile,
  subscribeAgentFiles,
  type AgentFilePath,
  type AgentFiles,
} from "../model/agentFiles";
import { addMemoryEntry, memoryDate, memoryEntry, memoryLines, withLineEdited, withoutLine } from "../model/agentMemory";
import { AgentAvatarPreview } from "./AgentAvatar";
import { ColorPicker, FacePicker, ProjectsField } from "./agentPanelParts";
import { Popover } from "../../../shared/ui/Popover";

type Props = {
  agent: Agent;
  /** Its conversation, whose model and permissions are set here rather than in the composer. */
  session: Pick<Session, "harness" | "model" | "modelSettings" | "runtimeMode" | "busy" | "cwd">;
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

type Page = "general" | "soul" | "memory";

const PAGE_TITLE: Record<Page, string> = { general: "General", soul: "Soul", memory: "Memory" };

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

const fieldClass =
  "w-full rounded-lg border border-stroke bg-content/5 px-2.5 py-1.5 text-[13px] text-content outline-none placeholder:text-content/35 focus:border-content/30";
const iconButton = "grid size-6 shrink-0 place-items-center rounded-md text-content/50 hover:bg-content/8 hover:text-content";

/** Settings use the same left navigation and grouped properties as Monos. */
export function AgentDetails({ agent, session, onModelChange, onModelSettingsChange, onRuntimeModeChange, recents, refreshKey, onPickFolders, onReset, onDelete }: Props) {
  const look = agentLook(agent);
  const { files, error } = useAgentFiles(agent.id, refreshKey);
  const [page, setPage] = useState<Page>("general");
  useEffect(() => setPage("general"), [agent.id]);
  const icons = { general: Settings, soul: Sparkles, memory: StickyNote };
  return <div aria-label={`${look.name} settings`} className="agent-settings-layout">
    <nav role="tablist" aria-label="Agent settings" aria-orientation="vertical" className="agent-settings-nav">
      <p>Settings</p>
      {(Object.keys(PAGE_TITLE) as Page[]).map((id) => {
        const Icon = icons[id];
        return <button key={id} type="button" role="tab" aria-selected={page === id} onClick={() => setPage(id)}><Icon className="size-3.5 shrink-0" strokeWidth={1.75} />{PAGE_TITLE[id]}</button>;
      })}
    </nav>
    <div className="agent-settings-content" role="tabpanel" aria-label={PAGE_TITLE[page]}>
      {page === "general" ? <div className="agent-settings-general">
        <h3>General</h3>
        <div className="agent-settings-identity">
          <AppearanceButton agent={agent} />
          <div className="mt-2 flex w-full max-w-sm flex-col items-center"><NameField key={`name:${agent.id}:${agent.name ?? ""}`} agent={agent} /><RoleField key={`role:${agent.id}:${agent.role ?? ""}`} agent={agent} /></div>
        </div>
        <h4 className="agent-setting-group-title">Model</h4>
        <div className="agent-setting-group">
          <SettingRow label="Model" description="What it thinks and replies with."><ModelPicker harness={session.harness} model={session.model} values={session.modelSettings} hideSettings onChange={onModelChange} onSettingsChange={onModelSettingsChange} /></SettingRow>
          <ModelSettingRows harness={session.harness} model={session.model} values={session.modelSettings} onSettingsChange={onModelSettingsChange}
            row={(label, control) => <SettingRow label={label}>{control}</SettingRow>} />
          <SettingRow label="Permissions" description="What it may do without asking."><AccessPicker value={session.runtimeMode} busy={!!session.busy} onChange={onRuntimeModeChange} /></SettingRow>
        </div>
        <h4 className="agent-setting-group-title">Files</h4>
        <div className="agent-setting-group">
          <WorkdirRow agent={agent} chatCwd={session.cwd} />
          <div className="agent-setting-row flex-col items-stretch">
            <div className="agent-setting-label"><span>Other folders</span><small>More folders it may read and work in.</small></div>
            <ProjectsField projects={agent.projects} recents={recents} onPickFolders={onPickFolders}
              onAdd={(path) => addAgentProject(agent.id, path)} onRemove={(path) => removeAgentProject(agent.id, path)} />
          </div>
        </div>
        <h4 className="agent-setting-group-title">Conversation</h4>
        <div className="agent-setting-group">
          <SettingRow label="Reset conversation" description="Clear messages. Soul, memory and habits stay."><button type="button" onClick={onReset} className="rounded-md border border-stroke px-3 py-1.5 text-xs text-red-400 hover:bg-red-400/8">Reset</button></SettingRow>
          <SettingRow label="Delete agent" description="Remove this agent and its conversation."><button type="button" onClick={onDelete} className="rounded-md border border-stroke px-3 py-1.5 text-xs text-red-400 hover:bg-red-400/8">Delete</button></SettingRow>
        </div>
        {error ? <p role="alert" className="mt-3 text-xs text-red-400/90">{error}</p> : null}
      </div> : <>
        <h3 className="agent-settings-page-title">{PAGE_TITLE[page]}</h3>
        {files ? page === "soul" ? <SoulPage key={agent.id} agentId={agent.id} files={files} /> : <MemoryPage key={agent.id} agentId={agent.id} files={files} />
          : <p role={error ? "alert" : "status"} className="p-6 text-xs text-content/50">{error ?? "Loading…"}</p>}
      </>}
    </div>
  </div>;
}

/**
 * Where the mentor keeps cloned source and experiments. Choosing a folder the
 * user already has uses it as it is; nothing in it is moved or changed.
 */
function WorkdirRow({ agent, chatCwd }: { agent: Agent; chatCwd?: string }) {
  const [shown, setShown] = useState(agent.workdir);
  const [error, setError] = useState<string>();
  useEffect(() => {
    setShown(agent.workdir);
    if (agent.workdir) return;
    let live = true;
    ensureAgentWorkdir(agent.id).then((path) => live && setShown(path), (reason: unknown) => live && setError(String(reason)));
    return () => { live = false; };
  }, [agent.id, agent.workdir]);
  const change = () => void pickFolder("Choose a working folder", shown).then(async (path) => {
    if (!path) return;
    try {
      setShown(await setAgentWorkdir(agent.id, path));
      setError(undefined);
    } catch (reason) {
      setError(String(reason));
    }
  });
  // A running chat stays in the folder it started in; its provider conversation is tied to it.
  const elsewhere = !!shown && !!chatCwd && !folderHolds(chatCwd, shown);
  const description = error ?? (elsewhere
    ? "The current chat keeps running in its own folder; Reset conversation to start it here."
    : "Cloned source and experiments go here.");
  return <SettingRow label="Working folder" description={description}>
    <div className="flex min-w-0 items-center gap-1.5">
      <span className="min-w-0 truncate text-[12px] text-content/70" title={shown}>{shown ? prettyCwd(shown) : "…"}</span>
      {shown ? <button type="button" onClick={() => void revealPath(shown)} className="shrink-0 rounded-md border border-stroke px-2 py-1 text-xs text-content/70 hover:bg-content/6">Reveal</button> : null}
      <button type="button" onClick={change} className="shrink-0 rounded-md border border-stroke px-2 py-1 text-xs text-content/70 hover:bg-content/6">Change…</button>
    </div>
  </SettingRow>;
}

function SettingRow({ label, description, children }: { label: string; description?: string; children: ReactNode }) {
  return <div className="agent-setting-row"><div className="agent-setting-label"><span>{label}</span>{description ? <small>{description}</small> : null}</div><div className="agent-setting-value">{children}</div></div>;
}

function AppearanceButton({ agent }: { agent: Agent }) {
  const [open, setOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  const look = agentLook(agent);
  return <>
    <button ref={anchor} type="button" aria-label="Change avatar and color" title="Change avatar and color" aria-haspopup="dialog" aria-expanded={open} onClick={() => setOpen((value) => !value)}
      className="grid size-20 place-items-center rounded-2xl border border-stroke bg-content/4 hover:bg-content/8"><AgentAvatarPreview name={look.avatar} color={look.color} className="size-12" /></button>
    {open ? <Popover anchor={anchor} side="bottom" align="center" width={280} constrainHeight={false} onDismiss={() => setOpen(false)} autoFocus role="dialog" aria-label="Avatar and color" data-dialog-popover className="flex flex-col gap-3 p-3">
      <FacePicker current={agent.avatar} color={agent.color} onPick={(avatar) => updateAgent(agent.id, (current) => ({ ...current, avatar }))} />
      <div className="border-t border-stroke pt-3"><ColorPicker current={agent.color} onPick={(color) => updateAgent(agent.id, (current) => ({ ...current, color }))} /></div>
    </Popover> : null}
  </>;
}

/** The agent's name under its face, edited in place; empty goes back to its face's name. */
function NameField({ agent }: { agent: Agent }) {
  const [name, setName] = useState(agent.name ?? "");
  const save = () => updateAgent(agent.id, (current) => ({ ...current, name: name.trim() }));
  return (
    <input aria-label="Name" value={name} maxLength={40} placeholder={defaultAgentName(agent.avatar)}
      className="w-full rounded-lg bg-transparent px-2 py-1 text-center text-[18px] font-medium text-content outline-none placeholder:text-content/60 hover:bg-content/5 focus:bg-content/6"
      onChange={(event) => setName(event.target.value)} onBlur={save}
      onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent)) event.currentTarget.blur(); }} />
  );
}

/** Its short job label; a new agent can infer it from the user's first message. */
function RoleField({ agent }: { agent: Agent }) {
  const [role, setRole] = useState(agent.role ?? "");
  const save = () => updateAgent(agent.id, (current) => ({ ...current, role: role.trim() }));
  return (
    <input aria-label="Role" value={role} maxLength={60} placeholder="What it is for, in a few words"
      className="w-full rounded-md bg-transparent px-2 py-0.5 text-center text-xs text-content/60 outline-none placeholder:text-content/30 hover:bg-content/5 focus:bg-content/6"
      onChange={(event) => setRole(event.target.value)} onBlur={save}
      onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent)) event.currentTarget.blur(); }} />
  );
}

/** The soul as its Markdown source; saved when you leave it, never over what the agent wrote meanwhile. */
function SoulPage({ agentId, files }: { agentId: string; files: AgentFiles }) {
  const [text, setText] = useState(files.soul);
  const opened = useRef({ text: files.soul, hash: files.soulHash });
  const [conflict, setConflict] = useState(false);
  const [error, setError] = useState<string>();
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
      setError(undefined);
    } catch (saveError) {
      // The draft stays in the field so nothing typed is lost.
      if (!(saveError instanceof AgentFileConflict)) setError(String(saveError));
      else setConflict(true);
    }
  };
  // Leaving the page is leaving the field.
  const latest = useRef(save);
  latest.current = save;
  useEffect(() => () => void latest.current().catch(() => undefined), []);
  return (
    <div className="agent-settings-file-page flex min-h-0 flex-1 flex-col gap-3">
      <p className="text-xs leading-snug text-content/45">The rules it keeps while helping you. Refine them here or in chat.</p>
      <textarea aria-label="Soul" value={text} spellCheck={false} className={`${fieldClass} min-h-0 flex-1 resize-none font-mono text-xs leading-relaxed`}
        onChange={(event) => setText(event.target.value)} onBlur={() => void save()} />
      {conflict ? (
        <div className="flex items-center gap-2 text-[11px] text-red-400/90">
          <span className="min-w-0 flex-1">It changed while you were editing.</span>
          <button type="button" className="underline" onClick={() => { opened.current = { text: files.soul, hash: files.soulHash }; setText(files.soul); setConflict(false); setError(undefined); }}>Load theirs</button>
          <button type="button" className="underline" onClick={() => { opened.current = { ...opened.current, hash: files.soulHash }; void save(); }}>Keep mine</button>
        </div>
      ) : null}
      {error ? <p role="alert" className="text-[11px] text-red-400">Could not save the Soul. {error}</p> : null}
    </div>
  );
}

/** Facts stay editable even if another writer inserts or removes rows. */
function MemoryPage({ agentId, files }: { agentId: string; files: AgentFiles }) {
  const [draft, setDraft] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string>();
  const topics = (files.topicNotes ?? []).filter((note) => memoryLines(note.text).length);
  const budget = memoryWithinBudget(memoryForContext(files));
  const run = async (path: AgentFilePath, edit: (text: string) => string) => {
    setSaving(true);
    try { await editAgentFile(agentId, path, edit); setError(undefined); return true; }
    catch (reason) { setError(String(reason)); return false; }
    finally { setSaving(false); }
  };
  const add = async () => {
    const fact = draft.trim();
    if (fact && await run("MEMORY.md", (text) => addMemoryEntry(text, memoryEntry(fact, memoryDate(new Date()))).text)) setDraft("");
  };
  const empty = !memoryLines(files.memory).length && !topics.length;
  return <div className="agent-settings-file-page flex min-h-0 flex-1 flex-col gap-3">
    <p className="text-xs leading-snug text-content/45">Facts and preferences carried across conversations, topics included.{budget.droppedLines ? ` ${budget.droppedLines} lines are past what loads.` : ""}</p>
    <div className="flex gap-1.5"><input aria-label="Add a fact" value={draft} placeholder="Add a fact…" className={`${fieldClass} min-w-0 flex-1`} onChange={(event) => setDraft(event.target.value)}
      onKeyDown={(event) => { if (event.key === "Enter" && !isImeComposition(event.nativeEvent) && !saving) void add(); }} /><button type="button" title="Add" aria-label="Add fact" onClick={() => void add()} disabled={saving || !draft.trim()} className="grid size-8 place-items-center rounded-md border border-stroke disabled:opacity-40"><Plus className="size-3.5" /></button></div>
    {error ? <p role="alert" className="text-xs text-red-400">{error}</p> : null}
    {empty ? <p className="py-6 text-center text-xs text-content/40">Nothing remembered yet.</p> : null}
    <div className="-mx-1.5 flex min-h-0 flex-col gap-3 overflow-y-auto">
      <MemoryFacts path="MEMORY.md" text={files.memory} saving={saving} run={run} onError={setError} />
      {topics.map((note) => <section key={note.name} className="flex flex-col gap-px">
        <h3 className="px-1.5 text-[11px] font-medium uppercase tracking-wide text-content/40">{note.name}</h3>
        <MemoryFacts path={`memory/${note.name}.md`} text={note.text} saving={saving} run={run} onError={setError} />
      </section>)}
    </div>
  </div>;
}

function MemoryFacts({ path, text, saving, run, onError }: {
  path: AgentFilePath;
  text: string;
  saving: boolean;
  run: (path: AgentFilePath, edit: (text: string) => string) => Promise<boolean>;
  onError: (error: string | undefined) => void;
}) {
  const [editing, setEditing] = useState<{ original: string; text: string }>();
  const facts = memoryLines(text);
  if (!facts.length) return null;
  const locate = (current: string, original: string) => {
    const indices = current.split("\n").flatMap((line, index) => line === original ? [index] : []);
    if (indices.length !== 1) throw new Error("This memory changed while you were editing. Your draft is kept; cancel and choose the updated fact to try again.");
    return indices[0];
  };
  const save = async () => {
    const edit = editing;
    if (edit && edit.text.trim() && await run(path, (current) => withLineEdited(current, locate(current, edit.original), edit.text, memoryDate(new Date())))) setEditing(undefined);
  };
  const editor = editing ? <div className="flex w-full flex-col gap-2 rounded-md border border-stroke p-2">
    <textarea aria-label="Edit memory" value={editing.text} rows={3} className={fieldClass} onChange={(event) => setEditing({ ...editing, text: event.target.value })} />
    <div className="flex justify-end gap-2 text-xs"><button type="button" disabled={saving} onClick={() => { setEditing(undefined); onError(undefined); }}>Cancel</button><button type="button" disabled={saving || !editing.text.trim()} onClick={() => void save()} className="rounded bg-content/10 px-2 py-1">{saving ? "Saving…" : "Save"}</button></div>
  </div> : null;
  const lines = text.split("\n");
  const originalPresent = editing && lines.includes(editing.original);
  return <>
    {!originalPresent ? editor : null}
    <ul className="flex flex-col gap-px">
      {facts.map((fact) => {
        const original = lines[fact.index];
        return <li key={`${fact.index}:${fact.text}`} className="group flex items-start gap-2 rounded-md px-1.5 py-2 hover:bg-content/5">
          {editing?.original === original ? editor : <>
            <span className="flex min-w-0 flex-1 flex-col gap-0.5"><span className={`text-[13px] leading-snug ${fact.struck ? "text-content/35 line-through" : "text-content/85"}`}>{fact.text}</span>{fact.date ? <span className="text-[11px] text-content/35">{fact.date}{fact.until ? ` · until ${fact.until}` : ""}</span> : null}</span>
            <button type="button" title="Edit" aria-label={`Edit: ${fact.text}`} disabled={saving} onClick={() => { setEditing({ original, text: fact.text }); onError(undefined); }} className={`${iconButton} opacity-0 group-hover:opacity-100 focus-visible:opacity-100`}><Pencil className="size-3" /></button>
            <button type="button" title="Forget" aria-label={`Forget: ${fact.text}`} disabled={saving} onClick={() => void run(path, (current) => withoutLine(current, locate(current, original)))} className={`${iconButton} opacity-0 group-hover:opacity-100 focus-visible:opacity-100`}><X className="size-3" /></button>
          </>}
        </li>;
      })}
    </ul>
  </>;
}
