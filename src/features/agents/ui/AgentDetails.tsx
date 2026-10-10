import { CANVASES_CHANGED_EVENT, loadCanvases, type Canvas } from "../../canvas/canvas";
import { requestOpenAppResource } from "../../../shared/lib/appResourceLinks";
import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { AiIdea, ChevronLeft, ChevronRight, File, Palette, Plus, RotateCcw, Trash2, X } from "../../../shared/ui/icons";
import type { RecentProject } from "../../projects/model/recents";
import type { HarnessId, RuntimeMode, Session } from "../../sessions/model/session";
import { AccessPicker } from "../../sessions/ui/AccessPicker";
import { ModelControlPills, ModelPicker } from "../../sessions/ui/ModelPicker";
import { loadModelControls, subscribeModelControls } from "../../settings/model/settings";
import { addAgentProject, agentCanvasScope, agentLook, removeAgentProject, updateAgent, type Agent } from "../model/agent";
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
import { listAgentDocuments, readAgentDocument, subscribeAgentDocuments, type StoredDocument } from "../model/agentDocuments";
import { openDocument } from "../../sessions/model/cards";
import { loadHabits, subscribeHabitsRunning } from "../model/agentHabits";
import { addMemoryEntry, memoryDate, memoryEntry, memoryLines, withoutLine } from "../model/agentMemory";
import { AgentAvatarPreview } from "./AgentAvatar";
import { AgentHabits } from "./AgentHabits";
import { ColorPicker, FacePicker, ProjectsField } from "./agentPanelParts";
import { useSavedWidgets } from "../../learning/hooks/useSavedWidgets";
import { openWidget, widgetRef } from "../../learning/model/widgets";
import type { StoredWidget } from "../../learning/model/types";

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

type Page = "soul" | "habits" | "memory" | "library";

const PAGE_TITLE: Record<Page, string> = { soul: "Soul", habits: "Habits", memory: "Memory", library: "Library" };

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

/** What the agent has written for the user, newest first, kept current as it writes. */
function useLibrary(agentId: string) {
  const [documents, setDocuments] = useState<StoredDocument[]>();
  const [error, setError] = useState<string>();
  const [version, setVersion] = useState(0);
  const owner = useRef(agentId);
  useEffect(() => {
    let current = true;
    let request = 0;
    if (owner.current !== agentId) {
      owner.current = agentId;
      setDocuments(undefined);
    }
    const load = () => {
      const turn = ++request;
      setError(undefined);
      void listAgentDocuments(agentId).then((found) => {
        if (current && turn === request) setDocuments(found);
      }, (reason: unknown) => {
        if (current && turn === request) setError(String(reason));
      });
    };
    load();
    const stop = subscribeAgentDocuments(load);
    return () => { current = false; stop(); };
  }, [agentId, version]);
  return { documents, error, reload: () => setVersion((value) => value + 1) };
}

