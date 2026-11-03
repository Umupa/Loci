import { useCallback, useEffect, useMemo, useState, useSyncExternalStore, type ComponentProps } from "react";
import { agentLook, agentsSnapshot, agentState, listAgents, subscribeAgents, type AgentState } from "../../features/agents/model/agent";
import { AgentSessionPane } from "../../features/agents/ui/AgentSessionPane";
import { MentorSettingsPage } from "../../features/agents/ui/MentorSettingsPage";
import { AgentGallery } from "../../features/agents/ui/AgentGallery";
import { MentorWorkspace } from "../../features/mentor/ui/MentorWorkspace";
import { requestAddToChat } from "../../features/sessions/model/quoteDraft";
import { readingSkipped, setAgentReading, sharedReading, skipReadingOnce } from "../../features/agents/model/agentReading";
import { sessionDisplayTitle, type Session } from "../../features/sessions/model/session";
import { LOCAL_MODEL_SOURCE, ModelSourceContext, type ModelSource } from "../../features/sessions/ui/modelSource";
import { SessionPane } from "../../features/sessions/ui/SessionPane";
import { TranscriptPool, TranscriptPoolOutlet } from "../../features/sessions/ui/TranscriptPool";
import type { OpenFileFn } from "../../features/files/model/filePlace";
import { requestFilePlace } from "../../features/files/model/filePlace";
import { ask, pickFolders } from "../../platform/dialog";
import { HAS_NATIVE_GLASS, IS_MAC } from "../../platform/tauri/platform";
import { REMOTE_TARGET, transport } from "../../platform/transport";
import { FileActionError } from "../../shared/ui/FileActionError";
import { ReadOnly } from "../../shared/ui/ReadOnly";
import { loadActiveMentorId, useActiveMentor } from "../hooks/useActiveMentor";
import { useMentorView } from "../hooks/useMentorView";
import { MentorRail } from "../shell/MentorRail";
import { SettingsNav } from "../shell/SettingsRail";
import { lazySurface } from "../../shared/ui/lazySurface";
import { loadSettingsSection, saveSettingsSection, type SettingsSectionId } from "../../features/settings/model/settings";
import { RemoteSettingsScopeContext } from "../../features/settings/model/settingsScope";
import { useWindowCommands } from "./useWindowCommands";
import { MentorSearch } from "../../features/mentor/ui/MentorSearch";
import type { MentorSearchItem } from "../../features/mentor/model/mentorSearch";
import { WindowControls } from "../shell/WindowControls";
import { useRemoteSessions, type RemoteSessionClient } from "./remoteSessions";

/**
 * The host's providers and models: this window's model stores hold what the
 * host reported (`applyHostModels`), and refreshing asks the host to probe
 * its CLIs again. This window never runs one.
 */
function remoteModelSource(client: RemoteSessionClient): ModelSource {
  return {
    ...LOCAL_MODEL_SOURCE, id: "remote",
    refresh: (harnesses) => void client.refreshModels(harnesses),
    inspectBinary: (harness, binaryPath) => client.inspectBinary(harness, binaryPath),
  };
}

const SettingsView = lazySurface(async () => ({ default: (await import("../../features/settings/ui/SettingsView")).SettingsView }), { suspense: false });

/** The host's name as its group lists it; "the host" for this Loci's own (development). */
function useHostName(): string {
  const [name, setName] = useState("the host");
  useEffect(() => {
    if (REMOTE_TARGET?.kind !== "device") return;
    const { deviceId } = REMOTE_TARGET;
    void transport.call<{ deviceId: string; name: string }[]>("remote_devices_list")
      .then((devices) => { const found = devices.find((device) => device.deviceId === deviceId)?.name; if (found) setName(found); })
      .catch(() => undefined);
  }, []);
  return name;
}

