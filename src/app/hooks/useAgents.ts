import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { ask } from "@tauri-apps/plugin-dialog";
import { homeDir } from "../../platform/tauri/fs";
import { forgetHarnessSession } from "../../integrations/harness/core/registry";
import { deleteSession } from "../../features/sessions/data/sessionStore";
import { sessionChildHarnesses } from "../../features/sessions/model/handoff";
import { newDefaultSession, type Block, type Session } from "../../features/sessions/model/session";
import {
  agentLook, agentState, agentsSnapshot, createAgent, findAgent, listAgents, removeAgent, subscribeAgents,
  type AgentState,
} from "../../features/agents/model/agent";
import { forgetAgentContext } from "../../features/agents/model/agentFiles";
import { forgetAgentRotation } from "../../features/agents/model/agentRotation";
import { ensureAgentSession, resetAgentSession } from "../../features/agents/model/agentWorkspace";
import { archiveOlderTurns, canArchive, loadTranscriptPage, planArchive, type TranscriptPage } from "../../features/agents/model/agentTranscript";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

type Options = {
  runtime: SessionRuntime;
  submission: SessionSubmission;
  /** A saved conversation by id, from memory or the store. */
  loadSession: (id: string) => Promise<Session | null>;
  onError: (error: unknown) => void;
  /** The agent's conversation is ready to be shown. */
  onShow: () => void;
  /** The conversation in view went away. */
  onHide: () => void;
};