/** The canvases in the agent's library: the ones it drew in no project. */
function useLibraryCanvases(agentId: string) {
  const [canvases, setCanvases] = useState<Canvas[]>();
  const [error, setError] = useState<string>();
  const [version, setVersion] = useState(0);
  const owner = useRef(agentId);
  useEffect(() => {
    let current = true;
    let request = 0;
    if (owner.current !== agentId) {
      owner.current = agentId;
      setCanvases(undefined);
    }
    const scope = agentCanvasScope(agentId);
    const load = (refresh = false) => {
      const turn = ++request;
      setError(undefined);
      void loadCanvases(refresh).then((all) => {
        if (current && turn === request) {
          setCanvases(all.filter((canvas) => canvas.cwd === scope));
        }
      }, (reason: unknown) => {
        if (current && turn === request) setError(String(reason));
      });
    };
    load(version > 0);
    const onChange = () => load(true);
    window.addEventListener(CANVASES_CHANGED_EVENT, onChange);
    return () => {
      current = false;
      window.removeEventListener(CANVASES_CHANGED_EVENT, onChange);
    };
  }, [agentId, version]);
  return { canvases, error, reload: () => setVersion((value) => value + 1) };
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
  const modelControls = useSyncExternalStore(subscribeModelControls, loadModelControls, () => "menu" as const);
  const controlsBeside = modelControls === "beside";
  const { files, error } = useAgentFiles(agent.id, refreshKey);
  const habits = useHabitCount(agent.id);
  const library = useLibrary(agent.id);
  const libraryCanvases = useLibraryCanvases(agent.id);
  const savedWidgets = useSavedWidgets({ kind: "agent", id: agent.id });
  const libraryCount = library.documents && libraryCanvases.canvases && savedWidgets.widgets
    ? library.documents.length + libraryCanvases.canvases.length + savedWidgets.widgets.length
    : undefined;
  const libraryError = library.error ?? libraryCanvases.error ?? savedWidgets.error;
  const [page, setPage] = useState<Page>();
  // Another agent's details start from the top.
  useEffect(() => setPage(undefined), [agent.id]);
  const facts = files ? memoryLines(files.memory).filter((fact) => !fact.struck).length : undefined;

  return (
    <aside aria-label={`${look.name} details`} className="flex w-[340px] max-w-full shrink-0 flex-col border-l border-stroke bg-background-base/70 backdrop-blur-xl">
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
      ) : page === "library" ? (
        <LibraryPage agentId={agent.id} documents={library.documents} canvases={libraryCanvases.canvases}
          widgets={savedWidgets.widgets} error={libraryError} onOpenCanvas={onClose}
          onRetry={() => { library.reload(); libraryCanvases.reload(); savedWidgets.reload(); }} />
      ) : page === "habits" ? (
        <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-4 pb-4">
          <p className="text-xs leading-snug text-content/45">What it does on its own, on a schedule, while Loci is open. It writes to this chat only when there is something to say.</p>
          <AgentHabits key={agent.id} agentId={agent.id} />
        </div>
      ) : (
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div className="flex flex-col items-center gap-3 px-4 pb-5 pt-3">
            <AgentAvatarPreview key={agent.id} name={look.avatar} color={look.color} />
            <div className="flex w-full flex-col items-center">
              <NameField key={`name:${agent.id}:${agent.name ?? ""}`} agent={agent} />
              <RoleField key={`role:${agent.id}:${agent.role ?? ""}`} agent={agent} />
            </div>
            <FacePicker current={agent.avatar} color={agent.color} onPick={(avatar) => updateAgent(agent.id, (current) => ({ ...current, avatar }))} />
            <ColorPicker current={agent.color} onPick={(color) => updateAgent(agent.id, (current) => ({ ...current, color }))} />
          </div>

          <div className="flex flex-col gap-1 border-t border-stroke px-4 py-3">
            <Property label="Model">
              <div className="flex flex-wrap items-center gap-1">
                <ModelPicker harness={session.harness} model={session.model} values={session.modelSettings}
                  hideSettings={controlsBeside} onChange={onModelChange} onSettingsChange={onModelSettingsChange} />
                {controlsBeside ? (
                  <ModelControlPills harness={session.harness} model={session.model} values={session.modelSettings}
                    onSettingsChange={onModelSettingsChange} />
                ) : null}
              </div>
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
            <PageRow title="Library" description="Documents, drawings and explanations." count={libraryCount} onOpen={() => setPage("library")} />
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

const libraryDate = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });
type LibraryEntry =
  | { kind: "document"; item: StoredDocument }
  | { kind: "canvas"; item: Canvas }
  | { kind: "widget"; item: StoredWidget };
const LIBRARY_KINDS = {
  document: { Icon: File, label: "Document" },
  canvas: { Icon: Palette, label: "Canvas" },
  widget: { Icon: AiIdea, label: "Interactive explanation" },
};