/** A one-line strip saying whether this window reaches its host. */
export function ConnectionBar({ client }: { client: RemoteSessionClient }) {
  const { status } = useRemoteSessions(client);
  const host = useHostName();
  const text = status.state === "connected" ? `Connected to ${host}`
    : status.state === "connecting" ? `Connecting to ${host}…`
      : `${host[0].toUpperCase()}${host.slice(1)} is offline. Showing what this device kept; read-only.`;
  return <div role="status" data-remote-connection={status.state} title={status.error}
    className="flex h-7 shrink-0 items-center justify-center gap-3 border-b border-stroke text-[12px] text-content/60" data-tauri-drag-region="deep">
    <span>{text}</span>
    {status.state === "disconnected"
      ? <button type="button" className="rounded px-2 py-0.5 text-content/80 hover:bg-content/8" onClick={() => void client.connect()}>Reconnect</button> : null}
  </div>;
}

/**
 * A window showing another device's mentors and conversations. It lays them
 * out like the host's own window, but every session comes from the host's
 * feed and every action is an intent the host runs.
 */
export function RemoteWorkspace({ client }: { client: RemoteSessionClient }) {
  const { status, sessions, error } = useRemoteSessions(client);
  const rosterSnapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const agents = useMemo(() => listAgents(), [rosterSnapshot]);
  const mentor = useActiveMentor();
  const mentorView = useMentorView();
  const [transcriptPool] = useState(() => new TranscriptPool());
  /** The mentor whose page Settings shows, in place of a section. */
  const [settingsMentorId, setSettingsMentorId] = useState<string | null>(null);
  const [galleryOpen, setGalleryOpen] = useState(false);
  // Settings take the workspace's place, as in a window of this device.
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsSection, setSettingsSection] = useState(loadSettingsSection);
  const selectSettingsSection = useCallback((section: SettingsSectionId) => { setSettingsSection(section); saveSettingsSection(section); setSettingsMentorId(null); }, []);
  const toggleSettings = useCallback(() => { setSettingsMentorId(null); setSettingsOpen((open) => !open); }, []);
  const openMentorSettings = useCallback((agentId: string) => { setSettingsMentorId(agentId); setSettingsOpen(true); }, []);
  const [searchOpen, setSearchOpen] = useState(false);
  useWindowCommands({ openSettings: () => setSettingsOpen(true), toggleSearch: () => setSearchOpen((open) => !open) });
  const hostName = useHostName();
  const [openError, setOpenError] = useState<string | null>(null);
  const intents = client.intents;
  const [modelSource] = useState(() => remoteModelSource(client));

  const connected = status.state === "connected";
  const offline = status.state === "disconnected";
  const openMentor = useCallback(async (agentId: string) => {
    // Offline, the host cannot open it; the conversation this device kept is shown, if any.
    const kept = agents.find((agent) => agent.id === agentId)?.sessionId;
    if (offline && kept) { mentor.open(agentId, { id: kept } as Session); return; }
    try {
      const sessionId = await client.openAgent(agentId);
      if (sessionId) mentor.open(agentId, { id: sessionId } as Session);
    } catch (reason) { setOpenError(String(reason)); }
  }, [agents, client, mentor.open, offline]); // eslint-disable-line react-hooks/exhaustive-deps

  const current = mentor.current;
  const firstAgentId = (agents.find((agent) => agent.id === loadActiveMentorId()) ?? agents[0])?.id;
  useEffect(() => {
    if ((connected || offline) && !current && firstAgentId) void openMentor(firstAgentId);
  }, [connected, offline, current, firstAgentId, openMentor]);
  // A mentor removed on the host closes here too.
  useEffect(() => {
    if (current && agents.length && !agents.some((agent) => agent.id === current.agentId)) mentor.forgetSession(current.sessionId);
  }, [agents, current]); // eslint-disable-line react-hooks/exhaustive-deps

  const page = current ? mentorView.stateFor(current.agentId).page : undefined;
  const viewedIds = [current?.sessionId, page?.kind === "session" ? page.id : undefined].filter((id): id is string => !!id);
  const viewedKey = viewedIds.join("\0");
  useEffect(() => client.view(viewedIds), [client, viewedKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const states = useMemo(() => {
    const map = new Map<string, AgentState>();
    for (const agent of agents) {
      const session = sessions.find((entry) => entry.id === agent.sessionId);
      if (session) map.set(agent.id, agentState(session));
    }
    return map;
  }, [agents, sessions]);

  /** The host would ask; this window asks instead, and tells the host it did. */
  const confirmThen = async (question: string, title: string, okLabel: string, run: () => Promise<unknown>) => {
    if (await ask(question, { title, kind: "warning", okLabel, cancelLabel: "Cancel" })) await run().catch(() => undefined);
  };
  const resetAgent = (agentId: string) => {
    const agent = agents.find((entry) => entry.id === agentId);
    if (agent) void confirmThen(`Reset ${agentLook(agent).name}'s conversation? Its messages are removed; its soul and memory stay.`,
      "Reset conversation", "Reset", () => intents["agent.reset"](agentId, { confirmed: true }));
  };
  const removeAgent = (agentId: string) => {
    const agent = agents.find((entry) => entry.id === agentId);
    if (agent) void confirmThen(`Delete ${agentLook(agent).name}? Its conversation is permanently removed. Its documents and courses go with it; its soul and memory files stay on disk.`,
      "Delete agent", "Delete", () => intents["agent.remove"](agentId, { confirmed: true }));
  };

  /** A search result: its mentor, then its page in the reader. A note no mentor owns reads in the open mentor's. */
  const openSearchResult = async (item: MentorSearchItem) => {
    setSettingsOpen(false);
    const agentId = item.agentId ?? mentor.currentRef.current?.agentId;
    if (!agentId) return;
    if (mentor.currentRef.current?.agentId !== agentId) await openMentor(agentId);
    if (item.page) mentorView.show(agentId, item.page);
  };

  const openFile = useCallback<OpenFileFn>((path, place, options) => {
    const agentId = mentor.currentRef.current?.agentId;
    if (!agentId) return;
    if (place) requestFilePlace(path, place);
    mentorView.show(agentId, { kind: "file", path, ...(options?.commit ? { commit: options.commit } : {}) }, { fromLine: options?.fromLine });
  }, [mentor.currentRef, mentorView]);

  /**
   * For a control that needs to know at once whether it was taken: it is, and
   * the host's answer comes back in the feed; a refusal shows as an error.
   */
  const taken = <A extends unknown[]>(send: (...args: A) => Promise<unknown>) => (...args: A) => {
    void send(...args).catch(() => undefined);
    return true;
  };
  const paneProps = (session: Session, focused: boolean): ComponentProps<typeof SessionPane> => ({
    session, visible: true, focused, inSplit: false, composerFocused: focused, composerFocusToken: mentor.composerFocusToken,
    recents: [], hideProjectPicker: true, transcriptPool,
    onFocus: () => undefined, onClose: () => undefined, onCwdChange: () => undefined,
    onModelChange: intents["session.changeModel"], onModelSettingsChange: intents["session.changeModelSettings"], onRuntimeModeChange: intents["session.changeRuntimeMode"],
    // The mentor on the host is told what this window's reader shows.
    onSubmit: taken((sessionId, text, attachments, options) => {
      const agentId = agents.find((agent) => agent.sessionId === sessionId)?.id;
      if (!agentId) return intents["session.submit"](sessionId, text, attachments, options);
      // Dismissed for this message: the host must not fall back to its own reader.
      const reading = readingSkipped(agentId) ? null : sharedReading(agentId) ?? null;
      if (reading === null) skipReadingOnce(agentId, false);
      return intents["session.submit"](sessionId, text, attachments, { ...options, reading });
    }),
    onSaveDraft: taken(intents["session.saveDraft"]), onRemoveDraft: taken(intents["session.removeDraft"]),
    onStop: intents["session.stop"], onCompactContext: taken(intents["session.compact"]),
    onDeleteQueuedMessage: intents["session.queue.delete"], onEditQueuedMessage: intents["session.queue.edit"],
    onQueuedMessageEditingChange: intents["session.queue.editing"], onSteerQueuedMessage: intents["session.queue.steer"], onResumeQueue: intents["session.queue.resume"],
    onUsageLimitResume: intents["session.usageLimit.resume"], onUsageLimitResumeAtReset: intents["session.usageLimit.resumeAtReset"], onUsageLimitDismiss: intents["session.usageLimit.dismiss"],
    onNoteCardDismiss: intents["session.dismissNoteCard"], onNoteSaved: () => undefined,
    onApproval: intents["session.approve"], onQuestionReply: intents["session.answer"], onQuestionInteraction: intents["session.keepQuestionOpen"],
    onOpenFile: openFile, onBtwSubmit: taken(intents["session.btw.submit"]), onBtwRetry: intents["session.btw.retry"], onBtwDelete: intents["session.btw.delete"],
    onBtwStop: intents["session.btw.stop"], onBtwModelChange: intents["session.btw.modelChange"],
  });

  const focusedAgent = current ? agents.find((agent) => agent.id === current.agentId) : undefined;
  const settingsAgent = settingsMentorId ? agents.find((agent) => agent.id === settingsMentorId) : undefined;
  const chatSession = current ? sessions.find((session) => session.id === current.sessionId) : undefined;
  const chat = focusedAgent && chatSession
    ? <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-pane-id={chatSession.id}>
      <AgentSessionPane agent={focusedAgent} state={states.get(focusedAgent.id) ?? { status: "idle" }} sessionPaneProps={paneProps(client.sessionWithEarlier(chatSession), true)}
        onOpenSettings={() => openMentorSettings(focusedAgent.id)}
        onLoadEarlier={client.hasEarlier(chatSession.id) ? () => void client.loadEarlier(chatSession.id) : undefined}
        // Offline, nothing can be sent; archived history is read from what this device kept.
        readOnly={offline} />
    </div>
    : <p role="status" className="mentor-reader-empty">Opening the conversation…</p>;
  const readerSession = (id: string) => {
    const session = sessions.find((entry) => entry.id === id);
    if (!session) return <p role="status" className="mentor-reader-empty">Opening the conversation…</p>;
    return <ReadOnly readOnly={offline}><div className="flex min-h-0 min-w-0 flex-1 flex-col" data-pane-id={id}><SessionPane {...paneProps(session, false)} composerFocused={false} /></div></ReadOnly>;
  };
  const sessionTitle = (id: string) => {
    const session = sessions.find((entry) => entry.id === id);
    return session ? sessionDisplayTitle(session.title, session.harness) : "Conversation";
  };
  const shownError = error ?? openError;

  return <ModelSourceContext.Provider value={modelSource}>
    <div className={`workspace-background flex h-full flex-col text-content ${HAS_NATIVE_GLASS ? "bg-background-base/[var(--window-background-opacity)]" : "bg-background-base"}`} data-remote-workspace>
      <ConnectionBar client={client} />
      <div className="flex min-h-0 min-w-0 flex-1">
        <MentorRail activeId={focusedAgent?.id} states={states} unseenIds={new Set()} settingsOpen={settingsOpen}
          onOpen={(id) => { setSettingsOpen(false); void openMentor(id); }} onOpenDetails={openMentorSettings}
          onCreate={() => setGalleryOpen(true)} onDelete={removeAgent}
          onSearch={() => setSearchOpen(true)} onOpenSettings={toggleSettings} />
        {settingsOpen ? <aside className="flex w-[220px] shrink-0 flex-col border-r border-stroke" aria-label="Settings sections">
          <div className="h-10 shrink-0" data-tauri-drag-region="deep" />
          <SettingsNav section={settingsSection} onSelect={selectSettingsSection} onClose={() => setSettingsOpen(false)}
            mentors={agents} mentorId={settingsAgent?.id ?? null} onSelectMentor={openMentorSettings} />
        </aside> : null}
        <div className="body-glass flex min-h-0 min-w-0 flex-1 flex-col">
          {settingsOpen ? <RemoteSettingsScopeContext.Provider value={{ host: hostName, offline }}>
            {settingsAgent ? <MentorSettingsPage agent={settingsAgent} session={sessions.find((session) => session.id === settingsAgent.sessionId)} recents={[]}
              onModelChange={intents["session.changeModel"]} onModelSettingsChange={intents["session.changeModelSettings"]} onRuntimeModeChange={intents["session.changeRuntimeMode"]}
              onPickFolders={() => pickFolders("Choose folders")} onReset={() => resetAgent(settingsAgent.id)} onDelete={() => removeAgent(settingsAgent.id)} readOnly={offline} />
              : <SettingsView section={settingsSection} cwd="~" besideRail onClose={() => setSettingsOpen(false)} onSelectSection={selectSettingsSection} />}
          </RemoteSettingsScopeContext.Provider>
          : current && focusedAgent ? <section data-agent-workspace={focusedAgent.id} className="flex min-h-0 min-w-0 flex-1 flex-col">
            <MentorWorkspace key={focusedAgent.id} agent={focusedAgent} state={mentorView.stateFor(focusedAgent.id)} busy={!!chatSession?.busy}
              trailing={IS_MAC ? undefined : <WindowControls />}
              onOpen={(next) => mentorView.show(focusedAgent.id, next)} onClose={() => mentorView.close(focusedAgent.id)}
              history={mentorView.historyFor(focusedAgent.id)} onBack={() => mentorView.back(focusedAgent.id)} onForward={() => mentorView.forward(focusedAgent.id)}
              onLessonChange={(lesson) => mentorView.setLesson(focusedAgent.id, lesson)}
              onRestoredChecked={(restored, exists) => mentorView.confirmRestored(focusedAgent.id, restored, exists)}
              onToggleLibrary={() => mentorView.toggleLibrary(focusedAgent.id)} onLibraryChange={(change) => mentorView.openLibrary(focusedAgent.id, change)}
              onDraft={(text) => { if (focusedAgent.sessionId) requestAddToChat(text, "prompt", { targetSessionId: focusedAgent.sessionId }); }}
              onToggleChat={() => mentorView.toggleChat(focusedAgent.id)}
              onResizeLibrary={(width) => mentorView.resizeLibrary(focusedAgent.id, width)} onResizeChat={(width) => mentorView.resizeChat(focusedAgent.id, width)}
              onReading={(reading) => setAgentReading(focusedAgent.id, reading)}
              onOpenFile={openFile}
              renderSession={readerSession} sessionTitle={sessionTitle} chat={chat} />
          </section> : <div className="flex flex-1 items-center justify-center p-8 text-sm text-content/60" role="status">
            {connected || offline ? (agents.length ? "Opening a mentor…" : offline ? "Nothing from the host was kept on this device yet." : "The host has no mentors yet.") : "Waiting for the host…"}
          </div>}
        </div>
      </div>
      {searchOpen ? <MentorSearch onClose={() => setSearchOpen(false)} onPick={(item) => void openSearchResult(item)} /> : null}
      {galleryOpen ? <AgentGallery onClose={() => setGalleryOpen(false)} onPick={(template) => {
        setGalleryOpen(false);
        void intents["agent.create"](template ?? undefined).then((id) => { if (typeof id === "string") void openMentor(id); }).catch(() => undefined);
      }} /> : null}
      {shownError ? <FileActionError message={shownError} onDismiss={() => { client.clearError(); setOpenError(null); }} /> : null}
    </div>
    <TranscriptPoolOutlet pool={transcriptPool} />
  </ModelSourceContext.Provider>;
}