/** Owns the agents' conversations: opening one into view, resetting it and deleting it. */
export function useAgents(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const { sessions } = options.runtime;
  const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const agents = useMemo(() => listAgents(), [snapshot]);
  const [viewId, setViewId] = useState<string | null>(null);
  const [detailsOpen, setDetailsOpen] = useState(false);
  const viewIdRef = useRef(viewId);
  viewIdRef.current = viewId;
  // A slower open must not replace the agent chosen after it.
  const request = useRef(0);

  const viewAgent = viewId ? agents.find((agent) => agent.id === viewId) : undefined;
  const viewSession = viewAgent?.sessionId ? sessions.find((session) => session.id === viewAgent.sessionId) : undefined;

  /** What each agent is doing; one whose conversation is not loaded is at rest. */
  const states = useMemo(() => {
    const map = new Map<string, AgentState>();
    for (const agent of agents) {
      const session = agent.sessionId ? sessions.find((entry) => entry.id === agent.sessionId) : undefined;
      if (session) map.set(agent.id, agentState(session));
    }
    return map;
  }, [agents, sessions]);

  /** Earlier turns of the conversation in view, read back from its archived pages. */
  const [earlier, setEarlier] = useState<{ sessionId: string; blocks: Block[]; next?: TranscriptPage }>();
  const viewSessionId = viewSession?.id;
  useEffect(() => {
    setEarlier(undefined);
    if (!viewSessionId) return;
    let current = true;
    void loadTranscriptPage(viewSessionId).then((next) => {
      if (current && next) setEarlier({ sessionId: viewSessionId, blocks: [], next });
    }).catch(() => undefined);
    return () => { current = false; };
  }, [viewSessionId]);
  const earlierBlocks = earlier && earlier.sessionId === viewSessionId ? earlier.blocks : undefined;
  const hasEarlier = !!earlier?.next && earlier.sessionId === viewSessionId;
  const loadEarlier = useCallback(async () => {
    const shown = earlier;
    if (!shown?.next) return;
    const page = shown.next;
    const next = page.hasOlder ? await loadTranscriptPage(shown.sessionId, page.seq).catch(() => undefined) : undefined;
    setEarlier((latestShown) => latestShown === shown ? { sessionId: shown.sessionId, blocks: [...page.blocks, ...shown.blocks], next } : latestShown);
  }, [earlier]);

  // An idle chat that has grown long hands its oldest turns to the page store. One in
  // view waits until the user leaves, so nothing they are reading disappears.
  const archiving = useRef(new Set<string>());
  useEffect(() => {
    for (const agent of agents) {
      const chat = agent.sessionId && agent.sessionId !== viewSessionId
        ? sessions.find((session) => session.id === agent.sessionId) : undefined;
      if (!chat || archiving.current.has(chat.id) || !canArchive(chat) || !planArchive(chat.blocks)) continue;
      archiving.current.add(chat.id);
      void archiveOlderTurns(chat).then(async (kept) => {
        if (!kept) return;
        const { runtime } = latest.current;
        // Only the exact chat that was archived gives up its turns.
        runtime.updateSessions((current) => current.map((session) => session === chat ? { ...session, blocks: kept } : session));
        await runtime.persistSession(chat.id);
      }).catch((error) => latest.current.onError(error)).finally(() => archiving.current.delete(chat.id));
    }
  }, [agents, sessions, viewSessionId]);

  const addSession = useCallback((session: Session) => {
    const { runtime } = latest.current;
    runtime.bindRestoredSession(session);
    runtime.updateSessions((current) => current.some((entry) => entry.id === session.id) ? current : [...current, session]);
  }, []);

  const open = useCallback(async (agentId: string) => {
    const turn = ++request.current;
    try {
      const session = await ensureAgentSession(agentId, {
        home: homeDir,
        load: (id) => latest.current.loadSession(id),
        create: (cwd) => newDefaultSession(cwd),
        add: addSession,
      });
      if (!session || turn !== request.current) return;
      setViewId(agentId);
      latest.current.onShow();
    } catch (error) {
      latest.current.onError(error);
    }
  }, [addSession]);

  /** A new agent opens straight away, ready to be told what it works on. */
  const create = useCallback(() => {
    setDetailsOpen(true);
    void open(createAgent().id);
  }, [open]);

  const close = useCallback(() => {
    request.current += 1;
    setViewId(null);
  }, []);

  /** Stops the conversation's work and deletes its record; the agent itself stays. */
  const discardSession = useCallback(async (session: Session) => {
    const { runtime, submission } = latest.current;
    await submission.stopSessionWork(session.id);
    await runtime.flushPersistence();
    await deleteSession(session.id);
    for (const harness of sessionChildHarnesses(session)) void forgetHarnessSession(harness, session.id).catch(() => undefined);
    runtime.updateSessions((current) => current.filter((entry) => entry.id !== session.id));
  }, []);

  const reset = useCallback(async (agentId: string) => {
    const agent = findAgent(agentId);
    const current = agent?.sessionId
      ? latest.current.runtime.sessionsRef.current.find((session) => session.id === agent.sessionId) : undefined;
    if (!agent || !current) return;
    if (!await ask(`Reset ${agentLook(agent).name}'s conversation? Its messages are removed; its soul and memory stay.`,
      { title: "Reset conversation", kind: "warning", okLabel: "Reset", cancelLabel: "Cancel" })) return;
    try {
      await resetAgentSession(current, {
        stop: (id) => latest.current.submission.stopSessionWork(id),
        remove: discardSession,
        replace: (_previousId, fresh) => addSession(fresh),
      });
    } catch (error) {
      latest.current.onError(error);
    }
  }, [addSession, discardSession]);

  /** Deletes the agent's conversation, then the agent. Its files stay on disk. */
  const remove = useCallback(async (agentId: string) => {
    const agent = findAgent(agentId);
    if (!agent) return;
    if (!await ask(`Delete ${agentLook(agent).name}? Its conversation is permanently removed. Its soul and memory files stay on disk.`,
      { title: "Delete agent", kind: "warning", okLabel: "Delete", cancelLabel: "Cancel" })) return;
    try {
      if (viewIdRef.current === agentId) {
        close();
        latest.current.onHide();
      }
      if (agent.sessionId) {
        const session = latest.current.runtime.sessionsRef.current.find((entry) => entry.id === agent.sessionId)
          ?? await latest.current.loadSession(agent.sessionId);
        if (session) await discardSession(session);
        forgetAgentContext(agent.sessionId);
        forgetAgentRotation(agent.sessionId);
      }
      removeAgent(agentId);
    } catch (error) {
      latest.current.onError(error);
    }
  }, [close, discardSession]);

  return {
    agents, states, viewAgent, viewSession, earlierBlocks, hasEarlier, loadEarlier, detailsOpen, setDetailsOpen,
    open, create, close, reset, remove,
  };
}