/** One recent-first list; metadata stays available without crowding titles. */
function LibraryPage({ agentId, documents, canvases, widgets, error, onOpenCanvas, onRetry }: {
  agentId: string;
  documents?: StoredDocument[];
  canvases?: Canvas[];
  widgets?: StoredWidget[];
  error?: string;
  onOpenCanvas: () => void;
  onRetry: () => void;
}) {
  const [openError, setOpenError] = useState<string>();
  const opening = useRef(0);
  useEffect(() => () => { opening.current += 1; }, [agentId]);
  const entries: LibraryEntry[] = [
    ...(documents ?? []).map((item): LibraryEntry => ({ kind: "document", item })),
    ...(canvases ?? []).map((item): LibraryEntry => ({ kind: "canvas", item })),
    ...(widgets ?? []).map((item): LibraryEntry => ({ kind: "widget", item })),
  ];
  entries.sort((a, b) => b.item.updatedAt - a.item.updatedAt || a.item.id.localeCompare(b.item.id));
  const loaded = documents !== undefined && canvases !== undefined && widgets !== undefined;
  const open = async (entry: LibraryEntry) => {
    const turn = ++opening.current;
    setOpenError(undefined);
    if (entry.kind === "canvas") {
      onOpenCanvas();
      requestOpenAppResource({ kind: "canvas", id: entry.item.id });
    } else if (entry.kind === "widget") {
      openWidget(widgetRef(entry.item), entry.item.sourceSessionId, entry.item.title);
    } else {
      try {
        const found = await readAgentDocument(agentId, entry.item.id);
        if (turn !== opening.current) return;
        if (found?.body == null) throw new Error("Document is no longer available.");
        openDocument({ id: found.id, title: found.title, ...(found.subject ? { subject: found.subject } : {}), body: found.body }, agentId);
      } catch (reason) {
        if (turn === opening.current) setOpenError(String(reason));
      }
    }
  };
  return (
    <div data-agent-library className="flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto px-2 pb-4">
      {entries.map((entry) => {
        const { Icon, label } = LIBRARY_KINDS[entry.kind];
        const subject = entry.kind === "canvas" ? undefined : entry.item.subject;
        return (
          <button key={`${entry.kind}:${entry.item.id}`} type="button"
            data-library-kind={entry.kind} data-library-id={entry.item.id}
            aria-label={`${label}: ${entry.item.title}`}
            title={[entry.item.title, [label, subject].filter(Boolean).join(" · "), libraryDate.format(entry.item.updatedAt)].join("\n")}
            onClick={() => void open(entry)}
            className="flex w-full items-start gap-2.5 rounded-lg px-2 py-2 text-left hover:bg-content/6 focus-visible:bg-content/6 focus-visible:outline-2 focus-visible:outline-content/30">
            <Icon aria-hidden className="mt-0.5 size-3.5 shrink-0 text-content/40" strokeWidth={1.75} />
            <span className="min-w-0 flex-1 line-clamp-2 break-words text-[13px] leading-5 text-content">{entry.item.title}</span>
          </button>
        );
      })}
      {openError ? <p role="alert" className="px-2 py-2 text-xs text-red-400" title={openError}>Could not open this document.</p> : null}
      {error ? (
        <div role="alert" className="flex items-center gap-2 px-2 py-2 text-xs text-content/50" title={error}>
          <span className="min-w-0 flex-1">Some items could not be loaded.</span>
          <button type="button" onClick={onRetry} className="shrink-0 rounded px-1 py-0.5 text-content/80 hover:bg-content/8">Retry</button>
        </div>
      ) : entries.length === 0 ? (
        <p role="status" className="px-2 py-6 text-center text-xs text-content/45">{loaded ? "Nothing saved yet." : "Loading library…"}</p>
      ) : null}
    </div>
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
      <p className="text-xs leading-snug text-content/45">The rules it keeps while helping you. Refine them here or in chat.</p>
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
